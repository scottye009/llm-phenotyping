

WITH type2_diabetes_diagnoses AS (
  SELECT person_id
  FROM public.condition_occurrence
  WHERE condition_concept_id IN (
    SELECT concept_id
    FROM public.concept
    WHERE concept_code IN ('250.0', 'E11.0', 'E11.1', 'E11.2', 'E11.3', 'E11.4', 'E11.5', 'E11.6', 'E11.7', 'E11.8', 'E11.9')
    AND vocabulary_id IN ('ICD9CM', 'ICD10CM')
  )
),
type2_diabetes_medications AS (
  SELECT person_id
  FROM public.drug_exposure
  WHERE drug_concept_id IN (
    SELECT concept_id
    FROM public.concept
    WHERE lower(concept_name) IN (
      'metformin', 'glipizide', 'glimepiride', 'pioglitazone', 'sitagliptin',
      'metformin hydrochloride', 'glipizide extended release', 'januvia'
    )
    OR concept_name IN ('Metformin', 'Glipizide', 'Glimepiride', 'Pioglitazone', 'Sitagliptin',
                       'Metformin Hydrochloride', 'Glipizide Extended Release', 'Januvia')
  )
),
hyperglycemia AS (
  SELECT person_id
  FROM public.measurement
  WHERE measurement_concept_id IN (
    SELECT concept_id
    FROM public.concept
    WHERE concept_name IN ('Hemoglobin A1c', 'Fasting glucose', '2-hour plasma glucose')
  )
  AND (
    (measurement_concept_id = (SELECT concept_id FROM public.concept WHERE concept_name = 'Hemoglobin A1c')
     AND value_as_number > 6.5)
    OR (measurement_concept_id = (SELECT concept_id FROM public.concept WHERE concept_name = 'Fasting glucose')
        AND value_as_number > 126)
    OR (measurement_concept_id = (SELECT concept_id FROM public.concept WHERE concept_name = '2-hour plasma glucose')
        AND value_as_number > 200)
  )
),
type1_diabetes_exclusion AS (
  SELECT person_id
  FROM public.condition_occurrence
  WHERE condition_concept_id IN (
    SELECT concept_id
    FROM public.concept
    WHERE concept_code IN ('250.x1', 'E10.0', 'E10.1', 'E10.2', 'E10.3', 'E10.4', 'E10.5', 'E10.6', 'E10.7', 'E10.8', 'E10.9')
    AND vocabulary_id IN ('ICD9CM', 'ICD10CM')
  )
),
exclusive_insulin_use AS (
  SELECT person_id
  FROM public.drug_exposure
  WHERE drug_concept_id IN (
    SELECT concept_id
    FROM public.concept
    WHERE lower(concept_name) LIKE '%insulin%'
  )
  AND person_id NOT IN (
    SELECT person_id
    FROM public.drug_exposure
    WHERE drug_concept_id NOT IN (
      SELECT concept_id
      FROM public.concept
      WHERE lower(concept_name) LIKE '%insulin%'
    )
  )
)

SELECT DISTINCT person_id
FROM (
  (
    SELECT person_id FROM type2_diabetes_diagnoses
    UNION
    SELECT person_id FROM type2_diabetes_medications
  ) t2d
  INTERSECT
  SELECT person_id FROM hyperglycemia
) AS confirmed_t2d
WHERE person_id NOT IN (
  SELECT person_id FROM type1_diabetes_exclusion
)
AND person_id NOT IN (
  SELECT person_id FROM exclusive_insulin_use
);

