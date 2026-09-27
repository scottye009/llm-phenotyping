-- Type 2 Diabetes Mellitus Phenotyping Algorithm
-- Uses diagnosis codes, lab values, and medications
-- Excludes type 1 diabetes and gestational diabetes

WITH 

-- Step 1: Identify type 2 diabetes diagnosis codes
t2dm_dx AS (
    SELECT DISTINCT
        person_id,
        condition_start_date
    FROM condition_occurrence
    WHERE (
        -- ICD-9-CM codes for type 2 diabetes (250.x0 and 250.x2)
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
        -- ICD-10-CM codes for type 2 diabetes (E11.%)
        condition_source_value ILIKE 'E11%'
    )
),

-- Step 2: Identify type 1 diabetes and gestational diabetes (exclusions)
exclusion_dx AS (
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE (
        -- ICD-9-CM type 1 diabetes (250.x1 and 250.x3)
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
        -- ICD-10-CM type 1 diabetes
        condition_source_value ILIKE 'E10%' OR
        -- Gestational diabetes
        condition_source_value ILIKE '648.8%' OR
        condition_source_value ILIKE 'O24%'
    )
),

-- Step 3: Identify abnormal glucose/HbA1c lab values
abnormal_labs AS (
    SELECT DISTINCT
        person_id,
        measurement_date
    FROM measurement
    WHERE (
        -- Elevated fasting glucose >= 126 mg/dL
        (measurement_source_value ILIKE '%fasting%glucose%' OR
         measurement_source_value ILIKE '%fasting%blood%sugar%' OR
         measurement_source_value ILIKE '%FBS%' OR
         measurement_source_value ILIKE '%FBG%')
        AND value_as_number >= 126
    ) OR (
        -- Elevated random/non-fasting glucose >= 200 mg/dL
        (measurement_source_value ILIKE '%glucose%' OR
         measurement_source_value ILIKE '%blood%sugar%')
        AND measurement_source_value NOT ILIKE '%fasting%'
        AND value_as_number >= 200
    ) OR (
        -- Elevated HbA1c >= 6.5%
        (measurement_source_value ILIKE '%HbA1c%' OR
         measurement_source_value ILIKE '%hemoglobin%A1c%' OR
         measurement_source_value ILIKE '%glycohemoglobin%' OR
         measurement_source_value ILIKE '%A1C%')
        AND value_as_number >= 6.5
    )
),

-- Step 4: Identify diabetes medications
diabetes_meds AS (
    SELECT DISTINCT person_id
    FROM drug_exposure
    WHERE 
        -- Metformin
        drug_source_value ILIKE '%metformin%' OR
        drug_concept_name ILIKE '%metformin%' OR
        -- Sulfonylureas
        drug_source_value ILIKE '%glipizide%' OR
        drug_source_value ILIKE '%glyburide%' OR
        drug_source_value ILIKE '%glimepiride%' OR
        drug_source_value ILIKE '%glibenclamide%' OR
        drug_concept_name ILIKE '%glipizide%' OR
        drug_concept_name ILIKE '%glyburide%' OR
        drug_concept_name ILIKE '%glimepiride%' OR
        -- DPP-4 inhibitors
        drug_source_value ILIKE '%sitagliptin%' OR
        drug_source_value ILIKE '%saxagliptin%' OR
        drug_source_value ILIKE '%linagliptin%' OR
        drug_source_value ILIKE '%alogliptin%' OR
        drug_concept_name ILIKE '%sitagliptin%' OR
        drug_concept_name ILIKE '%saxagliptin%' OR
        drug_concept_name ILIKE '%linagliptin%' OR
        -- GLP-1 agonists
        drug_source_value ILIKE '%exenatide%' OR
        drug_source_value ILIKE '%liraglutide%' OR
        drug_source_value ILIKE '%dulaglutide%' OR
        drug_source_value ILIKE '%semaglutide%' OR
        drug_concept_name ILIKE '%exenatide%' OR
        drug_concept_name ILIKE '%liraglutide%' OR
        drug_concept_name ILIKE '%semaglutide%' OR
        -- SGLT2 inhibitors
        drug_source_value ILIKE '%canagliflozin%' OR
        drug_source_value ILIKE '%dapagliflozin%' OR
        drug_source_value ILIKE '%empagliflozin%' OR
        drug_concept_name ILIKE '%canagliflozin%' OR
        drug_concept_name ILIKE '%dapagliflozin%' OR
        drug_concept_name ILIKE '%empagliflozin%' OR
        -- Thiazolidinediones
        drug_source_value ILIKE '%pioglitazone%' OR
        drug_source_value ILIKE '%rosiglitazone%' OR
        drug_concept_name ILIKE '%pioglitazone%' OR
        drug_concept_name ILIKE '%rosiglitazone%' OR
        -- Insulin (for type 2 diabetes)
        drug_source_value ILIKE '%insulin%' OR
        drug_concept_name ILIKE '%insulin%'
),

-- Step 5: Count diagnosis occurrences per person
dx_counts AS (
    SELECT 
        person_id,
        COUNT(DISTINCT condition_start_date) AS dx_count
    FROM t2dm_dx
    GROUP BY person_id
),

-- Step 6: Count abnormal lab occurrences per person
lab_counts AS (
    SELECT
        person_id,
        COUNT(DISTINCT measurement_date) AS lab_count
    FROM abnormal_labs
    GROUP BY person_id
),

-- Step 7: Apply phenotyping logic
t2dm_cohort AS (
    SELECT DISTINCT person_id
    FROM (
        -- Criterion 1: >= 2 diagnosis codes on different dates
        SELECT person_id FROM dx_counts WHERE dx_count >= 2
        
        UNION
        
        -- Criterion 2: >= 1 diagnosis + abnormal lab
        SELECT d.person_id 
        FROM t2dm_dx d
        INNER JOIN abnormal_labs l ON d.person_id = l.person_id
        
        UNION
        
        -- Criterion 3: >= 1 diagnosis + diabetes medication
        SELECT d.person_id
        FROM t2dm_dx d
        INNER JOIN diabetes_meds m ON d.person_id = m.person_id
        
        UNION
        
        -- Criterion 4: >= 2 abnormal labs + diabetes medication
        SELECT l.person_id
        FROM lab_counts l
        INNER JOIN diabetes_meds m ON l.person_id = m.person_id
        WHERE l.lab_count >= 2
    ) AS combined
)

-- Final output: Return person_id excluding type 1/gestational diabetes
SELECT DISTINCT person_id
FROM t2dm_cohort
WHERE person_id NOT IN (SELECT person_id FROM exclusion_dx)
ORDER BY person_id;