/* 
   Phenotype: Type 2 Diabetes Mellitus (T2DM)
   Logic: (Diagnosis OR (Labs AND Meds)) AND NOT (Exclusions)
*/

WITH T2DM_Diagnosis AS (
    SELECT person_id 
    FROM condition_occurrence 
    WHERE condition_concept_id = 443238 -- OMOP: Type 2 diabetes mellitus
       OR condition_source_value LIKE 'E11%' -- ICD-10
       OR condition_source_value IN ('250.00', '250.01') -- ICD-9
),

T2DM_Labs AS (
    SELECT person_id 
    FROM measurement 
    WHERE (measurement_concept_id = 3004320 AND measurement_value >= 6.5) -- HbA1c
       OR (measurement_concept_id = 3004321 AND measurement_value >= 126) -- Fasting Glucose
),

T2DM_Meds AS (
    SELECT person_id 
    FROM drug_exposure 
    WHERE drug_concept_id IN (
        -- Biguanides
        -- Metformin / Glucophage
        -- Sulfonylureas
        -- Glipizide / Glucotrol, Glyburide / Glynase
        -- DPP-4s
        -- Sitagliptin / Januvia, Saxagliptin / Onglyza
        -- SGLT2s
        -- Empagliflozin / Jardiance, Canagliflozin / Invokana
        -- GLP-1s
        -- Liraglutide / Victoza, Semaglutide / Ozempic
    )
),

Exclusions AS (
    SELECT person_id 
    FROM condition_occurrence 
    WHERE condition_source_value LIKE 'E10%' -- Type 1 (ICD-10)
       OR condition_source_value = '250.02' -- Type 1 (ICD-9)
       OR condition_source_value LIKE 'O24.4%' -- Gestational (ICD-10)
       OR condition_source_value = '782.4' -- Gestational (ICD-9)
       OR condition_source_value LIKE 'E13%' -- Other specified (ICD-10)
)

SELECT DISTINCT 
    p.person_id
FROM person p
JOIN (
    -- Inclusion Logic: Diagnosis OR (Labs AND Meds)
    SELECT person_id FROM T2DM_Diagnosis
    UNION
    SELECT l.person_id 
    FROM T2DM_Labs l 
    JOIN T2DM_Meds m ON l.person_id = m.person_id
) as inclusion ON p.person_id = inclusion.person_id
LEFT JOIN Exclusions e ON p.person_id = e.person_id
WHERE e.person_id IS NULL; -- NOT in Exclusions