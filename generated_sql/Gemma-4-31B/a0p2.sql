/* 
Phenotype: Type 2 Diabetes Mellitus (T2DM)
Logic: (Diagnosis OR Lab OR Medication) AND NOT (T1DM OR Gestational)
*/

WITH T2DM_Diagnosis AS (
    SELECT person_id 
    FROM condition_occurrence 
    WHERE condition_concept_id IN (
        -- ICD10 CM: E11.x (Type 2 Diabetes)
        -- ICD9 CM: 250.00, 250.01, 250.02, 250.1x, 250.2x
        -- Including OMOP concept mappings for T2DM
        SELECT concept_id FROM concept_relationship 
        WHERE relationship_id = 'Maps to' 
        AND concept_code IN ('E11', '250.00', '250.01', '250.02', '250.10', '250.11', '250.20')
    )
    GROUP BY person_id
    HAVING COUNT(DISTINCT condition_occurrence_id) >= 1
),

T2DM_Labs AS (
    SELECT person_id 
    FROM measurement 
    WHERE (
        (measurement_concept_id = 30040 -- HbA1c 
         AND value_as_number >= 6.5) 
        OR 
        (measurement_concept_id = 150748 -- Fasting Glucose 
         AND value_as_number >= 126)
    )
    GROUP BY person_id
    HAVING COUNT(DISTINCT measurement_id) >= 2 -- Requirement for 2 tests for high confidence
),

T2DM_Meds AS (
    SELECT person_id 
    FROM drug_exposure 
    WHERE drug_concept_id IN (
        -- Generic and Brand Names
        -- Metformin (Glucophage), Empagliflozin (Jardiance), 
        -- Canagliflozin (Invokana), Semaglutide (Ozempic), 
        -- Liraglutide (Victoza), Sitagliptin (Januvia), Glimepiride (Amaryl)
        SELECT concept_id FROM concept 
        WHERE concept_name LIKE '%Metformin%' 
           OR concept_name LIKE '%Glucophage%' 
           OR concept_name LIKE '%Empagliflozin%' 
           OR concept_name LIKE '%Jardiance%' 
           OR concept_name LIKE '%Semaglutide%' 
           OR concept_name LIKE '%Ozempic%' 
           OR concept_name LIKE '%Sitagliptin%'
    )
),

Exclusions AS (
    SELECT person_id 
    FROM condition_occurrence 
    WHERE condition_concept_id IN (
        -- Type 1 Diabetes (ICD10 E10 / ICD9 250.x specific to T1)
        -- Gestational Diabetes (ICD10 O24.4)
        SELECT concept_id FROM concept_relationship 
        WHERE relationship_id = 'Maps to' 
        AND concept_code IN ('E10', 'O24.4')
    )
)

-- Final Phenotype Assembly
SELECT DISTINCT p.person_id
FROM person p
JOIN (
    -- Rule 1: Multiple Diagnoses
    SELECT person_id FROM T2DM_Diagnosis 
    WHERE person_id IN (SELECT person_id FROM T2DM_Diagnosis GROUP BY person_id HAVING COUNT(*) >= 2)
    
    UNION
    
    -- Rule 2: Diagnosis AND Lab
    SELECT d.person_id 
    FROM T2DM_Diagnosis d 
    INNER JOIN T2DM_Labs l ON d.person_id = l.person_id
    
    UNION
    
    -- Rule 3: Diagnosis AND Medication
    SELECT d.person_id 
    FROM T2DM_Diagnosis d 
    INNER JOIN T2DM_Meds m ON d.person_id = m.person_id
    
    UNION
    
    -- Rule 4: High confidence Lab evidence alone
    SELECT person_id FROM T2DM_Labs
) AS T2DM_Criteria ON p.person_id = T2DM_Criteria.person_id

WHERE p.person_id NOT IN (SELECT person_id FROM Exclusions);