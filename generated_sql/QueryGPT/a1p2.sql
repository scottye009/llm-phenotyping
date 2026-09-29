
-- ===========================================
-- T2DM Phenotype (OMOP CDM, schema: public)
-- Single, end-to-end script: builds concept sets, pulls evidence,
-- applies inclusion/exclusion, and writes final cohort table.
-- ===========================================

DROP TABLE IF EXISTS public.t2dm_candidates;

WITH
-- ---------------------------
-- 0) Utility: adults (>=18)
-- ---------------------------
adult_person AS (
  SELECT p.person_id
  FROM public.person p
  CROSS JOIN LATERAL (
    -- Build best-effort birth_date
    SELECT COALESCE(p.birth_datetime::date,
                    make_date(p.year_of_birth,
                              NULLIF(p.month_of_birth,0),
                              NULLIF(p.day_of_birth,0)))
  ) b(birth_date)
  WHERE date_part('year', age(COALESCE(p.death_datetime::date, CURRENT_DATE), b.birth_date)) >= 18
),

-- ---------------------------
-- 1) DIAGNOSIS concept sets
-- ---------------------------
icd_t2dm AS (  -- ICD9CM 250.x0, 250.x2; ICD10CM E11*
  SELECT c.concept_id AS source_concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
      (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~ '^250\.[0-9]0$|^250\.[0-9]2$')
      OR (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E11%')
    )
    AND c.invalid_reason IS NULL
),
icd_t1dm AS (  -- ICD9CM 250.x1, 250.x3; ICD10CM E10*
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
      (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~ '^250\.[0-9]1$|^250\.[0-9]3$')
      OR (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E10%')
    )
    AND c.invalid_reason IS NULL
),
icd_gdm AS (  -- Gestational: ICD10CM O24.4*, ICD9CM 648.8*
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
      (c.vocabulary_id = 'ICD9CM' AND c.concept_code LIKE '6488%')
      OR (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'O24.4%')
    )
    AND c.invalid_reason IS NULL
),
icd_secondary_dm AS (  -- Optional: ICD10CM E08*, E09*
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id = 'ICD10CM'
    AND (c.concept_code LIKE 'E08%' OR c.concept_code LIKE 'E09%')
    AND c.invalid_reason IS NULL
),

-- Map ICD -> standard SNOMED condition concepts (target_concept_id)
std_t2dm AS (
  SELECT DISTINCT s.target_concept_id AS concept_id
  FROM public.source_to_standard_vocab_map s
  JOIN icd_t2dm i ON i.source_concept_id = s.source_concept_id
  WHERE s.target_domain_id = 'Condition'
    AND s.invalid_reason IS NULL
),
std_t1dm AS (
  SELECT DISTINCT s.target_concept_id AS concept_id
  FROM public.source_to_standard_vocab_map s
  JOIN icd_t1dm i ON i.concept_id = s.source_concept_id
  WHERE s.target_domain_id = 'Condition'
    AND s.invalid_reason IS NULL
),
std_gdm AS (
  SELECT DISTINCT s.target_concept_id AS concept_id
  FROM public.source_to_standard_vocab_map s
  JOIN icd_gdm i ON i.concept_id = s.source_concept_id
  WHERE s.target_domain_id = 'Condition'
    AND s.invalid_reason IS NULL
),
std_secondary_dm AS (
  SELECT DISTINCT s.target_concept_id AS concept_id
  FROM public.source_to_standard_vocab_map s
  JOIN icd_secondary_dm i ON i.concept_id = s.source_concept_id
  WHERE s.target_domain_id = 'Condition'
    AND s.invalid_reason IS NULL
),

-- Expand to descendants where applicable
t2dm_condition_set AS (
  SELECT DISTINCT ca.descendant_concept_id AS concept_id
  FROM public.concept_ancestor ca
  JOIN std_t2dm s ON s.concept_id = ca.ancestor_concept_id
),
t1dm_condition_set AS (
  SELECT DISTINCT ca.descendant_concept_id AS concept_id
  FROM public.concept_ancestor ca
  JOIN std_t1dm s ON s.concept_id = ca.ancestor_concept_id
),
gdm_condition_set AS (
  SELECT DISTINCT ca.descendant_concept_id AS concept_id
  FROM public.concept_ancestor ca
  JOIN std_gdm s ON s.concept_id = ca.ancestor_concept_id
),
secondary_dm_condition_set AS (
  SELECT DISTINCT ca.descendant_concept_id AS concept_id
  FROM public.concept_ancestor ca
  JOIN std_secondary_dm s ON s.concept_id = ca.ancestor_concept_id
),

