WITH 
-- Identify type 2 diabetes diagnoses through ICD9CM and ICD10CM concepts
diagnoses AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN public.concept_relationship cr ON co.condition_concept_id = cr.concept_id_2
    JOIN public.concept c ON cr.concept_id_1 = c.concept_id
    WHERE cr.relationship_id = 'Maps to'
        AND (c.concept_code LIKE '250.%' OR c.concept_code LIKE 'E11.%')  -- ICD9CM and ICD10CM for type 2 diabetes
),

-- Medications used for type 2 diabetes (example with metformin)
medications AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN public.concept c ON de.drug_concept_id = c.concept_id
    WHERE c.concept_name LIKE '%metformin%'  -- Example medication for type 2 diabetes
),

-- Lab results for HbA1c
lab_results AS (
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN public.concept c ON m.measurement_concept_id = c.concept_id
    WHERE c.concept_name LIKE '%HbA1c%' AND m.value_as_number > 6.5  -- Example lab result for type 2 diabetes
)

SELECT person_id
FROM (
    SELECT person_id FROM diagnoses
    UNION
    SELECT person_id FROM medications
    UNION
    SELECT person_id FROM lab_results
) AS combined
EXCEPT
SELECT co.person_id
FROM public.condition_occurrence co
JOIN public.concept c ON co.condition_concept_id = c.concept_id
WHERE c.concept_name LIKE '%Type 1 diabetes%';  -- Exclusion for type 1 diabetes diagnoses