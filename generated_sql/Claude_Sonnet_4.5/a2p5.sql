-- ============================================================================
-- Type 2 Diabetes Phenotyping Algorithm
-- Based on OMOP Common Data Model (CDM)
-- Schema: public
-- ============================================================================

WITH 

-- Step 1: Identify patients with Type 2 Diabetes diagnosis codes
diabetes_diagnosis AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date AS event_date,
        'diagnosis' AS criterion_type,
        c.concept_code,
        c.concept_name
    FROM public.condition_occurrence co
    INNER JOIN public.concept c ON co.condition_concept_id = c.concept_id
    WHERE (
        -- ICD10CM codes for Type 2 Diabetes
        c.concept_code IN (
            'E11', 'E11.0', 'E11.00', 'E11.01',
            'E11.1', 'E11.2', 'E11.21', 'E11.22', 'E11.29',
            'E11.3', 'E11.31', 'E11.32', 'E11.33', 'E11.34', 'E11.35', 'E11.36', 'E11.37', 'E11.39',
            'E11.4', 'E11.40', 'E11.41', 'E11.42', 'E11.43', 'E11.44', 'E11.49',
            'E11.5', 'E11.51', 'E11.52', 'E11.59',
            'E11.6', 'E11.61', 'E11.62', 'E11.63', 'E11.64', 'E11.65', 'E11.69',
            'E11.8', 'E11.9'
        )
        AND c.vocabulary_id = 'ICD10CM'
    )
    OR (
        -- ICD9CM codes for Type 2 Diabetes
        c.concept_code IN (
            '250.00', '250.02',
            '250.10', '250.12',
            '250.20', '250.22',
            '250.30', '250.32',
            '250.40', '250.42',
            '250.50', '250.52',
            '250.60', '250.62',
            '250.70', '250.72',
            '250.80', '250.82',
            '250.90', '250.92'
        )
        AND c.vocabulary_id = 'ICD9CM'
    )
),

-- Step 2: Identify patients with abnormal diabetes-related laboratory values
diabetes_labs AS (
    SELECT DISTINCT
        m.person_id,
        m.measurement_date AS event_date,
        'laboratory' AS criterion_type,
        c.concept_name,
        m.value_as_number,
        m.unit_concept_id
    FROM public.measurement m
    INNER JOIN public.concept c ON m.measurement_concept_id = c.concept_id
    WHERE (
        -- HbA1c >= 6.5%
        (c.concept_name ILIKE '%hemoglobin a1c%' OR c.concept_name ILIKE '%hba1c%' OR c.concept_name ILIKE '%glycohemoglobin%')
        AND m.value_as_number >= 6.5
    )
    OR (
        -- Fasting glucose >= 126 mg/dL
        (c.concept_name ILIKE '%fasting glucose%' OR c.concept_name ILIKE '%fasting blood glucose%')
        AND m.value_as_number >= 126
    )
    OR (
        -- Random glucose >= 200 mg/dL
        (c.concept_name ILIKE '%glucose%' AND c.concept_name NOT ILIKE '%fasting%')
        AND m.value_as_number >= 200
    )
),

