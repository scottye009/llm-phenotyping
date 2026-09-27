
-- ===========================================
-- OMOP CDM PHENOTYPE: TYPE 2 DIABETES MELLITUS
-- Target: person_id, index_date
-- Schema: public (OMOP v5.3+/v5.4)
-- ===========================================

WITH
-- -----------------------------
-- 1) DIAGNOSIS CONCEPT SETS
-- -----------------------------
t2dx_source AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
          -- ICD9CM 250.x0 or 250.x2 (Type 2)
          (vocabulary_id='ICD9CM' AND concept_code ~ '^250\.[0-9]0$|^250\.[0-9]2$|^2500$|^2502$')
          OR
          -- ICD10CM E11.*
          (vocabulary_id='ICD10CM' AND concept_code LIKE 'E11%')
        )
),
t1dx_source AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
          -- ICD9CM 250.x1 or 250.x3 (Type 1)
          (vocabulary_id='ICD9CM' AND concept_code ~ '^250\.[0-9]1$|^250\.[0-9]3$|^2501$|^2503$')
          OR
          -- ICD10CM E10.*
          (vocabulary_id='ICD10CM' AND concept_code LIKE 'E10%')
        )
),
gest_dx_source AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
          -- ICD9CM Gestational diabetes
          (vocabulary_id='ICD9CM' AND concept_code LIKE '6488%')
          OR
          -- ICD10CM Gestational diabetes
          (vocabulary_id='IC10CM' AND FALSE) -- safety; won't match
          OR
          (vocabulary_id='ICD10CM' AND concept_code LIKE 'O24.4%')
        )
),
sec_dx_source AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
          (vocabulary_id='ICD9CM' AND concept_code LIKE '249%')    -- Secondary diabetes
          OR
          (vocabulary_id='ICD10CM' AND (concept_code LIKE 'E08%' OR concept_code LIKE 'E09%' OR concept_code LIKE 'E13%'))
        )
),
prediabetes_source AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
          (vocabulary_id='ICD9CM' AND concept_code LIKE '7902%')
          OR
          (vocabulary_id='ICD10CM' AND concept_code LIKE 'R73%')
        )
),

-- Map ICD source concepts to STANDARD condition concepts (mostly SNOMED) and add descendants
t2dx_std AS (
  SELECT DISTINCT ca.descendant_concept_id AS concept_id
  FROM t2dx_source s
  JOIN public.concept_relationship cr
    ON cr.concept_id_1 = s.concept_id AND cr.relationship_id='Maps to'
  JOIN public.concept cstd
    ON cstd.concept_id = cr.concept_id_2 AND cstd.standard_concept='S'
  LEFT JOIN public.concept_ancestor ca
    ON ca.ancestor_concept_id = cstd.concept_id
  UNION
  SELECT DISTINCT cstd.concept_id
  FROM t2dx_source s
  JOIN public.concept_relationship cr
    ON cr.concept_id_1 = s.concept_id AND cr.relationship_id='Maps to'
  JOIN public.concept cstd
    ON cstd.concept_id = cr.concept_id_2 AND cstd.standard_concept='S'
),
t1dx_std AS (
  SELECT DISTINCT COALESCE(ca.descendant_concept_id, cstd.concept_id) AS concept_id
  FROM t1dx_source s
  JOIN public.concept_relationship cr ON cr.concept_id_1=s.concept_id AND cr.relationship_id='Maps to'
  JOIN public.concept cstd ON cstd.concept_id=cr.concept_id_2 AND cstd.standard_concept='S'
  LEFT JOIN public.concept_ancestor ca ON ca.ancestor_concept_id=cstd.concept_id
),
gest_dx_std AS (
  SELECT DISTINCT COALESCE(ca.descendant_concept_id, cstd.concept_id) AS concept_id
  FROM gest_dx_source s
  JOIN public.concept_relationship cr ON cr.concept_id_1=s.concept_id AND cr.relationship_id='Maps to'
  JOIN public.concept cstd ON cstd.concept_id=cr.concept_id_2 AND cstd.standard_concept='S'
  LEFT JOIN public.concept_ancestor ca ON ca.ancestor_concept_id=cstd.concept_id
),
sec_dx_std AS (
  SELECT DISTINCT COALESCE(ca.descendant_concept_id, cstd.concept_id) AS concept_id
  FROM sec_dx_source s
  JOIN public.concept_relationship cr ON cr.concept_id_1=s.concept_id AND cr.relationship_id='Maps to'
  JOIN public.concept cstd ON cstd.concept_id=cr.concept_id_2 AND cstd.standard_concept='S'
  LEFT JOIN public.concept_ancestor ca ON ca.ancestor_concept_id=cstd.concept_id
),
prediabetes_std AS (
  SELECT DISTINCT COALESCE(ca.descendant_concept_id, cstd.concept_id) AS concept_id
  FROM prediabetes_source s
  JOIN public.concept_relationship cr ON cr.concept_id_1=s.concept_id AND cr.relationship_id='Maps to'
  JOIN public.concept cstd ON cstd.concept_id=cr.concept_id_2 AND cstd.standard_concept='S'
  LEFT JOIN public.concept_ancestor ca ON ca.ancestor_concept_id=cstd.concept_id
),

