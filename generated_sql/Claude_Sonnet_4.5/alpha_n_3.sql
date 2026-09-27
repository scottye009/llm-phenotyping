-- =====================================================
-- Type 2 Diabetes Phenotyping Algorithm
-- Based on OMOP CDM v5.x
-- =====================================================

WITH 

-- Step 1: Identify T2DM diagnosis codes
t2dm_diagnosis AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date AS event_date,
        co.condition_concept_id,
        c.concept_name,
        'Diagnosis' AS criterion_type
    FROM public.condition_occurrence co
    INNER JOIN public.concept c ON co.condition_concept_id = c.concept_id
    INNER JOIN public.concept_ancestor ca ON c.concept_id = ca.descendant_concept_id
    WHERE 
        -- SNOMED: Type 2 Diabetes Mellitus
        ca.ancestor_concept_id IN (201826, 443238) -- T2DM SNOMED concepts
        -- ICD-10-CM codes
        OR co.condition_source_value IN (
            'E11', 'E11.0', 'E11.00', 'E11.01', 'E11.1', 'E11.10', 'E11.11',
            'E11.2', 'E11.21', 'E11.22', 'E11.29',
            'E11.3', 'E11.31', 'E11.32', 'E11.33', 'E11.34', 'E11.35', 'E11.36', 'E11.39',
            'E11.4', 'E11.40', 'E11.41', 'E11.42', 'E11.43', 'E11.44', 'E11.49',
            'E11.5', 'E11.51', 'E11.52', 'E11.59',
            'E11.6', 'E11.61', 'E11.62', 'E11.63', 'E11.64', 'E11.65', 'E11.69',
            'E11.8', 'E11.9'
        )
        -- ICD-9-CM codes
        OR co.condition_source_value IN (
            '250.00', '250.02', '250.10', '250.12', '250.20', '250.22',
            '250.30', '250.32', '250.40', '250.42', '250.50', '250.52',
            '250.60', '250.62', '250.70', '250.72', '250.80', '250.82',
            '250.90', '250.92'
        )
),

-- Step 2: Identify exclusion diagnoses (T1DM, gestational, secondary)
exclusion_diagnosis AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date AS event_date,
        'Exclusion' AS criterion_type
    FROM public.condition_occurrence co
    INNER JOIN public.concept c ON co.condition_concept_id = c.concept_id
    INNER JOIN public.concept_ancestor ca ON c.concept_id = ca.descendant_concept_id
    WHERE 
        -- Type 1 Diabetes
        ca.ancestor_concept_id IN (201254, 435216)
        -- Gestational Diabetes
        OR ca.ancestor_concept_id IN (4058243)
        -- Secondary Diabetes
        OR ca.ancestor_concept_id IN (195771)
        -- ICD-10 codes for exclusions
        OR co.condition_source_value LIKE 'E10%' -- T1DM
        OR co.condition_source_value LIKE 'O24%' -- Gestational
        OR co.condition_source_value IN ('E08%', 'E09%', 'E13%') -- Secondary/Other
        -- ICD-9 codes for exclusions
        OR co.condition_source_value IN (
            '250.01', '250.03', '250.11', '250.13', '250.21', '250.23',
            '250.31', '250.33', '250.41', '250.43', '250.51', '250.53',
            '250.61', '250.63', '250.71', '250.73', '250.81', '250.83',
            '250.91', '250.93', -- T1DM (odd numbers)
            '648.8', '648.80', '648.81', '648.82', '648.83', '648.84' -- Gestational
        )
),

-- Step 3: Identify anti-diabetic medications
t2dm_medications AS (
    SELECT DISTINCT
        de.person_id,
        de.drug_exposure_start_date AS event_date,
        de.drug_concept_id,
        c.concept_name,
        'Medication' AS criterion_type
    FROM public.drug_exposure de
    INNER JOIN public.concept c ON de.drug_concept_id = c.concept_id
    INNER JOIN public.concept_ancestor ca ON c.concept_id = ca.descendant_concept_id
    WHERE 
        ca.ancestor_concept_id IN (
            1529331, -- Metformin
            1530014, -- Sulfonylureas
            1594973, -- Glyburide
            1559684, -- Glipizide
            1597756, -- Glimepiride
            1580747, -- Pioglitazone
            1583722, -- Rosiglitazone
            40170911, -- DPP-4 inhibitors
            1545653, -- Sitagliptin
            40239216, -- Saxagliptin
            42479537, -- Linagliptin
            43013884, -- Alogliptin
            1503297, -- GLP-1 agonists
            40170911, -- Exenatide
            40166035, -- Liraglutide
            45774751, -- Dulaglutide
            42904205, -- Semaglutide
            1510202, -- SGLT2 inhibitors
            45775965, -- Canagliflozin
            45774435, -- Dapagliflozin
            45775965, -- Empagliflozin
            1530009, -- Acarbose
            1538454  -- Repaglinide
        )
        -- Generic and Brand Names
        OR LOWER(c.concept_name) LIKE '%metformin%'
        OR LOWER(c.concept_name) LIKE '%glucophage%'
        OR LOWER(c.concept_name) LIKE '%glyburide%'
        OR LOWER(c.concept_name) LIKE '%glipizide%'
        OR LOWER(c.concept_name) LIKE '%glimepiride%'
        OR LOWER(c.concept_name) LIKE '%pioglitazone%'
        OR LOWER(c.concept_name) LIKE '%actos%'
        OR LOWER(c.concept_name) LIKE '%rosiglitazone%'
        OR LOWER(c.concept_name) LIKE '%avandia%'
        OR LOWER(c.concept_name) LIKE '%sitagliptin%'
        OR LOWER(c.concept_name) LIKE '%januvia%'
        OR LOWER(c.concept_name) LIKE '%saxagliptin%'
        OR LOWER(c.concept_name) LIKE '%onglyza%'
        OR LOWER(c.concept_name) LIKE '%linagliptin%'
        OR LOWER(c.concept_name) LIKE '%tradjenta%'
        OR LOWER(c.concept_name) LIKE '%exenatide%'
        OR LOWER(c.concept_name) LIKE '%byetta%'
        OR LOWER(c.concept_name) LIKE '%bydureon%'
        OR LOWER(c.concept_name) LIKE '%liraglutide%'
        OR LOWER(c.concept_name) LIKE '%victoza%'
        OR LOWER(c.concept_name) LIKE '%dulaglutide%'
        OR LOWER(c.concept_name) LIKE '%trulicity%'
        OR LOWER(c.concept_name) LIKE '%semaglutide%'
        OR LOWER(c.concept_name) LIKE '%ozempic%'
        OR LOWER(c.concept_name) LIKE '%rybelsus%'
        OR LOWER(c.concept_name) LIKE '%canagliflozin%'
        OR LOWER(c.concept_name) LIKE '%invokana%'
        OR LOWER(c.concept_name) LIKE '%dapagliflozin%'
        OR LOWER(c.concept_name) LIKE '%farxiga%'
        OR LOWER(c.concept_name) LIKE '%empagliflozin%'
        OR LOWER(c.concept_name) LIKE '%jardiance%'
        OR LOWER(c.concept_name) LIKE '%acarbose%'
        OR LOWER(c.concept_name) LIKE '%precose%'
),

