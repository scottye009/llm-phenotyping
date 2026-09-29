-- PARAMETERS
WITH params AS (
  SELECT 
    DATE '2000-01-01' AS cohort_start,
    DATE '2100-12-31' AS cohort_end,
    TRUE  AS require_adult   -- set to FALSE if you don't want the age >=18 constraint
),

/* ============================================================
   CONCEPT SETS
   ============================================================ */

-- DX: Type 2 diabetes ICD codes (ICD9CM 250.x0, 250.x2; ICD10CM E11*)
t2dm_dx_source AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
      (vocabulary_id='ICD9CM'  AND concept_code ~ '^250\.[0-9]0$|^250\.[0-9]2$')  -- 250.x0 or 250.x2
      OR
      (vocabulary_id='ICD10CM' AND concept_code ~ '^E11.*')
    )
),
-- DX: Type 1 diabetes (for exclusion / differentiation)
t1dm_dx_source AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
      (vocabulary_id='ICD9CM'  AND concept_code ~ '^250\.[0-9]1$|^250\.[0-9]3$')  -- 250.x1 or 250.x3
      OR
      (vocabulary_id='ICD10CM' AND concept_code ~ '^E10.*')
    )
),
-- DX: gestational diabetes
gestational_dm_dx_source AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
      (vocabulary_id='ICD9CM'  AND concept_code ~ '^648\.8.*')
      OR
      (vocabulary_id='ICD10CM' AND concept_code ~ '^O24\.4.*')
    )
),
-- DX: secondary/other specified diabetes
secondary_dm_dx_source AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id='ICD10CM' AND concept_code ~ '^(E08|E09|E13).*'
),

-- Expand to STANDARD condition concepts via concept_relationship or concept_ancestor
t2dm_condition_std AS (
  SELECT DISTINCT c2.concept_id
  FROM t2dm_dx_source s
  JOIN public.concept_relationship cr 
    ON cr.concept_id_1 = s.concept_id 
   AND cr.relationship_id = 'Maps to'
  JOIN public.concept c2 
    ON c2.concept_id = cr.concept_id_2
   AND c2.standard_concept = 'S'
   AND c2.domain_id = 'Condition'
),
t1dm_condition_std AS (
  SELECT DISTINCT c2.concept_id
  FROM t1dm_dx_source s
  JOIN public.concept_relationship cr 
    ON cr.concept_id_1 = s.concept_id 
   AND cr.relationship_id = 'Maps to'
  JOIN public.concept c2 
    ON c2.concept_id = cr.concept_id_2
   AND c2.standard_concept = 'S'
   AND c2.domain_id = 'Condition'
),
gestational_dm_condition_std AS (
  SELECT DISTINCT c2.concept_id
  FROM gestational_dm_dx_source s
  JOIN public.concept_relationship cr 
    ON cr.concept_id_1 = s.concept_id 
   AND cr.relationship_id = 'Maps to'
  JOIN public.concept c2 
    ON c2.concept_id = cr.concept_id_2
   AND c2.standard_concept = 'S'
   AND c2.domain_id = 'Condition'
),
secondary_dm_condition_std AS (
  SELECT DISTINCT c2.concept_id
  FROM secondary_dm_dx_source s
  JOIN public.concept_relationship cr 
    ON cr.concept_id_1 = s.concept_id 
   AND cr.relationship_id = 'Maps to'
  JOIN public.concept c2 
    ON c2.concept_id = cr.concept_id_2
   AND c2.standard_concept = 'S'
   AND c2.domain_id = 'Condition'
),

