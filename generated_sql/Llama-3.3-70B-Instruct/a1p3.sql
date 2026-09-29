
SELECT DISTINCT p.person_id
INTO public.type2_diabetes_cohort
FROM public.person p
WHERE p.person_id IN (
  -- Diagnosis of type 2 diabetes
  SELECT co.person_id
  FROM public.condition_occurrence co
  WHERE co.condition_concept_id IN (
    SELECT c.concept_id
    FROM public.concept c
    JOIN public.vocabulary v ON c.vocabulary_id = v.vocabulary_id
    WHERE (c.concept_code = '250.x0' OR c.concept_code = '250.x2') AND v.vocabulary_name = 'ICD9CM'
    OR (c.concept_code = 'E11' AND v.vocabulary_name = 'ICD10CM')
  )
  
  -- OR Symptoms/Signs and Hyperglycemia
  OR p.person_id IN (
    SELECT m.person_id
    FROM public.measurement m
    WHERE m.measurement_concept_id IN (
      SELECT c.concept_id
      FROM public.concept c
      WHERE c.concept_name IN ('HbA1c', 'Fasting plasma glucose', '2-hour plasma glucose')
    )
    AND m.value_as_number >= (
      CASE
        WHEN m.measurement_concept_id IN (SELECT concept_id FROM public.concept WHERE concept_name = 'HbA1c') THEN 6.5
        WHEN m.measurement_concept_id IN (SELECT concept_id FROM public.concept WHERE concept_name = 'Fasting plasma glucose') THEN 126
        WHEN m.measurement_concept_id IN (SELECT concept_id FROM public.concept WHERE concept_name = '2-hour plasma glucose') THEN 200
      END
    )
  )
  
  -- OR Medications for Type 2 Diabetes
  OR p.person_id IN (
    SELECT de.person_id
    FROM public.drug_exposure de
    WHERE de.drug_concept_id IN (
      SELECT c.concept_id
      FROM public.concept c
      JOIN public.vocabulary v ON c.vocabulary_id = v.vocabulary_id
      WHERE (c.concept_name IN ('Metformin', 'Glipizide', 'Pioglitazone', 'Empagliflozin') AND v.vocabulary_name = 'RxNorm')
    )
  )
)
AND p.person_id NOT IN (
  -- Exclude Type 1 Diabetes Diagnosis
  SELECT co.person_id
  FROM public.condition_occurrence co
  WHERE co.condition_concept_id IN (
    SELECT c.concept_id
    FROM public.concept c
    JOIN public.vocabulary v ON c.vocabulary_id = v.vocabulary_id
    WHERE (c.concept_code = '250.x1' OR c.concept_code = '250.x3') AND v.vocabulary_name = 'ICD9CM'
    OR (c.concept_code = 'E10' AND v.vocabulary_name = 'ICD10CM')
  )
);
