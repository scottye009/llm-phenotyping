
-- non of the alpha prompts ran directly, fixed stuff like public --> memory ...
/* 
Type 2 Diabetes Phenotyping Algorithm
Modified for Shire Environment: Denormalized Source Value Matching
*/

WITH T2DM_Diagnosis AS (
    -- Patients with T2DM codes (ICD10: E11, ICD9: 250.00/250.01)
    SELECT person_id, COUNT(*) as diag_count
    FROM public.condition_occurrence
    WHERE (
        condition_source_value LIKE 'E11%' COLLATE NOCASE 
        OR condition_source_value LIKE '250.00%' COLLATE NOCASE 
        OR condition_source_value LIKE '250.01%' COLLATE NOCASE
    )
    GROUP BY person_id
),

T2DM_Meds AS (
    -- Patients using T2DM specific medications (Generic and Brand)
    SELECT DISTINCT person_id
    FROM public.drug_exposure
    WHERE (
        drug_source_value LIKE '%Metformin%' COLLATE NOCASE 
        OR drug_source_value LIKE '%Glucophage%' COLLATE NOCASE 
        OR drug_source_value LIKE '%Glimepiride%' COLLATE NOCASE 
        OR drug_source_value LIKE '%Amaryl%' COLLATE NOCASE 
        OR drug_source_value LIKE '%Sitagliptin%' COLLATE NOCASE 
        OR drug_source_value LIKE '%Januvia%' COLLATE NOCASE 
        OR drug_source_value LIKE '%Empagliflozin%' COLLATE NOCASE 
        OR drug_source_value LIKE '%Jardiance%' COLLATE NOCASE 
        OR drug_source_value LIKE '%Liraglutide%' COLLATE NOCASE 
        OR drug_source_value LIKE '%Victoza%' COLLATE NOCASE
    )
),

T2DM_Labs AS (
    -- Patients meeting glucose/HbA1c thresholds
    SELECT person_id
    FROM public.measurement
    WHERE (
        (measurement_source_value LIKE '%HbA1c%' COLLATE NOCASE AND value_as_number >= 6.5)
        OR 
        (measurement_source_value LIKE '%Glucose%' COLLATE NOCASE AND measurement_source_value LIKE '%Fasting%' COLLATE NOCASE AND value_as_number >= 126)
    )
    GROUP BY person_id
    HAVING COUNT(DISTINCT measurement_source_value) >= 1
),

Exclusions AS (
    -- Exclude Type 1 and Gestational Diabetes
    SELECT person_id
    FROM public.condition_occurrence
    WHERE (
        condition_source_value LIKE 'E10%' COLLATE NOCASE 
        OR condition_source_value LIKE '250.1%' COLLATE NOCASE 
        OR condition_source_value LIKE 'O24.4%' COLLATE NOCASE
    )
)

-- Final Cohort Derivation
SELECT p.person_id
FROM public.person p
JOIN T2DM_Diagnosis d ON p.person_id = d.person_id
LEFT JOIN T2DM_Meds m ON p.person_id = m.person_id
LEFT JOIN T2DM_Labs l ON p.person_id = l.person_id
WHERE (
    -- Scenario 1: Two or more diagnosis records
    (d.diag_count >= 2) 
    OR 
    -- Scenario 2: One diagnosis record AND therapeutic evidence
    (d.diag_count >= 1 AND (m.person_id IS NOT NULL OR l.person_id IS NOT NULL))
    OR 
    -- Scenario 3: Lab evidence alone (strict threshold combined with diagnosis)
    (l.person_id IS NOT NULL AND d.diag_count >= 1)
)
-- APPLY EXCLUSION
AND p.person_id NOT IN (SELECT person_id FROM Exclusions)