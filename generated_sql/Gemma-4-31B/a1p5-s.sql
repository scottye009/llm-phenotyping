-- Phenotyping Algorithm for Type 2 Diabetes Mellitus (T2DM)
-- Modified for Shire Environment: Denormalized Source Value Matching

WITH T2DM_Diagnosis AS (
    -- T2DM Identification using source values (ICD10 E11, ICD9 250.0x)
    SELECT DISTINCT person_id
    FROM public.condition_occurrence
    WHERE (
        condition_source_value LIKE 'E11%' COLLATE NOCASE 
        OR condition_source_value LIKE '250.0%' COLLATE NOCASE
        OR condition_source_value IN ('E11', 'E11.9', '250.00', '250.01') COLLATE NOCASE
    )
),

T1DM_Exclusion AS (
    -- T1DM and Gestational Diabetes Identification for Exclusion
    SELECT DISTINCT person_id
    FROM public.condition_occurrence
    WHERE (
        condition_source_value LIKE 'E10%' COLLATE NOCASE 
        OR condition_source_value LIKE 'O24.4%' COLLATE NOCASE
    )
),

Hyperglycemia_Labs AS (
    -- HbA1c >= 6.5% or Fasting Glucose >= 126 mg/dL
    SELECT DISTINCT person_id
    FROM public.measurement
    WHERE (
        (measurement_source_value LIKE '%Hemoglobin A1c%' COLLATE NOCASE OR measurement_source_value LIKE '%HbA1c%' COLLATE NOCASE AND value_as_number >= 6.5)
        OR 
        (measurement_source_value LIKE '%Glucose%' COLLATE NOCASE AND value_as_number >= 126)
    )
),

T2DM_Medications AS (
    -- Generic and Brand names for T2DM specific meds via source value
    SELECT DISTINCT person_id
    FROM public.drug_exposure
    WHERE (
        drug_source_value IN (
            'Metformin', 'Glucophage', 
            'Glimepiride', 'Amaryl', 
            'Sitagliptin', 'Januvia', 
            'Empagliflozin', 'Jardiance', 
            'Liraglutide', 'Victoza', 
            'Canagliflozin', 'Invokana'
        ) COLLATE NOCASE 
        OR drug_source_value LIKE '%Metformin%' COLLATE NOCASE
        -- Note: Concept ancestor logic (e.g. Biguanides) is replaced by keyword matching on source values
        OR drug_source_value LIKE '%Biguanide%' COLLATE NOCASE
    )
),

T2DM_Counts AS (
    -- Counting occurrences of T2DM codes for Pathway A
    SELECT person_id, COUNT(*) as diag_count
    FROM public.condition_occurrence
    WHERE condition_source_value LIKE 'E11%' COLLATE NOCASE
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
    )