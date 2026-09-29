-- Type 2 Diabetes Mellitus (T2DM) Phenotyping Algorithm
-- Modified for Shire Environment: Denormalized Source Value Matching

WITH t2dm_diagnoses AS (
-- Specific T2DM Codes (ICD-10: E11.x, ICD-9: 250.00)
    SELECT DISTINCT person_id
    FROM memory.condition_occurrence
    WHERE (
        condition_source_value LIKE 'E11%' COLLATE NOCASE 
        OR condition_source_value LIKE '250.00%' COLLATE NOCASE
    )
),

general_diabetes_diagnoses AS (
-- General Diabetes codes that require further evidence
-- Includes E10, etc., and any code starting with 250
    SELECT DISTINCT person_id
    FROM memory.condition_occurrence
    WHERE (
        condition_source_value LIKE 'E10%' COLLATE NOCASE 
        OR condition_source_value LIKE '250%' COLLATE NOCASE
    )
),

t2dm_meds AS (
-- T2DM Specific Medications: Metformin, Sitagliptin, etc.
    SELECT DISTINCT person_id
    FROM memory.drug_exposure
    WHERE (
        drug_source_value LIKE '%Metformin%' COLLATE NOCASE OR drug_source_value LIKE '%Glucophage%' COLLATE NOCASE 
        OR drug_source_value LIKE '%Sitagliptin%' COLLATE NOCASE OR drug_source_value LIKE '%Januvia%' COLLATE NOCASE
        OR drug_source_value LIKE '%Empagliflozin%' COLLATE NOCASE OR drug_source_value LIKE '%Jardiance%' COLLATE NOCASE
        OR drug_source_value LIKE '%Liraglutide%' COLLATE NOCASE OR drug_source_value LIKE '%Victoza%' COLLATE NOCASE
        OR drug_source_value LIKE '%Glimepiride%' COLLATE NOCASE OR drug_source_value LIKE '%Amaryl%' COLLATE NOCASE
    )
),

diabetes_labs AS (
-- Lab thresholds: HbA1c >= 6.5% OR Glucose >= 126 mg/dL
    SELECT DISTINCT person_id
    FROM memory.measurement
    WHERE (
        (measurement_source_value LIKE '%Hemoglobin A1c%' COLLATE NOCASE OR measurement_source_value LIKE '%HbA1c%' COLLATE NOCASE) 
        AND value_as_number >= 6.5
    ) 
    OR (
        (measurement_source_value LIKE '%Glucose%' COLLATE NOCASE) 
        AND value_as_number >= 126
    )
),

exclusion_criteria AS (
-- Exclude Type 1 and Gestational Diabetes
    SELECT DISTINCT person_id
    FROM memory.condition_occurrence
    WHERE (
        condition_source_value LIKE 'E10%' COLLATE NOCASE 
        OR condition_source_value LIKE 'O24.4%' COLLATE NOCASE
    )
)

-- Final Cohort Definition
SELECT DISTINCT p.person_id
FROM memory.person p
JOIN (
-- Logic: (Direct T2DM Dx)
--        OR (General Dx AND (Lab OR Med))
--        OR (No Dx AND (Lab AND Med))
    SELECT person_id FROM t2dm_diagnoses
    UNION
    SELECT gd.person_id 
    FROM general_diabetes_diagnoses gd
    WHERE gd.person_id IN (SELECT person_id FROM diabetes_labs) 
       OR gd.person_id IN (SELECT person_id FROM t2dm_meds)
    UNION
    SELECT dl.person_id 
    FROM diabetes_labs dl
    JOIN t2dm_meds tm ON dl.person_id = tm.person_id
) AS evidence ON p.person_id = evidence.person_id
WHERE p.person_id NOT IN (SELECT person_id FROM exclusion_criteria)