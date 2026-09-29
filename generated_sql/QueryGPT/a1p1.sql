-- ============================
-- TYPE 2 DIABETES PHENOTYPE
-- OMOP CDM (PostgreSQL / public)
-- ============================

WITH
-- 1) DIAGNOSIS CONCEPT SETS (ICD10CM/ICD9CM on SOURCE concepts)
t2_src AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id IN ('ICD10CM','ICD9CM')
    AND (
      (vocabulary_id = 'ICD10CM' AND concept_code LIKE 'E11%')
      OR (vocabulary_id = 'ICD9CM' AND concept_code ~ '^250\.[0-9][0-9]?[02]$') -- 250.x0 or 250.x2
    )
),
t1_src AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id IN ('ICD10CM','ICD9CM')
    AND (
      (vocabulary_id = 'ICD10CM' AND concept_code LIKE 'E10%')
      OR (vocabulary_id = 'ICD9CM' AND concept_code ~ '^250\.[0-9][0-9]?[13]$') -- 250.x1 or 250.x3
    )
),
gestational_src AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id = 'ICD10CM'
    AND concept_code LIKE 'O24%'
),
secondary_src AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id = 'ICD10CM'
    AND concept_code IN (
      -- secondary diabetes families (expand as needed)
      'E08','E08.0','E08.1','E08.2','E08.3','E08.4','E08.5','E08.6','E08.8','E08.9',
      'E09','E09.0','E09.1','E09.2','E09.3','E09.4','E09.5','E09.6','E09.8','E09.9',
      'E13','E13.0','E13.1','E13.2','E13.3','E13.4','E13.5','E13.6','E13.8','E13.9'
    )
  UNION ALL
  SELECT concept_id FROM public.concept
  WHERE vocabulary_id = 'ICD10CM' AND concept_code LIKE 'E08.%'
  UNION ALL
  SELECT concept_id FROM public.concept
  WHERE vocabulary_id = 'ICD10CM' AND concept_code LIKE 'E09.%'
  UNION ALL
  SELECT concept_id FROM public.concept
  WHERE vocabulary_id = 'ICD10CM' AND concept_code LIKE 'E13.%'
),

-- 2) LAB CONCEPT SETS (Standard OMOP Measurement concepts)
-- A1c (use standard concepts via concept_ancestor; seed with common A1c parent(s))
a1c_std AS (
  SELECT DISTINCT ca.descendant_concept_id AS concept_id
  FROM public.concept c
  JOIN public.concept_ancestor ca ON ca.ancestor_concept_id = c.concept_id
  WHERE c.standard_concept = 'S'
    AND c.vocabulary_id IN ('LOINC','SNOMED')
    AND LOWER(c.concept_name) LIKE '%hemoglobin a1c%'
),
-- Fasting plasma glucose (standard)
fpg_std AS (
  SELECT DISTINCT ca.descendant_concept_id AS concept_id
  FROM public.concept c
  JOIN public.concept_ancestor ca ON ca.ancestor_concept_id = c.concept_id
  WHERE c.standard_concept = 'S'
    AND c.vocabulary_id IN ('LOINC','SNOMED')
    AND (
      LOWER(c.concept_name) LIKE '%glucose%' AND LOWER(c.concept_name) LIKE '%fasting%'
    )
),
-- 2-hour OGTT glucose (standard)
ogtt2h_std AS (
  SELECT DISTINCT ca.descendant_concept_id AS concept_id
  FROM public.concept c
  JOIN public.concept_ancestor ca ON ca.ancestor_concept_id = c.concept_id
  WHERE c.standard_concept = 'S'
    AND c.vocabulary_id IN ('LOINC','SNOMED')
    AND (
      (LOWER(c.concept_name) LIKE '%glucose%' AND LOWER(c.concept_name) LIKE '%tolerance%')
      OR LOWER(c.concept_name) LIKE '%2 hour%'
    )
),

