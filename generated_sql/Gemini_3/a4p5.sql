-- filepath: [a4p5.sql](http://_vscodecontentref_/0)
WITH t2dm_concepts AS (
    -- Get standard T2DM diagnosis concepts and descendants
    SELECT descendant_concept_id AS concept_id
    FROM public.concept_ancestor
    WHERE ancestor_concept_id = 201820 -- Diabetes mellitus type 2
    UNION
    -- Map ICD9/ICD10 source codes to standard concepts
    SELECT cr.concept_id_2
    FROM public.concept c
    JOIN public.concept_relationship cr ON c.concept_id = cr.concept_id_1
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (c.concept_code ~ '^250\.0[02]' OR c.concept_code ~ '^E11')
      AND cr.relationship_id = 'Maps to'
),
t2dm_meds AS (
    -- Get standard concept IDs for Metformin and common T2DM drugs
    SELECT descendant_concept_id AS concept_id
    FROM public.concept_ancestor
    WHERE ancestor_concept_id IN (
        1503297, -- metformin
        1559684, -- glipizide
        1529331  -- glyburide
    )
),
t2dm_labs AS (
    -- HbA1c Measurement concepts
    SELECT concept_id
    FROM public.concept
    WHERE concept_id IN (3004410, 3005673) -- HbA1c LOINC codes
)

-- Final Phenotype: Patients matching diagnosis, medication, or lab criteria
SELECT DISTINCT person_id
FROM (
    -- 1. Diagnosis Criteria
    SELECT person_id 
    FROM public.condition_occurrence 
    WHERE condition_concept_id IN (SELECT concept_id FROM t2dm_concepts)
    
    UNION
    
    -- 2. Medication Criteria
    SELECT person_id 
    FROM public.drug_exposure 
    WHERE drug_concept_id IN (SELECT concept_id FROM t2dm_meds)
    
    UNION
    
    -- 3. Lab Criteria (HbA1c >= 6.5%)
    SELECT person_id 
    FROM public.measurement 
    WHERE measurement_concept_id IN (SELECT concept_id FROM t2dm_labs)
      AND value_as_number >= 6.5
) AS diabetes_cohort;