-- Phenotyping Algorithm for Type 2 Diabetes Mellitus (T2DM)
-- Implementation for PostgreSQL / pgAdmin 4 on OMOP CDM L3 Synthetic Database

WITH t2dm_concepts AS (
    -- Get the standard concept for Type 2 Diabetes and all its descendants
    -- This covers ICD9CM, ICD10CM, and SNOMED mappings via concept_ancestor
    SELECT descendant_concept_id AS concept_id
    FROM public.concept_ancestor
    WHERE ancestor_concept_id IN (
        SELECT concept_id 
        FROM public.concept 
        WHERE concept_name ILIKE '%Type 2 diabetes mellitus%' 
        AND standard_concept = 'S'
    )
),

diagnosis_cases AS (
    -- Patients with a recorded T2DM diagnosis
    SELECT DISTINCT person_id
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (SELECT concept_id FROM t2dm_concepts)
       OR condition_source_value IN (
           -- Fallback for common ICD codes if mapping is incomplete
           'E11', '250.00', '250.01' 
       )
),

medication_cases AS (
    -- Patients taking T2DM medications (Metformin, Glimepiride, Sitagliptin, etc.)
    -- We join with concept to identify drug classes via names
    SELECT DISTINCT drug_exposure.person_id
    FROM public.drug_exposure
    JOIN public.concept ON drug_exposure.drug_concept_id = concept.concept_id
    WHERE (
        concept.concept_name ILIKE '%Metformin%' OR
        concept.concept_name ILIKE '%Glimepiride%' OR
        concept.concept_name ILIKE '%Glipizide%' OR
        concept.concept_name ILIKE '%Sitagliptin%' OR
        concept.concept_name ILIKE '%Empagliflozin%' OR
        concept.concept_name ILIKE '%Liraglutide%' OR
        concept.concept_name ILIKE '%Pioglitazone%'
    )
),

lab_cases AS (
    -- Patients meeting clinical thresholds (HbA1c >= 6.5% or Fasting Glucose >= 126 mg/dL)
    SELECT DISTINCT person_id
    FROM public.measurement m
    JOIN public.concept c ON m.measurement_concept_id = c.concept_id
    WHERE (
        -- HbA1c logic: concept name match and value >= 6.5
        (c.concept_name ILIKE '%Hemoglobin A1c%' AND m.value_as_number >= 6.5)
        OR 
        -- Fasting Glucose logic: concept name match and value >= 126 (assuming mg/dL)
        (c.concept_name ILIKE '%Glucose%' AND c.concept_name ILIKE '%Fasting%' AND m.value_as_number >= 126)
        OR
        -- Random Glucose logic: value >= 200
        (c.concept_name ILIKE '%Glucose%' AND m.value_as_number >= 200)
    )
)

-- Combine all criteria to identify the final T2DM cohort
SELECT 
    p.person_id
FROM public.person p
WHERE p.person_id IN (SELECT person_id FROM diagnosis_cases)
   OR p.person_id IN (SELECT person_id FROM medication_cases)
   OR p.person_id IN (SELECT person_id FROM lab_cases);