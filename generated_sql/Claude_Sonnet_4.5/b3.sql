-- Type 2 Diabetes Mellitus Phenotyping Algorithm (Refined)
-- Identifies T2DM patients using diagnosis codes, medications, and lab values
-- Excludes Type 1 DM and gestational diabetes
-- Optimized for SHIRE database with DuckDB syntax

WITH

-- Type 2 DM diagnosis codes
t2dm_diagnosis AS (
    SELECT DISTINCT
        person_id,
        condition_start_date AS event_date
    FROM condition_occurrence
    WHERE (
        -- ICD-10-CM: E11.x (Type 2 diabetes mellitus)
        condition_source_value ILIKE 'E11%'
        OR
        -- ICD-9-CM: 250.x0 and 250.x2 (Type 2/unspecified diabetes)
        -- Match patterns: 250.00, 25000, 250.02, 25002, etc.
        regexp_matches(condition_source_value, '^250[.\s]?[0-9]0')
        OR regexp_matches(condition_source_value, '^250[.\s]?[0-9]2')
        OR
        -- Text-based matching in source concept name
        (condition_source_concept_name ILIKE '%type 2%diabetes%'
         OR condition_source_concept_name ILIKE '%type II%diabetes%'
         OR condition_source_concept_name ILIKE '%diabetes%type 2%'
         OR condition_source_concept_name ILIKE '%diabetes%type II%'
         OR condition_source_concept_name ILIKE '%NIDDM%'
         OR condition_source_concept_name ILIKE '%non-insulin%dependent%diabetes%'
         OR condition_source_concept_name ILIKE '%non insulin%dependent%diabetes%')
    )
),

-- Type 1 DM diagnosis codes (exclusion)
t1dm_diagnosis AS (
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE (
        -- ICD-10-CM: E10.x (Type 1 diabetes mellitus)
        condition_source_value ILIKE 'E10%'
        OR
        -- ICD-9-CM: 250.x1 and 250.x3 (Type 1/juvenile diabetes)
        regexp_matches(condition_source_value, '^250[.\s]?[0-9]1')
        OR regexp_matches(condition_source_value, '^250[.\s]?[0-9]3')
        OR
        -- Text-based matching
        (condition_source_concept_name ILIKE '%type 1%diabetes%'
         OR condition_source_concept_name ILIKE '%type I%diabetes%'
         OR condition_source_concept_name ILIKE '%IDDM%'
         OR condition_source_concept_name ILIKE '%insulin%dependent%diabetes%'
         OR condition_source_concept_name ILIKE '%juvenile%diabetes%')
    )
),

-- Gestational diabetes diagnosis codes (exclusion)
gestational_diagnosis AS (
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE (
        -- ICD-10: O24.x (Diabetes mellitus in pregnancy, childbirth and the puerperium)
        condition_source_value ILIKE 'O24%'
        OR
        -- ICD-9: 648.8x (Abnormal glucose tolerance of mother)
        condition_source_value ILIKE '648.8%'
        OR regexp_matches(condition_source_value, '^6488')
        OR
        -- Text-based matching
        condition_source_concept_name ILIKE '%gestational%diabetes%'
    )
),

