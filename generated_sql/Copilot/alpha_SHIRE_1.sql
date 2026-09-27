
/* SHIRE / OMOP-lite rewrite of Copilot/alpha_1.sql
   - No concept / concept_ancestor usage
   - Use source fields: condition_source_value, drug_source_value, measurement_source_value
   - Replace observation_period with visit_occurrence-derived window
   - Keep same high-level gates: criteria A/B/C, exclusions (type1-only, gestational-only, secondary-only)
*/

WITH
/* ---------------------------
   0) Visit-based observation window (replaces observation_period)
   --------------------------- */
op AS (
  SELECT
    person_id,
    MIN(try_cast(visit_start_date AS DATE)) AS op_start,
    MAX(try_cast(COALESCE(visit_end_date, visit_start_date) AS DATE)) AS op_end
  FROM memory.visit_occurrence
  GROUP BY person_id
),

/* ---------------------------
   1) Raw evidence: diagnoses (source values)
   --------------------------- */
t2dm_dx AS (
  SELECT
    co.person_id,
    try_cast(co.condition_start_date AS DATE) AS condition_start_date,
    co.condition_source_value
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'E11%'
    OR co.condition_source_value IN (
      '250.00','250.02','250.10','250.12','250.20','250.22',
      '250.30','250.32','250.40','250.42','250.50','250.52',
      '250.60','250.62','250.70','250.72','250.80','250.82',
      '250.90','250.92'
    )
),

t1dm_dx AS (
  SELECT
    co.person_id,
    try_cast(co.condition_start_date AS DATE) AS condition_start_date,
    co.condition_source_value
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'E10%'
    OR co.condition_source_value IN (
      '250.01','250.03','250.11','250.13','250.21','250.23',
      '250.31','250.33','250.41','250.43','250.51','250.53',
      '250.61','250.63','250.71','250.73','250.81','250.83',
      '250.91','250.93'
    )
),

gest_dm_dx AS (
  SELECT
    co.person_id,
    try_cast(co.condition_start_date AS DATE) AS condition_start_date,
    co.condition_source_value
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'O24.4%'
    OR co.condition_source_value ILIKE 'O24.9%'
    OR co.condition_source_value ILIKE '648.8%'
),

secondary_dm_dx AS (
  SELECT
    co.person_id,
    try_cast(co.condition_start_date AS DATE) AS condition_start_date,
    co.condition_source_value
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'E08%'
    OR co.condition_source_value ILIKE 'E09%'
    OR co.condition_source_value ILIKE 'E13%'
    OR co.condition_source_value ILIKE '249%'
),

/* ---------------------------
   2) Raw evidence: meds (source values)
   --------------------------- */
