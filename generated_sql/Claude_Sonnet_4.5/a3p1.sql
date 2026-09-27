-- Type 2 Diabetes Mellitus Phenotyping Algorithm
-- Identifies patients with T2DM based on diagnoses, medications, and lab values

WITH 

-- Identify Type 2 DM diagnosis codes (ICD-9: 250.x0, 250.x2; ICD-10: E11.x)
t2dm_diagnoses AS (
  SELECT DISTINCT
    person_id,
    condition_start_date AS dx_date
  FROM condition_occurrence
  WHERE (
    -- ICD-9-CM Type 2 DM codes (250.x0 or 250.x2)
    condition_source_value ILIKE '250.00%' OR
    condition_source_value ILIKE '250.02%' OR
    condition_source_value ILIKE '250.10%' OR
    condition_source_value ILIKE '250.12%' OR
    condition_source_value ILIKE '250.20%' OR
    condition_source_value ILIKE '250.22%' OR
    condition_source_value ILIKE '250.30%' OR
    condition_source_value ILIKE '250.32%' OR
    condition_source_value ILIKE '250.40%' OR
    condition_source_value ILIKE '250.42%' OR
    condition_source_value ILIKE '250.50%' OR
    condition_source_value ILIKE '250.52%' OR
    condition_source_value ILIKE '250.60%' OR
    condition_source_value ILIKE '250.62%' OR
    condition_source_value ILIKE '250.70%' OR
    condition_source_value ILIKE '250.72%' OR
    condition_source_value ILIKE '250.80%' OR
    condition_source_value ILIKE '250.82%' OR
    condition_source_value ILIKE '250.90%' OR
    condition_source_value ILIKE '250.92%' OR
    -- ICD-10-CM Type 2 DM codes (E11.x)
    condition_source_value ILIKE 'E11%' OR
    -- Source concept name contains Type 2 or Type II
    condition_source_concept_name ILIKE '%type 2%diabetes%' OR
    condition_source_concept_name ILIKE '%type ii%diabetes%' OR
    condition_source_concept_name ILIKE '%diabetes%type 2%' OR
    condition_source_concept_name ILIKE '%diabetes%type ii%'
  )
),

-- Exclude Type 1 DM diagnoses
t1dm_diagnoses AS (
  SELECT DISTINCT person_id
  FROM condition_occurrence
  WHERE (
    -- ICD-9-CM Type 1 DM codes (250.x1, 250.x3)
    condition_source_value ILIKE '250.01%' OR
    condition_source_value ILIKE '250.03%' OR
    condition_source_value ILIKE '250.11%' OR
    condition_source_value ILIKE '250.13%' OR
    condition_source_value ILIKE '250.21%' OR
    condition_source_value ILIKE '250.23%' OR
    condition_source_value ILIKE '250.31%' OR
    condition_source_value ILIKE '250.33%' OR
    condition_source_value ILIKE '250.41%' OR
    condition_source_value ILIKE '250.43%' OR
    condition_source_value ILIKE '250.51%' OR
    condition_source_value ILIKE '250.53%' OR
    condition_source_value ILIKE '250.61%' OR
    condition_source_value ILIKE '250.63%' OR
    condition_source_value ILIKE '250.71%' OR
    condition_source_value ILIKE '250.73%' OR
    condition_source_value ILIKE '250.81%' OR
    condition_source_value ILIKE '250.83%' OR
    condition_source_value ILIKE '250.91%' OR
    condition_source_value ILIKE '250.93%' OR
    -- ICD-10-CM Type 1 DM codes (E10.x)
    condition_source_value ILIKE 'E10%' OR
    -- Source concept name contains Type 1 or Type I
    condition_source_concept_name ILIKE '%type 1%diabetes%' OR
    condition_source_concept_name ILIKE '%type i%diabetes%'
  )
),

