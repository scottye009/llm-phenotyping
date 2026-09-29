/* SHIRE/OMOP-lite DuckDB rewrite of QueryGPT/a5.sql
   - Removes params + concept sets + maps-to expansions
   - Uses source fields directly
   - Keeps inclusion paths A/B/C and exclusions (gestational/secondary/only T1)
   - Outputs evidence flags and any_insulin_exposure like the original style
*/

WITH
/* diagnoses */
t2dm_dx AS (
  SELECT
    co.person_id,
    try_cast(co.condition_start_date AS DATE) AS dx_date
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'E11%'
    OR co.condition_source_value LIKE '250.%0'
    OR co.condition_source_value LIKE '250.%2'
),
t1dm_dx AS (
  SELECT
    co.person_id,
    try_cast(co.condition_start_date AS DATE) AS dx_date
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'E10%'
    OR co.condition_source_value LIKE '250.%1'
    OR co.condition_source_value LIKE '250.%3'
),
gestational_dm_dx AS (
  SELECT DISTINCT co.person_id
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE '648.8%'
    OR co.condition_source_value ILIKE 'O24.4%'
),
secondary_dm_dx AS (
  SELECT DISTINCT co.person_id
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'E08%'
    OR co.condition_source_value ILIKE 'E09%'
    OR co.condition_source_value ILIKE 'E13%'
    OR co.condition_source_value ILIKE '249%'
),

/* labs */
lab_person_dates AS (
  SELECT
    m.person_id,
    try_cast(m.measurement_date AS DATE) AS lab_date
  FROM memory.measurement m
  WHERE
    m.value_as_number IS NOT NULL
    AND (
      (
        (m.measurement_source_value ILIKE '%hemoglobin a1c%'
         OR m.measurement_source_value ILIKE '%hba1c%'
         OR m.measurement_source_value ILIKE '%a1c%')
        AND m.value_as_number >= 6.5
      )
      OR (
        m.measurement_source_value ILIKE '%glucose%'
        AND m.measurement_source_value ILIKE '%fast%'
        AND m.value_as_number >= 126
      )
      OR (
        m.measurement_source_value ILIKE '%glucose%'
        AND m.value_as_number >= 200
      )
    )
),

lab_counts AS (
  SELECT
    person_id,
    COUNT(DISTINCT lab_date) AS n_lab_dates,
    MIN(lab_date) AS first_lab_date
  FROM lab_person_dates
  GROUP BY person_id
),

/* meds */
non_insulin_rx AS (
  SELECT
    de.person_id,
    try_cast(COALESCE(de.drug_exposure_start_date, de.drug_exposure_start_datetime) AS DATE) AS rx_start_date
  FROM memory.drug_exposure de
  WHERE
    (
      de.drug_source_value ILIKE '%metformin%'
      OR de.drug_source_value ILIKE '%glipizide%'
      OR de.drug_source_value ILIKE '%glyburide%'
      OR de.drug_source_value ILIKE '%glimepiride%'
      OR de.drug_source_value ILIKE '%pioglitazone%'
      OR de.drug_source_value ILIKE '%rosiglitazone%'
      OR de.drug_source_value ILIKE '%sitagliptin%'
      OR de.drug_source_value ILIKE '%saxagliptin%'
      OR de.drug_source_value ILIKE '%linagliptin%'
      OR de.drug_source_value ILIKE '%alogliptin%'
      OR de.drug_source_value ILIKE '%exenatide%'
      OR de.drug_source_value ILIKE '%liraglutide%'
      OR de.drug_source_value ILIKE '%dulaglutide%'
      OR de.drug_source_value ILIKE '%semaglutide%'
      OR de.drug_source_value ILIKE '%tirzepatide%'
      OR de.drug_source_value ILIKE '%empagliflozin%'
      OR de.drug_source_value ILIKE '%canagliflozin%'
      OR de.drug_source_value ILIKE '%dapagliflozin%'
      OR de.drug_source_value ILIKE '%ertugliflozin%'
      OR de.drug_source_value ILIKE '%acarbose%'
      OR de.drug_source_value ILIKE '%miglitol%'
      OR de.drug_source_value ILIKE '%glucophage%'
      OR de.drug_source_value ILIKE '%januvia%'
      OR de.drug_source_value ILIKE '%ozempic%'
      OR de.drug_source_value ILIKE '%rybelsus%'
      OR de.drug_source_value ILIKE '%trulicity%'
      OR de.drug_source_value ILIKE '%victoza%'
      OR de.drug_source_value ILIKE '%jardiance%'
      OR de.drug_source_value ILIKE '%invokana%'
      OR de.drug_source_value ILIKE '%farxiga%'
      OR de.drug_source_value ILIKE '%steglatro%'
    )
    AND de.drug_source_value NOT ILIKE '%insulin%'
),
insulin_rx AS (
  SELECT
    de.person_id,
    try_cast(COALESCE(de.drug_exposure_start_date, de.drug_exposure_start_datetime) AS DATE) AS rx_start_date
  FROM memory.drug_exposure de
  WHERE de.drug_source_value ILIKE '%insulin%'
     OR de.drug_source_value ILIKE '%lantus%'
     OR de.drug_source_value ILIKE '%humalog%'
     OR de.drug_source_value ILIKE '%novolog%'
),

