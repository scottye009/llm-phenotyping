-- Type 2 Diabetes Mellitus Phenotyping Algorithm
-- Targets: Diagnosis, Medications, and Lab Values

WITH t2dm_concepts AS (
    -- Identify the standard concept for T2DM and all its descendants
    SELECT descendant_concept_id AS concept_id
    FROM public.concept_ancestor
    WHERE ancestor_concept_id = (
        SELECT concept_id 
        FROM public.concept 
        WHERE concept_name ILIKE '%Type 2 diabetes mellitus%' 
        AND standard_concept = 'S' 
        LIMIT 1
    )
),
diagnosis_evidence AS (
    -- Patients with a direct T2DM diagnosis
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN t2dm_concepts tc ON co.condition_concept_id = tc.concept_id
    
    UNION
    
    -- Patients with source codes (ICD10/ICD9) that map to T2DM
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN public.concept_relationship cr ON co.condition_source_concept_id = cr.concept_id_1
    JOIN t2dm_concepts tc ON cr.concept_id_2 = tc.concept_id
    WHERE cr.relationship_id = 'Maps to'
),
medication_evidence AS (
    -- Patients taking T2DM specific medications (Metformin, etc.)
    -- We look for ingredients or concept names related to common T2DM drugs
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN public.concept c ON de.drug_concept_id = c.concept_id
    WHERE (
        c.concept_name ILIKE '%Metformin%' OR 
        c.concept_name ILIKE '%Glimepiride%' OR 
        c.concept_name ILIKE '%Sitagliptin%' OR 
        c.concept_name ILIKE '%Empagliflozin%' OR 
        c.concept_name ILIKE '%Liraglutide%' OR 
        c.concept_name ILIKE '%Pioglitazone%'
    )
),
lab_evidence AS (
    -- Patients with HbA1c >= 6.5% or Glucose >= 126 mg/dL
    -- Using measurement_source_value to capture LOINC codes for A1c (4548-4) or Glucose (2345-7)
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    WHERE (
        (m.measurement_source_value ~* '4548-4' AND m.value_as_number >= 6.5) -- HbA1c
        OR 
        (m.measurement_source_value ~* '2345-7' AND m.value_as_number >= 126) -- Fasting Glucose
    )
),
combined_phenotype AS (
    -- Logic: Direct diagnosis OR (Medication AND any diabetes-related code) OR Lab evidence with supporting code
    SELECT d.person_id 
    FROM diagnosis_evidence d
    
    UNION
    
    SELECT m.person_id 
    FROM medication_evidence m
    JOIN public.condition_occurrence co ON m.person_id = co.person_id
    JOIN public.concept c ON co.condition_concept_id = c.concept_id
    WHERE c.concept_name ILIKE '%diabetes%'
    
    UNION
    
    SELECT l.person_id 
    FROM lab_evidence l
    JOIN public.condition_occurrence co ON l.person_id = co.person_id
    JOIN public.concept c ON co.condition_concept_id = c.concept_id
    WHERE c.concept_name ILIKE '%diabetes%'
)
-- Final output: Unique list of person_ids identified as T2DM
SELECT 
    p.person_id 
FROM public.person p
JOIN combined_phenotype cp ON p.person_id = cp.person_id;