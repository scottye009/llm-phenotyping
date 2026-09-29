
-- T2DM phenotyping algorithm (OMOP CDM; PostgreSQL; schema: public)
-- Assumes standard OMOP tables in public.* (concept, concept_relationship, concept_ancestor, condition_occurrence, measurement, drug_exposure, person, visit_occurrence, observation_period)

BEGIN;

-- 1) -------------------- DIAGNOSIS CONCEPT SETS --------------------

WITH t2dm_dx_source AS (
  -- ICD9CM 250.x0 / 250.x2 ; ICD10CM E11.*
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id IN ('ICD9CM','ICD10CM')
    AND invalid_reason IS NULL
    AND (
      (vocabulary_id = 'ICD9CM' AND concept_code ~ '^250\.[0-9][02]$')
      OR
      (vocabulary_id = 'ICD10CM' AND concept_code LIKE 'E11%')
    )
),
t2dm_dx_std AS (
  -- Map to standard (SNOMED) condition concepts
  SELECT DISTINCT cr.concept_id_2 AS concept_id
  FROM public.concept_relationship cr
  JOIN t2dm_dx_source s
    ON cr.concept_id_1 = s.concept_id
  JOIN public.concept c2
    ON c2.concept_id = cr.concept_id_2
  WHERE cr.relationship_id = 'Maps to'
    AND c2.standard_concept = 'S'
    AND c2.domain_id = 'Condition'
    AND cr.invalid_reason IS NULL
),
t1dm_dx_source AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id IN ('ICD9CM','ICD10CM')
    AND invalid_reason IS NULL
    AND (
      (vocabulary_id='ICD9CM' AND concept_code ~ '^250\.[0-9][13]$')
      OR
      (vocabulary_id='ICD10CM' AND concept_code LIKE 'E10%')
    )
),
t1dm_dx_std AS (
  SELECT DISTINCT cr.concept_id_2 AS concept_id
  FROM public.concept_relationship cr
  JOIN t1dm_dx_source s ON cr.concept_id_1 = s.concept_id
  JOIN public.concept c2 ON c2.concept_id = cr.concept_id_2
  WHERE cr.relationship_id='Maps to'
    AND c2.standard_concept='S'
    AND c2.domain_id='Condition'
    AND cr.invalid_reason IS NULL
),
excl_secondary_pregnancy_dx_source AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id IN ('ICD10CM','ICD9CM')
    AND invalid_reason IS NULL
    AND (
      concept_code LIKE 'E08%' OR
      concept_code LIKE 'E09%' OR
      concept_code LIKE 'E13%' OR
      concept_code LIKE 'O24.4%' OR
      concept_code LIKE '648.8%'
    )
),
excl_secondary_pregnancy_dx_std AS (
  SELECT DISTINCT cr.concept_id_2 AS concept_id
  FROM public.concept_relationship cr
  JOIN excl_secondary_pregnancy_dx_source s ON cr.concept_id_1 = s.concept_id
  JOIN public.concept c2 ON c2.concept_id = cr.concept_id_2
  WHERE cr.relationship_id='Maps to'
    AND c2.standard_concept='S'
    AND c2.domain_id='Condition'
    AND cr.invalid_reason IS NULL
),

-- 2) -------------------- LAB CONCEPT SETS --------------------

-- LOINC codes for HbA1c (examples: 4548-4, 17856-6, 41995-2, 4549-2)
-- Fasting plasma glucose (e.g., 1558-6, 14771-0, 76629-5), Random glucose (2339-0, 2345-7), 2hr OGTT (20436-2, 1518-0)
-- You can expand these lists as needed for your local lab coverage.

hba1c_meas AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id = 'LOINC'
    AND invalid_reason IS NULL
    AND concept_code IN ('4548-4','17856-6','41995-2','4549-2')
),
fpg_meas AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id = 'LOINC'
    AND invalid_reason IS NULL
    AND concept_code IN ('1558-6','14771-0','76629-5')
),
ogtt_2h_meas AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id = 'LOINC'
    AND invalid_reason IS NULL
    AND concept_code IN ('20436-2','1518-0')
),
rpg_meas AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id = 'LOINC'
    AND invalid_reason IS NULL
    AND concept_code IN ('2339-0','2345-7')
),

-- 3) -------------------- DRUG CONCEPT SETS (RxNorm INGREDIENTS → descendants) --------------------