-- Type 2 DM medications (oral agents and non-insulin injectables)
t2dm_medications AS (
    SELECT DISTINCT person_id
    FROM drug_exposure
    WHERE (
        -- Metformin (most common first-line)
        drug_source_value ILIKE '%metformin%'
        OR drug_concept_name ILIKE '%metformin%'
        OR drug_source_value ILIKE '%glucophage%'
        OR drug_concept_name ILIKE '%glucophage%'
        OR drug_source_value ILIKE '%glumetza%'
        OR drug_concept_name ILIKE '%glumetza%'
        OR
        -- Sulfonylureas
        drug_source_value ILIKE '%glipizide%'
        OR drug_source_value ILIKE '%glyburide%'
        OR drug_source_value ILIKE '%glimepiride%'
        OR drug_source_value ILIKE '%glibenclamide%'
        OR drug_source_value ILIKE '%gliclazide%'
        OR drug_concept_name ILIKE '%glipizide%'
        OR drug_concept_name ILIKE '%glyburide%'
        OR drug_concept_name ILIKE '%glimepiride%'
        OR drug_concept_name ILIKE '%gliclazide%'
        OR drug_source_value ILIKE '%glucotrol%'
        OR drug_source_value ILIKE '%micronase%'
        OR drug_source_value ILIKE '%amaryl%'
        OR
        -- DPP-4 inhibitors (gliptins)
        drug_source_value ILIKE '%sitagliptin%'
        OR drug_source_value ILIKE '%saxagliptin%'
        OR drug_source_value ILIKE '%linagliptin%'
        OR drug_source_value ILIKE '%alogliptin%'
        OR drug_concept_name ILIKE '%sitagliptin%'
        OR drug_concept_name ILIKE '%saxagliptin%'
        OR drug_concept_name ILIKE '%linagliptin%'
        OR drug_concept_name ILIKE '%alogliptin%'
        OR drug_source_value ILIKE '%januvia%'
        OR drug_source_value ILIKE '%onglyza%'
        OR drug_source_value ILIKE '%tradjenta%'
        OR drug_source_value ILIKE '%nesina%'
        OR drug_concept_name ILIKE '%januvia%'
        OR
        -- GLP-1 receptor agonists
        drug_source_value ILIKE '%exenatide%'
        OR drug_source_value ILIKE '%liraglutide%'
        OR drug_source_value ILIKE '%dulaglutide%'
        OR drug_source_value ILIKE '%semaglutide%'
        OR drug_source_value ILIKE '%lixisenatide%'
        OR drug_concept_name ILIKE '%exenatide%'
        OR drug_concept_name ILIKE '%liraglutide%'
        OR drug_concept_name ILIKE '%dulaglutide%'
        OR drug_concept_name ILIKE '%semaglutide%'
        OR drug_source_value ILIKE '%byetta%'
        OR drug_source_value ILIKE '%victoza%'
        OR drug_source_value ILIKE '%trulicity%'
        OR drug_source_value ILIKE '%ozempic%'
        OR drug_source_value ILIKE '%wegovy%'
        OR drug_concept_name ILIKE '%victoza%'
        OR drug_concept_name ILIKE '%trulicity%'
        OR drug_concept_name ILIKE '%ozempic%'
        OR
        -- SGLT2 inhibitors (gliflozins)
        drug_source_value ILIKE '%canagliflozin%'
        OR drug_source_value ILIKE '%dapagliflozin%'
        OR drug_source_value ILIKE '%empagliflozin%'
        OR drug_source_value ILIKE '%ertugliflozin%'
        OR drug_concept_name ILIKE '%canagliflozin%'
        OR drug_concept_name ILIKE '%dapagliflozin%'
        OR drug_concept_name ILIKE '%empagliflozin%'
        OR drug_concept_name ILIKE '%ertugliflozin%'
        OR drug_source_value ILIKE '%invokana%'
        OR drug_source_value ILIKE '%farxiga%'
        OR drug_source_value ILIKE '%jardiance%'
        OR drug_source_value ILIKE '%steglatro%'
        OR drug_concept_name ILIKE '%invokana%'
        OR drug_concept_name ILIKE '%farxiga%'
        OR drug_concept_name ILIKE '%jardiance%'
        OR
        -- Thiazolidinediones (TZDs)
        drug_source_value ILIKE '%pioglitazone%'
        OR drug_source_value ILIKE '%rosiglitazone%'
        OR drug_concept_name ILIKE '%pioglitazone%'
        OR drug_concept_name ILIKE '%rosiglitazone%'
        OR drug_source_value ILIKE '%actos%'
        OR drug_source_value ILIKE '%avandia%'
        OR drug_concept_name ILIKE '%actos%'
        OR
        -- Alpha-glucosidase inhibitors
        drug_source_value ILIKE '%acarbose%'
        OR drug_source_value ILIKE '%miglitol%'
        OR drug_concept_name ILIKE '%acarbose%'
        OR drug_concept_name ILIKE '%miglitol%'
        OR drug_source_value ILIKE '%precose%'
        OR drug_source_value ILIKE '%glyset%'
    )
),

