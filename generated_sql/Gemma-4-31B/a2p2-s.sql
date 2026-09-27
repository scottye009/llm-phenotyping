-- Type 2 Diabetes Mellitus (T2DM) Phenotyping Algorithm
-- Modified for Shire Environment: Denormalized Source Value Matching

WITH 
-- 1. Diagnostic Criteria: ICD-10 and ICD-9 codes for T2DM
t2dm_codes AS (
    SELECT DISTINCT person_id
    FROM public.condition_occurrence
    WHERE (
        condition_source_value LIKE 'E11%' COLLATE NOCASE -- ICD-10: E11.x
        OR condition_source_value LIKE '250.0%' COLLATE NOCASE -- ICD-9: 250.0x
    )
),

-- 2. Medication Criteria: T2DM Specific Drugs (Generic and Brand)
t2dm_meds AS (
    SELECT DISTINCT person_id
    FROM public.drug_exposure
    WHERE (
        drug_source_value IN (
            'Metformin', 'Glucophage', 
            'Glipizide', 'Glimepiride', 'Glyburide', 
            'Empagliflozin', 'Jardiance', 
            'Canagliflozin', 'Invokana', 
            'Sitagliptin', 'Januvia', 
            'Linagliptin', 'Tradjenta'
        ) COLLATE NOCASE
        OR drug_source_value LIKE '%Metformin%' COLLATE NOCASE
    )
),

-- 3. Lab Criteria: Hyperglycemia Markers
t2dm_labs AS (
    SELECT DISTINCT person_id
    FROM public.measurement
    WHERE (
        -- HbA1c >= 6.5%
        (measurement_source_value LIKE '%Hemoglobin A1c%' COLLATE NOCASE 
         OR measurement_source_value LIKE '%HbA1c%' COLLATE NOCASE) 
         AND value_as_number >= 6.5
        OR 
        -- Fasting Glucose >= 126 mg/dL
        (measurement_source_value LIKE '%Glucose%' COLLATE NOCASE AND measurement_source_value LIKE '%Fasting%' COLLATE NOCASE 
         AND value_as_number >= 126)
        OR
        -- Random Glucose >= 200 mg/dL
        (measurement_source_value LIKE '%Glucose%' COLLATE NOCASE AND measurement_source_value LIKE '%Random%' COLLATE NOCASE 
         AND value_as_number >= 200)
    )
),

-- 4. Exclusion Criteria: Type 1 or Gestational Diabetes
exclusion_criteria AS (
    SELECT DISTINCT person_id
    FROM public.condition_occurrence
    WHERE (
        condition_source_value LIKE 'E10%' COLLATE NOCASE -- Type 1
        OR condition_source_value LIKE 'O24.4%' COLLATE NOCASE -- Gestational
    )
)

-- Final Algorithm Assembly
SELECT 
    p.person_id
FROM 
    public.person p
WHERE 
    -- (Diagnostic Codes OR Medications)
    (p.person_id IN (SELECT person_id FROM t2dm_codes) 
     OR p.person_id IN (SELECT person_id FROM t2dm_meds))
    
    -- AND Laboratory Confirmation
    AND p.person_id IN (SELECT person_id FROM t2dm_labs)
    
    -- AND NOT Exclusion Criteria
    AND p.person_id NOT IN (SELECT person_id FROM exclusion_criteria)