antidiab_ingredients AS (
  SELECT concept_id, concept_name
  FROM public.concept
  WHERE vocabulary_id='RxNorm'
    AND standard_concept='S'
    AND concept_class_id='Ingredient'
    AND lower(concept_name) IN (
      -- Biguanide
      'metformin',
      -- Sulfonylureas
      'glipizide','glyburide','glimepiride',
      -- dpp-4
      'sitagliptin','saxagliptin','linagliptin','alogliptin',
      -- glp-1 ras
      'exenatide','liraglutide','semaglutide','dulaglutide','lixisenatide','tirzepatide',
      -- sglt2
      'canagliflozin','dapagliflozin','empagliflozin','ertugliflozin',
      -- tzds
      'pioglitazone','rosiglitazone',
      -- insulin (optional; counted only with T2 coding)
      'insulin'
    )
),
antidiab_drug_concepts AS (
  -- All descendants used in drug_exposure (brands, dose forms, combos, etc.)
  SELECT DISTINCT ca.descendant_concept_id AS concept_id
  FROM public.concept_ancestor ca
  JOIN antidiab_ingredients i
    ON ca.ancestor_concept_id = i.concept_id
  JOIN public.concept c
    ON c.concept_id = ca.descendant_concept_id
  WHERE c.standard_concept = 'S'
    AND c.domain_id = 'Drug'
),
non_insulin_drug_concepts AS (
  SELECT concept_id FROM antidiab_drug_concepts
  WHERE concept_id NOT IN (
    SELECT descendant_concept_id
    FROM public.concept_ancestor
    WHERE ancestor_concept_id IN (
      SELECT concept_id FROM public.concept
      WHERE vocabulary_id='RxNorm' AND concept_class_id='Ingredient' AND lower(concept_name)='insulin'
    )
  )
),

-- 4) -------------------- EVIDENCE FLAGS --------------------

dx_events AS (
  SELECT co.person_id,
         co.condition_start_date AS evt_date,
         vo.visit_concept_id,
         CASE WHEN vo.visit_concept_id IN (9201,9203) THEN 'OP'  -- 9201 Outpatient visit, 9203 ER
              WHEN vo.visit_concept_id = 9202 THEN 'IP'          -- 9202 Inpatient visit
              ELSE 'UNK' END AS setting
  FROM public.condition_occurrence co
  LEFT JOIN public.visit_occurrence vo
    ON vo.visit_occurrence_id = co.visit_occurrence_id
  WHERE co.condition_concept_id IN (SELECT concept_id FROM t2dm_dx_std)
),
dx_events_counts AS (
  SELECT person_id,
         COUNT(*) FILTER (WHERE setting IN ('OP','ER','UNK')) AS dx_any,
         COUNT(*) FILTER (WHERE setting = 'IP') AS dx_ip,
         COUNT(DISTINCT evt_date) AS dx_distinct_dates
  FROM dx_events
  GROUP BY person_id
),
dx_exclusion AS (
  SELECT DISTINCT co.person_id
  FROM public.condition_occurrence co
  WHERE co.condition_concept_id IN (
    SELECT concept_id FROM t1dm_dx_std
    UNION ALL
    SELECT concept_id FROM excl_secondary_pregnancy_dx_std
  )
),
lab_abnormal AS (
  -- Flag abnormal labs and keep measurement date
  SELECT m.person_id,
         m.measurement_date AS evt_date
  FROM public.measurement m
  LEFT JOIN public.concept u ON u.concept_id = m.unit_concept_id
  WHERE (
    -- HbA1c >= 6.5% OR >= 48 mmol/mol
    (
      m.measurement_concept_id IN (SELECT concept_id FROM hba1c_meas) AND
      (
        (COALESCE(lower(u.concept_name),'') LIKE '%percent%' OR lower(COALESCE(m.unit_source_value,'')) IN ('%','percent')) AND m.value_as_number >= 6.5
        OR
        (COALESCE(lower(u.concept_name),'') LIKE '%mmol/mol%' OR lower(COALESCE(m.unit_source_value,'')) = 'mmol/mol') AND m.value_as_number >= 48
      )
    )
    OR
    -- Fasting plasma glucose >= 126 mg/dL
    (m.measurement_concept_id IN (SELECT concept_id FROM fpg_meas) AND m.value_as_number >= 126)
    OR
    -- 2hr OGTT >= 200 mg/dL
    (m.measurement_concept_id IN (SELECT concept_id FROM ogtt_2h_meas) AND m.value_as_number >= 200)
    OR
    -- Random plasma glucose >= 200 mg/dL
    (m.measurement_concept_id IN (SELECT concept_id FROM rpg_meas) AND m.value_as_number >= 200)
  )
),
lab_rule AS (
  SELECT person_id,
         COUNT(DISTINCT evt_date) AS abnormal_lab_dates,
         MIN(evt_date) AS first_abn_lab_date
  FROM lab_abnormal
  GROUP BY person_id
),
rx_events AS (
  SELECT de.person_id,
         de.drug_exposure_start_date AS evt_date,
         CASE WHEN de.drug_concept_id IN (SELECT concept_id FROM non_insulin_drug_concepts) THEN 'NON_INSULIN'
              ELSE 'INSULIN_OR_OTHER' END AS drug_type
  FROM public.drug_exposure de
  WHERE de.drug_concept_id IN (SELECT concept_id FROM antidiab_drug_concepts)
),
rx_rule AS (
  SELECT person_id,
         MIN(evt_date) AS first_rx_date,
         COUNT(*) FILTER (WHERE drug_type='NON_INSULIN') AS non_insulin_count,
         COUNT(*) FILTER (WHERE drug_type='INSULIN_OR_OTHER') AS insulin_count,
         COUNT(DISTINCT evt_date) AS rx_distinct_dates
  FROM rx_events
  GROUP BY person_id
),