-- ---------------------------
-- 2) LAB concept sets (LOINC)
-- ---------------------------
loinc_hba1c AS (
  SELECT concept_id FROM public.concept
  WHERE vocabulary_id = 'LOINC'
    AND concept_code IN ('4548-4','17856-6','41995-2','59261-8')  -- extend as needed
    AND invalid_reason IS NULL
),
loinc_fpg AS (
  SELECT concept_id FROM public.concept
  WHERE vocabulary_id = 'LOINC'
    AND concept_code IN ('1558-6','14771-0','76629-5')
    AND invalid_reason IS NULL
),
loinc_ogtt AS (
  SELECT concept_id FROM public.concept
  WHERE vocabulary_id = 'LOINC'
    AND concept_code IN ('20436-2','14774-8')
    AND invalid_reason IS NULL
),
loinc_random_glu AS (
  SELECT concept_id FROM public.concept
  WHERE vocabulary_id = 'LOINC'
    AND concept_code IN ('2339-0','2345-7')
    AND invalid_reason IS NULL
),

-- Units for glucose to normalize to mg/dL (mmol/L * 18)
unit_mgdl AS (
  SELECT concept_id FROM public.concept
  WHERE lower(concept_name) LIKE '%milligram per deciliter%'
),
unit_mmol AS (
  SELECT concept_id FROM public.concept
  WHERE lower(concept_name) LIKE '%millimole per liter%'
),

-- ---------------------------
-- 3) DRUG concept sets (RxNorm ingredients + brands, expanded)
-- ---------------------------
rx_ingr AS (  -- base ingredients
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id = 'RxNorm'
    AND concept_class_id = 'Ingredient'
    AND concept_name IN (
      'Metformin','Glipizide','Glyburide','Glimepiride',
      'Sitagliptin','Saxagliptin','Linagliptin','Alogliptin',
      'Liraglutide','Semaglutide','Dulaglutide','Exenatide','Lixisenatide',
      'Empagliflozin','Canagliflozin','Dapagliflozin','Ertugliflozin',
      'Pioglitazone','Rosiglitazone'
    )
),
rx_brand AS (   -- key brands explicitly
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id = 'RxNorm'
    AND concept_class_id IN ('Brand Name','Branded Drug','Branded Drug Form')
    AND concept_name IN (
      'Glucophage','Glumetza','Riomet','Fortamet',
      'Glucotrol','Diabeta','Micronase','Glynase','Amaryl',
      'Januvia','Onglyza','Tradjenta','Nesina',
      'Victoza','Ozempic','Rybelsus','Trulicity','Byetta','Bydureon','Adlyxin',
      'Jardiance','Invokana','Farxiga','Steglatro',
      'Actos','Avandia'
    )
),
rx_antihyper_set AS (  -- expand to all descendant clinical/branded forms
  SELECT DISTINCT ca.descendant_concept_id AS concept_id
  FROM public.concept_ancestor ca
  JOIN (
      SELECT concept_id FROM rx_ingr
      UNION
      SELECT concept_id FROM rx_brand
  ) b ON ca.ancestor_concept_id = b.concept_id
),

