-- Type 2 Diabetes Mellitus Phenotyping Algorithm
-- Returns person_id for patients meeting T2DM criteria

WITH 

-- Type 1 diabetes exclusions (ICD-10: E10.*, ICD-9: 250.x1, 250.x3)
t1dm_patients AS (
  SELECT DISTINCT person_id
  FROM condition_occurrence
  WHERE condition_source_value ILIKE 'E10%'
     OR condition_source_value ILIKE '250._1'
     OR condition_source_value ILIKE '250._3'
),

-- Type 2 diabetes diagnosis codes
t2dm_dx AS (
  SELECT 
    person_id,
    condition_start_date AS event_date
  FROM condition_occurrence
  WHERE (
    -- ICD-10: E11.* (Type 2 diabetes mellitus)
    condition_source_value ILIKE 'E11%'
    -- ICD-9: 250.x0, 250.x2 (Type II or unspecified)
    OR condition_source_value ILIKE '250._0'
    OR condition_source_value ILIKE '250._2'
  )
  AND person_id NOT IN (SELECT person_id FROM t1dm_patients)
),

-- Count patients with 2+ diagnosis dates
t2dm_dx_criteria AS (
  SELECT person_id
  FROM (
    SELECT 
      person_id,
      COUNT(DISTINCT event_date) AS dx_count
    FROM t2dm_dx
    GROUP BY person_id
  )
  WHERE dx_count >= 2
),

-- Diabetes medications (excluding insulin-only)
diabetes_meds AS (
  SELECT DISTINCT person_id
  FROM drug_exposure
  WHERE (
    -- Metformin
    drug_source_value ILIKE '%metformin%'
    OR drug_concept_name ILIKE '%metformin%'
    -- Sulfonylureas
    OR drug_source_value ILIKE '%glyburide%'
    OR drug_source_value ILIKE '%glipizide%'
    OR drug_source_value ILIKE '%glimepiride%'
    OR drug_concept_name ILIKE '%glyburide%'
    OR drug_concept_name ILIKE '%glipizide%'
    OR drug_concept_name ILIKE '%glimepiride%'
    -- DPP-4 inhibitors
    OR drug_source_value ILIKE '%sitagliptin%'
    OR drug_source_value ILIKE '%saxagliptin%'
    OR drug_source_value ILIKE '%linagliptin%'
    OR drug_concept_name ILIKE '%sitagliptin%'
    OR drug_concept_name ILIKE '%saxagliptin%'
    OR drug_concept_name ILIKE '%linagliptin%'
    -- GLP-1 agonists
    OR drug_source_value ILIKE '%exenatide%'
    OR drug_source_value ILIKE '%liraglutide%'
    OR drug_source_value ILIKE '%dulaglutide%'
    OR drug_source_value ILIKE '%semaglutide%'
    OR drug_concept_name ILIKE '%exenatide%'
    OR drug_concept_name ILIKE '%liraglutide%'
    OR drug_concept_name ILIKE '%dulaglutide%'
    OR drug_concept_name ILIKE '%semaglutide%'
    -- SGLT2 inhibitors
    OR drug_source_value ILIKE '%canagliflozin%'
    OR drug_source_value ILIKE '%dapagliflozin%'
    OR drug_source_value ILIKE '%empagliflozin%'
    OR drug_concept_name ILIKE '%canagliflozin%'
    OR drug_concept_name ILIKE '%dapagliflozin%'
    OR drug_concept_name ILIKE '%empagliflozin%'
    -- Thiazolidinediones
    OR drug_source_value ILIKE '%pioglitazone%'
    OR drug_source_value ILIKE '%rosiglitazone%'
    OR drug_concept_name ILIKE '%pioglitazone%'
    OR drug_concept_name ILIKE '%rosiglitazone%'
  )
  AND person_id NOT IN (SELECT person_id FROM t1dm_patients)
),

-- Abnormal lab values for diabetes
abnormal_labs AS (
  SELECT DISTINCT person_id
  FROM measurement
  WHERE (
    -- HbA1c >= 6.5%
    (measurement_source_value ILIKE '%a1c%' 
     OR measurement_source_value ILIKE '%hemoglobin a1c%'
     OR measurement_source_value ILIKE '%glycohemoglobin%'
     OR measurement_source_value ILIKE '%hba1c%')
    AND value_as_number >= 6.5
  )
  OR (
    -- Fasting glucose >= 126 mg/dL
    (measurement_source_value ILIKE '%fasting%glucose%'
     OR measurement_source_value ILIKE '%fasting%blood%sugar%')
    AND value_as_number >= 126
  )
  OR (
    -- Random/non-fasting glucose >= 200 mg/dL
    (measurement_source_value ILIKE '%glucose%'
     OR measurement_source_value ILIKE '%blood%sugar%')
    AND measurement_source_value NOT ILIKE '%fasting%'
    AND value_as_number >= 200
  )
  AND person_id NOT IN (SELECT person_id FROM t1dm_patients)
),

-- Combine all criteria
t2dm_cohort AS (
  -- Criterion 1: 2+ diagnosis dates
  SELECT person_id, 'dx_2plus' AS criteria FROM t2dm_dx_criteria
  
  UNION
  
  -- Criterion 2: 1+ diagnosis + medication
  SELECT DISTINCT d.person_id, 'dx_med' AS criteria
  FROM t2dm_dx d
  INNER JOIN diabetes_meds m ON d.person_id = m.person_id
  
  UNION
  
  -- Criterion 3: 1+ diagnosis + abnormal lab
  SELECT DISTINCT d.person_id, 'dx_lab' AS criteria
  FROM t2dm_dx d
  INNER JOIN abnormal_labs l ON d.person_id = l.person_id
  
  UNION
  
  -- Criterion 4: medication + abnormal lab
  SELECT DISTINCT m.person_id, 'med_lab' AS criteria
  FROM diabetes_meds m
  INNER JOIN abnormal_labs l ON m.person_id = l.person_id
)

-- Final output: distinct person_id
SELECT DISTINCT person_id
FROM t2dm_cohort
ORDER BY person_id