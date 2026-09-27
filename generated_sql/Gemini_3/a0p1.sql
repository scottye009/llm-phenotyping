-- Identifying Type 2 Diabetes Mellitus (T2DM) Phenotype
--error
WITH Diagnosis_Criteria AS (
    SELECT person_id
    FROM condition_occurrence
    WHERE condition_source_value LIKE 'E11%' -- ICD10CM
       OR condition_source_value REGEXP '^250\.[0-9][02]' -- ICD9CM
),
Lab_Criteria AS (
    SELECT person_id
    FROM measurement
    WHERE (measurement_concept_id IN (3004410, 3005673) AND value_as_number >= 6.5) -- HbA1c (OMOP/LOINC)
       OR (measurement_concept_id IN (3000845, 3004501) AND value_as_number >= 126) -- Fasting Glucose
),
Medication_Criteria AS (
    SELECT person_id
    FROM drug_exposure
    WHERE drug_source_value IN (
        'Metformin', 'Glucophage', 
        'Glipizide', 'Glucotrol', 
        'Glyburide', 'Diabeta',
        'Sitagliptin', 'Januvia',
        'Empagliflozin', 'Jardiance',
        'Liraglutide', 'Victoza',
        'Pioglitazone', 'Actos',
        'Acarbose', 'Precose',
        'Glimepiride', 'Amaryl'
    )
),
Exclusion_Criteria AS (
    SELECT person_id
    FROM condition_occurrence
    WHERE condition_source_value LIKE 'E10%' -- Type 1 ICD10
       OR condition_source_value REGEXP '^250\.[0-9][13]' -- Type 1 ICD9
       OR condition_source_value LIKE 'O24.4%' -- Gestational
)

SELECT DISTINCT p.person_id
FROM person p
WHERE (
    p.person_id IN (SELECT person_id FROM Diagnosis_Criteria)
    OR p.person_id IN (SELECT person_id FROM Lab_Criteria)
    OR p.person_id IN (SELECT person_id FROM Medication_Criteria)
)
AND p.person_id NOT IN (SELECT person_id FROM Exclusion_Criteria);