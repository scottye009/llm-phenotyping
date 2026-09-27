WITH t2dm_concepts AS (
    -- Identify all descendants of the T2DM ancestor concept (SNOMED)
    -- Concept 200038 is a common ancestor for Type 2 Diabetes Mellitus
    SELECT descendant_concept_id AS concept_id
    FROM public.concept_ancestor
    WHERE ancestor_concept_id = 200038 
),
t2dm_mapped_codes AS (
    -- Map ICD9CM and ICD10CM source codes to standard T2DM concepts
    SELECT cr.concept_id_2 AS concept_id
    FROM public.concept_relationship cr
    JOIN public.concept c ON cr.concept_id_1 = c.concept_id
    WHERE cr.relationship_id = 'Maps to'
      AND c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      -- Filter for concepts typically related to T2DM (e.g., E11 in ICD10)
      AND (c.concept_code ~ '^E11' OR c.concept_code ~ '^250\.1')
),
type1_exclusion AS (
    -- Identify patients with Type 1 Diabetes to exclude them
    SELECT DISTINCT person_id
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (
        SELECT descendant_concept_id FROM public.concept_ancestor WHERE ancestor_concept_id = 4043356
    )
),
t2dm_diagnosis AS (
    -- Patients with T2DM diagnosis
    SELECT DISTINCT person_id
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (SELECT concept_id FROM t2dm_concepts)
       OR condition_concept_id IN (SELECT concept_id FROM t2dm_mapped_codes)
),
t2dm_meds AS (
    -- Patients taking T2DM medications (Metformin, etc.)
    SELECT DISTINCT person_id
    FROM public.drug_exposure
    WHERE drug_concept_id IN (
        SELECT descendant_concept_id 
        FROM public.concept_ancestor 
        WHERE ancestor_concept_id = 1308241 -- Antidiabetic agents ancestor
    )
),
t2dm_labs AS (
    -- Patients with diabetic lab values: HbA1c >= 6.5% or Glucose >= 126 mg/dL
    SELECT DISTINCT person_id
    FROM public.measurement
    WHERE (
        -- HbA1c (Concept 3004431 is a common ID for HbA1c)
        (measurement_concept_id = 3004431 AND value_as_number >= 6.5)
        OR 
        -- Fasting Glucose (Concept 3004423 is a common ID for Glucose)
        (measurement_concept_id = 3004423 AND value_as_number >= 126)
    )
)

-- Final Selection: Combine criteria and apply exclusion
SELECT DISTINCT p.person_id
FROM public.person p
WHERE (
    p.person_id IN (SELECT person_id FROM t2dm_diagnosis)
    OR p.person_id IN (SELECT person_id FROM t2dm_meds)
    OR p.person_id IN (SELECT person_id FROM t2dm_labs)
)
AND p.person_id NOT IN (SELECT person_id FROM type1_exclusion);