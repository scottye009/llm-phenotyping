WITH t2dm_standard_concepts AS (
    -- Combine standard T2DM concepts from hierarchies and ICD mappings
    SELECT descendant_concept_id AS concept_id
    FROM public.concept_ancestor
    WHERE ancestor_concept_id = 201820 -- Type 2 diabetes mellitus
    UNION
    SELECT cr.concept_id_2
    FROM public.concept c
    JOIN public.concept_relationship cr ON c.concept_id = cr.concept_id_1
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (c.concept_code ~ '^250\.[0-9][02]' OR c.concept_code ~ '^E11')
      AND cr.relationship_id = 'Maps to'
),
t1dm_exclusion_concepts AS (
    -- Identify Type 1 Diabetes concepts for exclusion
    SELECT descendant_concept_id AS concept_id
    FROM public.concept_ancestor
    WHERE ancestor_concept_id = 201254 -- Type 1 diabetes mellitus
    UNION
    SELECT cr.concept_id_2
    FROM public.concept c
    JOIN public.concept_relationship cr ON c.concept_id = cr.concept_id_1
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (c.concept_code ~ '^250\.[0-9][13]' OR c.concept_code ~ '^E10')
      AND cr.relationship_id = 'Maps to'
),
t2dm_meds AS (
    -- Identify standard concepts for Metformin and common T2DM non-insulin drugs
    SELECT descendant_concept_id AS concept_id
    FROM public.concept_ancestor
    WHERE ancestor_concept_id IN (
        1503297, -- metformin
        1559684, -- glipizide
        1529331, -- glyburide
        1597756, -- pioglitazone
        1583722  -- sitagliptin
    )
),
t2dm_labs AS (
    -- Identify HbA1c Measurement concepts (LOINC)
    SELECT concept_id
    FROM public.concept
    WHERE concept_id IN (3004410, 3005673, 3007261) -- HbA1c codes
),
cohort_candidates AS (
    -- 1. Patients with at least one T2DM diagnosis
    SELECT person_id, 'dx' AS criteria_type
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (SELECT concept_id FROM t2dm_standard_concepts)
    
    UNION
    
    -- 2. Patients with T2DM medication
    SELECT person_id, 'med' AS criteria_type
    FROM public.drug_exposure
    WHERE drug_concept_id IN (SELECT concept_id FROM t2dm_meds)
    
    UNION
    
    -- 3. Patients with HbA1c measurement >= 6.5%
    SELECT person_id, 'lab' AS criteria_type
    FROM public.measurement
    WHERE measurement_concept_id IN (SELECT concept_id FROM t2dm_labs)
      AND value_as_number >= 6.5
)
-- Final Selection: Require at least one T2DM indicator and exclude Type 1 DM
SELECT DISTINCT c.person_id
FROM cohort_candidates c
WHERE NOT EXISTS (
    -- Exclusion logic for Type 1 Diabetes
    SELECT 1 
    FROM public.condition_occurrence co
    WHERE co.person_id = c.person_id
      AND co.condition_concept_id IN (SELECT concept_id FROM t1dm_exclusion_concepts)
);