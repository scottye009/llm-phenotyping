-- =====================================================
-- Type 2 Diabetes Phenotyping Algorithm
-- OMOP CDM v5.x Compatible
-- =====================================================

WITH t2dm_diagnosis AS (
    -- Type 2 Diabetes diagnosis codes (ICD-9-CM and ICD-10-CM)
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date,
        co.condition_concept_id,
        c.concept_code,
        c.concept_name
    FROM public.condition_occurrence co
    INNER JOIN public.concept c ON co.condition_concept_id = c.concept_id
    WHERE (
        -- ICD-10-CM codes for Type 2 Diabetes
        c.concept_code IN (
            'E11', 'E11.9', 'E11.0', 'E11.00', 'E11.01',
            'E11.1', 'E11.10', 'E11.11',
            'E11.2', 'E11.21', 'E11.22', 'E11.29',
            'E11.3', 'E11.31', 'E11.32', 'E11.33', 'E11.34', 'E11.35', 'E11.36', 'E11.37', 'E11.39',
            'E11.4', 'E11.40', 'E11.41', 'E11.42', 'E11.43', 'E11.44', 'E11.49',
            'E11.5', 'E11.51', 'E11.52', 'E11.59',
            'E11.6', 'E11.61', 'E11.62', 'E11.63', 'E11.64', 'E11.65', 'E11.69',
            'E11.8', 'E11.9'
        )
        OR
        -- ICD-9-CM codes for Type 2 Diabetes
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
    )
    AND c.vocabulary_id IN ('ICD10CM', 'ICD9CM')
),

exclusion_diagnosis AS (
    -- Exclude Type 1 Diabetes, Gestational, and Secondary Diabetes
    SELECT DISTINCT
        co.person_id
    FROM public.condition_occurrence co
    INNER JOIN public.concept c ON co.condition_concept_id = c.concept_id
    WHERE (
        -- ICD-10-CM Type 1 Diabetes
        c.concept_code LIKE 'E10%'
        OR
        -- ICD-9-CM Type 1 Diabetes
        c.concept_code IN ('250.01', '250.03', '250.11', '250.13', '250.21', '250.23',
                           '250.31', '250.33', '250.41', '250.43', '250.51', '250.53',
                           '250.61', '250.63', '250.71', '250.73', '250.81', '250.83',
                           '250.91', '250.93')
        OR
        -- Gestational Diabetes
        c.concept_code IN ('O24.4', 'O24.41', 'O24.42', 'O24.43', 'O24.419', 'O24.429', 'O24.439', '648.8')
        OR
        -- Secondary Diabetes
        c.concept_code LIKE 'E08%' OR c.concept_code LIKE 'E09%' OR c.concept_code LIKE 'E13%'
    )
    AND c.vocabulary_id IN ('ICD10CM', 'ICD9CM')
),

t2dm_medications AS (
    -- Type 2 Diabetes medications (excluding insulin-only therapy)
    SELECT DISTINCT
        de.person_id,
        de.drug_exposure_start_date,
        de.drug_concept_id,
        c.concept_name
    FROM public.drug_exposure de
    INNER JOIN public.concept c ON de.drug_concept_id = c.concept_id
    INNER JOIN public.concept_ancestor ca ON c.concept_id = ca.descendant_concept_id
    WHERE ca.ancestor_concept_id IN (
        -- Metformin
        1503297, 1516766,
        -- Sulfonylureas (Glipizide, Glyburide, Glimepiride)
        1559684, 1560171, 1580747,
        -- DPP-4 Inhibitors (Sitagliptin, Saxagliptin, Linagliptin, Alogliptin)
        40239216, 40166035, 40166789, 43013024,
        -- GLP-1 Agonists (Exenatide, Liraglutide, Dulaglutide, Semaglutide)
        40170911, 40164635, 43013884, 45774751,
        -- SGLT2 Inhibitors (Canagliflozin, Dapagliflozin, Empagliflozin, Ertugliflozin)
        43013892, 44816332, 45774435, 46287377,
        -- Thiazolidinediones (Pioglitazone, Rosiglitazone)
        1547504, 1502809,
        -- Alpha-glucosidase inhibitors (Acarbose, Miglitol)
        1516976, 1525215,
        -- Meglitinides (Repaglinide, Nateglinide)
        1513876, 1510813
    )
    OR c.concept_name ILIKE ANY (ARRAY[
        '%metformin%', '%glucophage%', '%fortamet%', '%glumetza%',
        '%glipizide%', '%glucotrol%',
        '%glyburide%', '%diabeta%', '%glynase%', '%micronase%',
        '%glimepiride%', '%amaryl%',
        '%sitagliptin%', '%januvia%',
        '%saxagliptin%', '%onglyza%',
        '%linagliptin%', '%tradjenta%',
        '%alogliptin%', '%nesina%',
        '%exenatide%', '%byetta%', '%bydureon%',
        '%liraglutide%', '%victoza%',
        '%dulaglutide%', '%trulicity%',
        '%semaglutide%', '%ozempic%', '%rybelsus%',
        '%canagliflozin%', '%invokana%',
        '%dapagliflozin%', '%farxiga%',
        '%empagliflozin%', '%jardiance%',
        '%ertugliflozin%', '%steglatro%',
        '%pioglitazone%', '%actos%',
        '%rosiglitazone%', '%avandia%',
        '%acarbose%', '%precose%',
        '%miglitol%', '%glyset%',
        '%repaglinide%', '%prandin%',
        '%nateglinide%', '%starlix%'
    ])
),