-- LAB concepts: HbA1c + glucose (LOINC → standard Measurement concepts)
hba1c_source AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id='LOINC' AND concept_code IN ('4548-4','17856-6','41995-2')
),
glucose_random_source AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id='LOINC' AND concept_code IN ('2345-7')
),
glucose_fasting_source AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id='LOINC' AND concept_code IN ('1558-6')
),
hba1c_std AS (
  SELECT DISTINCT c2.concept_id
  FROM hba1c_source s
  JOIN public.concept_relationship cr 
    ON cr.concept_id_1 = s.concept_id AND cr.relationship_id='Maps to'
  JOIN public.concept c2 
    ON c2.concept_id = cr.concept_id_2
   AND c2.standard_concept='S' AND c2.domain_id='Measurement'
),
glucose_random_std AS (
  SELECT DISTINCT c2.concept_id
  FROM glucose_random_source s
  JOIN public.concept_relationship cr 
    ON cr.concept_id_1 = s.concept_id AND cr.relationship_id='Maps to'
  JOIN public.concept c2 
    ON c2.concept_id = cr.concept_id_2
   AND c2.standard_concept='S' AND c2.domain_id='Measurement'
),
glucose_fasting_std AS (
  SELECT DISTINCT c2.concept_id
  FROM glucose_fasting_source s
  JOIN public.concept_relationship cr 
    ON cr.concept_id_1 = s.concept_id AND cr.relationship_id='Maps to'
  JOIN public.concept c2 
    ON c2.concept_id = cr.concept_id_2
   AND c2.standard_concept='S' AND c2.domain_id='Measurement'
),

-- DRUG concepts: start from ingredient names, then expand to descendants (clinical/branded drugs)
non_insulin_ingredients AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id='RxNorm'
    AND standard_concept='S'
    AND concept_class_id='Ingredient'
    AND LOWER(concept_name) IN (
      -- Biguanide
      'metformin',
      -- Sulfonylureas
      'glipizide','glyburide','glimepiride',
      -- dpp-4 inhibitors
      'sitagliptin','saxagliptin','linagliptin','alogliptin',
      -- glp-1/gip-glp-1
      'exenatide','liraglutide','dulaglutide','semaglutide','lixisenatide','tirzepatide',
      -- sglt2 inhibitors
      'canagliflozin','dapagliflozin','empagliflozin','ertugliflozin',
      -- thiazolidinediones
      'pioglitazone','rosiglitazone',
      -- meglitinides
      'repaglinide','nateglinide',
      -- alpha-glucosidase inhibitors
      'acarbose','miglitol'
    )
),
non_insulin_drug_std AS (
  SELECT DISTINCT d.concept_id
  FROM non_insulin_ingredients i
  JOIN public.concept_ancestor ca
    ON ca.ancestor_concept_id = i.concept_id
  JOIN public.concept d
    ON d.concept_id = ca.descendant_concept_id
   AND d.standard_concept = 'S'
   AND d.domain_id = 'Drug'
),
insulin_ingredients AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id='RxNorm'
    AND standard_concept='S'
    AND concept_class_id='Ingredient'
    AND LOWER(concept_name) LIKE 'insulin%'  -- catches glargine, lispro, aspart, detemir, etc.
),

/* ============================================================
   EVIDENCE IDENTIFICATION
   ============================================================ */

-- T2DM diagnosis occurrences (standard concepts)
t2dm_dx AS (
  SELECT co.person_id,
         co.condition_start_date AS dx_date,
         vo.visit_concept_id
  FROM public.condition_occurrence co
  JOIN t2dm_condition_std sc ON sc.concept_id = co.condition_concept_id
  LEFT JOIN public.visit_occurrence vo
    ON vo.visit_occurrence_id = co.visit_occurrence_id
  JOIN params p ON co.condition_start_date BETWEEN p.cohort_start AND p.cohort_end
),

t1dm_dx AS (
  SELECT person_id, condition_start_date AS dx_date
  FROM public.condition_occurrence
  WHERE condition_concept_id IN (SELECT concept_id FROM t1dm_condition_std)
),

gestational_dm_dx AS (
  SELECT person_id, condition_start_date AS dx_date
  FROM public.condition_occurrence
  WHERE condition_concept_id IN (SELECT concept_id FROM gestational_dm_condition_std)
),

secondary_dm_dx AS (
  SELECT person_id, condition_start_date AS dx_date
  FROM public.condition_occurrence
  WHERE condition_concept_id IN (SELECT concept_id FROM secondary_dm_condition_std)
),

