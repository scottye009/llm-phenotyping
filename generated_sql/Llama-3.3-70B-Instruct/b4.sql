-- Type 2 Diabetes Mellitus Phenotyping Algorithm
WITH
  -- Identify type 2 diabetes diagnoses through ICD9CM and ICD10CM concepts
  diagnosed_type2 AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN public.concept c ON co.condition_concept_id = c.concept_id
    WHERE c.concept_name LIKE '%Type 2 diabetes%' AND c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
    UNION ALL
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN public.concept_relationship cr ON co.condition_concept_id = cr.concept_id_2
    JOIN public.concept c ON cr.concept_id_1 = c.concept_id
    WHERE cr.relationship_id = 'Maps to' AND c.concept_name LIKE '%Type 2 diabetes%' AND c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
  ),
  -- Identify individuals with diabetes-related medication use
  medicated AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN public.concept c ON de.drug_concept_id = c.concept_id
    WHERE c.concept_name IN ('Metformin', 'Glyburide', 'Glipizide', 'Glimepiride', 'Pioglitazone', 'Sitagliptin', 'Empagliflozin', 'Canagliflozin', 'Dapagliflozin', 'Linagliptin',
                              'Metformin hydrochloride', 'Glipizide extended release', 'Glimepiride tablet', 'Pioglitazone hydrochloride', 'Sitagliptin phosphate', 'Empagliflozin tablet',
                              'Canagliflozin tablet', 'Dapagliflozin tablet', 'Linagliptin tablet')
  ),
  -- Identify individuals with HbA1c lab results > 6.5%
  hba1c_lab AS (
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN public.concept c ON m.measurement_concept_id = c.concept_id
    WHERE c.concept_name LIKE '%Hemoglobin A1c%' AND m.value_as_number > 6.5
  )

-- Combine criteria for diagnosis, medication, and lab results
SELECT DISTINCT d.person_id
FROM (
  SELECT person_id FROM diagnosed_type2
  UNION
  SELECT person_id FROM medicated
  UNION
  SELECT person_id FROM hba1c_lab
) d
WHERE d.person_id NOT IN (
  SELECT co.person_id
  FROM public.condition_occurrence co
  JOIN public.concept c ON co.condition_concept_id = c.concept_id
  WHERE c.concept_name LIKE '%Gestational diabetes%' OR c.concept_name LIKE '%Type 1 diabetes%');