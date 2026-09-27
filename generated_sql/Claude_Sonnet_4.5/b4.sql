
  -- Type 2 Diabetes Mellitus Phenotyping
  -- Inclusion: >=2 T2DM dx on different dates, OR >=1 dx + T2DM med, OR >=1 dx + HbA1c >= 6.5%
  -- Exclusion: patients with more T1DM than T2DM diagnosis codes

  WITH t2dm_concepts AS (
      -- SNOMED T2DM hierarchy (concept_id 201826 = SNOMED 44054006)
      SELECT DISTINCT descendant_concept_id AS concept_id
      FROM public.concept_ancestor
      WHERE ancestor_concept_id = 201826
      UNION
      -- ICD10CM E11.x and ICD9CM 250.x0/250.x2 mapped to standard concepts
      SELECT DISTINCT cr.concept_id_2
      FROM public.concept c
      JOIN public.concept_relationship cr ON c.concept_id = cr.concept_id_1
      WHERE cr.relationship_id = 'Maps to'
        AND cr.invalid_reason IS NULL
        AND ((c.vocabulary_id = 'ICD10CM' AND c.concept_code ~ '^E11')
          OR (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~ '^250\.[0-9][02]$'))
  ),

  t1dm_concepts AS (
      -- SNOMED T1DM hierarchy (concept_id 201254 = SNOMED 46635009)
      SELECT DISTINCT descendant_concept_id AS concept_id
      FROM public.concept_ancestor
      WHERE ancestor_concept_id = 201254
      UNION
      -- ICD10CM E10.x and ICD9CM 250.x1/250.x3 mapped to standard concepts
      SELECT DISTINCT cr.concept_id_2
      FROM public.concept c
      JOIN public.concept_relationship cr ON c.concept_id = cr.concept_id_1
      WHERE cr.relationship_id = 'Maps to'
        AND cr.invalid_reason IS NULL
        AND ((c.vocabulary_id = 'ICD10CM' AND c.concept_code ~ '^E10')
          OR (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~ '^250\.[0-9][13]$'))
  ),

  -- T2DM-specific RxNorm ingredients (non-insulin antidiabetics)
  t2dm_med_ingredients AS (
      SELECT concept_id
      FROM public.concept
      WHERE vocabulary_id = 'RxNorm'
        AND concept_class_id = 'Ingredient'
        AND concept_name ~* '^(metformin|glipizide|glyburide|glimepiride|pioglitazone|rosiglitazone|sitagliptin|saxagliptin|linagliptin|alogliptin|exenatide|liraglutide|du
  laglutide|semaglutide|lixisenatide|canagliflozin|dapagliflozin|empagliflozin|ertugliflozin|repaglinide|nateglinide|acarbose|miglitol)$'
  ),

  -- All descendant drug products of those ingredients
  t2dm_drugs AS (
      SELECT DISTINCT ca.descendant_concept_id AS concept_id
      FROM t2dm_med_ingredients i
      JOIN public.concept_ancestor ca ON ca.ancestor_concept_id = i.concept_id
  ),

  -- HbA1c measurement concepts (LOINC)
  hba1c_concepts AS (
      SELECT concept_id
      FROM public.concept
      WHERE vocabulary_id = 'LOINC'
        AND concept_code IN ('4548-4', '4549-2', '17856-6', '59261-8')
  ),

  -- All T2DM condition occurrences
  t2dm_dx AS (
      SELECT person_id, condition_start_date
      FROM public.condition_occurrence
      WHERE condition_concept_id IN (SELECT concept_id FROM t2dm_concepts)
  ),

  -- Criterion A: >=2 T2DM diagnoses on different dates
  t2dm_2dx AS (
      SELECT person_id
      FROM t2dm_dx
      GROUP BY person_id
      HAVING COUNT(DISTINCT condition_start_date) >= 2
  ),

  -- Patients with at least 1 T2DM diagnosis
  t2dm_any AS (
      SELECT DISTINCT person_id FROM t2dm_dx
  ),

  -- Criterion B: T2DM-specific medication exposure
  t2dm_med_patients AS (
      SELECT DISTINCT person_id
      FROM public.drug_exposure
      WHERE drug_concept_id IN (SELECT concept_id FROM t2dm_drugs)
  ),

  -- Criterion C: HbA1c >= 6.5% (cap at 20 to guard against unit mismatches)
  elevated_hba1c AS (
      SELECT DISTINCT person_id
      FROM public.measurement
      WHERE measurement_concept_id IN (SELECT concept_id FROM hba1c_concepts)
        AND value_as_number >= 6.5
        AND value_as_number <= 20.0
  ),

  -- Union of all inclusion pathways
  included AS (
      SELECT person_id FROM t2dm_2dx
      UNION
      SELECT person_id FROM t2dm_any WHERE person_id IN (SELECT person_id FROM t2dm_med_patients)
      UNION
      SELECT person_id FROM t2dm_any WHERE person_id IN (SELECT person_id FROM elevated_hba1c)
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

  excluded AS (
      SELECT t1.person_id
      FROM t1dm_counts t1
      LEFT JOIN t2dm_counts t2 ON t1.person_id = t2.person_id
      WHERE t1.cnt > COALESCE(t2.cnt, 0)
  )

  -- Final T2DM cohort
  SELECT DISTINCT i.person_id
  FROM included i
  WHERE i.person_id NOT IN (SELECT person_id FROM excluded)
  ORDER BY i.person_id;