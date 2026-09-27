
-- Type 2 Diabetes Mellitus Phenotyping Algorithm
  -- Include: (≥2 T2DM dx on different days) OR (1 dx + T2DM med) OR (1 dx + HbA1c ≥6.5%)
  -- Exclude: patients with more T1DM than T2DM diagnosis codes

  WITH
  -- T2DM standard concepts via ICD-to-SNOMED mapping
  t2dm_concepts AS (
      -- ICD10CM E11.* -> standard
      SELECT DISTINCT cr.concept_id_2 AS concept_id
      FROM public.concept c
      JOIN public.concept_relationship cr ON c.concept_id = cr.concept_id_1
      WHERE c.vocabulary_id = 'ICD10CM'
        AND c.concept_code ~ '^E11'
        AND cr.relationship_id = 'Maps to'
        AND c.invalid_reason IS NULL
      UNION
      -- ICD9CM 250.x0, 250.x2 -> standard
      SELECT DISTINCT cr.concept_id_2 AS concept_id
      FROM public.concept c
      JOIN public.concept_relationship cr ON c.concept_id = cr.concept_id_1
      WHERE c.vocabulary_id = 'ICD9CM'
        AND c.concept_code ~ '^250\.\d[02]$'
        AND cr.relationship_id = 'Maps to'
        AND c.invalid_reason IS NULL
      UNION
      -- Include descendants of SNOMED T2DM concept
      SELECT descendant_concept_id AS concept_id
      FROM public.concept_ancestor
      WHERE ancestor_concept_id = 201826
  ),

  -- T2DM condition occurrences per patient
  t2dm_dx AS (
      SELECT co.person_id, co.condition_start_date
      FROM public.condition_occurrence co
      WHERE co.condition_concept_id IN (SELECT concept_id FROM t2dm_concepts)
  ),

  -- Patients with at least 1 T2DM diagnosis
  t2dm_any AS (
      SELECT DISTINCT person_id FROM t2dm_dx
  ),

  -- Patients with ≥2 T2DM diagnoses on different days
  t2dm_2dx AS (
      SELECT person_id
      FROM t2dm_dx
      GROUP BY person_id
      HAVING COUNT(DISTINCT condition_start_date) >= 2
  ),

  -- T2DM-specific medication ingredients (non-insulin antidiabetics)
  t2dm_med_ingredients AS (
      SELECT concept_id
      FROM public.concept
      WHERE vocabulary_id = 'RxNorm'
        AND concept_class_id = 'Ingredient'
        AND concept_name ~* '^(metformin|glipizide|glyburide|glimepiride|pioglitazone|rosiglitazone|sitagliptin|saxagliptin|linagliptin|alogliptin|canagliflozin|dapagliflozin|empagliflozin|ertugliflozin|exenatide|liraglutide|dulagluti
  de|semaglutide|repaglinide|nateglinide|acarbose|miglitol)$'
        AND invalid_reason IS NULL
  ),

  -- Patients with T2DM-specific drug exposure
  t2dm_meds AS (
      SELECT DISTINCT de.person_id
      FROM public.drug_exposure de
      JOIN public.concept_ancestor ca ON de.drug_concept_id = ca.descendant_concept_id
      WHERE ca.ancestor_concept_id IN (SELECT concept_id FROM t2dm_med_ingredients)
  ),

  -- HbA1c lab concepts (LOINC)
  hba1c_concepts AS (
      SELECT concept_id
      FROM public.concept
      WHERE vocabulary_id = 'LOINC'
        AND concept_code IN ('4548-4', '17856-6', '59261-8', '4549-2', '17855-8')
        AND invalid_reason IS NULL
  ),

  -- Patients with HbA1c ≥ 6.5%
  elevated_hba1c AS (
      SELECT DISTINCT m.person_id
      FROM public.measurement m
      WHERE m.measurement_concept_id IN (SELECT concept_id FROM hba1c_concepts)
        AND m.value_as_number >= 6.5
        AND m.value_as_number <= 20.0  -- ensures percentage scale
  ),

  -- T1DM concepts for exclusion
  t1dm_concepts AS (
      SELECT DISTINCT cr.concept_id_2 AS concept_id
      FROM public.concept c
      JOIN public.concept_relationship cr ON c.concept_id = cr.concept_id_1
      WHERE c.vocabulary_id = 'ICD10CM'
        AND c.concept_code ~ '^E10'
        AND cr.relationship_id = 'Maps to'
        AND c.invalid_reason IS NULL
      UNION
      SELECT DISTINCT cr.concept_id_2 AS concept_id
      FROM public.concept c
      JOIN public.concept_relationship cr ON c.concept_id = cr.concept_id_1
      WHERE c.vocabulary_id = 'ICD9CM'
        AND c.concept_code ~ '^250\.\d[13]$'
        AND cr.relationship_id = 'Maps to'
        AND c.invalid_reason IS NULL
      UNION
      SELECT descendant_concept_id AS concept_id
      FROM public.concept_ancestor
      WHERE ancestor_concept_id = 201254
  ),

  -- T1DM diagnosis count per patient
  t1dm_counts AS (
      SELECT person_id, COUNT(*) AS t1dm_count
      FROM public.condition_occurrence
      WHERE condition_concept_id IN (SELECT concept_id FROM t1dm_concepts)
      GROUP BY person_id
  ),

  -- T2DM diagnosis count per patient
  t2dm_counts AS (
      SELECT person_id, COUNT(*) AS t2dm_count
      FROM t2dm_dx
      GROUP BY person_id
  ),

  -- Exclude patients where T1DM codes outnumber T2DM codes
  t1dm_exclusion AS (
      SELECT t1.person_id
      FROM t1dm_counts t1
      LEFT JOIN t2dm_counts t2 ON t1.person_id = t2.person_id
      WHERE t1.t1dm_count > COALESCE(t2.t2dm_count, 0)
  )

  -- Final T2DM cohort
  SELECT DISTINCT person_id
  FROM (
      -- ≥2 T2DM diagnoses on different days
      SELECT person_id FROM t2dm_2dx
      UNION
      -- 1 T2DM diagnosis + T2DM-specific medication
      SELECT person_id FROM t2dm_any
      WHERE person_id IN (SELECT person_id FROM t2dm_meds)
      UNION
      -- 1 T2DM diagnosis + elevated HbA1c
      SELECT person_id FROM t2dm_any
      WHERE person_id IN (SELECT person_id FROM elevated_hba1c)
  ) included
  WHERE person_id NOT IN (SELECT person_id FROM t1dm_exclusion)
  ORDER BY person_id;