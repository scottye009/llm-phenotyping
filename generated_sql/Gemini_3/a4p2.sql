WITH t2dm_concepts AS (
    -- Identify standard concepts for T2DM from ICD9/10 codes
    SELECT DISTINCT cr.concept_id_2 as concept_id
    FROM public.concept c
    JOIN public.concept_relationship cr ON c.concept_id = cr.concept_id_1
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (c.concept_code ~* '^E11' OR c.concept_code ~* '^250\.[0-9]0' OR c.concept_code ~* '^250\.[0-9]2')
      AND cr.relationship_id = 'Maps to'
),
t1dm_exclusion AS (
    -- Identify patients with T1DM to exclude
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN public.concept c ON co.condition_source_concept_id = c.concept_id
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (c.concept_code ~* '^E10' OR c.concept_code ~* '^250\.[0-9]1' OR c.concept_code ~* '^250\.[0-9]3')
),
t2dm_meds AS (
    -- Identify patients on T2DM specific medications (non-insulin)
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN public.concept c ON de.drug_concept_id = c.concept_id
    WHERE c.concept_name ~* 'Metformin|Glipizide|Glyburide|Sitagliptin|Empagliflozin|Liraglutide'
      AND c.domain_id = 'Drug'
),
t2dm_labs AS (
    -- Identify patients with HbA1c >= 6.5%
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN public.concept c ON m.measurement_concept_id = c.concept_id
    WHERE (c.concept_code = '4548-4' OR c.concept_name ~* 'Hemoglobin A1c')
      AND m.value_as_number >= 6.5
)

SELECT DISTINCT p.person_id
FROM public.person p
LEFT JOIN public.condition_occurrence co ON p.person_id = co.person_id
WHERE (
    -- Criteria 1: Diagnosis
    co.condition_concept_id IN (SELECT concept_id FROM t2dm_concepts)
    OR 
    -- Criteria 2: Medications
    p.person_id IN (SELECT person_id FROM t2dm_meds)
    OR 
    -- Criteria 3: Labs
    p.person_id IN (SELECT person_id FROM t2dm_labs)
)
-- Exclusion: Criteria 4
AND p.person_id NOT IN (SELECT person_id FROM t1dm_exclusion);