-- ---------------------------
-- 4) Pull evidence from CDM tables
-- ---------------------------
t2dm_dx AS (
  SELECT co.person_id, co.condition_start_date::date AS dx_date
  FROM public.condition_occurrence co
  WHERE co.condition_concept_id IN (SELECT concept_id FROM t2dm_condition_set)
),
t1dm_dx AS (
  SELECT co.person_id, co.condition_start_date::date AS dx_date
  FROM public.condition_occurrence co
  WHERE co.condition_concept_id IN (SELECT concept_id FROM t1dm_condition_set)
),
gdm_dx AS (
  SELECT co.person_id, co.condition_start_date::date AS dx_date
  FROM public.condition_occurrence co
  WHERE co.condition_concept_id IN (SELECT concept_id FROM gdm_condition_set)
),
secondary_dm_dx AS (
  SELECT co.person_id, co.condition_start_date::date AS dx_date
  FROM public.condition_occurrence co
  WHERE co.condition_concept_id IN (SELECT concept_id FROM secondary_dm_condition_set)
),
drug_tx AS (
  SELECT de.person_id, de.drug_exposure_start_date::date AS drug_date
  FROM public.drug_exposure de
  WHERE de.drug_concept_id IN (SELECT concept_id FROM rx_antihyper_set)
),
labs AS (  -- normalize glucose to mg/dL; keep HbA1c in percent
  SELECT
    m.person_id,
    m.measurement_date::date AS lab_date,
    m.measurement_concept_id,
    m.value_as_number,
    m.unit_concept_id,
    CASE
      WHEN m.measurement_concept_id IN (SELECT concept_id FROM loinc_hba1c)
        THEN m.value_as_number  -- percent
      WHEN m.measurement_concept_id IN (
        SELECT concept_id FROM loinc_fpg
        UNION SELECT concept_id FROM loinc_ogtt
        UNION SELECT concept_id FROM loinc_random_glu
      )
        THEN CASE
               WHEN m.unit_concept_id IN (SELECT concept_id FROM unit_mgdl) THEN m.value_as_number
               WHEN m.unit_concept_id IN (SELECT concept_id FROM unit_mmol) AND m.value_as_number IS NOT NULL
                 THEN m.value_as_number * 18.0
               ELSE NULL
             END
      ELSE NULL
    END AS value_normalized_mgdl
  FROM public.measurement m
  WHERE m.measurement_concept_id IN (
      SELECT concept_id FROM loinc_hba1c
      UNION SELECT concept_id FROM loinc_fpg
      UNION SELECT concept_id FROM loinc_ogtt
      UNION SELECT concept_id FROM loinc_random_glu
  )
),
lab_flags AS (
  SELECT
    person_id,
    lab_date,
    MAX(CASE WHEN measurement_concept_id IN (SELECT concept_id FROM loinc_hba1c)
             AND value_as_number >= 6.5 THEN 1 ELSE 0 END) AS a1c_pos,
    MAX(CASE WHEN measurement_concept_id IN (SELECT concept_id FROM loinc_fpg)
             AND value_normalized_mgdl >= 126 THEN 1 ELSE 0 END) AS fpg_pos,
    MAX(CASE WHEN measurement_concept_id IN (SELECT concept_id FROM loinc_ogtt)
             AND value_normalized_mgdl >= 200 THEN 1 ELSE 0 END) AS ogtt_pos,
    MAX(CASE WHEN measurement_concept_id IN (SELECT concept_id FROM loinc_random_glu)
             AND value_normalized_mgdl >= 200 THEN 1 ELSE 0 END) AS rpg_pos
  FROM labs
  GROUP BY person_id, lab_date
),
lab_positive AS (
  SELECT person_id, lab_date
  FROM lab_flags
  WHERE (a1c_pos + fpg_pos + ogtt_pos + rpg_pos) > 0
),

