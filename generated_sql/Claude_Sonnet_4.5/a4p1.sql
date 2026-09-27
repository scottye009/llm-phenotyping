

  WITH t2dm_concepts AS (
      -- Descendants of SNOMED "Type 2 diabetes mellitus" (concept_id 201826)
      SELECT DISTINCT descendant_concept_id AS concept_id
      FROM public.concept_ancestor
      WHERE ancestor_concept_id = 201826

      UNION

      -- ICD10CM E11.x mapped to standard concepts
      SELECT DISTINCT cr.concept_id_2
      FROM public.concept c
      JOIN public.concept_relationship cr
        ON c.concept_id = cr.concept_id_1
      WHERE c.vocabulary_id = 'ICD10CM'
        AND c.concept_code ~ '^E11'
        AND cr.relationship_id = 'Maps to'
        AND cr.invalid_reason IS NULL

      UNION

      -- ICD9CM 250.x0, 250.x2 (type 2) mapped to standard concepts
      SELECT DISTINCT cr.concept_id_2
      FROM public.concept c
      JOIN public.concept_relationship cr
        ON c.concept_id = cr.concept_id_1
      WHERE c.vocabulary_id = 'ICD9CM'
        AND c.concept_code ~ '^250\.[0-9][02]$'
        AND cr.relationship_id = 'Maps to'
        AND cr.invalid_reason IS NULL
  ),

  t1dm_concepts AS (
      -- Descendants of SNOMED "Type 1 diabetes mellitus" (concept_id 201254)
      SELECT DISTINCT descendant_concept_id AS concept_id
      FROM public.concept_ancestor
      WHERE ancestor_concept_id = 201254

      UNION

      -- ICD10CM E10.x mapped to standard concepts
      SELECT DISTINCT cr.concept_id_2
      FROM public.concept c
      JOIN public.concept_relationship cr
        ON c.concept_id = cr.concept_id_1
      WHERE c.vocabulary_id = 'ICD10CM'
        AND c.concept_code ~ '^E10'
        AND cr.relationship_id = 'Maps to'
        AND cr.invalid_reason IS NULL

      UNION

      -- ICD9CM 250.x1, 250.x3 (type 1) mapped to standard concepts
      SELECT DISTINCT cr.concept_id_2
      FROM public.concept c
      JOIN public.concept_relationship cr
        ON c.concept_id = cr.concept_id_1
      WHERE c.vocabulary_id = 'ICD9CM'
        AND c.concept_code ~ '^250\.[0-9][13]$'
        AND cr.relationship_id = 'Maps to'
        AND cr.invalid_reason IS NULL
  ),

  -- T2DM-specific drug ingredients (excludes insulin)
  t2dm_drug_ingredients AS (
      SELECT concept_id
      FROM public.concept
      WHERE vocabulary_id = 'RxNorm'
        AND concept_class_id = 'Ingredient'
        AND concept_name ~* '^(metformin|glipizide|glyburide|glimepiride|pioglitazone|rosiglit
  azone|sitagliptin|saxagliptin|linagliptin|alogliptin|exenatide|liraglutide|dulaglutide|semag
  lutide|lixisenatide|canagliflozin|dapagliflozin|empagliflozin|ertugliflozin|repaglinide|nate
  glinide|acarbose|miglitol)$'
  ),

  t2dm_drugs AS (
      -- All drug products descending from T2DM-specific ingredients
      SELECT DISTINCT ca.descendant_concept_id AS concept_id
      FROM t2dm_drug_ingredients i
      JOIN public.concept_ancestor ca
        ON ca.ancestor_concept_id = i.concept_id
  ),

  -- HbA1c measurement concepts (LOINC 4548-4 and related)
  hba1c_concepts AS (
      SELECT concept_id
      FROM public.concept
      WHERE vocabulary_id = 'LOINC'
        AND concept_code IN ('4548-4', '4549-2', '17856-6', '59261-8')

      UNION

      SELECT DISTINCT descendant_concept_id
      FROM public.concept_ancestor
      WHERE ancestor_concept_id = 3004410
  ),

  -- Patients with T2DM diagnoses
  t2dm_dx AS (
      SELECT person_id, condition_start_date
      FROM public.condition_occurrence
      WHERE condition_concept_id IN (SELECT concept_id FROM t2dm_concepts)
  ),

  -- Criterion 1: >=2 T2DM diagnoses on different dates
  t2dm_2dx AS (
      SELECT person_id
      FROM t2dm_dx
      GROUP BY person_id
      HAVING COUNT(DISTINCT condition_start_date) >= 2
  ),

  -- Patients with at least 1 T2DM dx
  t2dm_1dx AS (
      SELECT DISTINCT person_id
      FROM t2dm_dx
  ),

  -- Criterion 2: T2DM-specific medication exposure
  t2dm_med AS (
      SELECT DISTINCT person_id
      FROM public.drug_exposure
      WHERE drug_concept_id IN (SELECT concept_id FROM t2dm_drugs)
  ),

  -- Criterion 3: HbA1c >= 6.5% (range filter 6.5-20 guards against unit mismatches)
  t2dm_lab AS (
      SELECT DISTINCT person_id
      FROM public.measurement
      WHERE measurement_concept_id IN (SELECT concept_id FROM hba1c_concepts)
        AND value_as_number >= 6.5
        AND value_as_number <= 20.0
  ),

  -- Combine inclusion criteria
  included AS (
      SELECT person_id FROM t2dm_2dx
      UNION
      SELECT person_id FROM t2dm_1dx WHERE person_id IN (SELECT person_id FROM t2dm_med)
      UNION
      SELECT person_id FROM t2dm_1dx WHERE person_id IN (SELECT person_id FROM t2dm_lab)
  ),

  -- Exclusion: patients with more T1DM codes than T2DM codes
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

  excluded AS (
      SELECT t1.person_id
      FROM t1dm_counts t1
      LEFT JOIN t2dm_counts t2 ON t1.person_id = t2.person_id
      WHERE t1.cnt > COALESCE(t2.cnt, 0)
  )

  -- Final: included patients minus exclusions
  SELECT DISTINCT i.person_id
  FROM included i
  WHERE i.person_id NOT IN (SELECT person_id FROM excluded)
  ORDER BY i.person_id;