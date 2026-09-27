
/* SHIRE / OMOP-lite rewrite of Copilot/alpha_4.sql
   - Remove vocab/ancestor logic
   - Use source fields
   - Keep inclusion blocks A1/A2/B/C (A2 inpatient proxy via visit_source_value '%hospital%')
   - Remove observation_period joins; use visit-derived op window only for age computation (as in alpha_4 it focused on inclusion/exclusion)
*/

WITH
/* Visit-based window */
op AS (
  SELECT
    person_id,
    MIN(try_cast(visit_start_date AS DATE)) AS op_start,
    MAX(try_cast(COALESCE(visit_end_date, visit_start_date) AS DATE)) AS op_end
  FROM memory.visit_occurrence
  GROUP BY person_id
),

/* Base diagnosis events */
t2dm_dx_events AS (
  SELECT
    co.person_id,
    try_cast(co.condition_start_date AS DATE) AS condition_start_date,
    co.visit_occurrence_id
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'E11%'
    OR co.condition_source_value LIKE '250.%0'
    OR co.condition_source_value LIKE '250.%2'
),

t1dm_dx_events AS (
  SELECT DISTINCT co.person_id
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'E10%'
    OR co.condition_source_value LIKE '250.%1'
    OR co.condition_source_value LIKE '250.%3'
),

gestational_dm_dx_events AS (
  SELECT DISTINCT co.person_id
  FROM memory.condition_occurrence co
  WHERE co.condition_source_value ILIKE 'O24.4%'
     OR co.condition_source_value ILIKE 'O24.9%'
     OR co.condition_source_value ILIKE '648.8%'
),

secondary_dm_dx_events AS (
  SELECT DISTINCT co.person_id
  FROM memory.condition_occurrence co
  WHERE co.condition_source_value ILIKE 'E08%'
     OR co.condition_source_value ILIKE 'E09%'
     OR co.condition_source_value ILIKE 'E13%'
     OR co.condition_source_value ILIKE '249%'
),

/* Drug events (non-insulin + insulin) */
t2dm_drug_events AS (
  SELECT
    de.person_id,
    try_cast(COALESCE(de.drug_exposure_start_date, de.drug_exposure_start_datetime) AS DATE) AS drug_exposure_start_date
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
      OR de.drug_source_value ILIKE '%canagliflozin%'
      OR de.drug_source_value ILIKE '%dapagliflozin%'
      OR de.drug_source_value ILIKE '%empagliflozin%'
      OR de.drug_source_value ILIKE '%ertugliflozin%'
      OR de.drug_source_value ILIKE '%acarbose%'
      OR de.drug_source_value ILIKE '%miglitol%'
      OR de.drug_source_value ILIKE '%nateglinide%'
      OR de.drug_source_value ILIKE '%repaglinide%'
    )
    AND de.drug_source_value NOT ILIKE '%insulin%'
),

insulin_drug_events AS (
  SELECT DISTINCT
    de.person_id,
    try_cast(COALESCE(de.drug_exposure_start_date, de.drug_exposure_start_datetime) AS DATE) AS drug_exposure_start_date
  FROM memory.drug_exposure de
  WHERE de.drug_source_value ILIKE '%insulin%'
),

/* Lab events */
dm_lab_events AS (
  SELECT
    m.person_id,
    try_cast(m.measurement_date AS DATE) AS measurement_date,
    m.measurement_source_value,
    m.value_as_number
  FROM memory.measurement m
  WHERE m.value_as_number IS NOT NULL
    AND (
      m.measurement_source_value ILIKE '%hba1c%'
      OR m.measurement_source_value ILIKE '%hemoglobin a1c%'
      OR m.measurement_source_value ILIKE '%a1c%'
      OR m.measurement_source_value ILIKE '%glucose%'
    )
),

abnormal_dm_labs AS (
  SELECT
    person_id,
    measurement_date
  FROM dm_lab_events
  WHERE
    (
      (measurement_source_value ILIKE '%hba1c%'
       OR measurement_source_value ILIKE '%hemoglobin a1c%'
       OR measurement_source_value ILIKE '%a1c%')
      AND value_as_number >= 6.5
    )
    OR
    (
      measurement_source_value ILIKE '%glucose%'
      AND value_as_number >= 126
    )
),

