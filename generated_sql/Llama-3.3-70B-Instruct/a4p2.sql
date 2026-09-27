-- Find people with Type 2 Diabetes based on diagnosis, medication, or lab results
WITH t2dm_diagnoses AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (
        -- Standard concept IDs for Type 2 Diabetes Mellitus
        SELECT c.concept_id
        FROM public.concept c
        WHERE c.concept_name LIKE '%Type 2 diabetes mellitus%'
    )
),
t2dm_medications AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    WHERE de.drug_concept_id IN (
        -- Standard concept IDs for medications used in T2DM management
        SELECT c.concept_id
        FROM public.concept c
        WHERE c.concept_name IN ('Metformin', 'Glipizide', 'Glimepiride')
    )
),
t2dm_lab_results AS (
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    WHERE m.measurement_concept_id IN (
        -- Standard concept IDs for relevant lab results (e.g., HbA1c)
        SELECT c.concept_id
        FROM public.concept c
        WHERE c.concept_name LIKE '%HbA1c%'
    )
    AND m.value_as_number > 6.5  -- HbA1c threshold for diabetes diagnosis
),
t1dm_diagnoses AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (
        -- Standard concept IDs for Type 1 Diabetes Mellitus
        SELECT c.concept_id
        FROM public.concept c
        WHERE c.concept_name LIKE '%Type 1 diabetes mellitus%'
    )
)

SELECT DISTINCT person_id
FROM (
    SELECT person_id
    FROM t2dm_diagnoses
    UNION
    SELECT person_id
    FROM t2dm_medications
    WHERE person_id NOT IN (SELECT person_id FROM t1dm_diagnoses)
    UNION
    SELECT person_id
    FROM t2dm_lab_results
    WHERE person_id NOT IN (SELECT person_id FROM t1dm_diagnoses)
) AS t2dm_cohort;