-- Abnormal lab values indicative of diabetes
abnormal_labs AS (
    SELECT DISTINCT
        person_id,
        measurement_date AS event_date
    FROM measurement
    WHERE (
        -- HbA1c >= 6.5% (diagnostic threshold)
        (
            (measurement_source_value ILIKE '%hba1c%'
             OR measurement_source_value ILIKE '%hemoglobin a1c%'
             OR measurement_source_value ILIKE '%glycohemoglobin%'
             OR measurement_source_value ILIKE '%glycated hemoglobin%'
             OR measurement_source_value ILIKE '%a1c%'
             OR measurement_concept_name ILIKE '%hemoglobin a1c%'
             OR measurement_concept_name ILIKE '%hba1c%')
            AND value_as_number >= 6.5
        )
        OR
        -- Fasting glucose >= 126 mg/dL (diagnostic threshold)
        (
            (measurement_source_value ILIKE '%fasting%glucose%'
             OR measurement_source_value ILIKE '%fasting%blood%glucose%'
             OR measurement_source_value ILIKE '%fasting%blood%sugar%'
             OR measurement_source_value ILIKE '%FBG%'
             OR measurement_source_value ILIKE '%FBS%'
             OR measurement_source_value ILIKE '%FPG%')
            AND value_as_number >= 126
        )
        OR
        -- Random/non-fasting glucose >= 200 mg/dL (diagnostic threshold)
        (
            (measurement_source_value ILIKE '%glucose%'
             OR measurement_source_value ILIKE '%blood%glucose%'
             OR measurement_source_value ILIKE '%blood%sugar%')
            AND measurement_source_value NOT ILIKE '%fasting%'
            AND value_as_number >= 200
        )
    )
),

-- Count distinct diagnosis dates per patient
dx_counts AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS num_dx_dates
    FROM t2dm_diagnosis
    GROUP BY person_id
),

-- Patients meeting inclusion criteria (4 pathways)
included_patients AS (
    -- Pathway 1: >= 2 T2DM diagnoses on different dates
    SELECT DISTINCT person_id, 'multiple_diagnoses' AS inclusion_pathway
    FROM dx_counts
    WHERE num_dx_dates >= 2
    
    UNION
    
    -- Pathway 2: >= 1 T2DM diagnosis + >= 1 T2DM medication
    SELECT DISTINCT d.person_id, 'diagnosis_plus_medication' AS inclusion_pathway
    FROM t2dm_diagnosis d
    INNER JOIN t2dm_medications m ON d.person_id = m.person_id
    
    UNION
    
    -- Pathway 3: >= 1 T2DM diagnosis + >= 1 abnormal lab
    SELECT DISTINCT d.person_id, 'diagnosis_plus_lab' AS inclusion_pathway
    FROM t2dm_diagnosis d
    INNER JOIN abnormal_labs l ON d.person_id = l.person_id
    
    UNION
    
    -- Pathway 4: >= 1 T2DM medication + >= 1 abnormal lab
    SELECT DISTINCT m.person_id, 'medication_plus_lab' AS inclusion_pathway
    FROM t2dm_medications m
    INNER JOIN abnormal_labs l ON m.person_id = l.person_id
)

-- Final cohort: Include T2DM patients, exclude T1DM and gestational diabetes
SELECT DISTINCT person_id
FROM included_patients
WHERE person_id NOT IN (SELECT person_id FROM t1dm_diagnosis)
  AND person_id NOT IN (SELECT person_id FROM gestational_diagnosis)
ORDER BY person_id;