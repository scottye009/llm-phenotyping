WITH t2dm_standard_concepts AS (
    -- Identify standard concepts for T2DM and their descendants
    SELECT descendant_concept_id AS concept_id
    FROM public.concept_ancestor
    WHERE ancestor_concept_id IN (201313, 201350, 201820) -- Common T2DM root concepts
    UNION
    SELECT concept_id
    FROM public.concept
    WHERE (concept_name ~* 'type 2 diabetes mellitus' 
           OR concept_name ~* 'non-insulin dependent diabetes mellitus')
      AND standard_concept = 'S'
      AND domain_id = 'Condition'
),
t1dm_exclusion_concepts AS (
    -- Identify standard concepts for T1DM for exclusion
    SELECT descendant_concept_id AS concept_id
    FROM public.concept_ancestor
    WHERE ancestor_concept_id IN (4042514, 444442, 4144310)
    UNION
    SELECT concept_id
    FROM public.concept
    WHERE concept_name ~* 'type 1 diabetes mellitus' 
      AND standard_concept = 'S' 
      AND domain_id = 'Condition'
),
t2dm_diagnosis AS (
    -- Patients with T2DM diagnosis: either via standard concept or mapped ICD source concept
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    LEFT JOIN public.concept_relationship cr ON co.condition_source_concept_id = cr.concept_id_1 
         AND cr.relationship_id = 'Maps to'
    WHERE co.condition_concept_id IN (SELECT concept_id FROM t2dm_standard_concepts)
       OR cr.concept_id_2 IN (SELECT concept_id FROM t2dm_standard_concepts)
),
t2dm_meds AS (
    -- Patients taking T2DM drugs (Generic/Brand) via concept name matching
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN public.concept c ON de.drug_concept_id = c.concept_id
    WHERE (c.concept_name ~* 'Metformin'
       OR c.concept_name ~* 'Glipizide'
       OR c.concept_name ~* 'Glyburide'
       OR c.concept_name ~* 'Glimepiride'
       OR c.concept_name ~* 'Sitagliptin'
       OR c.concept_name ~* 'Empagliflozin'
       OR c.concept_name ~* 'Canagliflozin'
       OR c.concept_name ~* 'Liraglutide'
       OR c.concept_name ~* 'Exenatide')
),
t2dm_labs AS (
    -- Patients with clinical evidence: HbA1c >= 6.5% or Glucose >= 126 mg/dL
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN public.concept c ON m.measurement_concept_id = c.concept_id
    WHERE (
        (c.concept_name ~* 'hemoglobin a1c' AND m.value_as_number >= 6.5)
        OR 
        (c.concept_name ~* 'glucose' AND m.value_as_number >= 126)
    )
),
t1dm_patients AS (
    -- Patients to be excluded’ (T1DM)
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    LEFT JOIN public.concept_relationship cr ON co.condition_source_concept_id = cr.concept_id_1 
         AND cr.relationship_id = 'Maps to'
    WHERE co.condition_concept_id IN (SELECT concept_id FROM t1dm_exclusion_concepts)
       OR cr.concept_id_2 IN (SELECT concept_id FROM t1dm_exclusion_concepts)
)

-- Final Selection: (Diagnosis OR Meds OR Labs) AND NOT T1DM
SELECT DISTINCT p.person_id
FROM public.person p
WHERE (
    p.person_id IN (SELECT person_id FROM t2dm_diagnosis)
    OR p.person_id IN (SELECT person_id FROM t2dm_meds)
    OR p.person_id IN (SELECT person_id FROM t2dm_labs)
)
AND p.person_id NOT IN (SELECT person_id FROM t1dm_patients);