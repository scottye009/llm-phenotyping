
/* SHIRE / OMOP-lite rewrite of Copilot/alpha_3.sql
   - Remove concept tables (ICD/LOINC/RxNorm not available)
   - Use source values for dx, meds, labs
   - Preserve inclusion: (>=2 dx) OR (>=1 dx AND >=1 drug) OR (>=2 abnormal labs)
   - Preserve exclusion block shaped like original (but on source-coded T1 / gestational)
*/

WITH
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

t1_or_gestational_dx AS (
  SELECT
    co.person_id,
    try_cast(co.condition_start_date AS DATE) AS dx_date,
    CASE
      WHEN (co.condition_source_value ILIKE 'E10%' OR co.condition_source_value LIKE '250.%1' OR co.condition_source_value LIKE '250.%3')
        THEN 'T1DM'
      WHEN (co.condition_source_value ILIKE 'O24.4%' OR co.condition_source_value ILIKE '648.8%')
        THEN 'GESTATIONAL'
      ELSE NULL
    END AS dx_type
  FROM memory.condition_occurrence co
  WHERE
    (co.condition_source_value ILIKE 'E10%' OR co.condition_source_value LIKE '250.%1' OR co.condition_source_value LIKE '250.%3')
    OR (co.condition_source_value ILIKE 'O24.4%' OR co.condition_source_value ILIKE '648.8%')
),

t2dm_drug AS (
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
      OR de.drug_source_value ILIKE '%exenatide%'
      OR de.drug_source_value ILIKE '%liraglutide%'
      OR de.drug_source_value ILIKE '%dulaglutide%'
      OR de.drug_source_value ILIKE '%semaglutide%'
      OR de.drug_source_value ILIKE '%canagliflozin%'
      OR de.drug_source_value ILIKE '%dapagliflozin%'
      OR de.drug_source_value ILIKE '%empagliflozin%'
      OR de.drug_source_value ILIKE '%ertugliflozin%'
      OR de.drug_source_value ILIKE '%insulin%'
    )
),

t2dm_abnormal_labs AS (
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
      OR
      (
        m.measurement_source_value ILIKE '%fast%'
        AND m.measurement_source_value ILIKE '%glucose%'
        AND m.value_as_number >= 126
      )
      OR
      (
        m.measurement_source_value ILIKE '%glucose%'
        AND m.value_as_number >= 200
      )
    )
),

dx_counts AS (
  SELECT person_id, COUNT(DISTINCT dx_date) AS t2dm_dx_dates
  FROM t2dm_dx
  GROUP BY person_id
),

lab_counts AS (
  SELECT person_id, COUNT(DISTINCT lab_date) AS abnormal_lab_dates
  FROM t2dm_abnormal_labs
  GROUP BY person_id
),

drug_counts AS (
  SELECT person_id, COUNT(DISTINCT drug_date) AS t2dm_drug_dates
  FROM t2dm_drug
  GROUP BY person_id
),

t1_or_gestational_flags AS (
  SELECT
    person_id,
    MAX(CASE WHEN dx_type = 'T1DM' THEN 1 ELSE 0 END) AS has_t1dm_dx,
    MAX(CASE WHEN dx_type = 'GESTATIONAL' THEN 1 ELSE 0 END) AS has_gestational_dx
  FROM t1_or_gestational_dx
  GROUP BY person_id
),

t2dm_candidates AS (
  SELECT
    p.person_id,
    COALESCE(dx_counts.t2dm_dx_dates, 0) AS t2dm_dx_dates,
    COALESCE(drug_counts.t2dm_drug_dates, 0) AS t2dm_drug_dates,
    COALESCE(lab_counts.abnormal_lab_dates, 0) AS abnormal_lab_dates,
    COALESCE(t1_or_gestational_flags.has_t1dm_dx, 0) AS has_t1dm_dx,
    COALESCE(t1_or_gestational_flags.has_gestational_dx, 0) AS has_gestational_dx
  FROM memory.person p
  LEFT JOIN dx_counts ON p.person_id = dx_counts.person_id
  LEFT JOIN drug_counts ON p.person_id = drug_counts.person_id
  LEFT JOIN lab_counts ON p.person_id = lab_counts.person_id
  LEFT JOIN t1_or_gestational_flags ON p.person_id = t1_or_gestational_flags.person_id
)

SELECT *
FROM t2dm_candidates
WHERE
  (
    t2dm_dx_dates >= 2
    OR (t2dm_dx_dates >= 1 AND t2dm_drug_dates >= 1)
    OR abnormal_lab_dates >= 2
  )
  AND NOT (
    t2dm_dx_dates = 0
    AND t2dm_drug_dates = 0
    AND abnormal_lab_dates = 0
    AND (has_t1dm_dx = 1 OR has_gestational_dx = 1)
  )
;