non_insulin_dm_drugs AS (
  SELECT
    de.person_id,
    try_cast(COALESCE(de.drug_exposure_start_date, de.drug_exposure_start_datetime) AS DATE) AS drug_exposure_start_date,
    de.drug_source_value
  FROM memory.drug_exposure de
  WHERE
    (
      -- generics
      de.drug_source_value ILIKE '%metformin%'
      OR de.drug_source_value ILIKE '%glipizide%'
      OR de.drug_source_value ILIKE '%glyburide%'
      OR de.drug_source_value ILIKE '%glimepiride%'
      OR de.drug_source_value ILIKE '%repaglinide%'
      OR de.drug_source_value ILIKE '%nateglinide%'
      OR de.drug_source_value ILIKE '%pioglitazone%'
      OR de.drug_source_value ILIKE '%rosiglitazone%'
      OR de.drug_source_value ILIKE '%sitagliptin%'
      OR de.drug_source_value ILIKE '%saxagliptin%'
      OR de.drug_source_value ILIKE '%linagliptin%'
      OR de.drug_source_value ILIKE '%alogliptin%'
      OR de.drug_source_value ILIKE '%exenatide%'
      OR de.drug_source_value ILIKE '%liraglutide%'
      OR de.drug_source_value ILIKE '%semaglutide%'
      OR de.drug_source_value ILIKE '%dulaglutide%'
      OR de.drug_source_value ILIKE '%lixisenatide%'
      OR de.drug_source_value ILIKE '%tirzepatide%'
      OR de.drug_source_value ILIKE '%canagliflozin%'
      OR de.drug_source_value ILIKE '%dapagliflozin%'
      OR de.drug_source_value ILIKE '%empagliflozin%'
      OR de.drug_source_value ILIKE '%ertugliflozin%'
      OR de.drug_source_value ILIKE '%acarbose%'
      OR de.drug_source_value ILIKE '%miglitol%'
      -- brands
      OR de.drug_source_value ILIKE '%glucophage%'
      OR de.drug_source_value ILIKE '%glumetza%'
      OR de.drug_source_value ILIKE '%riomet%'
      OR de.drug_source_value ILIKE '%fortamet%'
      OR de.drug_source_value ILIKE '%glucotrol%'
      OR de.drug_source_value ILIKE '%diabeta%'
      OR de.drug_source_value ILIKE '%micronase%'
      OR de.drug_source_value ILIKE '%glynase%'
      OR de.drug_source_value ILIKE '%amaryl%'
      OR de.drug_source_value ILIKE '%actos%'
      OR de.drug_source_value ILIKE '%avandia%'
      OR de.drug_source_value ILIKE '%januvia%'
      OR de.drug_source_value ILIKE '%onglyza%'
      OR de.drug_source_value ILIKE '%tradjenta%'
      OR de.drug_source_value ILIKE '%nesina%'
      OR de.drug_source_value ILIKE '%byetta%'
      OR de.drug_source_value ILIKE '%bydureon%'
      OR de.drug_source_value ILIKE '%victoza%'
      OR de.drug_source_value ILIKE '%ozempic%'
      OR de.drug_source_value ILIKE '%rybelsus%'
      OR de.drug_source_value ILIKE '%trulicity%'
      OR de.drug_source_value ILIKE '%adlyxin%'
      OR de.drug_source_value ILIKE '%mounjaro%'
      OR de.drug_source_value ILIKE '%invokana%'
      OR de.drug_source_value ILIKE '%farxiga%'
      OR de.drug_source_value ILIKE '%jardiance%'
      OR de.drug_source_value ILIKE '%steglatro%'
    )
    AND de.drug_source_value NOT ILIKE '%insulin%'
),

/* ---------------------------
   3) Raw evidence: labs (source values + numeric thresholds)
   --------------------------- */
dm_labs AS (
  SELECT
    m.person_id,
    try_cast(m.measurement_date AS DATE) AS measurement_date,
    m.measurement_source_value,
    m.value_as_number
  FROM memory.measurement m
  WHERE m.value_as_number IS NOT NULL
),

abnormal_dm_labs AS (
  SELECT
    l.person_id,
    l.measurement_date
  FROM dm_labs l
  WHERE
    (
      (l.measurement_source_value ILIKE '%hemoglobin a1c%'
       OR l.measurement_source_value ILIKE '%hba1c%'
       OR l.measurement_source_value ILIKE '%a1c%')
      AND l.value_as_number >= 6.5
    )
    OR
    (
      l.measurement_source_value ILIKE '%glucose%'
      AND l.measurement_source_value ILIKE '%fast%'
      AND l.value_as_number >= 126
    )
    OR
    (
      l.measurement_source_value ILIKE '%glucose%'
      AND (
        l.measurement_source_value ILIKE '%tolerance%'
        OR l.measurement_source_value ILIKE '%2 hour%'
        OR l.measurement_source_value ILIKE '%2-hour%'
        OR l.measurement_source_value ILIKE '%ogtt%'
      )
      AND l.value_as_number >= 200
    )
),

/* ---------------------------
   4) Derived criteria A/B/C
   --------------------------- */
criterion_a AS (
  SELECT
    person_id,
    MIN(condition_start_date) AS index_date,
    COUNT(DISTINCT condition_start_date) AS dx_dates
  FROM t2dm_dx
  GROUP BY person_id
  HAVING COUNT(DISTINCT condition_start_date) >= 2
),

criterion_b AS (
  SELECT
    d.person_id,
    MIN(d.condition_start_date) AS dx_date,
    MIN(n.drug_exposure_start_date) AS drug_date,
    LEAST(MIN(d.condition_start_date), MIN(n.drug_exposure_start_date)) AS index_date
  FROM t2dm_dx d
  JOIN non_insulin_dm_drugs n
    ON d.person_id = n.person_id
  GROUP BY d.person_id
),

