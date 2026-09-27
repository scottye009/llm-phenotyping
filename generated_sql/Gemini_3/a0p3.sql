--error
WITH T2DM_Codes AS (
    -- ICD-10: E11.x; ICD-9: 250.x0, 250.x2 (Non-insulin dependent)
    SELECT concept_id 
    FROM concept_relationship 
    WHERE relationship_id = 'Maps to' 
    AND concept_code IN ('E11', 'E11.9', 'E11.65', '250.00', '250.02')
),

T1DM_GDM_Exclusions AS (
    -- T1DM: E10.x, 250.x1, 250.x3; GDM: O24.4
    SELECT concept_id 
    FROM concept_relationship 
    WHERE relationship_id = 'Maps to' 
    AND concept_code IN ('E10', '250.01', '250.03', 'O24.4')
),

T2DM_Diagnosis_Evidence AS (
    SELECT person_id 
    FROM condition_occurrence 
    WHERE condition_concept_id IN (SELECT concept_id FROM T2DM_Codes)
    GROUP BY person_id 
    HAVING COUNT(DISTINCT condition_start_date) >= 2
),

T2DM_Lab_Evidence AS (
    SELECT person_id 
    FROM measurement 
    WHERE (
        (measurement_concept_id IN (3004410, 4078571) AND value_as_number >= 6.5) -- HbA1c
        OR 
        (measurement_concept_id IN (3000845, 3004501) AND value_as_number >= 126) -- Fasting Glucose
    )
    GROUP BY person_id 
    HAVING COUNT(DISTINCT measurement_date) >= 2
),

T2DM_Med_Evidence AS (
    SELECT person_id 
    FROM drug_exposure 
    WHERE drug_concept_id IN (
        SELECT concept_id FROM concept 
        WHERE (concept_name LIKE '%Metformin%' OR concept_name LIKE '%Glucophage%')
           OR (concept_name LIKE '%Sitagliptin%' OR concept_name LIKE '%Januvia%')
           OR (concept_name LIKE '%Empagliflozin%' OR concept_name LIKE '%Jardiance%')
           OR (concept_name LIKE '%Liraglutide%' OR concept_name LIKE '%Victoza%')
           OR (concept_name LIKE '%Glimepiride%' OR concept_name LIKE '%Amaryl%')
           OR (concept_name LIKE '%Pioglitazone%' OR concept_name LIKE '%Actos%')
    )
),

Exclusion_List AS (
    SELECT DISTINCT person_id 
    FROM condition_occurrence 
    WHERE condition_concept_id IN (SELECT concept_id FROM T1DM_GDM_Exclusions)
)

-- Final Phenotype Selection
SELECT DISTINCT p.person_id
FROM person p
INNER JOIN (
    SELECT person_id FROM T2DM_Diagnosis_Evidence
    UNION
    SELECT person_id FROM T2DM_Lab_Evidence
    UNION
    SELECT person_id FROM T2DM_Med_Evidence
) AS Evidence ON p.person_id = Evidence.person_id
LEFT JOIN Exclusion_List ex ON p.person_id = ex.person_id
WHERE ex.person_id IS NULL;