-- Step 4: Identify abnormal lab values
t2dm_labs AS (
    SELECT DISTINCT
        m.person_id,
        m.measurement_date AS event_date,
        m.measurement_concept_id,
        c.concept_name,
        m.value_as_number,
        m.unit_concept_id,
        'Laboratory' AS criterion_type
    FROM public.measurement m
    INNER JOIN public.concept c ON m.measurement_concept_id = c.concept_id
    WHERE 
        (
            -- HbA1c >= 6.5%
            (c.concept_id IN (3004410, 3005673, 3007263) -- HbA1c concepts
             AND m.value_as_number >= 6.5)
            OR
            -- Fasting glucose >= 126 mg/dL
            (c.concept_id IN (3004501, 3005131) -- Fasting glucose
             AND m.value_as_number >= 126)
            OR
            -- Random glucose >= 200 mg/dL
            (c.concept_id IN (3005131, 3004501, 3001784) -- Glucose
             AND m.value_as_number >= 200)
        )
),

-- Step 5: Combine all criteria events
all_criteria AS (
    SELECT person_id, event_date, criterion_type FROM t2dm_diagnosis
    UNION ALL
    SELECT person_id, event_date, criterion_type FROM t2dm_medications
    UNION ALL
    SELECT person_id, event_date, criterion_type FROM t2dm_labs
),

-- Step 6: Count criteria per person
criteria_counts AS (
    SELECT 
        person_id,
        COUNT(DISTINCT event_date) AS num_events,
        COUNT(DISTINCT criterion_type) AS num_criteria_types,
        MIN(event_date) AS first_event_date,
        MAX(event_date) AS last_event_date
    FROM all_criteria
    GROUP BY person_id
),

-- Step 7: Apply phenotyping logic
t2dm_cohort AS (
    SELECT 
        cc.person_id,
        cc.first_event_date AS index_date,
        cc.num_events,
        cc.num_criteria_types,
        p.birth_datetime,
        EXTRACT(YEAR FROM AGE(cc.first_event_date, p.birth_datetime)) AS age_at_index
    FROM criteria_counts cc
    INNER JOIN public.person p ON cc.person_id = p.person_id
    WHERE 
        (
            -- Criteria: At least 2 events on different dates
            cc.num_events >= 2
            OR
            -- OR: At least 2 different criterion types (e.g., diagnosis + medication)
            cc.num_criteria_types >= 2
        )
        -- Exclude if person has exclusion diagnosis
        AND NOT EXISTS (
            SELECT 1 
            FROM exclusion_diagnosis ed 
            WHERE ed.person_id = cc.person_id
            AND ed.event_date <= cc.last_event_date
        )
)

-- Step 8: Final cohort output
SELECT 
    tc.person_id,
    tc.index_date,
    tc.age_at_index,
    tc.num_events AS supporting_events,
    tc.num_criteria_types AS supporting_criteria_types,
    p.gender_concept_id,
    gc.concept_name AS gender,
    p.race_concept_id,
    rc.concept_name AS race,
    p.ethnicity_concept_id,
    ec.concept_name AS ethnicity
FROM t2dm_cohort tc
INNER JOIN public.person p ON tc.person_id = p.person_id
LEFT JOIN public.concept gc ON p.gender_concept_id = gc.concept_id
LEFT JOIN public.concept rc ON p.race_concept_id = rc.concept_id
LEFT JOIN public.concept ec ON p.ethnicity_concept_id = ec.concept_id
ORDER BY tc.person_id;

-- Optional: Create a results table
-- CREATE TABLE public.cohort AS
-- SELECT * FROM t2dm_cohort;

