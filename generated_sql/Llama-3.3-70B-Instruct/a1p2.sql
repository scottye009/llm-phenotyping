
SELECT 
    p.person_id
FROM 
    public.person p
WHERE 
    -- Diagnosis of Type 2 Diabetes
    p.person_id IN (
        SELECT 
            co.person_id
        FROM 
            public.condition_occurrence co
        JOIN 
            public.concept c ON co.condition_concept_id = c.concept_id
        WHERE 
            (c.concept_code = '250' AND c.vocabulary_id = 'ICD9CM') 
            OR (c.concept_code LIKE 'E11%' AND c.vocabulary_id = 'ICD10CM')
    )
    -- OR Symptoms and Lab Results
    OR p.person_id IN (
        SELECT 
            co.person_id
        FROM 
            public.condition_occurrence co
        JOIN 
            public.concept c ON co.condition_concept_id = c.concept_id
        WHERE 
            c.concept_name IN ('Polyuria', 'Polydipsia', 'Unexplained weight loss')
        INTERSECT
        SELECT 
            m.person_id
        FROM 
            public.measurement m
        JOIN 
            public.concept mc ON m.measurement_concept_id = mc.concept_id
        WHERE 
            (mc.concept_name = 'Fasting plasma glucose' AND m.value_as_number >= 126)
            OR (mc.concept_name = 'HbA1c' AND m.value_as_number >= 6.5)
    )
    -- AND Medication for Type 2 Diabetes
    AND p.person_id IN (
        SELECT 
            de.person_id
        FROM 
            public.drug_exposure de
        JOIN 
            public.concept dc ON de.drug_concept_id = dc.concept_id
        WHERE 
            dc.concept_name IN ('Metformin', 'Glucophage', 'Sulfonylureas', 'Glyburide', 'Diabeta', 'Meglitinides', 'Repaglinide', 'Prandin')
    )
    -- Exclude Type 1 Diabetes
    AND p.person_id NOT IN (
        SELECT 
            co.person_id
        FROM 
            public.condition_occurrence co
        JOIN 
            public.concept c ON co.condition_concept_id = c.concept_id
        WHERE 
            (c.concept_code = '250.1' AND c.vocabulary_id = 'ICD9CM') 
            OR (c.concept_code = 'E10' AND c.vocabulary_id = 'ICD10CM')
    );

