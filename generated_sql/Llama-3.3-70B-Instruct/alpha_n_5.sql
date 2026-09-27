WITH type2_diabetes AS (
  SELECT DISTINCT person_id
  FROM (
    -- Diagnosis of Type 2 Diabetes
    SELECT person_id
    FROM public.condition_occurrence
    WHERE concept_id IN (
      SELECT concept_id
      FROM public.concept
      WHERE concept_name IN ('Type 2 diabetes mellitus', 'Diabetes mellitus type 2')
        OR vocabulary_id = 'ICD9CM' AND concept_code IN ('250.00', '250.02', '250.10', '250.12')
        OR vocabulary_id = 'ICD10CM' AND concept_code LIKE 'E11.%'
    )
    UNION ALL
    -- Symptoms and Signs
    SELECT person_id
    FROM public.condition_occurrence
    WHERE concept_id IN (
      SELECT concept_id
      FROM public.concept
      WHERE concept_name IN ('Polyuria', 'Polydipsia', 'Polyphagia', 'Weight loss', 'Blurry vision')
    )
    INTERSECT
    -- Laboratory Tests
    SELECT person_id
    FROM public.measurement
    WHERE concept_id IN (
      SELECT concept_id
      FROM public.concept
      WHERE concept_name = 'Fasting plasma glucose'
    )
    AND value_as_number >= 126
    OR person_id IN (
      SELECT person_id
      FROM public.measurement
      WHERE concept_id IN (
        SELECT concept_id
        FROM public.concept
        WHERE concept_name = 'Hemoglobin A1c'
      )
      AND value_as_number >= 6.5
    )
    UNION ALL
    -- Medications
    SELECT person_id
    FROM public.drug_exposure
    WHERE concept_id IN (
      SELECT concept_id
      FROM public.concept
      WHERE concept_name IN ('Metformin', 'Glucophage', 'Sulfonylureas', 'Glipizide', 'Glyburide', 'Pioglitazone', 'Actos')
    )
  ) AS subquery
  -- Exclusion Criteria
  EXCEPT
  SELECT person_id
  FROM public.condition_occurrence
  WHERE concept_id IN (
    SELECT concept_id
    FROM public.concept
    WHERE concept_name IN ('Type 1 diabetes mellitus', 'Diabetes mellitus type 1', 'Gestational diabetes', 'Secondary diabetes')
      OR vocabulary_id = 'ICD9CM' AND concept_code IN ('250.01', '250.03', '648.00', '648.01')
      OR vocabulary_id = 'ICD10CM' AND concept_code LIKE 'E10.%' OR concept_code LIKE 'O24.%' OR concept_code LIKE 'E08.%'
  )
)
INSERT INTO public.cohort_definition (cohort_definition_id, cohort_definition_name)
VALUES (1, 'Type 2 Diabetes');

INSERT INTO public.cohort (cohort_id, cohort_definition_id, person_id)
SELECT 1, 1, person_id
FROM type2_diabetes;