-- Lab results
hba1c_pos AS (
  SELECT m.person_id,
         m.measurement_date AS lab_date
  FROM public.measurement m
  WHERE m.measurement_concept_id IN (SELECT concept_id FROM hba1c_std)
    AND m.value_as_number IS NOT NULL
    AND (
      (m.unit_source_value IS NULL OR m.unit_source_value IN ('%','percent','Percent','PERCENT'))
      OR m.unit_concept_id IS NULL  -- relax if unit concepts not used
    )
    AND m.value_as_number >= 6.5
),
glucose_random_pos AS (
  SELECT m.person_id,
         m.measurement_date AS lab_date
  FROM public.measurement m
  WHERE m.measurement_concept_id IN (SELECT concept_id FROM glucose_random_std)
    AND m.value_as_number IS NOT NULL
    AND (m.unit_source_value IS NULL OR m.unit_source_value ILIKE 'mg/dl')
    AND m.value_as_number >= 200
),
glucose_fasting_pos AS (
  SELECT m.person_id,
         m.measurement_date AS lab_date
  FROM public.measurement m
  WHERE m.measurement_concept_id IN (SELECT concept_id FROM glucose_fasting_std)
    AND m.value_as_number IS NOT NULL
    AND (m.unit_source_value IS NULL OR m.unit_source_value ILIKE 'mg/dl')
    AND m.value_as_number >= 126
),

-- Non-insulin antihyperglycemic exposure
non_insulin_rx AS (
  SELECT de.person_id,
         COALESCE(de.drug_exposure_start_date, de.drug_exposure_start_datetime)::date AS rx_start_date,
         COALESCE(de.days_supply, GREATEST(1, (de.drug_exposure_end_date - de.drug_exposure_start_date))) AS days_supply
  FROM public.drug_exposure de
  WHERE de.drug_concept_id IN (SELECT concept_id FROM non_insulin_drug_std)
),
-- Any insulin exposure (for "insulin-only" exclusion check)
insulin_rx AS (
  SELECT de.person_id,
         COALESCE(de.drug_exposure_start_date, de.drug_exposure_start_datetime)::date AS rx_start_date
  FROM public.drug_exposure de
  WHERE de.drug_concept_id IN (
      SELECT d.concept_id
      FROM insulin_ingredients i
      JOIN public.concept_ancestor ca
        ON ca.ancestor_concept_id = i.concept_id
      JOIN public.concept d
        ON d.concept_id = ca.descendant_concept_id
       AND d.standard_concept='S'
       AND d.domain_id='Drug'
  )
),

/* ============================================================
   RULES IMPLEMENTATION
   ============================================================ */

-- A) Diagnosis-only path: T2DM dx + (>=2 outpatient on distinct dates OR >=1 inpatient)
dx_outpatient_counts AS (
  SELECT person_id, COUNT(DISTINCT dx_date) AS n_op_dates
  FROM t2dm_dx
  WHERE COALESCE(visit_concept_id,0) IN (9202,9203)  -- outpatient (+/- ER)
  GROUP BY person_id
),
dx_inpatient_any AS (
  SELECT DISTINCT person_id
  FROM t2dm_dx
  WHERE visit_concept_id = 9201
),
path_A_candidates AS (
  SELECT person_id,
         MIN(dx_date) AS index_date_A,
         'A'::text AS path
  FROM t2dm_dx dx
  WHERE EXISTS (SELECT 1 FROM dx_inpatient_any i WHERE i.person_id = dx.person_id)
     OR EXISTS (SELECT 1 FROM dx_outpatient_counts o WHERE o.person_id=dx.person_id AND o.n_op_dates >= 2)
  GROUP BY person_id
),

-- B) Diagnosis + medication path: >=1 T2DM dx + >=1 non-insulin drug (optionally require >=30d)
path_B_candidates AS (
  SELECT dx.person_id,
         LEAST(MIN(dx.dx_date), MIN(rx.rx_start_date)) AS index_date_B,
         'B'::text AS path
  FROM t2dm_dx dx
  JOIN non_insulin_rx rx ON rx.person_id = dx.person_id
  GROUP BY dx.person_id
  HAVING COALESCE(MAX(rx.days_supply),0) >= 1 -- set to 30 if you want 30-day minimum
),