-- Identify anti-diabetic medications
diabetes_medications AS (
  SELECT DISTINCT
    person_id,
    drug_exposure_start_date AS med_date
  FROM drug_exposure
  WHERE (
    -- Metformin
    drug_source_value ILIKE '%metformin%' OR
    drug_concept_name ILIKE '%metformin%' OR
    -- Sulfonylureas
    drug_source_value ILIKE '%glyburide%' OR drug_concept_name ILIKE '%glyburide%' OR
    drug_source_value ILIKE '%glipizide%' OR drug_concept_name ILIKE '%glipizide%' OR
    drug_source_value ILIKE '%glimepiride%' OR drug_concept_name ILIKE '%glimepiride%' OR
    drug_source_value ILIKE '%gliclazide%' OR drug_concept_name ILIKE '%gliclazide%' OR
    -- DPP-4 inhibitors
    drug_source_value ILIKE '%sitagliptin%' OR drug_concept_name ILIKE '%sitagliptin%' OR
    drug_source_value ILIKE '%saxagliptin%' OR drug_concept_name ILIKE '%saxagliptin%' OR
    drug_source_value ILIKE '%linagliptin%' OR drug_concept_name ILIKE '%linagliptin%' OR
    drug_source_value ILIKE '%alogliptin%' OR drug_concept_name ILIKE '%alogliptin%' OR
    drug_source_value ILIKE '%januvia%' OR drug_concept_name ILIKE '%januvia%' OR
    -- GLP-1 agonists
    drug_source_value ILIKE '%exenatide%' OR drug_concept_name ILIKE '%exenatide%' OR
    drug_source_value ILIKE '%liraglutide%' OR drug_concept_name ILIKE '%liraglutide%' OR
    drug_source_value ILIKE '%dulaglutide%' OR drug_concept_name ILIKE '%dulaglutide%' OR
    drug_source_value ILIKE '%semaglutide%' OR drug_concept_name ILIKE '%semaglutide%' OR
    drug_source_value ILIKE '%victoza%' OR drug_concept_name ILIKE '%victoza%' OR
    drug_source_value ILIKE '%trulicity%' OR drug_concept_name ILIKE '%trulicity%' OR
    drug_source_value ILIKE '%ozempic%' OR drug_concept_name ILIKE '%ozempic%' OR
    -- SGLT2 inhibitors
    drug_source_value ILIKE '%empagliflozin%' OR drug_concept_name ILIKE '%empagliflozin%' OR
    drug_source_value ILIKE '%canagliflozin%' OR drug_concept_name ILIKE '%canagliflozin%' OR
    drug_source_value ILIKE '%dapagliflozin%' OR drug_concept_name ILIKE '%dapagliflozin%' OR
    drug_source_value ILIKE '%jardiance%' OR drug_concept_name ILIKE '%jardiance%' OR
    drug_source_value ILIKE '%invokana%' OR drug_concept_name ILIKE '%invokana%' OR
    drug_source_value ILIKE '%farxiga%' OR drug_concept_name ILIKE '%farxiga%' OR
    -- Thiazolidinediones
    drug_source_value ILIKE '%pioglitazone%' OR drug_concept_name ILIKE '%pioglitazone%' OR
    drug_source_value ILIKE '%rosiglitazone%' OR drug_concept_name ILIKE '%rosiglitazone%' OR
    drug_source_value ILIKE '%actos%' OR drug_concept_name ILIKE '%actos%' OR
    -- Insulin (various types)
    drug_source_value ILIKE '%insulin%' OR drug_concept_name ILIKE '%insulin%' OR
    -- Other combinations
    drug_source_value ILIKE '%glucophage%' OR drug_concept_name ILIKE '%glucophage%' OR
    drug_source_value ILIKE '%glucovance%' OR drug_concept_name ILIKE '%glucovance%'
  )
),

-- Identify abnormal lab values
abnormal_labs AS (
  SELECT DISTINCT
    person_id,
    measurement_date AS lab_date
  FROM measurement
  WHERE (
    -- HbA1c >= 6.5%
    (measurement_source_value ILIKE '%hba1c%' OR 
     measurement_source_value ILIKE '%hemoglobin a1c%' OR
     measurement_source_value ILIKE '%glycohemoglobin%' OR
     measurement_source_value ILIKE '%glycated hemoglobin%')
    AND value_as_number >= 6.5
  )
  OR (
    -- Fasting glucose >= 126 mg/dL
    (measurement_source_value ILIKE '%fasting%glucose%' OR
     measurement_source_value ILIKE '%fasting%blood%sugar%' OR
     measurement_source_value ILIKE '%fbg%' OR
     measurement_source_value ILIKE '%fbs%')
    AND value_as_number >= 126
  )
  OR (
    -- Random/non-fasting glucose >= 200 mg/dL
    (measurement_source_value ILIKE '%glucose%' OR
     measurement_source_value ILIKE '%blood%sugar%')
    AND measurement_source_value NOT ILIKE '%fasting%'
    AND value_as_number >= 200
  )
),

-- Count diagnoses per patient
dx_counts AS (
  SELECT
    person_id,
    COUNT(DISTINCT dx_date) AS dx_count
  FROM t2dm_diagnoses
  GROUP BY person_id
),

-- Flag patients meeting criteria
criteria_flags AS (
  SELECT DISTINCT
    p.person_id,
    CASE WHEN dc.dx_count >= 2 THEN 1 ELSE 0 END AS has_2plus_dx,
    CASE WHEN dc.dx_count >= 1 AND dm.person_id IS NOT NULL THEN 1 ELSE 0 END AS has_dx_and_med,
    CASE WHEN dc.dx_count >= 1 AND al.person_id IS NOT NULL THEN 1 ELSE 0 END AS has_dx_and_lab,
    CASE WHEN dm.person_id IS NOT NULL AND al.person_id IS NOT NULL THEN 1 ELSE 0 END AS has_med_and_lab
  FROM person p
  LEFT JOIN dx_counts dc ON p.person_id = dc.person_id
  LEFT JOIN (SELECT DISTINCT person_id FROM diabetes_medications) dm ON p.person_id = dm.person_id
  LEFT JOIN (SELECT DISTINCT person_id FROM abnormal_labs) al ON p.person_id = al.person_id
  WHERE dc.person_id IS NOT NULL 
     OR dm.person_id IS NOT NULL 
     OR al.person_id IS NOT NULL
)

-- Final cohort: meet any criteria AND not Type 1 DM
SELECT DISTINCT
  cf.person_id
FROM criteria_flags cf
WHERE (
  cf.has_2plus_dx = 1 OR
  cf.has_dx_and_med = 1 OR
  cf.has_dx_and_lab = 1 OR
  cf.has_med_and_lab = 1
)
AND cf.person_id NOT IN (SELECT person_id FROM t1dm_diagnoses)
ORDER BY cf.person_id;