-- Step 3: Identify patients on diabetes medications
diabetes_medications AS (
    SELECT DISTINCT
        de.person_id,
        de.drug_exposure_start_date AS event_date,
        'medication' AS criterion_type,
        c.concept_name
    FROM public.drug_exposure de
    INNER JOIN public.concept c ON de.drug_concept_id = c.concept_id
    WHERE (
        -- Metformin (generic and brand names)
        c.concept_name ILIKE '%metformin%' OR c.concept_name ILIKE '%glucophage%' OR c.concept_name ILIKE '%fortamet%' OR c.concept_name ILIKE '%glumetza%'
    )
    OR (
        -- Sulfonylureas
        c.concept_name ILIKE '%glyburide%' OR c.concept_name ILIKE '%glibenclamide%' OR c.concept_name ILIKE '%diabeta%' OR c.concept_name ILIKE '%glynase%'
        OR c.concept_name ILIKE '%glipizide%' OR c.concept_name ILIKE '%glucotrol%'
        OR c.concept_name ILIKE '%glimepiride%' OR c.concept_name ILIKE '%amaryl%'
    )
    OR (
        -- Thiazolidinediones (TZDs)
        c.concept_name ILIKE '%pioglitazone%' OR c.concept_name ILIKE '%actos%'
        OR c.concept_name ILIKE '%rosiglitazone%' OR c.concept_name ILIKE '%avandia%'
    )
    OR (
        -- DPP-4 inhibitors
        c.concept_name ILIKE '%sitagliptin%' OR c.concept_name ILIKE '%januvia%'
        OR c.concept_name ILIKE '%saxagliptin%' OR c.concept_name ILIKE '%onglyza%'
        OR c.concept_name ILIKE '%linagliptin%' OR c.concept_name ILIKE '%tradjenta%'
        OR c.concept_name ILIKE '%alogliptin%' OR c.concept_name ILIKE '%nesina%'
    )
    OR (
        -- GLP-1 receptor agonists
        c.concept_name ILIKE '%exenatide%' OR c.concept_name ILIKE '%byetta%' OR c.concept_name ILIKE '%bydureon%'
        OR c.concept_name ILIKE '%liraglutide%' OR c.concept_name ILIKE '%victoza%'
        OR c.concept_name ILIKE '%dulaglutide%' OR c.concept_name ILIKE '%trulicity%'
        OR c.concept_name ILIKE '%semaglutide%' OR c.concept_name ILIKE '%ozempic%' OR c.concept_name ILIKE '%rybelsus%'
    )
    OR (
        -- SGLT2 inhibitors
        c.concept_name ILIKE '%canagliflozin%' OR c.concept_name ILIKE '%invokana%'
        OR c.concept_name ILIKE '%dapagliflozin%' OR c.concept_name ILIKE '%farxiga%'
        OR c.concept_name ILIKE '%empagliflozin%' OR c.concept_name ILIKE '%jardiance%'
        OR c.concept_name ILIKE '%ertugliflozin%' OR c.concept_name ILIKE '%steglatro%'
    )
    OR (
        -- Insulin (for Type 2 DM patients)
        c.concept_name ILIKE '%insulin%'
    )
    OR (
        -- Meglitinides
        c.concept_name ILIKE '%repaglinide%' OR c.concept_name ILIKE '%prandin%'
        OR c.concept_name ILIKE '%nateglinide%' OR c.concept_name ILIKE '%starlix%'
    )
    OR (
        -- Alpha-glucosidase inhibitors
        c.concept_name ILIKE '%acarbose%' OR c.concept_name ILIKE '%precose%'
        OR c.concept_name ILIKE '%miglitol%' OR c.concept_name ILIKE '%glyset%'
    )
),

-- Step 4: Exclude Type 1 Diabetes
exclusion_type1_diabetes AS (
    SELECT DISTINCT
        co.person_id
    FROM public.condition_occurrence co
    INNER JOIN public.concept c ON co.condition_concept_id = c.concept_id
    WHERE (
        -- ICD10CM codes for Type 1 Diabetes
        c.concept_code LIKE 'E10%'
        AND c.vocabulary_id = 'ICD10CM'
    )
    OR (
        -- ICD9CM codes for Type 1 Diabetes
        c.concept_code IN (
            '250.01', '250.03', '250.11', '250.13', '250.21', '250.23',
            '250.31', '250.33', '250.41', '250.43', '250.51', '250.53',
            '250.61', '250.63', '250.71', '250.73', '250.81', '250.83',
            '250.91', '250.93'
        )
        AND c.vocabulary_id = 'ICD9CM'
    )
),

-- Step 5: Exclude Gestational Diabetes
exclusion_gestational_diabetes AS (
    SELECT DISTINCT
        co.person_id
    FROM public.condition_occurrence co
    INNER JOIN public.concept c ON co.condition_concept_id = c.concept_id
    WHERE (
        -- ICD10CM codes for Gestational Diabetes
        c.concept_code LIKE 'O24.4%'
        AND c.vocabulary_id = 'ICD10CM'
    )
    OR (
        -- ICD9CM codes for Gestational Diabetes
        c.concept_code IN ('648.80', '648.81', '648.82', '648.83', '648.84')
        AND c.vocabulary_id = 'ICD9CM'
    )
),