t2dm_labs AS (
    -- Laboratory values indicating diabetes
    SELECT DISTINCT
        m.person_id,
        m.measurement_date,
        m.value_as_number,
        c.concept_name AS lab_name
    FROM public.measurement m
    INNER JOIN public.concept c ON m.measurement_concept_id = c.concept_id
    WHERE (
        -- HbA1c >= 6.5%
        (c.concept_id IN (3004410, 3003309, 3005673) AND m.value_as_number >= 6.5)
        OR
        -- Fasting Glucose >= 126 mg/dL
        (c.concept_id IN (3004501, 3005131) AND m.value_as_number >= 126)
        OR
        -- Random/Non-fasting Glucose >= 200 mg/dL
        (c.concept_id IN (3004501, 3005131, 3000483) AND m.value_as_number >= 200)
    )
),

diagnosis_count AS (
    -- Count diagnosis occurrences per person (at least 2 on different dates within 2 years)
    SELECT
        person_id,
        COUNT(DISTINCT condition_start_date) AS dx_count,
        MIN(condition_start_date) AS first_dx_date,
        MAX(condition_start_date) AS last_dx_date
    FROM t2dm_diagnosis
    GROUP BY person_id
    HAVING COUNT(DISTINCT condition_start_date) >= 2
        AND (MAX(condition_start_date) - MIN(condition_start_date)) <= 730  -- Within 2 years
),

dx_plus_labs AS (
    -- Patients with at least 1 diagnosis AND abnormal labs
    SELECT DISTINCT
        d.person_id,
        d.condition_start_date AS index_date
    FROM t2dm_diagnosis d
    INNER JOIN t2dm_labs l ON d.person_id = l.person_id
        AND l.measurement_date BETWEEN (d.condition_start_date - 90) AND (d.condition_start_date + 90)
),

dx_plus_meds AS (
    -- Patients with at least 1 diagnosis AND T2DM medications
    SELECT DISTINCT
        d.person_id,
        d.condition_start_date AS index_date
    FROM t2dm_diagnosis d
    INNER JOIN t2dm_medications m ON d.person_id = m.person_id
        AND m.drug_exposure_start_date >= d.condition_start_date
        AND m.drug_exposure_start_date <= (d.condition_start_date + 365)
),

t2dm_cohort AS (
    -- Combine all inclusion criteria
    SELECT DISTINCT
        person_id,
        'Multiple Diagnoses' AS inclusion_criteria
    FROM diagnosis_count
    
    UNION
    
    SELECT DISTINCT
        person_id,
        'Diagnosis + Labs' AS inclusion_criteria
    FROM dx_plus_labs
    
    UNION
    
    SELECT DISTINCT
        person_id,
        'Diagnosis + Medications' AS inclusion_criteria
    FROM dx_plus_meds
)

-- Final cohort: Include patients meeting criteria AND exclude those with exclusion diagnoses
SELECT DISTINCT
    tc.person_id,
    p.gender_concept_id,
    p.year_of_birth,
    p.race_concept_id,
    p.ethnicity_concept_id,
    STRING_AGG(DISTINCT tc.inclusion_criteria, '; ') AS criteria_met,
    MIN(d.condition_start_date) AS earliest_t2dm_date
FROM t2dm_cohort tc
INNER JOIN public.person p ON tc.person_id = p.person_id
LEFT JOIN t2dm_diagnosis d ON tc.person_id = d.person_id
WHERE tc.person_id NOT IN (SELECT person_id FROM exclusion_diagnosis)
GROUP BY tc.person_id, p.gender_concept_id, p.year_of_birth, p.race_concept_id, p.ethnicity_concept_id
ORDER BY tc.person_id;
