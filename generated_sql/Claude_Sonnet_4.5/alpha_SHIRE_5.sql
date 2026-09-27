
-- Type 2 Diabetes Phenotyping Algorithm (SHIRE / OMOP-lite, DuckDB)
-- Changes:
--   * remove concept joins
--   * replace LEFT JOIN fanout with EXISTS + scalar subqueries
--   * keep original inclusion branches and exclusions
--   * keep cohort_start_date = earliest evidence date across dx/med/lab among included persons

WITH
type2_diabetes_dx AS (
  SELECT DISTINCT
    co.person_id,
    try_cast(co.condition_start_date AS DATE) AS dx_date
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

type1_diabetes_exclusion AS (
  SELECT DISTINCT co.person_id
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

gestational_diabetes_exclusion AS (
  SELECT DISTINCT co.person_id
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'O24.4%'
    OR co.condition_source_value ILIKE '648.8%'
),

t2dm_medications AS (
  SELECT DISTINCT
    de.person_id,
    try_cast(COALESCE(de.drug_exposure_start_date, de.drug_exposure_start_datetime) AS DATE) AS med_date
  FROM memory.drug_exposure de
  WHERE
    de.drug_source_value ILIKE '%metformin%'
    OR de.drug_source_value ILIKE '%glucophage%'
    OR de.drug_source_value ILIKE '%fortamet%'
    OR de.drug_source_value ILIKE '%glumetza%'
    OR de.drug_source_value ILIKE '%glipizide%'
    OR de.drug_source_value ILIKE '%glucotrol%'
    OR de.drug_source_value ILIKE '%glyburide%'
    OR de.drug_source_value ILIKE '%diabeta%'
    OR de.drug_source_value ILIKE '%glimepiride%'
    OR de.drug_source_value ILIKE '%amaryl%'
    OR de.drug_source_value ILIKE '%sitagliptin%'
    OR de.drug_source_value ILIKE '%januvia%'
    OR de.drug_source_value ILIKE '%saxagliptin%'
    OR de.drug_source_value ILIKE '%onglyza%'
    OR de.drug_source_value ILIKE '%linagliptin%'
    OR de.drug_source_value ILIKE '%tradjenta%'
    OR de.drug_source_value ILIKE '%exenatide%'
    OR de.drug_source_value ILIKE '%byetta%'
    OR de.drug_source_value ILIKE '%liraglutide%'
    OR de.drug_source_value ILIKE '%victoza%'
    OR de.drug_source_value ILIKE '%dulaglutide%'
    OR de.drug_source_value ILIKE '%trulicity%'
    OR de.drug_source_value ILIKE '%semaglutide%'
    OR de.drug_source_value ILIKE '%ozempic%'
    OR de.drug_source_value ILIKE '%canagliflozin%'
    OR de.drug_source_value ILIKE '%invokana%'
    OR de.drug_source_value ILIKE '%dapagliflozin%'
    OR de.drug_source_value ILIKE '%farxiga%'
    OR de.drug_source_value ILIKE '%empagliflozin%'
    OR de.drug_source_value ILIKE '%jardiance%'
    OR de.drug_source_value ILIKE '%pioglitazone%'
    OR de.drug_source_value ILIKE '%actos%'
    OR de.drug_source_value ILIKE '%rosiglitazone%'
    OR de.drug_source_value ILIKE '%avandia%'
),

diabetes_labs AS (
  SELECT DISTINCT
    m.person_id,
    try_cast(m.measurement_date AS DATE) AS lab_date
  FROM memory.measurement m
  WHERE
    m.value_as_number IS NOT NULL
    AND (
      (
        (m.measurement_source_value ILIKE '%hba1c%'
         OR m.measurement_source_value ILIKE '%hemoglobin a1c%'
         OR m.measurement_source_value ILIKE '%glycohemoglobin%'
         OR m.measurement_source_value ILIKE '%a1c%')
        AND m.value_as_number >= 6.5
      )
      OR (
        (m.measurement_source_value ILIKE '%fasting glucose%'
         OR m.measurement_source_value ILIKE '%fasting blood glucose%'
         OR (m.measurement_source_value ILIKE '%glucose%' AND m.measurement_source_value ILIKE '%fast%'))
        AND m.value_as_number >= 126
      )
      OR (
        (m.measurement_source_value ILIKE '%glucose%' OR m.measurement_source_value ILIKE '%blood glucose%')
        AND m.measurement_source_value NOT ILIKE '%fast%'
        AND m.value_as_number >= 200
      )
    )
),

eligible_persons AS (
  SELECT p.person_id
  FROM memory.person p
  WHERE
    p.person_id NOT IN (SELECT person_id FROM type1_diabetes_exclusion)
    AND p.person_id NOT IN (SELECT person_id FROM gestational_diabetes_exclusion)
    AND (
      (SELECT COUNT(DISTINCT dx_date) FROM type2_diabetes_dx d WHERE d.person_id = p.person_id) >= 2
      OR (EXISTS (SELECT 1 FROM type2_diabetes_dx d WHERE d.person_id = p.person_id)
          AND EXISTS (SELECT 1 FROM t2dm_medications m WHERE m.person_id = p.person_id))
      OR (EXISTS (SELECT 1 FROM type2_diabetes_dx d WHERE d.person_id = p.person_id)
          AND EXISTS (SELECT 1 FROM diabetes_labs l WHERE l.person_id = p.person_id))
      OR (EXISTS (SELECT 1 FROM t2dm_medications m WHERE m.person_id = p.person_id)
          AND EXISTS (SELECT 1 FROM diabetes_labs l WHERE l.person_id = p.person_id))
    )
),

cohort_dates AS (
  SELECT
    ep.person_id,
    MIN(d) AS cohort_start_date
  FROM eligible_persons ep
  JOIN (
    SELECT person_id, dx_date AS d FROM type2_diabetes_dx
    UNION ALL
    SELECT person_id, med_date AS d FROM t2dm_medications
    UNION ALL
    SELECT person_id, lab_date AS d FROM diabetes_labs
  ) all_dates
    ON all_dates.person_id = ep.person_id
  GROUP BY ep.person_id
)

SELECT
  cd.person_id,
  cd.cohort_start_date,
  'Type 2 Diabetes' AS cohort_definition_name,
  p.year_of_birth,
  p.gender_concept_id,
  EXTRACT(YEAR FROM cd.cohort_start_date) - p.year_of_birth AS age_at_diagnosis
FROM cohort_dates cd
JOIN memory.person p
  ON p.person_id = cd.person_id
ORDER BY cd.person_id
;