-- 5) -------------------- APPLY RULE LOGIC --------------------

diagnosis_rule AS (
  SELECT d.person_id,
         MIN(e.evt_date) AS first_dx_date
  FROM dx_events e
  JOIN dx_events_counts d ON d.person_id = e.person_id
  WHERE (d.dx_ip >= 1 OR d.dx_distinct_dates >= 2)
  GROUP BY d.person_id
),
combined_logic AS (
  SELECT p.person_id,
         -- Rule components
         (dr.person_id IS NOT NULL) AS has_dx_rule,
         (lr.abnormal_lab_dates >= 2) AS has_lab_rule,
         (
           (rx.non_insulin_count >= 1) OR
           (rx.insulin_count >= 2 AND (dr.person_id IS NOT NULL))  -- insulin requires T2DM coding somewhere
         ) AS has_rx_rule,
         -- Index date = earliest date among satisfied components
         LEAST(
           COALESCE(dr.first_dx_date, DATE '9999-12-31'),
           COALESCE(lr.first_abn_lab_date, DATE '9999-12-31'),
           COALESCE(rx.first_rx_date, DATE '9999-12-31')
         ) AS candidate_index_date
  FROM public.person p
  LEFT JOIN diagnosis_rule dr ON dr.person_id = p.person_id
  LEFT JOIN lab_rule lr ON lr.person_id = p.person_id
  LEFT JOIN rx_rule rx ON rx.person_id = p.person_id
),
age_at_index AS (
  SELECT c.person_id,
         c.candidate_index_date AS index_date,
         DATE_PART('year', AGE(c.candidate_index_date, p.birth_datetime))::int AS age_years
  FROM combined_logic c
  JOIN public.person p ON p.person_id = c.person_id
),
t2dm_cases AS (
  SELECT a.person_id, a.index_date
  FROM combined_logic c
  JOIN age_at_index a ON a.person_id = c.person_id
  WHERE
    -- Combination: (DX AND (LAB OR RX)) OR (RX AND LAB)
    (
      (c.has_dx_rule AND (c.has_lab_rule OR c.has_rx_rule))
      OR
      (c.has_rx_rule AND c.has_lab_rule)
    )
    AND a.age_years >= 18
    AND c.candidate_index_date IS NOT NULL
    -- Exclusions
    AND c.person_id NOT IN (SELECT person_id FROM dx_exclusion)
)

-- 6) -------------------- OUTPUT COHORT --------------------

CREATE TABLE IF NOT EXISTS public.cohort_t2dm (
  person_id BIGINT PRIMARY KEY,
  index_date DATE
);

TRUNCATE TABLE public.cohort_t2dm;

INSERT INTO public.cohort_t2dm (person_id, index_date)
SELECT person_id, index_date
FROM t2dm_cases
ORDER BY person_id;
