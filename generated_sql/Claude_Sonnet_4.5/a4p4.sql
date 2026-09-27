
  -- Type 2 Diabetes Mellitus Phenotyping Algorithm
  -- Inclusion: (>=2 T2DM dx on different dates) OR (1 dx + T2DM med) OR (1 dx + HbA1c>=6.5%)
  -- Exclusion: More T1DM codes than T2DM codes

  WITH t2dm_dx_concepts AS (
      -- Standard concepts mapped from T2DM ICD codes
      SELECT DISTINCT cr.concept_id_2 AS concept_id
      FROM public.concept c
      JOIN public.concept_relationship cr
          ON c.concept_id = cr.concept_id_1
          AND cr.relationship_id = 'Maps to'
          AND cr.invalid_reason IS NULL
      WHERE (c.vocabulary_id = 'ICD10CM' AND c.concept_code ~ '^E11')
         OR (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~ '^250\.[0-9][02]$')
  ),
  t1dm_dx_concepts AS (
      -- Standard concepts mapped from T1DM ICD codes (for exclusion)
      SELECT DISTINCT cr.concept_id_2 AS concept_id
      FROM public.concept c
      JOIN public.concept_relationship cr
          ON c.concept_id = cr.concept_id_1
          AND cr.relationship_id = 'Maps to'
          AND cr.invalid_reason IS NULL
      WHERE (c.vocabulary_id = 'ICD10CM' AND c.concept_code ~ '^E10')
         OR (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~ '^250\.[0-9][13]$')
  ),
  t2dm_conditions AS (
      -- All T2DM diagnosis events
      SELECT co.person_id, co.condition_start_date
      FROM public.condition_occurrence co
      WHERE co.condition_concept_id IN (SELECT concept_id FROM t2dm_dx_concepts)
  ),
  t1dm_conditions AS (
      -- All T1DM diagnosis events
      SELECT co.person_id, co.condition_start_date
      FROM public.condition_occurrence co
      WHERE co.condition_concept_id IN (SELECT concept_id FROM t1dm_dx_concepts)
  ),
  dx_criterion AS (
      -- >=2 T2DM diagnoses on distinct dates
      SELECT person_id
      FROM t2dm_conditions
      GROUP BY person_id
      HAVING COUNT(DISTINCT condition_start_date) >= 2
  ),
  t2dm_med_concepts AS (
      -- T2DM-specific medication concepts (excludes insulin due to T1DM overlap)
      SELECT DISTINCT c.concept_id
      FROM public.concept c
      WHERE c.domain_id = 'Drug'
        AND c.concept_name ~* '(metformin|glipizide|glyburide|glimepiride|pioglitazone|rosiglitazone|sitagliptin|saxagliptin|linagliptin|alogliptin|exenatide|liraglutide|d
  ulaglutide|semaglutide|canagliflozin|dapagliflozin|empagliflozin|acarbose|miglitol|repaglinide|nateglinide)'
  ),
  dx_med_criterion AS (
      -- 1 T2DM dx + T2DM-specific medication
      SELECT DISTINCT t.person_id
      FROM t2dm_conditions t
      JOIN public.drug_exposure de ON t.person_id = de.person_id
      WHERE de.drug_concept_id IN (SELECT concept_id FROM t2dm_med_concepts)
  ),
  hba1c_concepts AS (
      -- HbA1c measurement concepts via LOINC codes
      SELECT DISTINCT c.concept_id
      FROM public.concept c
      WHERE c.domain_id = 'Measurement'
        AND (c.concept_code IN ('4548-4', '17856-6', '4549-2', '41995-2')
             OR c.concept_name ~* 'hemoglobin a1c')
  ),
  dx_lab_criterion AS (
      -- 1 T2DM dx + HbA1c >= 6.5%
      SELECT DISTINCT t.person_id
      FROM t2dm_conditions t
      JOIN public.measurement m ON t.person_id = m.person_id
      WHERE m.measurement_concept_id IN (SELECT concept_id FROM hba1c_concepts)
        AND m.value_as_number >= 6.5
  ),
  included AS (
      -- Union of all inclusion pathways
      SELECT person_id FROM dx_criterion
      UNION
      SELECT person_id FROM dx_med_criterion
      UNION
      SELECT person_id FROM dx_lab_criterion
  ),
  excluded AS (
      -- Patients with more T1DM than T2DM codes
      SELECT t1.person_id
      FROM (SELECT person_id, COUNT(*) AS cnt FROM t1dm_conditions GROUP BY person_id) t1
      JOIN (SELECT person_id, COUNT(*) AS cnt FROM t2dm_conditions GROUP BY person_id) t2
          ON t1.person_id = t2.person_id
      WHERE t1.cnt > t2.cnt
  )
  SELECT DISTINCT i.person_id
  FROM included i
  WHERE i.person_id NOT IN (SELECT person_id FROM excluded);