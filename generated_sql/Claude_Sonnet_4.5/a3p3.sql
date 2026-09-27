-- Type 2 Diabetes Mellitus Phenotyping Algorithm
-- Identifies patients with T2DM using diagnosis codes, lab values, and medications
-- Excludes Type 1 diabetes and gestational diabetes

WITH 

-- T2DM diagnosis codes (ICD-9-CM and ICD-10-CM)
t2dm_dx AS (
  SELECT DISTINCT
    person_id,
    condition_start_date AS dx_date
  FROM condition_occurrence
  WHERE 
    -- ICD-10-CM: E11.x (Type 2 diabetes mellitus)
    (condition_source_value ILIKE 'E11%')
    OR
    -- ICD-9-CM: 250.x0 and 250.x2 (Type 2 diabetes, adult onset)
    (condition_source_value ILIKE '250.%0' OR condition_source_value ILIKE '250.%2')
    OR
    -- Text-based matching in source concept name
    (condition_source_concept_name ILIKE '%type 2 diabetes%' 
     OR condition_source_concept_name ILIKE '%type II diabetes%'
     OR condition_source_concept_name ILIKE '%diabetes mellitus type 2%'
     OR condition_source_concept_name ILIKE '%NIDDM%'
     OR condition_source_concept_name ILIKE '%non-insulin dependent diabetes%')
),

-- Type 1 diabetes exclusion codes
t1dm_dx AS (
  SELECT DISTINCT person_id
  FROM condition_occurrence
  WHERE 
    -- ICD-10-CM: E10.x (Type 1 diabetes mellitus)
    (condition_source_value ILIKE 'E10%')
    OR
    -- ICD-9-CM: 250.x1 and 250.x3 (Type 1 diabetes, juvenile onset)
    (condition_source_value ILIKE '250.%1' OR condition_source_value ILIKE '250.%3')
    OR
    -- Text-based matching
    (condition_source_concept_name ILIKE '%type 1 diabetes%'
     OR condition_source_concept_name ILIKE '%type I diabetes%'
     OR condition_source_concept_name ILIKE '%IDDM%'
     OR condition_source_concept_name ILIKE '%insulin dependent diabetes%')
),

-- Gestational diabetes exclusion
gestational_dx AS (
  SELECT DISTINCT person_id
  FROM condition_occurrence
  WHERE 
    (condition_source_value ILIKE 'O24%' OR condition_source_value ILIKE '648.8%')
    OR condition_source_concept_name ILIKE '%gestational diabetes%'
),

-- Elevated HbA1c (≥6.5%)
elevated_a1c AS (
  SELECT DISTINCT
    person_id,
    measurement_date AS lab_date
  FROM measurement
  WHERE 
    (measurement_source_value ILIKE '%hba1c%' 
     OR measurement_source_value ILIKE '%hemoglobin a1c%'
     OR measurement_source_value ILIKE '%glycohemoglobin%'
     OR measurement_source_value ILIKE '%glycated hemoglobin%')
    AND value_as_number >= 6.5
),

-- Elevated fasting glucose (≥126 mg/dL)
elevated_fasting_glucose AS (
  SELECT DISTINCT
    person_id,
    measurement_date AS lab_date
  FROM measurement
  WHERE 
    (measurement_source_value ILIKE '%fasting glucose%'
     OR measurement_source_value ILIKE '%fasting blood glucose%'
     OR measurement_source_value ILIKE '%FBG%'
     OR measurement_source_value ILIKE '%FPG%')
    AND value_as_number >= 126
),

-- Elevated random glucose (≥200 mg/dL)
elevated_random_glucose AS (
  SELECT DISTINCT
    person_id,
    measurement_date AS lab_date
  FROM measurement
  WHERE 
    (measurement_source_value ILIKE '%glucose%' 
     OR measurement_source_value ILIKE '%blood sugar%')
    AND measurement_source_value NOT ILIKE '%fasting%'
    AND value_as_number >= 200
),

