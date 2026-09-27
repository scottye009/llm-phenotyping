/* 
Type 2 Diabetes Phenotyping Algorithm
Schema: OMOP CDM (public)
*/

WITH T2DM_Diagnosis AS (
    -- Patients with T2DM codes (ICD10: E11, ICD9: 250.00/250.01)
    SELECT person_id, COUNT(*) as diag_count
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (
        SELECT concept_id 
        FROM public.concept 
        WHERE concept_code IN ('E11', '250.00', '250.01') 
        OR concept_id = 201826 -- OMOP Concept for T2DM
    )
    GROUP BY person_id
),

T2DM_Meds AS (
    -- Patients using T2DM specific medications (Generic and Brand)
    SELECT DISTINCT person_id
    FROM public.drug_exposure
    WHERE drug_concept_id IN (
        SELECT concept_id 
        FROM public.concept 
        WHERE concept_name LIKE '%Metformin%' 
           OR concept_name LIKE '%Glucophage%' 
           OR concept_name LIKE '%Glimepiride%' 
           OR concept_name LIKE '%Amaryl%' 
           OR concept_name LIKE '%Sitagliptin%' 
           OR concept_name LIKE '%Januvia%' 
           OR concept_name LIKE '%Empagliflozin%' 
           OR concept_name LIKE '%Jardiance%' 
           OR concept_name LIKE '%Liraglutide%' 
           OR concept_name LIKE '%Victoza%'
    )
),

T2DM_Labs AS (
    -- Patients meeting glucose/HbA1c thresholds
    SELECT person_id
    FROM public.measurement
    WHERE (
        (measurement_concept_id = 3004435 -- HbA1c
         AND value_as_number >= 6.5)
        OR 
        (measurement_concept_id = 3004436 -- Fasting Glucose
         AND value_as_number >= 126)
    )
    GROUP BY person_id
    HAVING COUNT(DISTINCT measurement_concept_id) >= 1
),

Exclusions AS (
    -- Exclude Type 1 and Gestational Diabetes
    SELECT person_id
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (
        SELECT concept_id 
        FROM public.concept 
        WHERE concept_code IN ('E10', '250.1', 'O24.4') -- T1DM and Gestational
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
    -- Scenario 3: Lab evidence alone (strict threshold)
    (l.person_id IS NOT NULL AND d.diag_count >= 1)
)
-- APPLY EXCLUSION
AND p.person_id NOT IN (SELECT person_id FROM Exclusions);