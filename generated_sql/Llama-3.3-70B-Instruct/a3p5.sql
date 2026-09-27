-- Define the criteria for Type 2 Diabetes Mellitus
WITH diabetes_diagnoses AS (
  SELECT DISTINCT person_id
  FROM condition_occurrence
  WHERE condition_source_value ILIKE ANY (ARRAY['250.%', 'E11.%'])  -- ICD9CM and ICD10CM codes for Type 2 Diabetes
),
  
diabetes_medications AS (
  SELECT DISTINCT person_id
  FROM drug_exposure
  WHERE drug_source_value ILIKE ANY (ARRAY['metformin', 'glipizide', 'glyburide', 'glimepiride', 'pioglitazone', 'rosiglitazone', 'sitagliptin', 'saxagliptin', 'linagliptin', 'exenatide', 'liraglutide'])  -- Generic names of common Type 2 Diabetes medications
  OR drug_source_value ILIKE ANY (ARRAY['Glucophage', 'Glucotrol', 'DiaBeta', 'Amaryl', 'Actos', 'Avandia', 'Januvia', 'Onglyza', 'Tradjenta', 'Byetta', 'Victoza'])  -- Brand names of common Type 2 Diabetes medications
),
  
diabetes_labs AS (
  SELECT DISTINCT person_id
  FROM measurement
  WHERE measurement_source_value ILIKE ANY (ARRAY['Hemoglobin A1c', 'HbA1c'])  -- Lab tests for Diabetes
  AND value_as_number > 6.5  -- Threshold for Diabetes diagnosis
  AND unit_source_value = '%'  -- Unit for HbA1c measurement
),
  
diabetes_obs AS (
  SELECT DISTINCT person_id
  FROM observation
  WHERE observation_source_value ILIKE ANY (ARRAY['Diabetes', 'Type 2 Diabetes'])  -- Observation text for Diabetes
)
  
-- Combine the criteria to identify patients with Type 2 Diabetes
SELECT DISTINCT person_id
FROM (
  SELECT person_id FROM diabetes_diagnoses
  UNION
  SELECT person_id FROM diabetes_medications
  UNION
  SELECT person_id FROM diabetes_labs
  UNION-- Define the criteria for Type 2 Diabetes Mellitus
WITH diabetes_diagnoses AS (
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE condition_source_value ILIKE '250.%'
       OR condition_source_value ILIKE 'E11.%'
),

diabetes_medications AS (
    SELECT DISTINCT person_id
    FROM drug_exposure
    WHERE LOWER(drug_source_value) IN (
        'metformin',
        'glipizide',
        'glyburide',
        'glimepiride',
        'pioglitazone',
        'rosiglitazone',
        'sitagliptin',
        'saxagliptin',
        'linagliptin',
        'exenatide',
        'liraglutide',
        'glucophage',
        'glucotrol',
        'diabeta',
        'amaryl',
        'actos',
        'avandia',
        'januvia',
        'onglyza',
        'tradjenta',
        'byetta',
        'victoza'
    )
),

diabetes_labs AS (
    SELECT DISTINCT person_id
    FROM measurement
    WHERE LOWER(measurement_source_value) IN (
        'hemoglobin a1c',
        'hba1c'
    )
      AND value_as_number > 6.5
      AND unit_source_value = '%'
),

diabetes_obs AS (
    SELECT DISTINCT person_id
    FROM observation
    WHERE LOWER(observation_source_value) IN (
        'diabetes',
        'type 2 diabetes'
    )
)

-- Combine the criteria to identify patients with Type 2 Diabetes
SELECT person_id FROM diabetes_diagnoses

UNION

SELECT person_id FROM diabetes_medications

UNION

SELECT person_id FROM diabetes_labs

UNION

SELECT person_id FROM diabetes_obs;
  SELECT person_id FROM diabetes_obs
) AS diabetes Patients;