-- =========================
-- T2DM Phenotype (OMOP)
-- =========================
-- You can wrap this in CREATE TABLE AS or CREATE VIEW as needed.

WITH
-- --------------------------------------------
-- Concept sets for diagnoses (ICD9CM/ICD10CM)
-- --------------------------------------------
t2dm_icd AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id IN ('ICD10CM','ICD9CM')
    AND (
          (vocabulary_id='ICD10CM' AND concept_code LIKE 'E11%')
       OR (vocabulary_id='ICD9CM'  AND (concept_code LIKE '250.%0' OR concept_code LIKE '250.%2'))
    )
),
t1dm_icd AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id IN ('ICD10CM','ICD9CM')
    AND (
          (vocabulary_id='ICD10CM' AND concept_code LIKE 'E10%')
       OR (vocabulary_id='ICD9CM'  AND (concept_code LIKE '250.%1' OR concept_code LIKE '250.%3'))
    )
),
secondary_dm_icd AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id IN ('ICD10CM','ICD9CM')
    AND (
          (vocabulary_id='ICD10CM' AND (concept_code LIKE 'E08%' OR concept_code LIKE 'E09%' OR concept_code LIKE 'E13%'))
       OR (vocabulary_id='ICD9CM'  AND concept_code LIKE '249%')
    )
),
gestational_dm_icd AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id IN ('ICD10CM','ICD9CM')
    AND (
          (vocabulary_id='ICD10CM' AND concept_code LIKE 'O24.4%')
       OR (vocabulary_id='ICD9CM'  AND concept_code LIKE '648.8%')
    )
),

-- Optional SNOMED backup: Type 2 diabetes mellitus (44054006) + descendants
t2dm_snomed AS (
  SELECT ca.descendant_concept_id AS concept_id
  FROM public.concept c
  JOIN public.concept_ancestor ca
    ON ca.ancestor_concept_id = c.concept_id
  WHERE c.vocabulary_id = 'SNOMED'
    AND c.concept_code = '44054006' -- Type 2 diabetes mellitus
),

-- --------------------------------------------
-- Drug concepts: non-insulin antihyperglycemics (RxNorm ingredient + descendants)
-- --------------------------------------------
drug_ingredients AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id = 'RxNorm'
    AND concept_class_id = 'Ingredient'
    AND lower(concept_name) IN (
      -- Biguanide
      'metformin',
      -- Sulfonylureas
      'glipizide','glyburide','glimepiride',
      -- Meglitinides
      'repaglinide','nateglinide',
      -- Thiazolidinediones
      'pioglitazone','rosiglitazone',
      -- dpp-4
      'sitagliptin','saxagliptin','linagliptin','alogliptin',
      -- glp-1 ras / incretins (incl. dual incretin)
      'exenatide','liraglutide','semaglutide','dulaglutide','lixisenatide','tirzepatide',
      -- sglt2 inhibitors
      'canagliflozin','dapagliflozin','empagliflozin','ertugliflozin',
      -- alpha-glucosidase
      'acarbose','miglitol'
    )
),
non_insulin_antidiab AS (
  -- get all descendants (brands/forms/clinical drugs)
  SELECT DISTINCT ca.descendant_concept_id AS concept_id
  FROM drug_ingredients di
  JOIN public.concept_ancestor ca
    ON ca.ancestor_concept_id = di.concept_id
),
-- If you also want to count fixed-dose combos, the descendant expansion above covers them.

-- --------------------------------------------
-- LOINC concept sets for measurements
-- --------------------------------------------
a1c_concepts AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id='LOINC'
    AND standard_concept='S'
    AND lower(concept_name) LIKE '%hemoglobin a1c%'
),
fasting_glucose_concepts AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id='LOINC'
    AND standard_concept='S'
    AND lower(concept_name) LIKE '%glucose%'
    AND lower(concept_name) LIKE '%fasting%'
),
ogtt_2h_glucose_concepts AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id='LOINC'
    AND standard_concept='S'
    AND (lower(concept_name) LIKE '%glucose%'
         AND (lower(concept_name) LIKE '%tolerance%' OR lower(concept_name) LIKE '%2 hour%'))
),
random_glucose_concepts AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id='LOINC'
    AND standard_concept='S'
    AND lower(concept_name) LIKE '%glucose%'
    AND (lower(concept_name) NOT LIKE '%fasting%' AND lower(concept_name) NOT LIKE '%tolerance%' AND lower(concept_name) NOT LIKE '%2 hour%')
),

