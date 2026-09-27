WITH t2dm_concepts AS (
    -- Get standard concept for T2DM and all its descendants
    SELECT descendant_concept_id AS concept_id
    FROM public.concept_ancestor
    WHERE ancestor_concept_id = 201820 -- Type 2 diabetes mellitus
),
icd_mapped_concepts AS (
    -- Map ICD9/10 source codes to standard concepts as per instructions
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM public.concept c
    JOIN public.concept_relationship cr ON c.concept_id = cr.concept_id_1
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (c.concept_code ~* '^E11' OR c.concept_code ~* '^250\.0' OR c.concept_code ~* '^250\.2')
      AND cr.relationship_id = 'Maps to'
),
t2dm_meds AS (
    -- Identify descendants of common T2DM medication classes
    SELECT descendant_concept_id AS concept_id
    FROM public.concept_ancestor
    WHERE ancestor_concept_id IN (
        1503297, -- Metformin
        1550557, -- Glipizide
        1580747, -- Glimepiride
        1529331, -- Glyburide
        1510202, -- Sitagliptin
        43013884, -- Liraglutide
        43526465  -- Empagliflozin
    )
),
t1dm_exclusion AS (
    -- Identify T1DM descendants for exclusion
    SELECT descendant_concept_id AS concept_id
    FROM public.concept_ancestor
    WHERE ancestor_concept_id = 201254 -- Type 1 diabetes mellitus
)

-- Final Phenotype List
(
    -- Criteria 1: Diagnosis (Standard or Mapped)
    SELECT DISTINCT person_id
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (SELECT concept_id FROM t2dm_concepts)
       OR condition_concept_id IN (SELECT concept_id FROM icd_mapped_concepts)

    UNION

    -- Criteria 2: T2DM Medications
    SELECT DISTINCT person_id
    FROM public.drug_exposure
    WHERE drug_concept_id IN (SELECT concept_id FROM t2dm_meds)

    UNION

    -- Criteria 3: Lab Results (HbA1c >= 6.5)
    SELECT DISTINCT person_id
    FROM public.measurement
    WHERE measurement_concept_id IN (3004410, 3007261) -- HbA1c LOINC concepts
      AND value_as_number >= 6.5
)
EXCEPT
-- Exclusion Logic: Remove T1DM patients
SELECT DISTINCT person_id
FROM public.condition_occurrence
WHERE condition_concept_id IN (SELECT concept_id FROM t1dm_exclusion);