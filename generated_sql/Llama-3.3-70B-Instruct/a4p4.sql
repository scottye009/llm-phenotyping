WITH 
-- Mapping ICD9CM and ICD10CM concepts to standard concept IDs for Type 2 diabetes mellitus
type2_diabetes_concepts AS (
  SELECT DISTINCT c2.concept_id
  FROM public.concept c1
  JOIN public.concept_relationship cr ON c1.concept_id = cr.concept_id_1
  JOIN public.concept c2 ON cr.concept_id_2 = c2.concept_id
  WHERE c1.vocabulary_id IN ('ICD9CM', 'ICD10CM')
    AND cr.relationship_id = 'Maps to'
    AND c2.concept_name LIKE '%Type 2 diabetes%'
),
-- Mapping medication concepts for Type 2 diabetes mellitus
type2_diabetes_medications AS (
  SELECT DISTINCT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('RxNorm', 'SNOMED')
    AND c.concept_name LIKE '%metformin%'
    OR c.concept_name LIKE '%sulfonylurea%'
    OR c.concept_name LIKE '%pioglitazone%'
),
-- Mapping lab concepts for HbA1c
hba1c_concepts AS (
  SELECT DISTINCT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('LOINC', 'SNOMED')
    AND c.concept_name LIKE '%HbA1c%'
)

-- Identifying patients with Type 2 diabetes mellitus based on diagnosis, medication, and lab results
SELECT DISTINCT p.person_id
FROM public.person p
JOIN public.condition_occurrence co ON p.person_id = co.person_id
JOIN type2_diabetes_concepts t2d ON co.condition_concept_id = t2d.concept_id
WHERE co.condition_start_date IS NOT NULL
  AND co.condition_end_date IS NULL  -- Assuming active diagnoses

UNION

SELECT DISTINCT p.person_id
FROM public.person p
JOIN public.drug_exposure de ON p.person_id = de.person_id
JOIN type2_diabetes_medications t2dm ON de.drug_concept_id = t2dm.concept_id
WHERE de.drug_exposure_start_date IS NOT NULL
  AND de.drug_exposure_end_date IS NULL  -- Assuming ongoing medication

UNION

SELECT DISTINCT p.person_id
FROM public.person p
JOIN public.measurement m ON p.person_id = m.person_id
JOIN hba1c_concepts h ON m.measurement_concept_id = h.concept_id
WHERE m.measurement_date IS NOT NULL
  AND m.value_as_number > 6.5  -- Using a common HbA1c threshold for diabetes diagnosis

-- Excluding patients with Type 1 diabetes mellitus
EXCEPT

SELECT DISTINCT p.person_id
FROM public.person p
JOIN public.condition_occurrence co ON p.person_id = co.person_id
JOIN public.concept c ON co.condition_concept_id = c.concept_id
WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
  AND c.concept_name LIKE '%Type 1 diabetes%';