-- 3) MEDICATION CONCEPT SET (RxNorm standard: ingredients + brands + clinical/branded drugs)
antihyper_rx AS (
  SELECT DISTINCT concept_id
  FROM public.concept
  WHERE vocabulary_id = 'RxNorm'
    AND standard_concept = 'S'
    AND (
      -- Ingredients
      LOWER(concept_name) IN (
        'metformin','glimepiride','glipizide','glyburide',
        'pioglitazone','rosiglitazone',
        'sitagliptin','saxagliptin','linagliptin','alogliptin',
        'liraglutide','dulaglutide','semaglutide','exenatide','tirzepatide',
        'empagliflozin','canagliflozin','dapagliflozin','ertugliflozin'
      )
      OR LOWER(concept_name) IN (
        -- Brand names (some are Branded Drug or Brand Name classes)
        'glucophage','glumetza','riomet','fortamet',
        'amaryl','glucotrol','glynase',
        'actos','avandia',
        'januvia','onglyza','tradjenta','nesina',
        'victoza','trulicity','ozempic','rybelsus','byetta','bydureon','mounjaro',
        'jardiance','invokana','farxiga','steglatro'
      )
    )
  UNION
  SELECT DISTINCT d.concept_id_2
  FROM public.concept c
  JOIN public.concept_relationship d
    ON d.concept_id_1 = c.concept_id
   AND d.relationship_id IN ('RxNorm has ing','Has brand name','Brand name of','RxNorm is a')
  WHERE c.concept_id IN (SELECT concept_id FROM antihyper_rx)
),

-- 4) DIAGNOSIS HITS
t2_dx AS (
  SELECT person_id, condition_start_date::date AS dx_date
  FROM public.condition_occurrence co
  WHERE co.condition_source_concept_id IN (SELECT concept_id FROM t2_src)
),
t1_dx AS (
  SELECT person_id, condition_start_date::date AS dx_date
  FROM public.condition_occurrence
  WHERE condition_source_concept_id IN (SELECT concept_id FROM t1_src)
),
gestational_dx AS (
  SELECT person_id, condition_start_date::date AS dx_date
  FROM public.condition_occurrence
  WHERE condition_source_concept_id IN (SELECT concept_id FROM gestational_src)
),
secondary_dx AS (
  SELECT person_id, condition_start_date::date AS dx_date
  FROM public.condition_occurrence
  WHERE condition_source_concept_id IN (SELECT concept_id FROM secondary_src)
),

-- 5) LAB HITS (normalize units to common thresholds when possible;
-- here we assume unit already mg/dL for glucose and % for A1c)
a1c_pos AS (
  SELECT person_id, measurement_date::date AS meas_date
  FROM public.measurement
  WHERE measurement_concept_id IN (SELECT concept_id FROM a1c_std)
    AND value_as_number >= 6.5
),
fpg_pos AS (
  SELECT person_id, measurement_date::date AS meas_date
  FROM public.measurement
  WHERE measurement_concept_id IN (SELECT concept_id FROM fpg_std)
    AND value_as_number >= 126
),
ogtt2h_pos AS (
  SELECT person_id, measurement_date::date AS meas_date
  FROM public.measurement
  WHERE measurement_concept_id IN (SELECT concept_id FROM ogtt2h_std)
    AND value_as_number >= 200
),

-- require TWO distinct dates for fasting glucose or OGTT
fpg_pair AS (
  SELECT person_id, MIN(meas_date) AS first_date
  FROM (
    SELECT DISTINCT person_id, meas_date
    FROM fpg_pos
  ) x
  GROUP BY person_id
  HAVING COUNT(*) FILTER (WHERE TRUE) >= 2
),
ogtt_pair AS (
  SELECT person_id, MIN(meas_date) AS first_date
  FROM (
    SELECT DISTINCT person_id, meas_date
    FROM ogtt2h_pos
  ) x
  GROUP BY person_id
  HAVING COUNT(*) FILTER (WHERE TRUE) >= 2
),

-- 6) MED HITS
antihyper_rx_hits AS (
  SELECT person_id, drug_exposure_start_date::date AS rx_date
  FROM public.drug_exposure
  WHERE drug_concept_id IN (SELECT concept_id FROM antihyper_rx)
),

