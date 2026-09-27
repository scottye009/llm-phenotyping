-- T2DM Phenotyping Algorithm
-- Schema: public (OMOP CDM)

WITH 
-- 1. Diagnosis Criteria: T2DM Specific
t2dm_dx AS (
    SELECT person_id 
    FROM condition_occurrence 
    WHERE condition_concept_id IN (
        -- ICD10CM: E11 (Type 2 diabetes mellitus)
        -- ICD9CM: 250.00, 250.01, 250.02 (T2DM without complications)
        -- Concept IDs would be mapped here from the 'concept' table
        SELECT concept_id FROM concept 
        WHERE (vocabulary_id = 'ICD10CM' AND concept_code LIKE 'E11%')
           OR (vocabulary_id = 'ICD9CM' AND concept_code LIKE '250.0%')
    )
),

-- 2. Medication Criteria: T2DM Specific Drugs
t2dm_meds AS (
    SELECT DISTINCT person_id 
    FROM drug_exposure 
    WHERE drug_concept_id IN (
        -- Metformin (Glucophage), Sitagliptin (Januvia), Empagliflozin (Jardiance), etc.
        SELECT concept_id FROM concept 
        WHERE concept_name LIKE '%Metformin%' 
           OR concept_name LIKE '%Sitagliptin%' 
           OR concept_name LIKE '%Empagliflozin%'
           OR concept_name LIKE '%Glimepiride%'
    )
),

-- 3. Lab Criteria: Hyperglycemia
hyperglycemia_labs AS (
    SELECT person_id 
    FROM measurement 
    WHERE measurement_concept_id IN (
        -- HbA1c, Fasting Glucose, Glucose
        SELECT concept_id FROM concept 
        WHERE concept_name LIKE '%Hemoglobin A1c%' 
           OR concept_name LIKE '%Glucose%'
    ) 
    AND value_as_number >= 6.5 -- Simplified threshold (e.g., HbA1c >= 6.5)
),

-- 4. Exclusion Criteria: T1DM or Gestational
exclusion_criteria AS (
    SELECT person_id 
    FROM condition_occurrence 
    WHERE condition_concept_id IN (
        -- ICD10CM: E10 (Type 1), O24.4 (Gestational diabetes)
        SELECT concept_id FROM concept 
        WHERE (vocabulary_id = 'ICD10CM' AND (concept_code LIKE 'E10%' OR concept_code LIKE 'O24.4%'))
           OR (vocabulary_id = 'ICD9CM' AND concept_code LIKE '250.1%')
    )
)

-- Final Cohort Derivation
SELECT DISTINCT p.person_id
FROM person p
JOIN (
    -- Logic: (Multiple DX) OR (DX AND (Med OR Lab)) OR (Lab AND Med)
    SELECT person_id FROM t2dm_dx
    UNION 
    SELECT t2dm_dx.person_id 
    FROM t2dm_dx 
    JOIN t2dm_meds ON t2dm_dx.person_id = t2dm_meds.person_id
    UNION
    SELECT t2dm_dx.person_id 
    FROM t2dm_dx 
    JOIN hyperglycemia_labs ON t2dm_dx.person_id = hyperglycemia_labs.person_id
    UNION
    SELECT t2dm_meds.person_id 
    FROM t2dm_meds 
    JOIN hyperglycemia_labs ON t2dm_meds.person_id = hyperglycemia_labs.person_id
) as inclusion ON p.person_id = inclusion.person_id
WHERE p.person_id NOT IN (SELECT person_id FROM exclusion_criteria);