-- --------------------------------------------
-- Evidence: diagnoses
-- --------------------------------------------
t2dm_dx AS (
  SELECT co.person_id, co.condition_start_date AS dx_date
  FROM public.condition_occurrence co
  WHERE
    -- by source ICD
    co.condition_source_concept_id IN (SELECT concept_id FROM t2dm_icd)
    -- or by standard SNOMED
    OR co.condition_concept_id IN (SELECT concept_id FROM t2dm_snomed)
),
t1dm_dx AS (
  SELECT co.person_id, co.condition_start_date AS dx_date
  FROM public.condition_occurrence co
  WHERE co.condition_source_concept_id IN (SELECT concept_id FROM t1dm_icd)
),
secondary_dm_dx AS (
  SELECT co.person_id, co.condition_start_date AS dx_date
  FROM public.condition_occurrence co
  WHERE co.condition_source_concept_id IN (SELECT concept_id FROM secondary_dm_icd)
),
gestational_dm_dx AS (
  SELECT co.person_id, co.condition_start_date AS dx_date
  FROM public.condition_occurrence co
  WHERE co.condition_source_concept_id IN (SELECT concept_id FROM gestational_dm_icd)
),

-- --------------------------------------------
-- Evidence: drugs (non-insulin antihyperglycemics)
-- --------------------------------------------
antidiab_rx AS (
  SELECT de.person_id, COALESCE(de.drug_exposure_start_date, de.drug_exposure_start_datetime)::date AS rx_date
  FROM public.drug_exposure de
  WHERE de.drug_concept_id IN (SELECT concept_id FROM non_insulin_antidiab)
),

-- --------------------------------------------
-- Evidence: labs
-- --------------------------------------------
a1c_pos AS (
  SELECT m.person_id, m.measurement_date AS lab_date
  FROM public.measurement m
  WHERE m.measurement_concept_id IN (SELECT concept_id FROM a1c_concepts)
    AND m.value_as_number IS NOT NULL
    AND (
          (m.unit_concept_id IS NULL AND m.value_as_number >= 6.5)  -- assume %
       OR (m.unit_concept_id IN (
              SELECT concept_id FROM public.concept WHERE lower(concept_name) IN ('%','percent','percent [ratio]')
          ) AND m.value_as_number >= 6.5)
        )
),
fpg_pos AS (
  SELECT m.person_id, m.measurement_date AS lab_date
  FROM public.measurement m
  WHERE m.measurement_concept_id IN (SELECT concept_id FROM fasting_glucose_concepts)
    AND m.value_as_number IS NOT NULL
    AND (
          (m.unit_concept_id IS NULL AND m.value_as_number >= 126)
       OR (m.unit_concept_id IN (
              SELECT concept_id FROM public.concept WHERE lower(concept_name) IN ('mg/dl','mg per dL','milligram per deciliter')
          ) AND m.value_as_number >= 126)
        )
),
ogtt2h_pos AS (
  SELECT m.person_id, m.measurement_date AS lab_date
  FROM public.measurement m
  WHERE m.measurement_concept_id IN (SELECT concept_id FROM ogtt_2h_glucose_concepts)
    AND m.value_as_number IS NOT NULL
    AND (
          (m.unit_concept_id IS NULL AND m.value_as_number >= 200)
       OR (m.unit_concept_id IN (
              SELECT concept_id FROM public.concept WHERE lower(concept_name) IN ('mg/dl','mg per dL','milligram per deciliter')
          ) AND m.value_as_number >= 200)
        )
),
random_glucose_pos AS (
  SELECT m.person_id, m.measurement_date AS lab_date
  FROM public.measurement m
  WHERE m.measurement_concept_id IN (SELECT concept_id FROM random_glucose_concepts)
    AND m.value_as_number IS NOT NULL
    AND (
          (m.unit_concept_id IS NULL AND m.value_as_number >= 200)
       OR (m.unit_concept_id IN (
              SELECT concept_id FROM public.concept WHERE lower(concept_name) IN ('mg/dl','mg per dL','milligram per deciliter')
          ) AND m.value_as_number >= 200)
        )
),
lab_evidence AS (
  SELECT person_id, lab_date
  FROM (
    SELECT * FROM a1c_pos
    UNION ALL SELECT * FROM fpg_pos
    UNION ALL SELECT * FROM ogtt2h_pos
    UNION ALL SELECT * FROM random_glucose_pos
  ) u
),

