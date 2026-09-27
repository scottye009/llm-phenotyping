-- Phenotyping for Type 2 Diabetes Mellitus
WITH t2dm_concepts AS (
    -- Get standard concepts for T2DM and their descendants
    SELECT descendant_concept_id AS concept_id 
    FROM public.concept_ancestor 
    WHERE ancestor_concept_id = 201350 -- Concept for Type 2 Diabetes Mellitus
    UNION 
    SELECT concept_id FROM public.concept WHERE concept_id = 201350
),
t1dm_concepts AS (
    -- Get standard concepts for Type 1 Diabetes to exclude
    SELECT descendant_concept_id AS concept_id 
    FROM public.concept_ancestor 
    WHERE ancestor_concept_id = 444442 -- Concept for Type 1 Diabetes Mellitus
    UNION 
    SELECT concept_id FROM public.concept WHERE concept_id = 444442
),
diagnosis_t2dm AS (
    -- Identify T2DM via standard concept or mapped ICD codes
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    LEFT JOIN public.concept_relationship cr ON co.condition_source_concept_id = cr.concept_id_1 
        AND cr.relationship_id = 'Maps to'
    WHERE co.condition_concept_id IN (SELECT concept_id FROM t2dm_concepts)
       OR cr.concept_id_2 IN (SELECT concept_id FROM t2dm_concepts)
),
medication_t2dm AS (
    -- Identify T2DM via medication (Metformin, etc.)
    -- Using concept names for broad identification of glucose lowering agents
    SELECT person_id
    FROM public.drug_exposure de
    JOIN public.concept c ON de.drug_concept_id = c.concept_id
    WHERE (c.concept_name ~* 'Metformin' 
       OR c.concept_name ~* 'Glipizide' 
       OR c.concept_name ~* 'Glyburide' 
       OR c.concept_name ~* 'Sitagliptin' 
       OR c.concept_name ~* 'Empagliflozin' 
       OR c.concept_name ~* 'Canagliflozin')
    GROUP BY person_id
    HAVING COUNT(DISTINCT drug_exposure_id) >= 2
),
labs_t2dm AS (
    -- Identify T2DM via lab values (HbA1c >= 6.5% or Glucose >= 126 mg/dL)
    SELECT person_id
    FROM public.measurement m
    JOIN public.concept c ON m.measurement_concept_id = c.concept_id
    WHERE ((c.concept_name ~* 'HbA1c' AND m.value_as_number >= 6.5)
       OR (c.concept_name ~* 'Glucose' AND m.value_as_number >= 126))
    GROUP BY person_id
    HAVING COUNT(DISTINCT measurement_id) >= 2
),
exclusion_t1dm AS (
    -- Exclude Type 1 Diabetes
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    LEFT JOIN public.concept_relationship cr ON co.condition_source_concept_id = cr.concept_id_1 
        AND cr.relationship_id = 'Maps to'
    WHERE co.condition_concept_id IN (SELECT concept_id FROM t1dm_concepts)
       OR cr.concept_id_2 IN (SELECT concept_id FROM t1dm_concepts)
)
-- Final selection: (Diagnosis OR Meds OR Labs) AND NOT Type 1
SELECT DISTINCT p.person_id
FROM public.person p
WHERE (
    p.person_id IN (SELECT person_id FROM diagnosis_t2dm) OR
    p.person_id IN (SELECT person_id FROM medication_t2dm) OR
    p.person_id IN (SELECT person_id FROM labs_t2dm)
)
AND p.person_id NOT IN (SELECT person_id FROM exclusion_t1dm);