criterion_c AS (
  SELECT
    a.person_id,
    MIN(a.measurement_date) AS first_abnormal_date,
    COUNT(DISTINCT a.measurement_date) AS abnormal_dates,
    MIN(n.drug_exposure_start_date) AS drug_date,
    LEAST(MIN(a.measurement_date), MIN(n.drug_exposure_start_date)) AS index_date
  FROM abnormal_dm_labs a
  JOIN non_insulin_dm_drugs n
    ON a.person_id = n.person_id
  GROUP BY a.person_id
  HAVING COUNT(DISTINCT a.measurement_date) >= 2
),

/* ---------------------------
   5) Exclusion patterns (only if NO T2DM dx evidence)
   --------------------------- */
type1_only AS (
  SELECT person_id
  FROM t1dm_dx
  GROUP BY person_id
  HAVING COUNT(*) >= 1
     AND person_id NOT IN (SELECT person_id FROM t2dm_dx)
),

gestational_only AS (
  SELECT person_id
  FROM gest_dm_dx
  GROUP BY person_id
  HAVING COUNT(*) >= 1
     AND person_id NOT IN (SELECT person_id FROM t2dm_dx)
),

secondary_only AS (
  SELECT person_id
  FROM secondary_dm_dx
  GROUP BY person_id
  HAVING COUNT(*) >= 1
     AND person_id NOT IN (SELECT person_id FROM t2dm_dx)
),

/* ---------------------------
   6) Combine criteria
   --------------------------- */
combined_cases AS (
  SELECT person_id, index_date, 'A' AS criterion FROM criterion_a
  UNION
  SELECT person_id, index_date, 'B' AS criterion FROM criterion_b
  UNION
  SELECT person_id, index_date, 'C' AS criterion FROM criterion_c
),

/* ---------------------------
   7) Age gate (>=18) using year_of_birth (DuckDB-safe)
   --------------------------- */
eligible_cases AS (
  SELECT
    cc.person_id,
    cc.index_date,
    cc.criterion,
    (
      EXTRACT(YEAR FROM cc.index_date) - p.year_of_birth
      - CASE
          WHEN strftime(cc.index_date, '%m%d')
               < lpad(CAST(COALESCE(p.month_of_birth, 1) AS VARCHAR), 2, '0')
                 || lpad(CAST(COALESCE(p.day_of_birth, 1) AS VARCHAR), 2, '0')
          THEN 1 ELSE 0
        END
    ) AS age_at_index
  FROM combined_cases cc
  JOIN memory.person p
    ON cc.person_id = p.person_id
  WHERE (
      EXTRACT(YEAR FROM cc.index_date) - p.year_of_birth
      - CASE
          WHEN strftime(cc.index_date, '%m%d')
               < lpad(CAST(COALESCE(p.month_of_birth, 1) AS VARCHAR), 2, '0')
                 || lpad(CAST(COALESCE(p.day_of_birth, 1) AS VARCHAR), 2, '0')
          THEN 1 ELSE 0
        END
    ) >= 18
),

/* ---------------------------
   8) Observation window gate: index inside visit window AND >=365d span
   --------------------------- */
eligible_cases_with_observation AS (
  SELECT
    e.person_id,
    e.index_date,
    e.criterion,
    e.age_at_index
  FROM eligible_cases e
  JOIN op
    ON e.person_id = op.person_id
   AND e.index_date BETWEEN op.op_start AND op.op_end
   AND date_diff('day', op.op_start, op.op_end) >= 365
),

/* ---------------------------
   9) Apply exclusions
   --------------------------- */
final_t2dm_cases AS (
  SELECT DISTINCT
    ec.person_id,
    ec.index_date,
    ec.criterion,
    ec.age_at_index
  FROM eligible_cases_with_observation ec
  WHERE ec.person_id NOT IN (SELECT person_id FROM type1_only)
    AND ec.person_id NOT IN (SELECT person_id FROM gestational_only)
    AND ec.person_id NOT IN (SELECT person_id FROM secondary_only)
)

SELECT
  f.person_id,
  f.index_date,
  f.criterion,
  f.age_at_index
FROM final_t2dm_cases f
ORDER BY f.person_id, f.index_date
;