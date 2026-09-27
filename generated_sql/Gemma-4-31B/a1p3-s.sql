-- Type 2 Diabetes Mellitus Phenotyping Algorithm
-- Modified for Shire Environment: Denormalized Source Value Matching

WITH

-- 1. Identify Patient Evidence via Source Values

patient_evidence AS (
SELECT
    p.person_id,

    -- Count distinct diagnosis occurrences using source value matching
    (SELECT COUNT(*) 
     FROM memory.condition_occurrence co 
     WHERE co.person_id = p.person_id
     AND (
         co.condition_source_value LIKE 'E11%' COLLATE NOCASE 
         OR co.condition_source_value LIKE '250.0%' COLLATE NOCASE
         OR co.condition_source_value IN ('E11', '250.00', '250.01', '250.02')
     )
    ) as diag_count,
     
    -- Check for drug exposure using source value matching
    (SELECT MAX(1) 
     FROM memory.drug_exposure de 
     WHERE de.person_id = p.person_id
     AND (
         de.drug_source_value LIKE '%Metformin%' COLLATE NOCASE OR 
         de.drug_source_value LIKE '%Glucophage%' COLLATE NOCASE OR
         de.drug_source_value LIKE '%Sitagliptin%' COLLATE NOCASE OR
         de.drug_source_value LIKE '%Januvia%' COLLATE NOCASE OR
         de.drug_source_value LIKE '%Empagliflozin%' COLLATE NOCASE OR
         de.drug_source_value LIKE '%Jardiance%' COLLATE NOCASE OR
         de.drug_source_value LIKE '%Pioglitazone%' COLLATE NOCASE
     )
    ) as has_med,
     
    -- Check for abnormal lab results using source value text and numeric thresholds
    (SELECT MAX(1) 
     FROM memory.measurement m 
     WHERE m.person_id = p.person_id 
     AND (
         (m.measurement_source_value LIKE '%Hemoglobin A1c%' COLLATE NOCASE OR m.measurement_source_value LIKE '%HbA1c%' COLLATE NOCASE AND m.value_as_number >= 6.5)
         OR 
         (m.measurement_source_value LIKE '%Glucose%' COLLATE NOCASE AND m.measurement_source_value LIKE '%Fasting%' COLLATE NOCASE AND m.value_as_number >= 126)
     )
    ) as has_lab,
     
    -- Exclusion flag (Type 1 or Gestational) using source values
    (SELECT MAX(1) 
     FROM memory.condition_occurrence co 
     WHERE co.person_id = p.person_id
     AND (
         co.condition_source_value LIKE 'E10%' COLLATE NOCASE 
         OR co.condition_source_value LIKE 'O24.4%' COLLATE NOCASE 
         OR co.condition_source_value LIKE '250.03%' COLLATE NOCASE
         OR co.condition_source_value IN ('E10', 'O24.4', '250.03')
     )
    ) as is_excluded
FROM memory.person p
)

-- 2. Apply Final Logic

SELECT
    person_id
FROM
    patient_evidence
WHERE
    -- EXCLUSION CRITERIA (NOT)
    is_excluded IS NULL

    AND (
        -- INCLUSION CRITERIA
        -- Case 1: 2+ Diagnoses
        (diag_count >= 2) 
        OR 
        -- Case 2: 1 Diagnosis AND (Med OR Lab)
        (diag_count >= 1 AND (has_med = 1 OR has_lab = 1)) 
        OR 
        -- Case 3: Med AND Lab
        (has_med = 1 AND has_lab = 1)
    )