/* Criteria */
criterion_A1 AS (
  SELECT person_id
  FROM t2dm_dx_events
  GROUP BY person_id
  HAVING COUNT(DISTINCT condition_start_date) >= 2
),

/* Inpatient proxy: join condition to visit_occurrence and check text */
criterion_A2 AS (
  SELECT DISTINCT dx.person_id
  FROM t2dm_dx_events dx
  JOIN memory.visit_occurrence vo
    ON vo.visit_occurrence_id = dx.visit_occurrence_id
  WHERE COALESCE(vo.visit_source_value, '') ILIKE '%hospital%'
),

criterion_B AS (
  SELECT DISTINCT dx.person_id
  FROM t2dm_dx_events dx
  JOIN t2dm_drug_events dr
    ON dx.person_id = dr.person_id
),

criterion_C_labs AS (
  SELECT person_id
  FROM abnormal_dm_labs
  GROUP BY person_id
  HAVING COUNT(DISTINCT measurement_date) >= 2
),

criterion_C AS (
  SELECT DISTINCT l.person_id
  FROM criterion_C_labs l
  JOIN t2dm_drug_events dr
    ON l.person_id = dr.person_id
),

/* Age at first evidence */
first_evidence AS (
  SELECT
    p.person_id,
    MIN(e.event_date) AS first_event_date
  FROM memory.person p
  JOIN (
    SELECT person_id, condition_start_date AS event_date FROM t2dm_dx_events
    UNION ALL
    SELECT person_id, drug_exposure_start_date AS event_date FROM t2dm_drug_events
    UNION ALL
    SELECT person_id, measurement_date AS event_date FROM dm_lab_events
  ) e
    ON p.person_id = e.person_id
  GROUP BY p.person_id
),

age_eligible AS (
  SELECT
    f.person_id
  FROM first_evidence f
  JOIN memory.person p
    ON p.person_id = f.person_id
  WHERE (
    EXTRACT(YEAR FROM f.first_event_date) - p.year_of_birth
    - CASE
        WHEN strftime(f.first_event_date, '%m%d')
             < lpad(CAST(COALESCE(p.month_of_birth, 1) AS VARCHAR), 2, '0')
               || lpad(CAST(COALESCE(p.day_of_birth, 1) AS VARCHAR), 2, '0')
        THEN 1 ELSE 0
      END
  ) >= 18
),

gestational_or_secondary_only AS (
  SELECT DISTINCT
    p.person_id
  FROM memory.person p
  LEFT JOIN t2dm_dx_events t2
    ON p.person_id = t2.person_id
  LEFT JOIN gestational_dm_dx_events g
    ON p.person_id = g.person_id
  LEFT JOIN secondary_dm_dx_events s
    ON p.person_id = s.person_id
  WHERE t2.person_id IS NULL
    AND (g.person_id IS NOT NULL OR s.person_id IS NOT NULL)
),

pure_type1_pattern AS (
  SELECT DISTINCT
    p.person_id
  FROM memory.person p
  LEFT JOIN t2dm_dx_events t2
    ON p.person_id = t2.person_id
  LEFT JOIN t1dm_dx_events t1
    ON p.person_id = t1.person_id
  LEFT JOIN t2dm_drug_events t2d
    ON p.person_id = t2d.person_id
  LEFT JOIN insulin_drug_events ins
    ON p.person_id = ins.person_id
  WHERE t2.person_id IS NULL
    AND t1.person_id IS NOT NULL
    AND t2d.person_id IS NULL
    AND ins.person_id IS NOT NULL
),

inclusion_any AS (
  SELECT person_id FROM criterion_A1
  UNION
  SELECT person_id FROM criterion_A2
  UNION
  SELECT person_id FROM criterion_B
  UNION
  SELECT person_id FROM criterion_C
),

t2dm_final AS (
  SELECT DISTINCT inc.person_id
  FROM inclusion_any inc
  JOIN age_eligible ae
    ON inc.person_id = ae.person_id
  LEFT JOIN gestational_or_secondary_only gso
    ON inc.person_id = gso.person_id
  LEFT JOIN pure_type1_pattern pt1
    ON inc.person_id = pt1.person_id
  WHERE gso.person_id IS NULL
    AND pt1.person_id IS NULL
)

SELECT *
FROM t2dm_final
;