-- --------------------------------------------
-- Inclusion logic
-- --------------------------------------------
inc_A_two_dx AS (
  SELECT person_id, MIN(dx_date) AS index_date
  FROM (
    SELECT DISTINCT person_id, dx_date
    FROM t2dm_dx
  ) d
  GROUP BY person_id
  HAVING COUNT(*) FILTER (WHERE TRUE) >= 2
),
inc_B_dx_plus_rx AS (
  SELECT d.person_id, MIN(LEAST(d.dx_date, r.rx_date)) AS index_date
  FROM t2dm_dx d
  JOIN antidiab_rx r
    ON r.person_id = d.person_id
       AND r.rx_date BETWEEN d.dx_date - INTERVAL '365 days' AND d.dx_date + INTERVAL '365 days'
  GROUP BY d.person_id
),
-- labs on >=2 distinct dates
inc_C_two_labs AS (
  SELECT person_id, MIN(lab_date) AS index_date
  FROM (
    SELECT DISTINCT person_id, lab_date FROM lab_evidence
  ) l
  GROUP BY person_id
  HAVING COUNT(*) FILTER (WHERE TRUE) >= 2
),
-- >=1 lab + drug
inc_D_lab_plus_rx AS (
  SELECT l.person_id, MIN(LEAST(l.lab_date, r.rx_date)) AS index_date
  FROM lab_evidence l
  JOIN antidiab_rx r
    ON r.person_id = l.person_id
       AND r.rx_date BETWEEN l.lab_date - INTERVAL '365 days' AND l.lab_date + INTERVAL '365 days'
  GROUP BY l.person_id
),

inclusions AS (
  SELECT person_id, MIN(index_date) AS index_date
  FROM (
    SELECT * FROM inc_A_two_dx
    UNION ALL SELECT * FROM inc_B_dx_plus_rx
    UNION ALL SELECT * FROM inc_C_two_labs
    UNION ALL SELECT * FROM inc_D_lab_plus_rx
  ) x
  GROUP BY person_id
),

-- --------------------------------------------
-- Exclusions
-- --------------------------------------------
excl_t1dm AS (
  SELECT i.person_id
  FROM inclusions i
  JOIN t1dm_dx t1
    ON t1.person_id = i.person_id
   AND t1.dx_date <= i.index_date
),
excl_secondary AS (
  SELECT i.person_id
  FROM inclusions i
  JOIN secondary_dm_dx s
    ON s.person_id = i.person_id
   AND s.dx_date <= i.index_date
),
excl_gestational AS (
  SELECT i.person_id
  FROM inclusions i
  JOIN gestational_dm_dx g
    ON g.person_id = i.person_id
   AND g.dx_date BETWEEN (i.index_date - INTERVAL '300 days') AND (i.index_date + INTERVAL '300 days')
),

-- --------------------------------------------
-- Age >= 18 at index
-- --------------------------------------------
age_ok AS (
  SELECT i.person_id, i.index_date
  FROM inclusions i
  JOIN public.person p
    ON p.person_id = i.person_id
  WHERE (date_part('year', i.index_date) - p.year_of_birth
         - CASE WHEN to_char(i.index_date, 'MMDD') < COALESCE(lpad(p.month_of_birth::text,2,'0')||lpad(p.day_of_birth::text,2,'0'),'0101') THEN 1 ELSE 0 END) >= 18
)

SELECT a.person_id, a.index_date
FROM age_ok a
LEFT JOIN excl_t1dm e1 ON e1.person_id = a.person_id
LEFT JOIN excl_secondary e2 ON e2.person_id = a.person_id
LEFT JOIN excl_gestational e3 ON e3.person_id = a.person_id
WHERE e1.person_id IS NULL
  AND e2.person_id IS NULL
  AND e3.person_id IS NULL
ORDER BY a.person_id;
