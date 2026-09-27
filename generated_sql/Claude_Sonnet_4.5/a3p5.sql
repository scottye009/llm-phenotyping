-- Type 2 Diabetes Mellitus Phenotyping Algorithm
-- Identifies patients with Type 2 DM using diagnosis codes, medications, and lab values
-- Excludes patients with Type 1 DM diagnosis codes

WITH t2dm_diagnosis AS (
    -- Type 2 DM diagnosis codes (ICD-9: 250.x0, 250.x2; ICD-10: E11.x)
    SELECT DISTINCT
        person_id,
        condition_start_date AS event_date
    FROM condition_occurrence
    WHERE (
        -- ICD-9-CM Type 2 DM codes (5th digit 0 or 2)
        condition_source_value ILIKE '250.%0' OR
        condition_source_value ILIKE '250.%2' OR
        -- ICD-10-CM Type 2 DM codes
        condition_source_value ILIKE 'E11.%' OR
        -- Alternative patterns without decimal
        condition_source_value ILIKE '250_0' OR
        condition_source_value ILIKE '250_2' OR
        -- Text-based matching in source concept name
        condition_source_concept_name ILIKE '%type 2 diabetes%' OR
        condition_source_concept_name ILIKE '%type II diabetes%' OR
        condition_source_concept_name ILIKE '%diabetes mellitus type 2%' OR
        condition_source_concept_name ILIKE '%NIDDM%'
    )
),

t1dm_diagnosis AS (
    -- Type 1 DM diagnosis codes to exclude (ICD-9: 250.x1, 250.x3; ICD-10: E10.x)
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE (
        -- ICD-9-CM Type 1 DM codes (5th digit 1 or 3)
        condition_source_value ILIKE '250.%1' OR
        condition_source_value ILIKE '250.%3' OR
        -- ICD-10-CM Type 1 DM codes
        condition_source_value ILIKE 'E10.%' OR
        -- Alternative patterns
        condition_source_value ILIKE '250_1' OR
        condition_source_value ILIKE '250_3' OR
        -- Text-based matching
        condition_source_concept_name ILIKE '%type 1 diabetes%' OR
        condition_source_concept_name ILIKE '%type I diabetes%' OR
        condition_source_concept_name ILIKE '%IDDM%'
    )
),

t2dm_medications AS (
    -- Type 2 DM medications (excluding insulin-only therapy)
    SELECT DISTINCT
        person_id,
        drug_exposure_start_date AS event_date
    FROM drug_exposure
    WHERE (
        -- Metformin
        drug_source_value ILIKE '%metformin%' OR
        drug_concept_name ILIKE '%metformin%' OR
        -- Sulfonylureas
        drug_source_value ILIKE '%glipizide%' OR
        drug_source_value ILIKE '%glyburide%' OR
        drug_source_value ILIKE '%glimepiride%' OR
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
        drug_concept_name ILIKE '%alogliptin%' OR
        drug_source_value ILIKE '%januvia%' OR
        drug_concept_name ILIKE '%januvia%' OR
        -- GLP-1 agonists
        drug_source_value ILIKE '%exenatide%' OR
        drug_source_value ILIKE '%liraglutide%' OR
        drug_source_value ILIKE '%dulaglutide%' OR
        drug_source_value ILIKE '%semaglutide%' OR
        drug_concept_name ILIKE '%exenatide%' OR
        drug_concept_name ILIKE '%liraglutide%' OR
        drug_concept_name ILIKE '%dulaglutide%' OR
        drug_concept_name ILIKE '%semaglutide%' OR
        drug_source_value ILIKE '%victoza%' OR
        drug_source_value ILIKE '%trulicity%' OR
        drug_source_value ILIKE '%ozempic%' OR
        drug_concept_name ILIKE '%victoza%' OR
        drug_concept_name ILIKE '%trulicity%' OR
        drug_concept_name ILIKE '%ozempic%' OR
        -- SGLT2 inhibitors
        drug_source_value ILIKE '%canagliflozin%' OR
        drug_source_value ILIKE '%dapagliflozin%' OR
        drug_source_value ILIKE '%empagliflozin%' OR
        drug_concept_name ILIKE '%canagliflozin%' OR
        drug_concept_name ILIKE '%dapagliflozin%' OR
        drug_concept_name ILIKE '%empagliflozin%' OR
        drug_source_value ILIKE '%invokana%' OR
        drug_source_value ILIKE '%farxiga%' OR
        drug_source_value ILIKE '%jardiance%' OR
        drug_concept_name ILIKE '%invokana%' OR
        drug_concept_name ILIKE '%farxiga%' OR
        drug_concept_name ILIKE '%jardiance%' OR
        -- Thiazolidinediones
        drug_source_value ILIKE '%pioglitazone%' OR
        drug_source_value ILIKE '%rosiglitazone%' OR
        drug_concept_name ILIKE '%pioglitazone%' OR
        drug_concept_name ILIKE '%rosiglitazone%' OR
        drug_source_value ILIKE '%actos%' OR
        drug_concept_name ILIKE '%actos%'
    )
),

