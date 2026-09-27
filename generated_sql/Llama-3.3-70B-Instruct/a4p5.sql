-- Find person_ids with Type 2 diabetes based on diagnoses, medications, and lab results
WITH 
  -- Type 2 diabetes ICD codes
  type2_diabetes_icd AS (
    SELECT DISTINCT concept_id
    FROM public.concept
    WHERE concept_name LIKE '%Type 2 diabetes%' AND vocabulary_id IN ('ICD9CM', 'ICD10CM')
  ),
  
  -- Map source ICD codes to standard concepts
  mapped_icd_concepts AS (
    SELECT cr.concept_id_2 AS concept_id
    FROM public.concept_relationship cr
    JOIN type2_diabetes_icd t2d ON cr.concept_id_1 = t2d.concept_id
    WHERE cr.relationship_id = 'Maps to'
  ),
  
  -- Type 2 diabetes diagnoses
  diagnoses AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN type2_diabetes_icd t2d ON co.condition_concept_id = t2d.concept_id
    UNION ALL
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN mapped_icd_concepts mic ON co.condition_concept_id = mic.concept_id
  ),
  
  -- Type 2 diabetes medications
  medications AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN public.concept c ON de.drug_concept_id = c.concept_id
    WHERE c.concept_name LIKE '%Metformin%' OR c.concept_name LIKE '%Sulfonylurea%' 
    -- Add more medication names as needed
  ),
  
  -- Type 2 diabetes lab results (e.g., HbA1c >= 6.5%)
  lab_results AS (
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN public.concept c ON m.measurement_concept_id = c.concept_id
    WHERE c.concept_name LIKE '%HbA1c%' AND m.value_as_number >= 6.5
  )

-- Combine diagnoses, medications, and lab results to identify persons with Type 2 diabetes
SELECT DISTINCT person_id
FROM (
  SELECT person_id FROM diagnoses
  UNION ALL
  SELECT person_id FROM medications
  UNION ALL
  SELECT person_id FROM lab_results
) AS t2d_persons;