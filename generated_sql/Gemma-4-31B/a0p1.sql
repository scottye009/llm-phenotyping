WITH T2DM_Diagnosis AS (
    -- ICD-10 E11.x or ICD-9 250.00/250.01
    SELECT person_id 
    FROM condition_occurrence 
    WHERE condition_concept_id IN (
        SELECT concept_id FROM concept 
        WHERE (concept_code LIKE 'E11%' AND vocabulary_id = 'ICD10CM') 
           OR (concept_code IN ('250.00', '250.01') AND vocabulary_id = 'ICD9CM')
    )
),

T2DM_Labs AS (
    -- HbA1c >= 6.5% OR FPG >= 126 OR Random Glucose >= 200
    -- OMOP Concept IDs: HbA1c (3004621), Fasting Glucose (4026956), Glucose (3004611)
    SELECT person_id 
    FROM measurement 
    WHERE (measurement_concept_id = 3004621 AND value_as_number >= 6.5)
       OR (measurement_concept_id = 4026956 AND value_as_number >= 126)
       OR (measurement_concept_id = 3004611 AND value_as_number >= 200)
    GROUP BY person_id 
    HAVING COUNT(DISTINCT measurement_date) >= 2 -- Requirement for reproducibility
),

T2DM_Meds AS (
    -- Generic and Brand names for T2DM specific drugs
    SELECT person_id 
    FROM drug_exposure 
    WHERE drug_concept_id IN (
        SELECT concept_id FROM concept 
        WHERE concept_name IN (
            'Metformin', 'Glucophage', 
            'Glimepiride', 'Amaryl', 
            'Glyburide', 'DiaBeta', 
            'Glipizide', 'Glucotrol', 
            'Sitagliptin', 'Januvia', 
            'Saxagliptin', 'Onglyza', 
            'Empagliflozin', 'Jardiance', 
            'Dapagliflozin', 'Farxiga', 
            'Liraglutide', 'Victoza', 
            'Semaglutide', 'Ozempic', 
            'Pioglitazone', 'Actos'
        )
    )
),

Exclusions AS (
    -- Exclude Type 1 and Gestational Diabetes
    SELECT person_id 
    FROM condition_occurrence 
    WHERE condition_concept_id IN (
        SELECT concept_id FROM concept 
        WHERE (concept_code LIKE 'E10%' AND vocabulary_id = 'ICD10CM') -- T1DM
           OR (concept_code LIKE 'O24.4%' AND vocabulary_id = 'ICD10CM') -- Gestational
    )
)

-- Final Phenotype Logic
SELECT DISTINCT p.person_id
FROM person p
JOIN (
    SELECT person_id FROM T2DM_Diagnosis
    UNION 
    SELECT person_id FROM T2DM_Labs
    UNION 
    SELECT person_id FROM T2DM_Meds
) AS inclusion ON p.person_id = inclusion.person_id
WHERE p.person_id NOT IN (SELECT person_id FROM Exclusions);