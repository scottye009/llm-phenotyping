WITH t2dm_concepts AS (
    -- Get all descendants of the standard Type 2 Diabetes concept
    -- Concept 201820 contains 'Type 2 diabetes mellitus'
    SELECT descendant_concept_id AS concept_id
    FROM public.concept_ancestor
    WHERE ancestor_concept_id = 201820
),
t2dm_mappings AS (
    -- Map source ICD codes to standard concepts
    SELECT cr.concept_id_2 AS concept_id
    FROM public.concept_relationship cr
    JOIN public.concept c ON cr.concept_id_1 = c.concept_id
    WHERE cr.relationship_id = 'Maps to'
      AND c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (c.concept_name ~* 'type 2 diabetes' OR c.concept_name ~* 'non-insulin dependent diabetes')
),
t1dm_exclusion AS (
    -- Identify patients with Type 1 Diabetes to exclude them
    SELECT DISTINCT person_id
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (
        SELECT descendant_concept_id FROM public.concept_ancestor WHERE ancestor_concept_id = 443354
    )
),
diabetes_meds AS (
    -- Metformin, Sulfonylureas, and Insulin (Generic/Brand)
    SELECT DISTINCT person_id
    FROM public.drug_exposure
    WHERE drug_concept_id IN (
        SELECT descendant_concept_id FROM public.concept_ancestor WHERE ancestor_concept_id = 1308214 -- Antidiabetic agents
    )
),
glucose_labs AS (
    -- HbA1c >= 6.5% or Glucose >= 126mg/dL
    SELECT DISTINCT person_id
    FROM public.measurement
    WHERE (
        (measurement_concept_id = 3004530 AND value_as_number >= 6.5) -- HbA1c
        OR 
        (measurement_concept_id IN (3004461, 3004462) AND value_as_number >= 126) -- Plasma glucose
    )
)

SELECT DISTINCT p.person_id
FROM public.person p
LEFT JOIN t1dm_exclusion ex ON p.person_id = ex.person_id
WHERE ex.person_id IS NULL -- Exclude Type 1 Diabetes
AND (
    -- Logic 1: Direct Diagnosis of T2DM
    EXISTS (
        SELECT 1 FROM public.condition_occurrence co
        WHERE co.person_id = p.person_id 
        AND (co.condition_concept_id IN (SELECT concept_id FROM t2dm_concepts) 
             OR co.condition_concept_id IN (SELECT concept_id FROM t2dm_mappings))
    )
    -- Logic 2: Unspecified diabetes diagnosis + diabetic medication
    OR (
        EXISTS (
            SELECT 1 FROM public.condition_occurrence co
            WHERE co.person_id = p.person_id 
            AND co.condition_concept_id IN (SELECT descendant_concept_id FROM public.concept_ancestor WHERE ancestor_concept_id = 443354) -- Diabetes Mellitus ancestor
        )
        AND p.person_id IN (SELECT person_id FROM diabetes_meds)
    )
    -- Logic 3: Clinical laboratory confirmation
    OR p.person_id IN (SELECT person_id FROM glucose_labs)
);