-- -----------------------------
-- 2) LAB CONCEPT SETS (LOINC)
-- -----------------------------
loinc_a1c AS (
  SELECT concept_id FROM public.concept
  WHERE vocabulary_id='LOINC'
    AND concept_code IN ('4548-4','17856-6','41995-2','4549-2')  -- extend with site list
),
loinc_fpg AS (
  SELECT concept_id FROM public.concept
  WHERE vocabulary_id='LOINC'
    AND (
      concept_name ILIKE '%Glucose%' AND concept_name ILIKE '%fast%'
      OR concept_code IN ('14771-0','1558-6')  -- site-validate
    )
),
loinc_ogtt2h AS (
  SELECT concept_id FROM public.concept
  WHERE vocabulary_id='LOINC'
    AND (
      concept_name ILIKE '%Glucose%' AND concept_name ILIKE '%tolerance%' AND concept_name ILIKE '%2%'
      OR concept_code IN ('14749-6','20436-2')  -- site-validate
    )
),
lab_std AS (  -- expand LOINC to Standard measurement concepts (often LOINC already standard)
  SELECT DISTINCT COALESCE(ca.descendant_concept_id, cstd.concept_id) AS concept_id, 'A1C' AS lab
  FROM loinc_a1c s
  JOIN public.concept cstd ON cstd.concept_id=s.concept_id AND cstd.standard_concept='S'
  LEFT JOIN public.concept_ancestor ca ON ca.ancestor_concept_id=cstd.concept_id
  UNION ALL
  SELECT DISTINCT COALESCE(ca.descendant_concept_id, cstd.concept_id) AS concept_id, 'FPG' AS lab
  FROM loinc_fpg s
  JOIN public.concept cstd ON cstd.concept_id=s.concept_id AND cstd.standard_concept='S'
  LEFT JOIN public.concept_ancestor ca ON ca.ancestor_concept_id=cstd.concept_id
  UNION ALL
  SELECT DISTINCT COALESCE(ca.descendant_concept_id, cstd.concept_id) AS concept_id, 'OGTT2H' AS lab
  FROM loinc_ogtt2h s
  JOIN public.concept cstd ON cstd.concept_id=s.concept_id AND cstd.standard_concept='S'
  LEFT JOIN public.concept_ancestor ca ON ca.ancestor_concept_id=cstd.concept_id
),

-- -----------------------------
-- 3) DRUG CONCEPT SETS (RxNorm)
-- -----------------------------
rx_ing_or_brand AS (  -- seed by generic + brand names
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id='RxNorm'
    AND (
      (concept_class_id IN ('Ingredient','Brand Name')) AND concept_name IN (
        -- Biguanide
        'Metformin','Glucophage','Glumetza','Riomet','Fortamet',
        -- Sulfonylureas
        'Glipizide','Glucotrol','Glyburide','Diabeta','Glynase','Glimepiride','Amaryl',
        -- TZDs
        'Pioglitazone','Actos','Rosiglitazone','Avandia',
        -- DPP-4
        'Sitagliptin','Januvia','Saxagliptin','Onglyza','Linagliptin','Tradjenta','Alogliptin','Nesina',
        -- SGLT2
        'Canagliflozin','Invokana','Dapagliflozin','Farxiga','Empagliflozin','Jardiance','Ertugliflozin','Steglatro',
        -- GLP-1 RAs
        'Exenatide','Byetta','Bydureon','Liraglutide','Victoza','Dulaglutide','Trulicity','Semaglutide','Ozempic','Rybelsus','Lixisenatide','Adlyxin',
        -- Others (optional, add as needed)
        'Repaglinide','Nateglinide','Acarbose','Miglitol'
      )
    )
),
rx_insulin_seed AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id='RxNorm'
    AND (
      concept_class_id='Ingredient' AND concept_name ILIKE 'Insulin%'
      OR concept_name IN (
        'Insulin glargine','Lantus','Basaglar','Toujeo',
        'Insulin detemir','Levemir',
        'Insulin degludec','Tresiba',
        'Insulin isophane','NPH insulin','Humulin N','Novolin N',
        'Insulin aspart','NovoLog',
        'Insulin lispro','HumaLog',
        'Insulin glulisine','Apidra',
        'Regular insulin','Humulin R','Novolin R',
        'Insulin 70/30','Humalog Mix 75/25','Novolog Mix 70/30'
      )
    )
),
rx_niad_std AS (   -- descend to all clinical drugs/forms/strengths
  SELECT DISTINCT COALESCE(ca.descendant_concept_id, s.concept_id) AS concept_id
  FROM rx_ing_or_brand s
  LEFT JOIN public.concept_ancestor ca ON ca.ancestor_concept_id=s.concept_id
),
rx_insulin_std AS (
  SELECT DISTINCT COALESCE(ca.descendant_concept_id, s.concept_id) AS concept_id
  FROM rx_insulin_seed s
  LEFT JOIN public.concept_ancestor ca ON ca.ancestor_concept_id=s.concept_id
),

