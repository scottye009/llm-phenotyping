WITH type2_diabetes_diagnosis AS (
  SELECT DISTINCT person_id
  FROM public.condition_occurrence
  WHERE concept_id IN (
    SELECT concept_id
    FROM public.concept
    WHERE concept_name IN ('Diabetes mellitus type 2 (disorder)', 'Type 2 diabetes mellitus')
    AND vocabulary_id IN ('ICD9CM', 'ICD10CM')
  )
  AND standard_concept = 'S'
),
type2_diabetes_symptoms AS (
  SELECT DISTINCT person_id
  FROM public.condition_occurrence
  WHERE concept_id IN (
    SELECT concept_id
    FROM public.concept
    WHERE concept_name IN ('Polyuria', 'Polydipsia', 'Polyphagia', 'Unexplained weight loss')
  )
  AND standard_concept = 'S'
),
type2_diabetes_laboratory AS (
  SELECT DISTINCT person_id
  FROM public.measurement
  WHERE concept_id IN (
    SELECT concept_id
    FROM public.concept
    WHERE concept_name IN ('Fasting plasma glucose', 'Hemoglobin A1c')
  )
  AND value_as_number > 126 -- FPG > 126 mg/dL or HbA1c > 6.5%
),
type2_diabetes_medications AS (
  SELECT DISTINCT person_id
  FROM public.drug_exposure
  WHERE concept_id IN (
    SELECT concept_id
    FROM public.concept
    WHERE concept_name IN ('Metformin', 'Glimepiride', 'Pioglitazone', 'Actos', 'Avandia')
  )
  AND standard_concept = 'S'
)

INSERT INTO public.cohort (cohort_definition_id, subject_id)
SELECT 1, person_id
FROM (
  SELECT person_id
  FROM type2_diabetes_diagnosis
  UNION
  SELECT person_id
  FROM (
    SELECT person_id
    FROM type2_diabetes_symptoms
    GROUP BY person_id
    HAVING COUNT(DISTINCT concept_id) >= 2
  ) AS symptoms
  INTERSECT
  SELECT person_id
  FROM type2_diabetes_laboratory
  UNION
  SELECT person_id
  FROM type2_diabetes_medications
) AS type2_diabetes_cohort;

