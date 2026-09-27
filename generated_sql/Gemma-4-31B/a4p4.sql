WITH t2dm_concepts AS (
    -- Define standard concepts and their descendants for T2DM
    -- concept_id 200038 is a common SNOMED concept for Type 2 Diabetes
    SELECT descendant_concept_id AS concept_id 
    FROM public.concept_ancestor 
    WHERE ancestor_concept_id = 200038
    UNION
    SELECT concept_id FROM public.concept WHERE concept_name ~* 'type 2 diabetes mellitus'
),
t2dm_mappings AS (
    -- Map ICD9/ICD10 source codes to standard T2DM concepts
    SELECT cr.concept_id_1 AS source_concept_id, cr.concept_id_2 AS target_concept_id 
    FROM public.concept_relationship cr
    JOIN t2dm_concepts tc ON cr.concept_id_2 = tc.concept_id
    WHERE cr.relationship_id = 'Maps to'
),
exclusion_concepts AS (
    -- Identify Type 1 Diabetes for exclusion
    SELECT descendant_concept_id AS concept_id 
    FROM public.concept_ancestor 
    WHERE ancestor_concept_id = 4144310 -- Type 1 Diabetes ancestor
    UNION
    SELECT concept_id FROM public.concept WHERE concept_name ~* 'type 1 diabetes'
),
diagnosed_t2dm AS (
    -- Patients with T2DM diagnosis (standard or mapped)
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    LEFT JOIN t2dm_mappings tm ON co.condition_source_concept_id = tm.source_concept_id
    WHERE co.condition_concept_id IN (SELECT concept_id FROM t2dm_concepts)
       OR tm.target_concept_id IN (SELECT concept_id FROM t2dm_concepts)
),
medicated_t2dm AS (
    -- Patients taking common T2DM drugs (e.g., Metformin)
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN public.concept c ON de.drug_concept_id = c.concept_id
    WHERE c.concept_name ~* '(metformin|glipizide|glimepiride|sitagliptin|empagliflozin|canagliflozin)'
),
lab_confirmed AS (
    -- Patients with HbA1c >= 6.5% or Glucose >= 126 mg/dL
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN public.concept c ON m.measurement_concept_id = c.concept_id
    WHERE (c.concept_name ~* 'hemoglobin a1c' AND m.value_as_number >= 6.5)
       OR (c.concept_name ~* 'glucose' AND m.value_as_number >= 126)
),
excluded_patients AS (
    -- Patients identified as Type 1 Diabetes
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (SELECT concept_id FROM exclusion_concepts)
)
-- Final Result: Union of criteria minus exclusions
SELECT DISTINCT p.person_id
FROM public.person p
WHERE (
    p.person_id IN (SELECT person_id FROM diagnosed_t2dm) OR 
    p.person_id IN (SELECT person_id FROM medicated_t2dm) OR 
    p.person_id IN (SELECT person_id FROM lab_confirmed)
)
AND p.person_id NOT IN (SELECT person_id FROM excluded_patients);