-- -----------------------------
-- 4) BUILD SIGNALS
-- -----------------------------
age18 AS (
  SELECT p.person_id, p.year_of_birth,
         DATE_TRUNC('day', MAKE_DATE(p.year_of_birth, COALESCE(p.month_of_birth,1), COALESCE(p.day_of_birth,1))) AS dob
  FROM public.person p
),
t2dx_events AS (
  SELECT co.person_id, co.condition_start_date AS event_date, co.visit_occurrence_id
  FROM public.condition_occurrence co
  WHERE co.condition_concept_id IN (SELECT concept_id FROM t2dx_std)
),
t1dx_events AS (
  SELECT co.person_id, co.condition_start_date AS event_date
  FROM public.condition_occurrence co
  WHERE co.condition_concept_id IN (SELECT concept_id FROM t1dx_std)
),
gest_events AS (
  SELECT co.person_id, co.condition_start_date AS event_date
  FROM public.condition_occurrence co
  WHERE co.condition_concept_id IN (SELECT concept_id FROM gest_dx_std)
),
sec_events AS (
  SELECT co.person_id, co.condition_start_date AS event_date
  FROM public.condition_occurrence co
  WHERE co.condition_concept_id IN (SELECT concept_id FROM sec_dx_std)
),
prediabetes_events AS (
  SELECT co.person_id, co.condition_start_date AS event_date
  FROM public.condition_occurrence co
  WHERE co.condition_concept_id IN (SELECT concept_id FROM prediabetes_std)
),
lab_positive AS (  -- A1C >= 6.5% OR FPG >=126 mg/dL OR OGTT >=200 mg/dL
  SELECT m.person_id, m.measurement_date AS event_date
  FROM public.measurement m
  JOIN lab_std ls ON ls.concept_id = m.measurement_concept_id
  WHERE (
    (ls.lab='A1C'     AND m.value_as_number >= 6.5)
    OR
    (ls.lab='FPG'     AND m.value_as_number >= 126)
    OR
    (ls.lab='OGTT2H'  AND m.value_as_number >= 200)
  )
  -- Optional: enforce expected units; uncomment if your site standardizes units
  -- AND ( (ls.lab='A1C' AND m.unit_concept_id IN (SELECT concept_id FROM public.concept WHERE concept_name='percent'))
  --    OR (ls.lab IN ('FPG','OGTT2H') AND m.unit_concept_id IN (SELECT concept_id FROM public.concept WHERE concept_name='milligram per deciliter')) )
),
drug_niad AS (
  SELECT de.person_id, de.drug_exposure_start_date AS event_date
  FROM public.drug_exposure de
  WHERE de.drug_concept_id IN (SELECT concept_id FROM rx_niad_std)
),
drug_insulin AS (
  SELECT de.person_id, de.drug_exposure_start_date AS event_date
  FROM public.drug_exposure de
  WHERE de.drug_concept_id IN (SELECT concept_id FROM rx_insulin_std)
),
visits AS (
  SELECT vo.visit_occurrence_id, vo.person_id, vo.visit_start_date, vo.visit_concept_id
  FROM public.visit_occurrence vo
),
-- classify Dx setting
t2dx_with_setting AS (
  SELECT e.person_id,
         e.event_date,
         CASE WHEN v.visit_concept_id IN (9201) THEN 'INPATIENT'
              WHEN v.visit_concept_id IN (9202,9203) THEN 'AMB_ED'
              ELSE 'OTHER' END AS setting
  FROM t2dx_events e
  LEFT JOIN visits v ON v.visit_occurrence_id = e.visit_occurrence_id
),

