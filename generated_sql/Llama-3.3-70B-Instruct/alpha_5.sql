
SELECT 
    p.person_id
INTO 
    public.type2diabetes_cohort
FROM 
    public.person p
WHERE 
    p.person_id IN (
        SELECT 
            co.person_id
        FROM 
            public.condition_occurrence co
        JOIN 
            public.concept c ON co.condition_concept_id = c.concept_id
        WHERE 
            c.concept_code IN ('250.x', 'E11.x') 
            AND c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
    )
    OR p.person_id IN (
        SELECT 
            de.person_id
        FROM 
            public.drug_exposure de
        JOIN 
            public.concept c ON de.drug_concept_id = c.concept_id
        WHERE 
            c.concept_name IN ('Metformin', 'Glucophage', 'Glyburide', 'DiaBeta')
    )
    OR p.person_id IN (
        SELECT 
            m.person_id
        FROM 
            public.measurement m
        JOIN 
            public.concept c ON m.measurement_concept_id = c.concept_id
        WHERE 
            (c.concept_name = 'HbA1c' AND m.value_as_number >= 6.5)
            OR (c.concept_name = 'Fasting plasma glucose' AND m.value_as_number >= 126)
    );
