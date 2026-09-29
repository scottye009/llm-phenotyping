
WITH t2dm_concepts AS (
    -- Identifying T2DM ICD9/10 and SNOMED through the Concept table
    SELECT concept_id FROM public.concept 
    WHERE (concept_code LIKE 'E11%' OR concept_code LIKE '250.00' OR concept_code LIKE '250.02')
    AND domain_id = 'Condition'
),
t1dm_exclusion AS (
    -- Type 1 and Gestational exclusions
    SELECT person_id FROM public.condition_occurrence
    WHERE condition_concept_id IN (
        SELECT concept_id FROM public.concept 
        WHERE concept_code LIKE 'E10%' OR concept_code LIKE '648.0%' OR concept_code LIKE 'O24%'
    )
),
medication_users AS (
    -- T2DM Medications: Metformin (Glucophage), Glipizide (Glucotrol), Empagliflozin (Jardiance), etc.
    SELECT DISTINCT person_id FROM public.drug_exposure
    WHERE drug_concept_id IN (
        SELECT concept_id FROM public.concept 
        WHERE lower(concept_name) ~ 'metformin|glucophage|glipizide|glucotrol|sitagliptin|januvia|empagliflozin|jardiance'
    )
),
lab_confirmed AS (
    -- HbA1c >= 6.5%
    SELECT DISTINCT person_id FROM public.measurement
    WHERE measurement_concept_id IN (3004410, 3007263, 40758583) -- Standard OMOP HbA1c concepts
    AND value_as_number >= 6.5
)

SELECT DISTINCT p.person_id
FROM public.person p
JOIN public.condition_occurrence co ON p.person_id = co.person_id
WHERE co.condition_concept_id IN (SELECT concept_id FROM t2dm_concepts)
-- EXCLUSION LOGIC: NOT T1DM
AND p.person_id NOT IN (SELECT person_id FROM t1dm_exclusion)
-- CRITERIA COMBINATION
AND (
    -- Two separate diagnosis dates
    p.person_id IN (
        SELECT person_id FROM public.condition_occurrence 
        WHERE condition_concept_id IN (SELECT concept_id FROM t2dm_concepts)
        GROUP BY person_id HAVING COUNT(DISTINCT condition_start_date) >= 2
    )
    OR p.person_id IN (SELECT person_id FROM medication_users)
    OR p.person_id IN (SELECT person_id FROM lab_confirmed)
);
