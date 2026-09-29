WITH type2_diabetes_diagnoses AS (
  SELECT DISTINCT person_id
  FROM public.condition_occurrence co
  JOIN public.concept c ON co.condition_concept_id = c.concept_id
  WHERE c.concept_code IN ('250.x0', '250.x2') -- ICD9CM
  OR c.concept_code IN ('E11.x') -- ICD10CM
),
type2_diabetes_labs AS (
  SELECT DISTINCT person_id
  FROM public.measurement m
  JOIN public.concept c ON m.measurement_concept_id = c.concept_id
  WHERE (c.concept_code = 'HbA1c' AND m.value_as_number >= 6.5)
  OR (c.concept_code = 'Fasting plasma glucose' AND m.value_as_number >= 126)
  OR (c.concept_code = '2-hour plasma glucose during OGTT' AND m.value_as_number >= 200)
),
type2_diabetes_meds AS (
  SELECT DISTINCT person_id
  FROM public.drug_exposure de
  JOIN public.concept c ON de.drug_concept_id = c.concept_id
  WHERE c.concept_name IN ('Metformin', 'Glipizide', 'Insulin Glargine (Lantus)', 'Insulin Aspart (NovoLog)')
)

SELECT DISTINCT person_id
INTO public.cohort
FROM (
  SELECT person_id
  FROM type2_diabetes_diagnoses
  UNION
  SELECT person_id
  FROM type2_diabetes_labs
  UNION
  SELECT person_id
  FROM type2_diabetes_meds
) AS combined
WHERE person_id IN (
  SELECT person_id
  FROM type2_diabetes_diagnoses
  INTERSECT
  SELECT person_id
  FROM type2_diabetes_labs
)
OR person_id IN (
  SELECT person_id
  FROM type2_diabetes_diagnoses
  INTERSECT
  SELECT person_id
  FROM type2_diabetes_meds
)
OR person_id IN (
  SELECT person_id
  FROM type2_diabetes_labs
  INTERSECT
  SELECT person_id
  FROM type2_diabetes_meds
);