-- -----------------------------
-- 5) APPLY RULES
-- -----------------------------
rule_dx AS (  -- >=1 inpatient/ED OR >=2 outpatient on different dates
  SELECT person_id,
         MIN(event_date) AS index_date
  FROM (
    -- 1 inpatient/ED
    SELECT person_id, event_date
    FROM t2dx_with_setting
    WHERE setting IN ('INPATIENT','AMB_ED')

    UNION ALL

    -- 2+ outpatient on different dates (AMB_ED covers ED; you can split if desired)
    SELECT person_id, MIN(event_date) AS event_date
    FROM (
      SELECT person_id, event_date
      FROM t2dx_with_setting
      WHERE setting IN ('AMB_ED')  -- treat as ambulatory/ED
      GROUP BY person_id, event_date
    ) d
    GROUP BY person_id
    HAVING COUNT(*) >= 2
  ) x
  GROUP BY person_id
),
rule_lab_plus_meds AS (  -- lab (+/- window) AND NIAD; or Lab + Insulin + any T2 Dx
  -- Lab + NIAD within +/- 365 days
  SELECT l.person_id, MIN(LEAST(l.event_date, d.event_date)) AS index_date
  FROM lab_positive l
  JOIN drug_niad d
    ON d.person_id = l.person_id
   AND d.event_date BETWEEN (l.event_date - INTERVAL '365 days') AND (l.event_date + INTERVAL '365 days')
  GROUP BY l.person_id

  UNION

  -- Lab + Insulin within window AND any T2 Dx ever
  SELECT l.person_id, MIN(LEAST(l.event_date, ins.event_date)) AS index_date
  FROM lab_positive l
  JOIN drug_insulin ins
    ON ins.person_id = l.person_id
   AND ins.event_date BETWEEN (l.event_date - INTERVAL '365 days') AND (l.event_date + INTERVAL '365 days')
  WHERE EXISTS (SELECT 1 FROM t2dx_events td WHERE td.person_id = l.person_id)
  GROUP BY l.person_id
),
inclusion AS (
  SELECT person_id, MIN(index_date) AS index_date
  FROM (
    SELECT * FROM rule_dx
    UNION
    SELECT * FROM rule_lab_plus_meds
  ) u
  GROUP BY person_id
),
exclusion_any AS (
  SELECT DISTINCT person_id
  FROM (
    -- Pure T1DM (any T1 and no T2)
    SELECT t1.person_id
    FROM t1dx_events t1
    WHERE NOT EXISTS (SELECT 1 FROM t2dx_events t2 WHERE t2.person_id=t1.person_id)

    UNION
    -- Gestational without post-pregnancy T2 (simple exclusion: any gestational and no T2)
    SELECT g.person_id
    FROM gest_events g
    WHERE NOT EXISTS (SELECT 1 FROM t2dx_events t2 WHERE t2.person_id=g.person_id)

    UNION
    -- Secondary diabetes without T2
    SELECT s.person_id
    FROM sec_events s
    WHERE NOT EXISTS (SELECT 1 FROM t2dx_events t2 WHERE t2.person_id=s.person_id)

    UNION
    -- Optional: insulin only, no T2Dx and no NIAD
    SELECT i.person_id
    FROM drug_insulin i
    WHERE NOT EXISTS (SELECT 1 FROM t2dx_events t2 WHERE t2.person_id=i.person_id)
      AND NOT EXISTS (SELECT 1 FROM drug_niad n WHERE n.person_id=i.person_id)
  ) z
),
age_filtered AS (
  SELECT inc.person_id, inc.index_date
  FROM inclusion inc
  JOIN age18 a ON a.person_id=inc.person_id
  WHERE DATE_PART('year', AGE(inc.index_date, a.dob)) >= 18
)

-- -----------------------------
-- 6) FINAL COHORT
-- -----------------------------
SELECT af.person_id,
       af.index_date
FROM age_filtered af
LEFT JOIN exclusion_any ex ON ex.person_id = af.person_id
WHERE ex.person_id IS NULL
;
