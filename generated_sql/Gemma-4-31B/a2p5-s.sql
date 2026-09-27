-- T2DM Phenotyping Algorithm
-- Modified for Shire Environment: Denormalized Source Value Matching

WITH 
-- 1. Diagnosis Criteria: T2DM Specific
t2dm_dx AS (
    SELECT DISTINCT person_id 
    FROM memory.condition_occurrence 
    WHERE (
        condition_source_value LIKE 'E11%' COLLATE NOCASE -- ICD10CM: E11 (T2DM)
        OR condition_source_value LIKE '250.0%' COLLATE NOCASE -- ICD9CM: 250.0x (T2DM)
    )
),

-- 2. Medication Criteria: T2DM Specific Drugs
t2dm_meds AS (
    SELECT DISTINCT person_id 
    FROM memory.drug_exposure 
    WHERE (
        drug_source_value LIKE '%Metformin%' COLLATE NOCASE 
        OR drug_source_value LIKE '%Sitagliptin%' COLLATE NOCASE 
        OR drug_source_value LIKE '%Empagliflozin%' COLLATE NOCASE
        OR drug_source_value LIKE '%Glimepiride%' COLLATE NOCASE
    )
),

-- 3. Lab Criteria: Hyperglycemia
hyperglycemia_labs AS (
    SELECT DISTINCT person_id 
    FROM memory.measurement 
    WHERE (
        (measurement_source_value LIKE '%Hemoglobin A1c%' COLLATE NOCASE 
         OR measurement_source_value LIKE '%HbA1c%' COLLATE NOCASE) 
        OR 
        (measurement_source_value LIKE '%Glucose%' COLLATE NOCASE)
    ) 
    AND value_as_number >= 6.5 -- Preserving logic: Simplified overall threshold
),

-- 4. Exclusion Criteria: T1DM or Gestational
exclusion_criteria AS (
    SELECT DISTINCT person_id 
    FROM memory.condition_occurrence 
    WHERE (
        condition_source_value LIKE 'E10%' COLLATE NOCASE -- ICD10CM: E10 (Type 1)
        OR condition_source_value LIKE 'O24.4%' COLLATE NOCASE -- ICD10CM: O24.4 (Gestational)
        OR condition_source_value LIKE '250.1%' COLLATE NOCASE -- ICD9CM: 250.1 (Type 1)
    )
)

-- Final Cohort Derivation
SELECT DISTINCT p.person_id
FROM memory.person p
JOIN (
-- Logic: (Multiple DX) OR (DX AND (Med OR Lab)) OR (Lab AND Med)
-- Note:- In the original "Multiple DX" was simplified to a UNION of t2dm_dx
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
WHERE p.person_id NOT IN (SELECT person_id FROM exclusion_criteria)