
-- Type 2 Diabetes Phenotyping Algorithm (SHIRE / OMOP-lite)
-- DuckDB: run over CSV-backed views in schema `memory`
-- Changes vs original:
--   * remove all concept joins and concept-dependent unit logic
--   * use *_source_value text matching + value_as_number thresholds
--   * DuckDB-friendly syntax (no ARRAY/ILIKE ANY; use OR chains)
--   * keep overall logic: evidence from dx, labs, meds; require >=2 distinct dates; exclude T1/GDM/secondary

WITH
t2dm_diagnosis AS (
  SELECT DISTINCT
    co.person_id,
    try_cast(co.condition_start_date AS DATE) AS index_date,
    'Diagnosis' AS criteria_type
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

abnormal_labs AS (
  SELECT DISTINCT
    m.person_id,
    try_cast(m.measurement_date AS DATE) AS index_date,
    'Laboratory' AS criteria_type
  FROM memory.measurement m
  WHERE
    m.value_as_number IS NOT NULL
    AND (
      (
        (m.measurement_source_value ILIKE '%hemoglobin a1c%'
         OR m.measurement_source_value ILIKE '%hba1c%'
         OR m.measurement_source_value ILIKE '%a1c%'
         OR m.measurement_source_value ILIKE '%glycohemoglobin%')
        AND m.value_as_number >= 6.5
      )
      OR
      (
        (m.measurement_source_value ILIKE '%fasting glucose%'
         OR m.measurement_source_value ILIKE '%fasting blood glucose%'
         OR (m.measurement_source_value ILIKE '%glucose%' AND m.measurement_source_value ILIKE '%fast%'))
        AND m.value_as_number >= 126
      )
      OR
      (
        (m.measurement_source_value ILIKE '%glucose%' OR m.measurement_source_value ILIKE '%blood glucose%')
        AND m.measurement_source_value NOT ILIKE '%fast%'
        AND m.value_as_number >= 200
      )
    )
),

diabetes_medications AS (
  SELECT DISTINCT
    de.person_id,
    try_cast(COALESCE(de.drug_exposure_start_date, de.drug_exposure_start_datetime) AS DATE) AS index_date,
    'Medication' AS criteria_type
  FROM memory.drug_exposure de
  WHERE
    (
      -- Metformin + brands
      de.drug_source_value ILIKE '%metformin%'
      OR de.drug_source_value ILIKE '%glucophage%'
      OR de.drug_source_value ILIKE '%fortamet%'
      OR de.drug_source_value ILIKE '%glumetza%'
      OR de.drug_source_value ILIKE '%riomet%'

      -- Sulfonylureas + brands
      OR de.drug_source_value ILIKE '%glipizide%'
      OR de.drug_source_value ILIKE '%glyburide%'
      OR de.drug_source_value ILIKE '%glimepiride%'
      OR de.drug_source_value ILIKE '%gliclazide%'
      OR de.drug_source_value ILIKE '%glucotrol%'
      OR de.drug_source_value ILIKE '%diabeta%'
      OR de.drug_source_value ILIKE '%micronase%'
      OR de.drug_source_value ILIKE '%amaryl%'

      -- DPP-4 inhibitors + brands
      OR de.drug_source_value ILIKE '%sitagliptin%'
      OR de.drug_source_value ILIKE '%saxagliptin%'
      OR de.drug_source_value ILIKE '%linagliptin%'
      OR de.drug_source_value ILIKE '%alogliptin%'
      OR de.drug_source_value ILIKE '%januvia%'
      OR de.drug_source_value ILIKE '%onglyza%'
      OR de.drug_source_value ILIKE '%tradjenta%'
      OR de.drug_source_value ILIKE '%nesina%'

      -- GLP-1 agonists + brands
      OR de.drug_source_value ILIKE '%exenatide%'
      OR de.drug_source_value ILIKE '%liraglutide%'
      OR de.drug_source_value ILIKE '%dulaglutide%'
      OR de.drug_source_value ILIKE '%semaglutide%'
      OR de.drug_source_value ILIKE '%byetta%'
      OR de.drug_source_value ILIKE '%victoza%'
      OR de.drug_source_value ILIKE '%trulicity%'
      OR de.drug_source_value ILIKE '%ozempic%'
      OR de.drug_source_value ILIKE '%wegovy%'

      -- SGLT2 inhibitors + brands
      OR de.drug_source_value ILIKE '%canagliflozin%'
      OR de.drug_source_value ILIKE '%dapagliflozin%'
      OR de.drug_source_value ILIKE '%empagliflozin%'
      OR de.drug_source_value ILIKE '%ertugliflozin%'
      OR de.drug_source_value ILIKE '%invokana%'
      OR de.drug_source_value ILIKE '%farxiga%'
      OR de.drug_source_value ILIKE '%jardiance%'
      OR de.drug_source_value ILIKE '%steglatro%'

      -- TZDs + brands
      OR de.drug_source_value ILIKE '%pioglitazone%'
      OR de.drug_source_value ILIKE '%rosiglitazone%'
      OR de.drug_source_value ILIKE '%actos%'
      OR de.drug_source_value ILIKE '%avandia%'

      -- Meglitinides + brands
      OR de.drug_source_value ILIKE '%repaglinide%'
      OR de.drug_source_value ILIKE '%nateglinide%'
      OR de.drug_source_value ILIKE '%prandin%'
      OR de.drug_source_value ILIKE '%starlix%'
    )
),

exclusions AS (
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
    OR co.condition_source_value ILIKE 'O24.4%'
    OR co.condition_source_value ILIKE '648.8%'
    OR co.condition_source_value ILIKE 'E08%'
    OR co.condition_source_value ILIKE 'E09%'
    OR co.condition_source_value ILIKE 'E13%'
),

all_evidence AS (
  SELECT * FROM t2dm_diagnosis
  UNION ALL
  SELECT * FROM abnormal_labs
  UNION ALL
  SELECT * FROM diabetes_medications
),

qualified_patients AS (
  SELECT
    person_id,
    MIN(index_date) AS first_index_date,
    COUNT(DISTINCT index_date) AS evidence_count,
    string_agg(DISTINCT criteria_type, ', ' ORDER BY criteria_type) AS criteria_met
  FROM all_evidence
  GROUP BY person_id
  HAVING COUNT(DISTINCT index_date) >= 2
)

SELECT
  qp.person_id,
  qp.first_index_date,
  qp.evidence_count,
  qp.criteria_met,
  p.year_of_birth,
  p.gender_concept_id,
  p.race_concept_id,
  p.ethnicity_concept_id
FROM qualified_patients qp
JOIN memory.person p
  ON p.person_id = qp.person_id
LEFT JOIN exclusions e
  ON e.person_id = qp.person_id
WHERE e.person_id IS NULL
ORDER BY qp.person_id
;