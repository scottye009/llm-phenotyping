-- Phenotyping Algorithm for Type 2 Diabetes Mellitus (T2DM)
WITH t2dm_dx AS (
    -- identify patients with T2DM diagnosis codes (ICD-10 E11 or ICD-9 250)
    -- explicitly excluding Type 1 (E10) where possible via source value
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE (
        condition_source_value ILIKE 'E11%' -- ICD-10 T2DM
        OR condition_source_value ILIKE '250%' -- ICD-9 Diabetes
    )
    AND NOT (
        condition_source_value ILIKE 'E10%' -- Exclude Type 1
        OR condition_source_concept_name ILIKE '%type 1%'
    )
),

t2dm_labs AS (
    -- identify patients with glycemic markers above diagnostic thresholds
    SELECT 
        person_id, 
        COUNT(DISTINCT measurement_id) as high_glucose_count
    FROM measurement
    WHERE (
        -- HbA1c >= 6.5%
        (measurement_source_value ILIKE '%HbA1c%' AND value_as_number >= 6.5)
        OR 
        -- Fasting Plasma Glucose >= 126 mg/dL
        (measurement_source_value ILIKE '%glucose%' 
         AND measurement_source_value ILIKE '%fasting%' 
         AND value_as_number >= 126)
    )
    GROUP BY person_id
),

t2dm_rx AS (
    -- identify patients taking T2DM medications (Generic and Brand)
    SELECT DISTINCT person_id
    FROM drug_exposure
    WHERE (
        drug_concept_name ILIKE '%Metformin%' -- Glucophage
        OR drug_source_value ILIKE '%Metformin%'
        OR drug_concept_name ILIKE '%Glipizide%' -- Glibenclamide/Glyburide
        OR drug_source_value ILIKE '%Glipizide%'
        OR drug_concept_name ILIKE '%Glyburide%'
        OR drug_source_value ILIKE '%Glyburide%'
        OR drug_concept_name ILIKE '%Sitagliptin%' -- Januvia
        OR drug_source_value ILIKE '%Sitagliptin%'
        OR drug_concept_name ILIKE '%Empagliflozin%' -- Jardiance
        OR drug_source_value ILIKE '%Empagliflozin%'
        OR drug_concept_name ILIKE '%Dapagliflozin%' -- Farxiga
        OR drug_source_value ILIKE '%Dapagliflozin%'
        OR drug_concept_name ILIKE '%Pioglitazone%' -- Actos
        OR drug_source_value ILIKE '%Pioglitazone%'
        OR drug_concept_name ILIKE '%Insulin%'
        OR drug_source_value ILIKE '%Insulin%'
    )
)

-- Final selection based on combination logic
SELECT DISTINCT p.person_id
FROM person p
LEFT JOIN t2dm_dx dx ON p.person_id = dx.person_id
LEFT JOIN t2dm_labs labs ON p.person_id = labs.person_id
LEFT JOIN t2dm_rx rx ON p.person_id = rx.person_id
WHERE 
    dx.person_id IS NOT NULL -- Criterion 1: Direct diagnosis
    OR labs.high_glucose_count >= 2 -- Criterion 2: Two or more abnormal labs
    OR (labs.high_glucose_count >= 1 AND rx.person_id IS NOT NULL) -- Criterion 3: Lab + Meds
    OR rx.person_id IS NOT NULL; -- Criterion 4: Medication use alone (broad)