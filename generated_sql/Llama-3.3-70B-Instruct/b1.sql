SELECT DISTINCT p.person_id
FROM public.person p
WHERE p.person_id IN (
  -- Diagnosis of Type 2 Diabetes
  SELECT co.person_id
  FROM public.condition_occurrence co
  JOIN public.concept c ON co.condition_concept_id = c.concept_id
  WHERE (c.concept_code LIKE '250.%' AND c.vocabulary_id = 'ICD9CM' AND c.concept_code NOT IN ('250.x1', '250.x3'))
  OR (c.concept_code LIKE 'E11.%' AND c.vocabulary_id = 'ICD10CM')
)
OR p.person_id IN (
  -- Symptoms/Signs and Hyperglycemia
  SELECT m.person_id
  FROM public.measurement m
  JOIN public.concept c ON m.measurement_concept_id = c.concept_id
  WHERE (c.concept_name = 'Hemoglobin A1c' AND m.value_as_number > 6.5)
  OR (c.concept_name = 'Fasting glucose' AND m.value_as_number > 126)
  OR (c.concept_name = '2-hour plasma glucose' AND m.value_as_number > 200)
)
OR p.person_id IN (
  -- Medications for Type 2 Diabetes
  SELECT de.person_id
  FROM public.drug_exposure de
  JOIN public.concept c ON de.drug_concept_id = c.concept_id
  WHERE c.concept_name IN ('Metformin', 'Glipizide', 'Glimepiride', 'Pioglitazone', 'Sitagliptin', 'Metformin Hydrochloride', 'Glipizide Extended Release', 'Januvia')
)
AND p.person_id NOT IN (
  -- Exclude Type 1 Diabetes Diagnosis
  SELECT co.person_id
  FROM public.condition_occurrence co
  JOIN public.concept c ON co.condition_concept_id = c.concept_id
  WHERE (c.concept_code LIKE '250.x1' AND c.vocabulary_id = 'ICD9CM')
  OR (c.concept_code LIKE 'E10.%' AND c.vocabulary_id = 'ICD10CM')
)
AND p.person_id NOT IN (
  -- Exclude Exclusive Insulin Use
  SELECT de.person_id
  FROM public.drug_exposure de
  JOIN public.concept c ON de.drug_concept_id = c.concept_id
  WHERE c.concept_name LIKE '%insulin%'
  AND de.person_id NOT IN (
    SELECT de2.person_id
    FROM public.drug_exposure de2
    JOIN public.concept c2 ON de2.drug_concept_id = c2.concept_id
    WHERE c2.concept_name NOT LIKE '%insulin%'
  )
);

