WITH type2_diabetes_diagnosis AS (
  SELECT person_id
  FROM public.condition_occurrence
  WHERE concept_id IN (
    SELECT concept_id
    FROM public.concept
    WHERE concept_name IN ('Type 2 diabetes mellitus', 'Diabetes mellitus type 2')
    AND vocabulary_id IN ('ICD9CM', 'ICD10CM')
    AND concept_code IN ('250.0', '250.1', '250.2', '250.3', 'E11.0', 'E11.1', 'E11.2', 'E11.3')
  )
),
type2_diabetes_symptoms AS (
  SELECT person_id
  FROM public.observation
  WHERE concept_id IN (
    SELECT concept_id
    FROM public.concept
    WHERE concept_name IN ('Polyuria', 'Polydipsia', 'Polyphagia')
  )
  GROUP BY person_id
  HAVING COUNT(DISTINCT concept_id) >= 2
),
type2_diabetes_labs AS (
  SELECT person_id
  FROM public.measurement
  WHERE concept_id IN (
    SELECT concept_id
    FROM public.concept
    WHERE concept_name IN ('Hemoglobin A1c', 'Fasting plasma glucose')
  )
  AND value AS FLOAT >= 6.5 OR value AS FLOAT >= 126
),
type2_diabetes_meds AS (
  SELECT person_id
  FROM public.drug_exposure
  WHERE concept_id IN (
    SELECT concept_id
    FROM public.concept
    WHERE concept_name IN ('Metformin', 'Glipizide', 'Glyburide', 'Insulin')
  )
),
type1_diabetes_diagnosis AS (
  SELECT person_id
  FROM public.condition_occurrence
  WHERE concept_id IN (
    SELECT concept_id
    FROM public.concept
    WHERE concept_name IN ('Type 1 diabetes mellitus', 'Diabetes mellitus type 1')
    AND vocabulary_id IN ('ICD9CM', 'ICD10CM')
    AND concept_code IN ('250.0', '250.1', '250.2', '250.3', 'E10.0', 'E10.1', 'E10.2', 'E10.3')
  )
)
INSERT INTO public.cohort (person_id)
SELECT person_id
FROM (
 SELECT person_id
  FROM type2_diabetes_diagnosis
  UNION
  SELECT person_id
  FROM (
    SELECT person_id
    FROM type2_diabetes_symptoms
    INTERSECT
    SELECT person_id
    FROM type2_diabetes_labs
    INTERSECT
    SELECT person_id
    FROM type2_diabetes_meds
  ) AS intersection_table
) AS union_table
WHERE person_id NOT IN (
  SELECT person_id
  FROM type1_diabetes_diagnosis
);

