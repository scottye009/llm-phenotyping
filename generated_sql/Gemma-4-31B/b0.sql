SELECT DISTINCT p.person_id
FROM person p
WHERE (
    -- 1. Diagnosis Pathway: ICD-10 (E11.x) and ICD-9 (250.00, 250.01, etc.)
    p.person_id IN (
        SELECT co.person_id
        FROM condition_occurrence co
        JOIN concept c ON co.condition_concept_id = c.concept_id
        WHERE (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E11%')
           OR (c.vocabulary_id = 'ICD9CM' AND c.concept_code IN ('250.00', '250.01', '250.02', '250.10', '250.11', '250.20'))
    )
    OR 
    -- 2. Lab Pathway: HbA1c >= 6.5 or FPG >= 126 or Random Glucose >= 200
    -- Requirement: At least 2 distinct dates of abnormal results to ensure stability
    p.person_id IN (
        SELECT m.person_id
        FROM measurement m
        JOIN concept c ON m.measurement_concept_id = c.concept_id
        WHERE (c.concept_name = 'Hemoglobin A1c' AND m.value_as_number >= 6.5)
           OR (c.concept_name = 'Fasting plasma glucose' AND m.value_as_number >= 126)
           OR (c.concept_name = 'Glucose' AND m.value_as_number >= 200)
        GROUP BY m.person_id
        HAVING COUNT(DISTINCT m.measurement_date) >= 2
    )
    OR 
    -- 3. Medication Pathway: Generic and Brand names
    p.person_id IN (
        SELECT de.person_id
        FROM drug_exposure de
        JOIN concept c ON de.drug_concept_id = c.concept_id
        WHERE c.concept_name IN (
            'Metformin', 'Glucophage', 'Fortamet', 'Glumetza',
            'Glipizide', 'Glucotrol', 'Glyburide', 'DiaBeta', 'Glimepiride', 'Amaryl',
            'Canagliflozin', 'Invokana', 'Dapagliflozin', 'Farxiga', 'Empagliflozin', 'Jardiance',
            'Sitagliptin', 'Januvia', 'Saxagliptin', 'Onglyza', 'Linagliptin', 'Tradjenta',
            'Exenatide', 'Byetta', 'Liraglutide', 'Victoza', 'Dulaglutide', 'Trulicity', 'Semaglutide', 'Ozempic', 'Rybelsus',
            'Pioglitazone', 'Actos'
        )
    )
)
AND p.person_id NOT IN (
    -- Exclusion Pathway: Type 1 and Gestational Diabetes
    SELECT co.person_id
    FROM condition_occurrence co
    JOIN concept c ON co.condition_concept_id = c.concept_id
    WHERE (c.vocabulary_id = 'ICD10CM' AND (c.concept_code LIKE 'E10%' OR c.concept_code LIKE 'O24.4%'))
       OR (c.vocabulary_id = 'ICD9CM' AND (c.concept_code = '250.02' OR c.concept_code = '782.4'))
);

