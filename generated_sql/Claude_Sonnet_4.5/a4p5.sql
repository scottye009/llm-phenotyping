
 -- Type 2 Diabetes Mellitus Phenotyping Algorithm
  -- Inclusion: ≥2 T2DM dx on different days, OR ≥1 dx + T2DM med, OR ≥1 dx + HbA1c ≥6.5%
  -- Exclusion: patients with more T1DM codes than T2DM codes

  WITH t2dm_concepts AS (
      -- T2DM standard concepts via SNOMED ancestor hierarchy
      SELECT DISTINCT ca.descendant_concept_id AS concept_id
      FROM public.concept c
      JOIN public.concept_ancestor ca ON ca.ancestor_concept_id = c.concept_id
      WHERE c.vocabulary_id = 'SNOMED'
        AND c.concept_code = '44054006' -- Type 2 diabetes mellitus

      UNION

      -- ICD10CM/ICD9CM T2DM codes mapped to standard concepts
      SELECT DISTINCT cr.concept_id_2 AS concept_id
      FROM public.concept c
      JOIN public.concept_relationship cr ON cr.concept_id_1 = c.concept_id
      WHERE cr.relationship_id = 'Maps to'
        AND cr.invalid_reason IS NULL
        AND (
            (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E11%')
            OR (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~ '^250\.[0-9][02]$')
        )
  ),

  t1dm_concepts AS (
      -- T1DM standard concepts via SNOMED ancestor hierarchy
      SELECT DISTINCT ca.descendant_concept_id AS concept_id
      FROM public.concept c
      JOIN public.concept_ancestor ca ON ca.ancestor_concept_id = c.concept_id
      WHERE c.vocabulary_id = 'SNOMED'
        AND c.concept_code = '46635009' -- Type 1 diabetes mellitus

      UNION

      -- ICD10CM/ICD9CM T1DM codes mapped to standard concepts
      SELECT DISTINCT cr.concept_id_2 AS concept_id
      FROM public.concept c
      JOIN public.concept_relationship cr ON cr.concept_id_1 = c.concept_id
      WHERE cr.relationship_id = 'Maps to'
        AND cr.invalid_reason IS NULL
        AND (
            (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E10%')
            OR (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~ '^250\.[0-9][13]$')
        )
  ),

  -- T2DM diagnoses per patient
  t2dm_dx AS (
      SELECT person_id, condition_start_date
      FROM public.condition_occurrence
      WHERE condition_concept_id IN (SELECT concept_id FROM t2dm_concepts)
  ),

  -- Criterion A: ≥2 T2DM diagnoses on different days
  dx_twice AS (
      SELECT DISTINCT a.person_id
      FROM t2dm_dx a
      JOIN t2dm_dx b
        ON a.person_id = b.person_id
       AND a.condition_start_date <> b.condition_start_date
  ),

  -- T2DM-specific drug ingredients (non-insulin antidiabetics)
  t2dm_med_ingredients AS (
      SELECT concept_id
      FROM public.concept
      WHERE vocabulary_id = 'RxNorm'
        AND concept_class_id = 'Ingredient'
        AND standard_concept = 'S'
        AND concept_name ~* '^(metformin|glipizide|glyburide|glimepiride|pioglitazone|rosiglitazone|sitagliptin|saxagliptin|linagliptin|alogliptin|exenatide|liraglutide|du
  laglutide|semaglutide|canagliflozin|dapagliflozin|empagliflozin|ertugliflozin|repaglinide|nateglinide|acarbose|miglitol)$'
  ),

  -- All drug products descending from those ingredients
  t2dm_drug_concepts AS (
      SELECT DISTINCT ca.descendant_concept_id AS concept_id
      FROM t2dm_med_ingredients i
      JOIN public.concept_ancestor ca ON ca.ancestor_concept_id = i.concept_id
  ),

  -- Criterion B: ≥1 T2DM dx + T2DM-specific medication
  dx_plus_med AS (
      SELECT DISTINCT co.person_id
      FROM public.condition_occurrence co
      JOIN public.drug_exposure de ON de.person_id = co.person_id
      WHERE co.condition_concept_id IN (SELECT concept_id FROM t2dm_concepts)
        AND de.drug_concept_id IN (SELECT concept_id FROM t2dm_drug_concepts)
  ),

  -- HbA1c lab concepts (LOINC)
  hba1c_concepts AS (
      SELECT concept_id
      FROM public.concept
      WHERE vocabulary_id = 'LOINC'
        AND concept_code IN ('4548-4', '4549-2', '17856-6', '59261-8')
  ),

  -- Criterion C: ≥1 T2DM dx + HbA1c ≥ 6.5%
  dx_plus_hba1c AS (
      SELECT DISTINCT co.person_id
      FROM public.condition_occurrence co
      JOIN public.measurement m ON m.person_id = co.person_id
      WHERE co.condition_concept_id IN (SELECT concept_id FROM t2dm_concepts)
        AND m.measurement_concept_id IN (SELECT concept_id FROM hba1c_concepts)
        AND m.value_as_number >= 6.5
  ),

  -- Union of all inclusion criteria
  t2dm_candidates AS (
      SELECT person_id FROM dx_twice
      UNION
      SELECT person_id FROM dx_plus_med
      UNION
      SELECT person_id FROM dx_plus_hba1c
  ),

  -- Exclusion: T1DM code count exceeds T2DM code count
  t1dm_counts AS (
      SELECT person_id, COUNT(*) AS cnt
      FROM public.condition_occurrence
      WHERE condition_concept_id IN (SELECT concept_id FROM t1dm_concepts)
      GROUP BY person_id
  ),

  t2dm_counts AS (
      SELECT person_id, COUNT(*) AS cnt
      FROM public.condition_occurrence
      WHERE condition_concept_id IN (SELECT concept_id FROM t2dm_concepts)
      GROUP BY person_id
  ),

  t1dm_exclusion AS (
      SELECT t1.person_id
      FROM t1dm_counts t1
      LEFT JOIN t2dm_counts t2 ON t1.person_id = t2.person_id
      WHERE t1.cnt > COALESCE(t2.cnt, 0)
  )

  -- Final cohort: T2DM candidates minus T1DM-predominant patients
  SELECT DISTINCT tc.person_id
  FROM t2dm_candidates tc
  WHERE tc.person_id NOT IN (SELECT person_id FROM t1dm_exclusion)
  ORDER BY tc.person_id;