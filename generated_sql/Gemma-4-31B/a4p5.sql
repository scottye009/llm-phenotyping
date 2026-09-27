-- T2DM Phenotype Identification
WITH t2dm_concepts AS (
    -- Identify standard concepts for T2DM using the ancestor table and concept names
    -- This captures the hierarchy of T2DM (e.g., T2DM with complications)
    SELECT descendant_concept_id AS concept_id 
    FROM public.concept_ancestor 
    WHERE ancestor_concept_id = 201313 -- SNOMED code for Type 2 diabetes mellitus
    UNION
    SELECT concept_id 
    FROM public.concept 
    WHERE concept_name ~* 'type 2 diabetes' AND standard_concept = 'S'
),
t1dm_concepts AS (
    -- Identify concepts for Type 1 Diabetes for exclusion
    SELECT descendant_concept_id AS concept_id 
    FROM public.concept_ancestor 
    WHERE ancestor_concept_id = 4042514 -- SNOMED code for Type 1 diabetes mellitus
    UNION
    SELECT concept_id 
    FROM public.concept 
    WHERE concept_name ~* 'type 1 diabetes' AND standard_concept = 'S'
),
t2dm_drugs AS (
    -- Identify common T2DM medications (e.g., Metformin, etc.)
    SELECT concept_id 
    FROM public.concept 
    WHERE (concept_name ~* 'Metformin' 
       OR concept_name ~* 'Glipizide' 
       OR concept_name ~* 'Glyburide' 
       OR concept_name ~* 'Sitagliptin' 
       OR concept_name ~* 'Empagliflozin' 
       OR concept_name ~* 'Liraglutide')
    AND domain_id = 'Drug'
),
diabetes_labs AS (
    -- Identify patients with hyperglycemia based on common lab concepts
    -- HbA1c >= 6.5% or Fasting Glucose >= 126 mg/dL
    SELECT person_id 
    FROM public.measurement 
    WHERE (
        (measurement_concept_id = 3004410 AND value_as_number >= 6.5) -- HbA1c
        OR 
        (measurement_concept_id = 3004421 AND value_as_number >= 126) -- Glucose
    )
),
mapped_diagnoses AS (
    -- Handle mapping of ICD source codes to standard concepts
    SELECT co.person_id, co.condition_concept_id
    FROM public.condition_occurrence co
    JOIN public.concept_relationship cr ON co.condition_source_concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'
)

SELECT DISTINCT p.person_id
FROM public.person p
-- Join with candidate rules
LEFT JOIN public.condition_occurrence co ON p.person_id = co.person_id
LEFT JOIN mapped_diagnoses md ON p.person_id = md.person_id
LEFT JOIN public.drug_exposure de ON p.person_id = de.person_id
LEFT JOIN diabetes_labs dl ON p.person_id = dl.person_id
WHERE (
    -- Rule 1: T2DM Diagnosis (Standard or Mapped)
    co.condition_concept_id IN (SELECT concept_id FROM t2dm_concepts)
    OR md.condition_concept_id IN (SELECT concept_id FROM t2dm_concepts)
    
    -- Rule 2: T2DM-specific Medication
    OR de.drug_concept_id IN (SELECT concept_id FROM t2dm_drugs)
    
    -- Rule 3: Lab-based evidence
    OR dl.person_id IS NOT NULL
)
-- Exclusion Logic: Remove Type 1 Diabetes
AND p.person_id NOT IN (
    SELECT person_id 
    FROM public.condition_occurrence 
    WHERE condition_concept_id IN (SELECT concept_id FROM t1dm_concepts)
);