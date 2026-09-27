-- Phenotyping Algorithm for Type 2 Diabetes Mellitus (T2DM)
-- Schema: public

WITH T2DM_Diagnosis AS (
    -- T2DM Concept IDs (mapping ICD10 E11 and ICD9 250.0x)
    SELECT DISTINCT person_id
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (
        SELECT concept_id FROM public.concept 
        WHERE (concept_code IN ('E11', 'E11.9', '250.00', '250.01') 
               AND vocabulary_id IN ('ICD10CM', 'ICD9CM'))
        OR concept_id IN (
            -- Including OMOP Standardized concepts for T2DM
            SELECT concept_id FROM public.concept WHERE concept_name LIKE '%Type 2 diabetes mellitus%' 
            AND domain_id = 'Condition'
        )
    )
),

T1DM_Exclusion AS (
    -- T1DM and Gestational Diabetes Concept IDs for Exclusion
    SELECT DISTINCT person_id
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (
        SELECT concept_id FROM public.concept 
        WHERE (concept_code LIKE 'E10%' OR concept_code LIKE 'O24.4%') 
               AND vocabulary_id IN ('ICD10CM', 'ICD9CM')
    )
),

Hyperglycemia_Labs AS (
    -- HbA1c >= 6.5% or Fasting Glucose >= 126 mg/dL
    SELECT DISTINCT person_id
    FROM public.measurement
    WHERE (
        (measurement_concept_id IN (SELECT concept_id FROM public.concept WHERE concept_name LIKE '%Hemoglobin A1c%') 
         AND value_as_number >= 6.5)
        OR 
        (measurement_concept_id IN (SELECT concept_id FROM public.concept WHERE concept_name LIKE '%Glucose%') 
         AND value_as_number >= 126)
    )
),

T2DM_Medications AS (
    -- Generic and Brand names for T2DM specific meds
    SELECT DISTINCT person_id
    FROM public.drug_exposure
    WHERE drug_concept_id IN (
        SELECT concept_id FROM public.concept 
        WHERE (concept_name IN (
            'Metformin', 'Glucophage', 
            'Glimepiride', 'Amaryl', 
            'Sitagliptin', 'Januvia', 
            'Empagliflozin', 'Jardiance', 
            'Liraglutide', 'Victoza', 
            'Canagliflozin', 'Invokana'
        ))
        OR concept_id IN (
            SELECT concept_id FROM public.concept_ancestor 
            WHERE ancestor_concept_id IN (
                -- Target common medication classes (e.g., Biguanides)
                SELECT concept_id FROM public.concept WHERE concept_name = 'Biguanides'
            )
        )
    )
),

T2DM_Counts AS (
    -- Counting occurrences of T2DM codes for Pathway A
    SELECT person_id, COUNT(*) as diag_count
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (SELECT concept_id FROM public.concept WHERE concept_code = 'E11')
    GROUP BY person_id
)

-- Final Cohort Assembly
SELECT 
    p.person_id
FROM public.person p
JOIN T2DM_Diagnosis d ON p.person_id = d.person_id
LEFT JOIN T1DM_Exclusion e ON p.person_id = e.person_id
LEFT JOIN Hyperglycemia_Labs l ON p.person_id = l.person_id
LEFT JOIN T2DM_Medications m ON p.person_id = m.person_id
LEFT JOIN T2DM_Counts c ON p.person_id = c.person_id
WHERE 
    -- EXCLUSION: Must NOT have T1DM or Gestational Diabetes
    e.person_id IS NULL 
    AND (
        -- Pathway A: High frequency of diagnostic codes
        (c.diag_count >= 2) 
        OR 
        -- Pathway B: Diagnosis AND Lab Verification
        (d.person_id IS NOT NULL AND l.person_id IS NOT NULL) 
        OR 
        -- Pathway C: Diagnosis AND Medication
        (d.person_id IS NOT NULL AND m.person_id IS NOT NULL) 
        OR 
        -- Pathway D: Medication AND Lab Verification
        (m.person_id IS NOT NULL AND l.person_id IS NOT NULL)
    );