-- ---------------------------
-- 5) Build inclusion evidence
-- ---------------------------
inclusion_A AS (  -- diagnoses-based
  SELECT person_id,
         MIN(dx_date) AS index_date,
         'A_diag'::text AS rule
  FROM (
    -- 2+ T2DM on distinct dates
    SELECT t.person_id, MIN(t.dx_date) AS dx_date
    FROM (SELECT DISTINCT person_id, dx_date FROM t2dm_dx) t
    GROUP BY t.person_id
    HAVING COUNT(*) >= 2

    UNION ALL
    -- 1 T2DM + 1 drug within ±365d
    SELECT d.person_id, MIN(d.dx_date) AS dx_date
    FROM t2dm_dx d
    JOIN drug_tx x ON x.person_id = d.person_id
                  AND x.drug_date BETWEEN d.dx_date - INTERVAL '365 days' AND d.dx_date + INTERVAL '365 days'
    GROUP BY d.person_id
  ) q
  GROUP BY person_id
),
inclusion_B AS (  -- lab-based
  SELECT person_id,
         MIN(lab_date) AS index_date,
         'B_lab'::text AS rule
  FROM (
    -- 2 positive labs on distinct dates
    SELECT lp.person_id, MIN(lp.lab_date) AS lab_date
    FROM (SELECT DISTINCT person_id, lab_date FROM lab_positive) lp
    GROUP BY lp.person_id
    HAVING COUNT(*) >= 2

    UNION ALL
    -- 1 positive lab + 1 drug within ±365d
    SELECT lp.person_id, MIN(lp.lab_date) AS lab_date
    FROM lab_positive lp
    JOIN drug_tx x ON x.person_id = lp.person_id
                  AND x.drug_date BETWEEN lp.lab_date - INTERVAL '365 days' AND lp.lab_date + INTERVAL '365 days'
    GROUP BY lp.person_id
  ) q
  GROUP BY person_id
),
inclusion_C AS (  -- medication-dominant with clinical support
  SELECT person_id,
         MIN(index_date) AS index_date,
         'C_med'::text AS rule
  FROM (
    -- >=2 drug exposures on different dates AND (any positive lab OR any T2DM dx anytime)
    SELECT x.person_id,
           MIN(x1.drug_date) AS index_date
    FROM (
      SELECT person_id, COUNT(DISTINCT drug_date) AS n_dates
      FROM (SELECT DISTINCT person_id, drug_date FROM drug_tx) d
      GROUP BY person_id
      HAVING COUNT(DISTINCT drug_date) >= 2
    ) x
    JOIN (SELECT DISTINCT person_id, drug_date FROM drug_tx) x1 ON x1.person_id = x.person_id
    LEFT JOIN t2dm_dx d ON d.person_id = x.person_id
    LEFT JOIN lab_positive lp ON lp.person_id = x.person_id
    WHERE d.person_id IS NOT NULL OR lp.person_id IS NOT NULL
    GROUP BY x.person_id
  ) q
  GROUP BY person_id
),
inclusions AS (
  SELECT * FROM inclusion_A
  UNION ALL SELECT * FROM inclusion_B
  UNION ALL SELECT * FROM inclusion_C
),

-- ---------------------------
-- 6) Exclusions
-- ---------------------------
excl_any_t1_on_or_before AS (
  SELECT i.person_id
  FROM inclusions i
  JOIN t1dm_dx e ON e.person_id = i.person_id AND e.dx_date <= i.index_date
  GROUP BY i.person_id
),
excl_any_gdm_on_or_before AS (
  SELECT i.person_id
  FROM inclusions i
  JOIN gdm_dx e ON e.person_id = i.person_id AND e.dx_date <= i.index_date
  GROUP BY i.person_id
),
excl_secondary_dm_on_or_before AS (
  SELECT i.person_id
  FROM inclusions i
  JOIN secondary_dm_dx e ON e.person_id = i.person_id AND e.dx_date <= i.index_date
  GROUP BY i.person_id
),

-- ---------------------------
-- 7) Final cohort
-- ---------------------------
first_hit AS (
  SELECT person_id, MIN(index_date) AS index_date
  FROM inclusions
  GROUP BY person_id
)
SELECT
  f.person_id,
  f.index_date,
  CASE WHEN a.person_id IS NOT NULL THEN 1 ELSE 0 END AS rule_A_diag,
  CASE WHEN b.person_id IS NOT NULL THEN 1 ELSE 0 END AS rule_B_lab,
  CASE WHEN c.person_id IS NOT NULL THEN 1 ELSE 0 END AS rule_C_med
INTO public.t2dm_candidates
FROM first_hit f
LEFT JOIN inclusion_A a ON a.person_id = f.person_id AND a.index_date = f.index_date
LEFT JOIN inclusion_B b ON b.person_id = f.person_id AND b.index_date = f.index_date
LEFT JOIN inclusion_C c ON c.person_id = f.person_id AND c.index_date = f.index_date
JOIN adult_person ap ON ap.person_id = f.person_id
LEFT JOIN excl_any_t1_on_or_before et1 ON et1.person_id = f.person_id
LEFT JOIN excl_any_gdm_on_or_before eg ON eg.person_id = f.person_id
LEFT JOIN excl_secondary_dm_on_or_before es ON es.person_id = f.person_id
WHERE et1.person_id IS NULL      -- NOT Type 1 on/before index
  AND eg.person_id IS NULL       -- NOT gestational on/before index
  AND es.person_id IS NULL;      -- (optional) NOT secondary diabetes

CREATE INDEX IF NOT EXISTS idx_t2dm_candidates_person ON public.t2dm_candidates(person_id);