/* ============================
   PATHS
   ============================ */

path_A_candidates AS (
  /* >=2 T2DM dx on distinct dates */
  SELECT person_id, MIN(dx_date) AS index_date, 'A' AS path
  FROM (SELECT DISTINCT person_id, dx_date FROM t2dm_dx) d
  GROUP BY person_id
  HAVING COUNT(*) >= 2
),

path_B_candidates AS (
  /* >=1 T2DM dx + >=1 non-insulin drug */
  SELECT dx.person_id,
         LEAST(MIN(dx.dx_date), MIN(rx.rx_start_date)) AS index_date,
         'B' AS path
  FROM t2dm_dx dx
  JOIN non_insulin_rx rx
    ON rx.person_id = dx.person_id
  GROUP BY dx.person_id
),

path_C_candidates AS (
  /* labs on >=2 distinct dates OR 1 lab + 1 T2DM dx */
  SELECT lc.person_id,
         lc.first_lab_date AS index_date,
         'C' AS path
  FROM lab_counts lc
  WHERE lc.n_lab_dates >= 2

  UNION ALL

  SELECT DISTINCT l.person_id,
         LEAST(l.lab_date, d.dx_date) AS index_date,
         'C' AS path
  FROM lab_person_dates l
  JOIN t2dm_dx d ON d.person_id = l.person_id
),

inclusion_union AS (
  SELECT person_id, index_date, path FROM path_A_candidates
  UNION ALL
  SELECT person_id, index_date, path FROM path_B_candidates
  UNION ALL
  SELECT person_id, index_date, path FROM path_C_candidates
),

/* earliest index per person */
after_inclusion AS (
  SELECT person_id, MIN(index_date) AS index_date
  FROM inclusion_union
  GROUP BY person_id
),

/* exclusions */
excl_gestational AS (SELECT DISTINCT person_id FROM gestational_dm_dx),
excl_secondary_only AS (
  SELECT s.person_id
  FROM secondary_dm_dx s
  LEFT JOIN (SELECT DISTINCT person_id FROM t2dm_dx) t ON t.person_id = s.person_id
  WHERE t.person_id IS NULL
),
only_t1dm AS (
  SELECT t1.person_id
  FROM (SELECT DISTINCT person_id FROM t1dm_dx) t1
  LEFT JOIN (SELECT DISTINCT person_id FROM t2dm_dx) t2
    ON t2.person_id = t1.person_id
  WHERE t2.person_id IS NULL
),

/* adults at index */
age_at_index AS (
  SELECT a.person_id, a.index_date,
         (EXTRACT(YEAR FROM a.index_date) - p.year_of_birth) AS age_years
  FROM after_inclusion a
  JOIN memory.person p ON p.person_id = a.person_id
),
inclusion_final AS (
  SELECT person_id, index_date
  FROM age_at_index
  WHERE age_years >= 18
),

after_exclusions AS (
  SELECT i.person_id,
         i.index_date,
         CASE WHEN EXISTS (SELECT 1 FROM path_A_candidates x WHERE x.person_id=i.person_id) THEN 1 ELSE 0 END AS evidence_dx_only_path,
         CASE WHEN EXISTS (SELECT 1 FROM path_B_candidates x WHERE x.person_id=i.person_id) THEN 1 ELSE 0 END AS evidence_dx_plus_med_path,
         CASE WHEN EXISTS (SELECT 1 FROM path_C_candidates x WHERE x.person_id=i.person_id) THEN 1 ELSE 0 END AS evidence_lab_path,
         CASE WHEN EXISTS (SELECT 1 FROM insulin_rx x WHERE x.person_id=i.person_id) THEN 1 ELSE 0 END AS any_insulin_exposure
  FROM inclusion_final i
  LEFT JOIN excl_gestational g ON g.person_id = i.person_id
  LEFT JOIN excl_secondary_only s ON s.person_id = i.person_id
  LEFT JOIN only_t1dm o ON o.person_id = i.person_id
  WHERE g.person_id IS NULL
    AND s.person_id IS NULL
    AND o.person_id IS NULL
)

SELECT *
FROM after_exclusions
ORDER BY person_id;