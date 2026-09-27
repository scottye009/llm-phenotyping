-- Define the criteria for Type 2 Diabetes Mellitus
WITH 
  -- Diagnosis criteria
  diagnosis AS (
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE condition_source_value ILIKE '%250.%'  -- ICD-9 code for Type 2 Diabetes
       OR condition_source_value ILIKE 'E11.%'  -- ICD-10 code for Type 2 Diabetes
  ),
  
  -- Medication criteria
  medication AS (
    SELECT DISTINCT person_id
    FROM drug_exposure
    WHERE drug_source_value ILIKE '%metformin%'  -- Common medication for Type 2 Diabetes
       OR drug_source_value ILIKE '%glipizide%'  -- Common medication for Type 2 Diabetes
       OR drug_source_value ILIKE '%glyburide%'  -- Common medication for Type 2 Diabetes
       OR drug_source_value ILIKE '%pioglitazone%'  -- Common medication for Type 2 Diabetes
  ),
  
  -- Laboratory criteria
  laboratory AS (
    SELECT DISTINCT person_id
    FROM measurement
    WHERE (measurement_source_value ILIKE '%hemoglobin a1c%'  -- HbA1c test
           AND value_as_number > 6.5)  -- HbA1c threshold for Type 2 Diabetes
       OR (measurement_source_value ILIKE '%fasting plasma glucose%'  -- FPG test
           AND value_as_number > 126)  -- FPG threshold for Type 2 Diabetes
       OR (measurement_source_value ILIKE '%2-hour plasma glucose%'  -- 2-hour PG test
           AND value_as_number > 200)  -- 2-hour PG threshold for Type 2 Diabetes
  )

-- Combine the criteria to identify individuals with Type 2 Diabetes Mellitus
SELECT person_id
FROM (
  SELECT person_id, 
         COUNT(*) AS num_criteria
  FROM (
    SELECT person_id FROM diagnosis
    UNION ALL
    SELECT person_id FROM medication
    UNION ALL
    SELECT person_id FROM laboratory
  ) AS combined_criteria
  GROUP BY person_id
) AS combined
WHERE num_criteria >= 1;  -- At least one criterion must be met