-- 7) DIAGNOSIS RULE A
ruleA AS (
  -- >=2 T2 diagnoses on distinct dates OR 1 inpatient T2 diagnosis
  SELECT person_id, MIN(dx_date) AS index_date
  FROM (
    -- two-or-more distinct dates
    SELECT person_id, dx_date
    FROM (
      SELECT person_id, dx_date, COUNT(*) OVER (PARTITION BY person_id) AS n
      FROM (SELECT DISTINCT person_id, dx_date FROM t2_dx) z
    ) y
    WHERE n >= 2

    UNION ALL
    -- inpatient T2 (visit_occurrence.concept inpatient)
    SELECT t.person_id, t.dx_date
    FROM t2_dx t
    JOIN public.visit_occurrence v
      ON v.person_id = t.person_id
     AND v.visit_start_date::date <= t.dx_date
     AND v.visit_end_date::date >= t.dx_date
    JOIN public.concept vc
      ON vc.concept_id = v.visit_concept_id
    WHERE vc.concept_name ILIKE '%inpatient%'
  ) q
  GROUP BY person_id
),

-- 8) DIAGNOSIS + LABS RULE B
ruleB AS (
  SELECT person_id,
         MIN(evidence_date) AS index_date
  FROM (
    SELECT d.person_id,
           LEAST(d.dx_date, a.meas_date) AS evidence_date
    FROM t2_dx d
    LEFT JOIN a1c_pos a
      ON a.person_id = d.person_id

    UNION ALL
    SELECT d.person_id, LEAST(d.dx_date, f.first_date) AS evidence_date
    FROM t2_dx d
    JOIN fpg_pair f ON f.person_id = d.person_id

    UNION ALL
    SELECT d.person_id, LEAST(d.dx_date, o.first_date) AS evidence_date
    FROM t2_dx d
    JOIN ogtt_pair o ON o.person_id = d.person_id
  ) u
  GROUP BY person_id
),

-- 9) DIAGNOSIS + MEDS RULE C
ruleC AS (
  SELECT d.person_id, MIN(LEAST(d.dx_date, r.rx_date)) AS index_date
  FROM t2_dx d
  JOIN antihyper_rx_hits r
    ON r.person_id = d.person_id
  GROUP BY d.person_id
),

-- 10) BASE INCLUSIONS (A OR B OR C)
base_inclusions AS (
  SELECT person_id, MIN(index_date) AS index_date
  FROM (
    SELECT * FROM ruleA
    UNION ALL
    SELECT * FROM ruleB
    UNION ALL
    SELECT * FROM ruleC
  ) z
  GROUP BY person_id
),

-- 11) EXCLUSIONS
t1_predominant AS (
  -- >=2 T1 diagnoses on distinct dates AND no T2 diagnosis at all
  SELECT x.person_id
  FROM (
    SELECT person_id, COUNT(DISTINCT dx_date) AS n
    FROM t1_dx
    GROUP BY person_id
  ) x
  LEFT JOIN t2_dx t2 USING (person_id)
  WHERE x.n >= 2 AND t2.person_id IS NULL
),
has_gestational AS (
  SELECT DISTINCT person_id FROM gestational_dx
),
has_secondary AS (
  SELECT DISTINCT person_id FROM secondary_dx
),

-- 12) OPTIONAL: ensure index inside observation period and age >=18
eligible_base AS (
  SELECT b.person_id, b.index_date
  FROM base_inclusions b
  JOIN public.observation_period op
    ON op.person_id = b.person_id
   AND b.index_date BETWEEN op.observation_period_start_date AND op.observation_period_end_date
  JOIN public.person p
    ON p.person_id = b.person_id
  WHERE DATE_PART('year', age(b.index_date, p.birth_datetime)) >= 18
)

-- FINAL COHORT
SELECT e.person_id,
       e.index_date
FROM eligible_base e
LEFT JOIN t1_predominant t1 ON t1.person_id = e.person_id
LEFT JOIN has_gestational g ON g.person_id = e.person_id
LEFT JOIN has_secondary s ON s.person_id = e.person_id
WHERE t1.person_id IS NULL           -- NOT Type 1 predominant
  AND g.person_id IS NULL            -- NOT gestational diabetes
  AND s.person_id IS NULL            -- NOT secondary diabetes
ORDER BY person_id;
