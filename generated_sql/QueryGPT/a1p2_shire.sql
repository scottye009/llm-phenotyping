/* SHIRE/OMOP-lite DuckDB rewrite of QueryGPT/a2.sql
   - Remove all vocabulary tables and mapping tables
   - Use source fields in event tables
   - Output: person_id + index_date
*/

WITH
/* adults at CURRENT_DATE (original used death/current; keep simple and fast) */
adult_person AS (
  SELECT person_id
  FROM memory.person
  WHERE (EXTRACT(YEAR FROM CURRENT_DATE) - year_of_birth) >= 18
),

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
gdm_dx AS (
  SELECT DISTINCT co.person_id
  FROM memory.condition_occurrence co
  WHERE co.condition_source_value ILIKE 'O24.4%'
     OR co.condition_source_value ILIKE '648.8%'
),
secondary_dm_dx AS (
  SELECT DISTINCT co.person_id
  FROM memory.condition_occurrence co
  WHERE co.condition_source_value ILIKE 'E08%'
     OR co.condition_source_value ILIKE 'E09%'
),

/* drug exposure (non-insulin antihyperglycemics) */
drug_tx AS (
  SELECT
    de.person_id,
    try_cast(COALESCE(de.drug_exposure_start_date, de.drug_exposure_start_datetime) AS DATE) AS drug_date
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
      OR de.drug_source_value ILIKE '%liraglutide%'
      OR de.drug_source_value ILIKE '%semaglutide%'
      OR de.drug_source_value ILIKE '%dulaglutide%'
      OR de.drug_source_value ILIKE '%exenatide%'
      OR de.drug_source_value ILIKE '%empagliflozin%'
      OR de.drug_source_value ILIKE '%canagliflozin%'
      OR de.drug_source_value ILIKE '%dapagliflozin%'
      OR de.drug_source_value ILIKE '%ertugliflozin%'
      OR de.drug_source_value ILIKE '%glucophage%'
      OR de.drug_source_value ILIKE '%januvia%'
      OR de.drug_source_value ILIKE '%ozempic%'
      OR de.drug_source_value ILIKE '%rybelsus%'
      OR de.drug_source_value ILIKE '%jardiance%'
      OR de.drug_source_value ILIKE '%farxiga%'
      OR de.drug_source_value ILIKE '%invokana%'
    )
    AND de.drug_source_value NOT ILIKE '%insulin%'
),

/* labs: normalize glucose by simply applying thresholds on value_as_number */
lab_positive AS (
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
        AND (
          m.measurement_source_value ILIKE '%tolerance%'
          OR m.measurement_source_value ILIKE '%ogtt%'
          OR m.measurement_source_value ILIKE '%2 hour%'
          OR m.measurement_source_value ILIKE '%2-hour%'
        )
        AND m.value_as_number >= 200
      )
      OR (
        m.measurement_source_value ILIKE '%glucose%'
        AND m.measurement_source_value NOT ILIKE '%fast%'
        AND m.measurement_source_value NOT ILIKE '%tolerance%'
        AND m.measurement_source_value NOT ILIKE '%2 hour%'
        AND m.measurement_source_value NOT ILIKE '%2-hour%'
        AND m.value_as_number >= 200
      )
    )
),

/* inclusion: (2+ dx) OR (dx & drug within ±365) OR (2+ labs) OR (lab & drug within ±365) */
inc_A_two_dx AS (
  SELECT person_id, MIN(dx_date) AS index_date
  FROM (SELECT DISTINCT person_id, dx_date FROM t2dm_dx) d
  GROUP BY person_id
  HAVING COUNT(*) >= 2
),
inc_B_dx_plus_rx AS (
  SELECT d.person_id, MIN(LEAST(d.dx_date, x.drug_date)) AS index_date
  FROM t2dm_dx d
  JOIN drug_tx x
    ON x.person_id = d.person_id
   AND x.drug_date BETWEEN d.dx_date - INTERVAL 365 DAY AND d.dx_date + INTERVAL 365 DAY
  GROUP BY d.person_id
),
inc_C_two_labs AS (
  SELECT person_id, MIN(lab_date) AS index_date
  FROM (SELECT DISTINCT person_id, lab_date FROM lab_positive) l
  GROUP BY person_id
  HAVING COUNT(*) >= 2
),
inc_D_lab_plus_rx AS (
  SELECT l.person_id, MIN(LEAST(l.lab_date, x.drug_date)) AS index_date
  FROM lab_positive l
  JOIN drug_tx x
    ON x.person_id = l.person_id
   AND x.drug_date BETWEEN l.lab_date - INTERVAL 365 DAY AND l.lab_date + INTERVAL 365 DAY
  GROUP BY l.person_id
),

incl_by_person AS (
  SELECT person_id, MIN(index_date) AS index_date
  FROM (
    SELECT * FROM inc_A_two_dx
    UNION ALL SELECT * FROM inc_B_dx_plus_rx
    UNION ALL SELECT * FROM inc_C_two_labs
    UNION ALL SELECT * FROM inc_D_lab_plus_rx
  ) u
  GROUP BY person_id
),

final AS (
  SELECT i.person_id, i.index_date
  FROM incl_by_person i
  JOIN adult_person a
    ON a.person_id = i.person_id
  LEFT JOIN (SELECT DISTINCT person_id FROM t1dm_dx) t1 ON t1.person_id = i.person_id
  LEFT JOIN gdm_dx g ON g.person_id = i.person_id
  LEFT JOIN secondary_dm_dx s ON s.person_id = i.person_id
  WHERE t1.person_id IS NULL
    AND g.person_id IS NULL
    AND s.person_id IS NULL
)

SELECT * FROM final
ORDER BY person_id;