-- Antidiabetic medications (excluding insulin-only)
dm_meds AS (
  SELECT DISTINCT person_id
  FROM drug_exposure
  WHERE 
    -- Metformin
    (drug_source_value ILIKE '%metformin%' OR drug_concept_name ILIKE '%metformin%')
    OR
    -- Sulfonylureas
    (drug_source_value ILIKE '%glyburide%' OR drug_concept_name ILIKE '%glyburide%'
     OR drug_source_value ILIKE '%glipizide%' OR drug_concept_name ILIKE '%glipizide%'
     OR drug_source_value ILIKE '%glimepiride%' OR drug_concept_name ILIKE '%glimepiride%')
    OR
    -- DPP-4 inhibitors
    (drug_source_value ILIKE '%sitagliptin%' OR drug_concept_name ILIKE '%sitagliptin%'
     OR drug_source_value ILIKE '%saxagliptin%' OR drug_concept_name ILIKE '%saxagliptin%'
     OR drug_source_value ILIKE '%linagliptin%' OR drug_concept_name ILIKE '%linagliptin%')
    OR
    -- GLP-1 agonists
    (drug_source_value ILIKE '%exenatide%' OR drug_concept_name ILIKE '%exenatide%'
     OR drug_source_value ILIKE '%liraglutide%' OR drug_concept_name ILIKE '%liraglutide%'
     OR drug_source_value ILIKE '%dulaglutide%' OR drug_concept_name ILIKE '%dulaglutide%'
     OR drug_source_value ILIKE '%semaglutide%' OR drug_concept_name ILIKE '%semaglutide%')
    OR
    -- SGLT2 inhibitors
    (drug_source_value ILIKE '%empagliflozin%' OR drug_concept_name ILIKE '%empagliflozin%'
     OR drug_source_value ILIKE '%canagliflozin%' OR drug_concept_name ILIKE '%canagliflozin%'
     OR drug_source_value ILIKE '%dapagliflozin%' OR drug_concept_name ILIKE '%dapagliflozin%')
    OR
    -- Thiazolidinediones
    (drug_source_value ILIKE '%pioglitazone%' OR drug_concept_name ILIKE '%pioglitazone%'
     OR drug_source_value ILIKE '%rosiglitazone%' OR drug_concept_name ILIKE '%rosiglitazone%')
),

-- Combine lab criteria
abnormal_labs AS (
  SELECT person_id FROM elevated_a1c
  UNION
  SELECT person_id FROM elevated_fasting_glucose
  UNION
  SELECT person_id FROM elevated_random_glucose
),

-- Count distinct diagnosis dates per patient
dx_counts AS (
  SELECT 
    person_id,
    COUNT(DISTINCT dx_date) AS num_dx_dates
  FROM t2dm_dx
  GROUP BY person_id
),

-- Patients meeting inclusion criteria
included_patients AS (
  -- Criterion 1: 2+ T2DM diagnoses on different dates
  SELECT DISTINCT person_id, 'multiple_diagnoses' AS criteria
  FROM dx_counts
  WHERE num_dx_dates >= 2
  
  UNION
  
  -- Criterion 2: 1+ T2DM diagnosis + abnormal lab
  SELECT DISTINCT t.person_id, 'diagnosis_plus_lab' AS criteria
  FROM t2dm_dx t
  INNER JOIN abnormal_labs l ON t.person_id = l.person_id
  
  UNION
  
  -- Criterion 3: 1+ T2DM diagnosis + antidiabetic medication
  SELECT DISTINCT t.person_id, 'diagnosis_plus_med' AS criteria
  FROM t2dm_dx t
  INNER JOIN dm_meds m ON t.person_id = m.person_id
  
  UNION
  
  -- Criterion 4: Abnormal labs + antidiabetic medication (no diagnosis required)
  SELECT DISTINCT l.person_id, 'lab_plus_med' AS criteria
  FROM abnormal_labs l
  INNER JOIN dm_meds m ON l.person_id = m.person_id
)

-- Final cohort: Include T2DM patients, exclude T1DM and gestational
SELECT DISTINCT person_id
FROM included_patients
WHERE person_id NOT IN (SELECT person_id FROM t1dm_dx)
  AND person_id NOT IN (SELECT person_id FROM gestational_dx)
ORDER BY person_id;