--0row
WITH T2DM_Diagnosis AS (
    -- ICD-10 E11.x or ICD-9 250.x0/250.x2
    SELECT person_id 
    FROM condition_occurrence 
    WHERE condition_concept_id IN (
        SELECT concept_id FROM concept 
        WHERE (concept_code LIKE 'E11%' AND vocabulary_id = 'ICD10CM') 
           OR (concept_code LIKE '250.%0' AND vocabulary_id = 'ICD9CM')
           OR (concept_code LIKE '250.%2' AND vocabulary_id = 'ICD9CM')
    )
),

T2DM_Labs AS (
    -- HbA1c >= 6.5% OR Random/Fasting Glucose >= 200 mg/dL
    -- OMOP Concept IDs: HbA1c (3004621), Glucose (3004611, 4026956)
    SELECT person_id 
    FROM measurement 
    WHERE (measurement_concept_id = 3004621 AND value_as_number >= 6.5)
       OR (measurement_concept_id IN (3004611, 4026956) AND value_as_number >= 200)
    GROUP BY person_id 
    HAVING COUNT(DISTINCT measurement_date) >= 2 
),

T2DM_Meds AS (
    -- Generic and Brand names for T2DM specific drugs
    SELECT person_id 
    FROM drug_exposure 
    WHERE drug_concept_id IN (
        SELECT concept_id FROM concept 
        WHERE LOWER(concept_name) IN (
            'metformin', 'glucophage', 'fortamet', 'glumetza',
            'glipizide', 'glucotrol', 
            'glyburide', 'diabeta', 'glynase',
            'glimepiride', 'amaryl',
            'sitagliptin', 'januvia',
            'saxagliptin', 'onglyza',
            'linagliptin', 'tradjenta',
            'empagliflozin', 'jardiance',
            'dapagliflozin', 'farxiga',
            'canagliflozin', 'invokana',
            'liraglutide', 'victoza',
            'semaglutide', 'ozempic', 'rybelsus',
            'pioglitazone', 'actos'
        )
    )
),

Exclusions AS (
    -- Exclude Type 1 Diabetes and Gestational Diabetes
    SELECT person_id 
    FROM condition_occurrence 
    WHERE condition_concept_id IN (
        SELECT concept_id FROM concept 
        WHERE (concept_code LIKE 'E10%' AND vocabulary_id = 'ICD10CM') -- T1DM
           OR (concept_code LIKE '250.%1' AND vocabulary_id = 'ICD9CM') -- T1DM
           OR (concept_code LIKE '250.%3' AND vocabulary_id = 'ICD9CM') -- T1DM
           OR (concept_code LIKE 'O24.4%' AND vocabulary_id = 'ICD10CM') -- Gestational
           OR (concept_code = '648.8' AND vocabulary_id = 'ICD9CM') -- Gestational
    )
)

-- Final Phenotype logic: (Diagnosis OR Labs OR Meds) AND NOT Exclusions
SELECT DISTINCT inclusion.person_id
FROM (
    SELECT person_id FROM T2DM_Diagnosis
    UNION 
    SELECT person_id FROM T2DM_Labs
    UNION 
    SELECT person_id FROM T2DM_Meds
) AS inclusion
LEFT JOIN Exclusions e ON inclusion.person_id = e.person_id
WHERE e.person_id IS NULL;