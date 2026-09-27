-- Phenotyping Algorithm for Type 2 Diabetes Mellitus (T2DM)
-- Schema: Public (OMOP CDM)

WITH t2dm_diagnoses AS (
    -- Specific T2DM Codes (ICD-10: E11.x, ICD-9: 250.00)
    SELECT person_id
    FROM condition_occurrence
    WHERE condition_concept_id IN (
        -- OMOP Concepts mapping to ICD-10 E11 (T2DM) and ICD-9 250.00
        -- Example: 443250 (T2DM), 201820 (T2DM with complications)
        SELECT concept_id FROM concept 
        WHERE concept_code IN ('E11', '250.00') 
        AND vocabulary_id IN ('ICD10CM', 'ICD9CM')
    )
),

general_diabetes_diagnoses AS (
    -- General Diabetes codes that require further evidence
    SELECT person_id
    FROM condition_occurrence
    WHERE condition_concept_id IN (
        SELECT concept_id FROM concept 
        WHERE concept_code LIKE 'E10%' OR concept_code LIKE '250%' 
        AND vocabulary_id IN ('ICD10CM', 'ICD9CM')
    )
),

t2dm_meds AS (
    -- T2DM Specific Medications: Metformin (Glucophage), Sitagliptin (Januvia), etc.
    SELECT DISTINCT person_id
    FROM drug_exposure
    WHERE drug_concept_id IN (
        SELECT concept_id FROM concept 
        WHERE (concept_name LIKE '%Metformin%' OR concept_name LIKE '%Glucophage%' 
               OR concept_name LIKE '%Sitagliptin%' OR concept_name LIKE '%Januvia%'
               OR concept_name LIKE '%Empagliflozin%' OR concept_name LIKE '%Jardiance%'
               OR concept_name LIKE '%Liraglutide%' OR concept_name LIKE '%Victoza%'
               OR concept_name LIKE '%Glimepiride%' OR concept_name LIKE '%Amaryl%')
        AND domain_id = 'Drug'
    )
),

diabetes_labs AS (
    -- Lab thresholds: HbA1c >= 6.5% OR Fasting Glucose >= 126 mg/dL
    -- Concept IDs for HbA1c (e.g., 3004415) and Glucose (e.g., 3004421)
    SELECT person_id
    FROM measurement
    WHERE (measurement_concept_id IN (SELECT concept_id FROM concept WHERE concept_name = 'Hemoglobin A1c') 
           AND value_as_number >= 6.5)
       OR (measurement_concept_id IN (SELECT concept_id FROM concept WHERE concept_name = 'Glucose') 
           AND value_as_number >= 126)
),

exclusion_criteria AS (
    -- Exclude Type 1 and Gestational Diabetes
    SELECT person_id
    FROM condition_occurrence
    WHERE condition_concept_id IN (
        SELECT concept_id FROM concept 
        WHERE (concept_code LIKE 'E10%' OR concept_code LIKE 'O24.4%') 
        AND vocabulary_id IN ('ICD10CM', 'ICD9CM')
    )
)

-- Final Cohort Definition
SELECT DISTINCT p.person_id
FROM person p
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
WHERE p.person_id NOT IN (SELECT person_id FROM exclusion_criteria);