-- C) Lab path:
-- positive labs on >=2 distinct dates OR 1 positive lab + 1 T2DM dx
lab_person_dates AS (
  SELECT person_id, lab_date FROM hba1c_pos
  UNION ALL
  SELECT person_id, lab_date FROM glucose_fasting_pos
  UNION ALL
  SELECT person_id, lab_date FROM glucose_random_pos
),
lab_counts AS (
  SELECT person_id, COUNT(DISTINCT lab_date) AS n_lab_dates, MIN(lab_date) AS first_lab_date
  FROM lab_person_dates
  GROUP BY person_id
),
path_C_candidates AS (
  SELECT lc.person_id,
         lc.first_lab_date AS index_date_C,
         'C'::text AS path
  FROM lab_counts lc
  WHERE lc.n_lab_dates >= 2
  UNION
  SELECT DISTINCT l.person_id,
         LEAST(l.lab_date, d.dx_date) AS index_date_C,
         'C'::text AS path
  FROM lab_person_dates l
  JOIN t2dm_dx d ON d.person_id = l.person_id
),

-- Combine all inclusion paths
inclusion_union AS (
  SELECT person_id, index_date_A AS index_date, path FROM path_A_candidates
  UNION
  SELECT person_id, index_date_B, path FROM path_B_candidates
  UNION
  SELECT person_id, index_date_C, path FROM path_C_candidates
),

-- Exclusions:
--   1) Gestational diabetes anywhere near index
--   2) Secondary/other specified diabetes WITHOUT any T2DM dx
--   3) Only T1DM codes and no T2DM evidence (strict "only" T1DM)
excl_gestational AS (
  SELECT DISTINCT person_id FROM gestational_dm_dx
),
excl_secondary_only AS (
  SELECT s.person_id
  FROM secondary_dm_dx s
  LEFT JOIN t2dm_dx t ON t.person_id = s.person_id
  WHERE t.person_id IS NULL
  GROUP BY s.person_id
),
only_t1dm AS (
  SELECT t1.person_id
  FROM t1dm_dx t1
  LEFT JOIN t2dm_dx t2 ON t2.person_id = t1.person_id
  WHERE t2.person_id IS NULL
  GROUP BY t1.person_id
),

-- Optional: adults only at index
age_at_index AS (
  SELECT iu.person_id,
         iu.index_date,
         DATE_PART('year', AGE(iu.index_date, p.birth_datetime))::int AS age_years
  FROM inclusion_union iu
  JOIN public.person p ON p.person_id = iu.person_id
),
inclusion_final AS (
  SELECT ai.person_id, ai.index_date
  FROM age_at_index ai
  JOIN params prm ON TRUE
  WHERE (NOT prm.require_adult) OR ai.age_years >= 18
),

-- Apply exclusions
after_exclusions AS (
  SELECT i.person_id, MIN(i.index_date) AS index_date
  FROM inclusion_final i
  LEFT JOIN excl_gestational g ON g.person_id = i.person_id
  LEFT JOIN excl_secondary_only s ON s.person_id = i.person_id
  LEFT JOIN only_t1dm o ON o.person_id = i.person_id
  WHERE g.person_id IS NULL
    AND s.person_id IS NULL
    AND o.person_id IS NULL
  GROUP BY i.person_id
),

/* ============================================================
   OUTPUT
   ============================================================ */
t2dm_cohort AS (
  SELECT a.person_id,
         a.index_date,
         -- Evidence flags (helpful for QC)
         CASE WHEN EXISTS (SELECT 1 FROM path_A_candidates x WHERE x.person_id=a.person_id) THEN 1 ELSE 0 END AS evidence_dx_only_path,
         CASE WHEN EXISTS (SELECT 1 FROM path_B_candidates x WHERE x.person_id=a.person_id) THEN 1 ELSE 0 END AS evidence_dx_plus_med_path,
         CASE WHEN EXISTS (SELECT 1 FROM path_C_candidates x WHERE x.person_id=a.person_id) THEN 1 ELSE 0 END AS evidence_lab_path,
         CASE WHEN EXISTS (SELECT 1 FROM insulin_rx x WHERE x.person_id=a.person_id) THEN 1 ELSE 0 END AS any_insulin_exposure
  FROM after_exclusions a
)

SELECT * FROM t2dm_cohort
ORDER BY person_id;