-- Step 6: Exclude Secondary Diabetes
exclusion_secondary_diabetes AS (
    SELECT DISTINCT
        co.person_id
    FROM public.condition_occurrence co
    INNER JOIN public.concept c ON co.condition_concept_id = c.concept_id
    WHERE (
        -- ICD10CM codes for Secondary Diabetes
        c.concept_code LIKE 'E08%' OR c.concept_code LIKE 'E09%' OR c.concept_code LIKE 'E13%'
        AND c.vocabulary_id = 'ICD10CM'
    )
),

-- Step 7: Combine all positive criteria (diagnosis OR labs OR medications)
all_diabetes_evidence AS (
    SELECT person_id, event_date, criterion_type FROM diabetes_diagnosis
    UNION ALL
    SELECT person_id, event_date, criterion_type FROM diabetes_labs
    UNION ALL
    SELECT person_id, event_date, criterion_type FROM diabetes_medications
),

-- Step 8: Count evidence by type for each patient
evidence_summary AS (
    SELECT
        person_id,
        MIN(event_date) AS first_evidence_date,
        MAX(event_date) AS last_evidence_date,
        COUNT(DISTINCT event_date) AS total_evidence_count,
        COUNT(DISTINCT CASE WHEN criterion_type = 'diagnosis' THEN event_date END) AS diagnosis_count,
        COUNT(DISTINCT CASE WHEN criterion_type = 'laboratory' THEN event_date END) AS lab_count,
        COUNT(DISTINCT CASE WHEN criterion_type = 'medication' THEN event_date END) AS medication_count,
        COUNT(DISTINCT criterion_type) AS distinct_criterion_types
    FROM all_diabetes_evidence
    GROUP BY person_id
)

-- Step 9: Final cohort selection with confidence levels
SELECT
    p.person_id,
    p.gender_concept_id,
    p.year_of_birth,
    p.race_concept_id,
    p.ethnicity_concept_id,
    es.first_evidence_date AS t2dm_index_date,
    es.last_evidence_date,
    es.total_evidence_count,
    es.diagnosis_count,
    es.lab_count,
    es.medication_count,
    es.distinct_criterion_types,
    CASE
        -- High confidence: Multiple criteria types AND multiple occurrences
        WHEN es.distinct_criterion_types >= 2 AND es.total_evidence_count >= 2 THEN 'High'
        -- Medium confidence: Single strong criterion (diagnosis or abnormal lab)
        WHEN es.diagnosis_count >= 1 OR es.lab_count >= 1 THEN 'Medium'
        -- Low confidence: Only medication without diagnosis or labs
        WHEN es.medication_count >= 2 THEN 'Low'
        ELSE 'Very Low'
    END AS confidence_level
FROM public.person p
INNER JOIN evidence_summary es ON p.person_id = es.person_id
WHERE
    -- Include: Has at least one piece of evidence
    es.total_evidence_count >= 1
    
    -- AND: Require at least one strong criterion OR multiple medication exposures
    AND (
        es.diagnosis_count >= 1 
        OR es.lab_count >= 1 
        OR es.medication_count >= 2
    )
    
    -- AND NOT: Exclude Type 1 Diabetes
    AND p.person_id NOT IN (SELECT person_id FROM exclusion_type1_diabetes)
    
    -- AND NOT: Exclude Gestational Diabetes
    AND p.person_id NOT IN (SELECT person_id FROM exclusion_gestational_diabetes)
    
    -- AND NOT: Exclude Secondary Diabetes
    AND p.person_id NOT IN (SELECT person_id FROM exclusion_secondary_diabetes)

ORDER BY confidence_level DESC, es.first_evidence_date;

-- ============================================================================
-- Optional: Create a summary statistics view
-- ============================================================================

-- SELECT
--     confidence_level,
--     COUNT(DISTINCT person_id) AS patient_count,
--     AVG(total_evidence_count) AS avg_evidence_count,
--     AVG(EXTRACT(YEAR FROM last_evidence_date) - year_of_birth) AS avg_age_at_last_evidence
-- FROM [above query]
-- GROUP BY confidence_level
-- ORDER BY confidence_level DESC;

