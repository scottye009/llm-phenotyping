-- Type 2 Diabetes Mellitus Phenotyping Algorithm

WITH 
-- Identify individuals with a diagnosis of Type 2 Diabetes
diagnosed_t2d AS (
  SELECT DISTINCT person_id
  FROM condition_occurrence
  WHERE condition_source_value ILIKE '%250.%'  -- ICD9CM code for diabetes mellitus without specification of type
     OR condition_source_value ILIKE 'E11.%'   -- ICD10CM code for Type 2 diabetes mellitus
),

-- Identify individuals exposed to diabetes medications
treated_t2d AS (
  SELECT DISTINCT person_id
  FROM drug_exposure
  WHERE drug_source_value ILIKE '%metformin%' 
     OR drug_source_value ILIKE '%glipizide%' 
     OR drug_source_value ILIKE '%glyburide%' 
     OR drug_source_value ILIKE '%glimepiride%' 
     OR drug_source_value ILIKE '%insulin%'
),

-- Identify individuals with elevated HbA1c or glucose levels
lab_confirmed_t2d AS (
  SELECT DISTINCT person_id
  FROM measurement
  WHERE (measurement_source_value ILIKE '%HbA1c%' AND value_as_number >= 6.5)
     OR (measurement_source_value ILIKE '%fasting glucose%' AND value_as_number >= 126)
     OR (measurement_source_value ILIKE '%plasma glucose%' AND value_as_number >= 200)
)

-- Combine all criteria to identify individuals with Type 2 Diabetes Mellitus
SELECT DISTINCT person_id
FROM (
  SELECT person_id FROM diagnosed_t2d
  UNION
  SELECT person_id FROM treated_t2d
  UNION
  SELECT person_id FROM lab_confirmed_t2d
) AS combined_criteria;