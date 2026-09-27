-- Type 2 Diabetes Mellitus (T2DM) Phenotyping Algorithm
-- Schema: Public (OMOP CDM)

WITH 
-- 1. Diagnostic Criteria: ICD-10 and ICD-9 codes for T2DM
t2dm_codes AS (
    SELECT person_id
    FROM condition_occurrence
    WHERE condition_concept_id IN (
        -- ICD-10: E11.x (Type 2 diabetes mellitus)
        -- ICD-9: 250.00, 250.01, etc.
        -- These would be mapped to OMOP concept IDs via the 'concept' table
        SELECT concept_id FROM concept 
        WHERE (concept_code LIKE 'E11%' AND vocabulary_id = 'ICD10CM')
           OR (concept_code LIKE '250.0%' AND vocabulary_id = 'ICD9CM')
    )
),

-- 2. Medication Criteria: T2DM Specific Drugs (Generic and Brand)
t2dm_meds AS (
    SELECT person_id
    FROM drug_exposure
    WHERE drug_concept_id IN (
        SELECT concept_id FROM concept 
        WHERE concept_name IN (
            'Metformin', 'Glucophage', 
            'Glipizide', 'Glimepiride', 'Glyburide', 
            'Empagliflozin', 'Jardiance', 
            'Canagliflozin', 'Invokana', 
            'Sitagliptin', 'Januvia', 
            'Linagliptin', 'Tradjenta'
        )
    )
),

-- 3. Lab Criteria: Hyperglycemia Markers
t2dm_labs AS (
    SELECT person_id
    FROM measurement
    WHERE (
        -- HbA1c >= 6.5%
        (measurement_concept_id IN (SELECT concept_id FROM concept WHERE concept_name = 'Hemoglobin A1c') 
         AND value_as_number >= 6.5)
        OR 
        -- Fasting Glucose >= 126 mg/dL
        (measurement_concept_id IN (SELECT concept_id FROM concept WHERE concept_name = 'Glucose [Fasting]') 
         AND value_as_number >= 126)
        OR
        -- Random Glucose >= 200 mg/dL
        (measurement_concept_id IN (SELECT concept_id FROM concept WHERE concept_name = 'Glucose [Random]') 
         AND value_as_number >= 200)
    )
),

-- 4. Exclusion Criteria: Type 1 or Gestational Diabetes
exclusion_criteria AS (
    SELECT person_id
    FROM condition_occurrence
    WHERE condition_concept_id IN (
        SELECT concept_id FROM concept 
        WHERE (concept_code LIKE 'E10%' AND vocabulary_id = 'ICD10CM') -- Type 1
           OR (concept_code LIKE 'O24.4%' AND vocabulary_id = 'ICD10CM') -- Gestational
    )
)

-- Final Algorithm Assembly
SELECT 
    p.person_id
FROM 
    person p
WHERE 
    -- (Diagnostic Codes OR Medications)
    (p.person_id IN (SELECT person_id FROM t2dm_codes) 
     OR p.person_id IN (SELECT person_id FROM t2dm_meds))
    
    -- AND Laboratory Confirmation
    AND p.person_id IN (SELECT person_id FROM t2dm_labs)
    
    -- AND NOT Exclusion Criteria
    AND p.person_id NOT IN (SELECT person_id FROM exclusion_criteria);