abnormal_labs AS (
    -- Abnormal lab values indicative of diabetes
    SELECT DISTINCT
        person_id,
        measurement_date AS event_date
    FROM measurement
    WHERE (
        -- HbA1c >= 6.5%
        (
            (measurement_source_value ILIKE '%hba1c%' OR
             measurement_source_value ILIKE '%hemoglobin a1c%' OR
             measurement_source_value ILIKE '%glycohemoglobin%' OR
             measurement_concept_name ILIKE '%hemoglobin a1c%')
            AND value_as_number >= 6.5
        )
        OR
        -- Fasting glucose >= 126 mg/dL
        (
            (measurement_source_value ILIKE '%fasting%glucose%' OR
             measurement_source_value ILIKE '%fasting%blood%sugar%' OR
             measurement_source_value ILIKE '%FBS%' OR
             measurement_source_value ILIKE '%FBG%')
            AND value_as_number >= 126
        )
        OR
        -- Random glucose >= 200 mg/dL
        (
            (measurement_source_value ILIKE '%glucose%' OR
             measurement_source_value ILIKE '%blood%sugar%')
            AND value_as_number >= 200
        )
    )
),

-- Path A: >=2 Type 2 DM diagnoses on different dates
path_a AS (
    SELECT person_id
    FROM t2dm_diagnosis
    GROUP BY person_id
    HAVING COUNT(DISTINCT event_date) >= 2
),

-- Path B: >=1 Type 2 DM diagnosis + >=1 T2DM medication
path_b AS (
    SELECT DISTINCT d.person_id
    FROM t2dm_diagnosis d
    INNER JOIN t2dm_medications m ON d.person_id = m.person_id
),

-- Path C: >=1 Type 2 DM diagnosis + abnormal lab
path_c AS (
    SELECT DISTINCT d.person_id
    FROM t2dm_diagnosis d
    INNER JOIN abnormal_labs l ON d.person_id = l.person_id
),

-- Path D: >=1 T2DM medication + abnormal lab
path_d AS (
    SELECT DISTINCT m.person_id
    FROM t2dm_medications m
    INNER JOIN abnormal_labs l ON m.person_id = l.person_id
),

-- Combine all paths
all_t2dm_patients AS (
    SELECT person_id FROM path_a
    UNION
    SELECT person_id FROM path_b
    UNION
    SELECT person_id FROM path_c
    UNION
    SELECT person_id FROM path_d
)

-- Final cohort: Type 2 DM patients excluding Type 1 DM
SELECT DISTINCT person_id
FROM all_t2dm_patients
WHERE person_id NOT IN (SELECT person_id FROM t1dm_diagnosis)
ORDER BY person_id;