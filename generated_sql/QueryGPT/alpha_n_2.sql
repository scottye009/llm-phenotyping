
-- ================================
-- T2DM Phenotype (OMOP CDM v5+)
-- Schema: public
-- Output: public.t2dm_cases
-- ================================

DROP TABLE IF EXISTS public.t2dm_cases;

WITH
-- ---------------------------------------------------------
-- A) DIAGNOSIS CONCEPT SETS (ICD9CM/ICD10CM in source)
-- ---------------------------------------------------------
t2dm_dx_icd AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
      -- ICD-9-CM 250.x0 or 250.x2
      (vocabulary_id = 'ICD9CM' AND concept_code ~ '^250\.[0-9]?[02]$')
      -- ICD-10-CM E11.*
      OR (vocabulary_id = 'ICD10CM' AND concept_code LIKE 'E11%')
    )
),
exclude_t1dm_icd AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
      -- Type 1 DM
      (vocabulary_id='ICD9CM' AND concept_code ~ '^250\.[0-9]?[13]$')
      OR (vocabulary_id='ICD10CM' AND concept_code LIKE 'E10%')
    )
),
exclude_secondary_icd AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id='ICD10CM'
    AND (
      concept_code LIKE 'E08%'  -- due to underlying condition
      OR concept_code LIKE 'E09%' -- drug/chemical induced
      OR concept_code LIKE 'E13%' -- other specified
    )
),
exclude_gestational_icd AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id='ICD10CM'
    AND concept_code LIKE 'O24.4%' -- gestational diabetes mellitus
),

-- ---------------------------------------------------------
-- B) LAB CONCEPT SETS (LOINC standard concepts)
--     We grab LOINC codes and expand via concept_ancestor
-- ---------------------------------------------------------
loinc_a1c AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id='LOINC'
    AND concept_code IN ('4548-4','17856-6','41995-2') -- HbA1c
),
loinc_fpg AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id='LOINC'
    AND concept_code IN ('1558-6','14771-0','83208-7') -- fasting glucose
),
loinc_ogtt AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id='LOINC'
    AND concept_code IN ('20436-2','1518-0') -- 2h OGTT glucose
),
lab_concepts AS (
  -- standardize using concept_ancestor where needed
  SELECT descendant_concept_id AS concept_id FROM public.concept_ancestor WHERE ancestor_concept_id IN (SELECT concept_id FROM loinc_a1c)
  UNION
  SELECT descendant_concept_id FROM public.concept_ancestor WHERE ancestor_concept_id IN (SELECT concept_id FROM loinc_fpg)
  UNION
  SELECT descendant_concept_id FROM public.concept_ancestor WHERE ancestor_concept_id IN (SELECT concept_id FROM loinc_ogtt)
),

-- ---------------------------------------------------------
-- C) DRUG CONCEPT SETS (RxNorm ingredients + brands)
-- ---------------------------------------------------------
rxnorm_ingredients AS (
  SELECT concept_id, concept_name
  FROM public.concept
  WHERE vocabulary_id='RxNorm'
    AND concept_class_id='Ingredient'
    AND lower(concept_name) IN (
      -- Biguanide
      'metformin',
      -- Sulfonylureas
      'glipizide','glyburide','glimepiride',
      -- TZD
      'pioglitazone','rosiglitazone',
      -- DPP-4
      'sitagliptin','saxagliptin','linagliptin','alogliptin',
      -- SGLT2
      'empagliflozin','canagliflozin','dapagliflozin','ertugliflozin',
      -- GLP-1 RA / GIP
      'semaglutide','liraglutide','dulaglutide','exenatide','tirzepatide',
      -- Insulins
      'insulin glargine','insulin detemir','insulin degludec','insulin lispro','insulin aspart','insulin glulisine','insulin human'
    )
),
rxnorm_brands AS (
  SELECT concept_id, concept_name
  FROM public.concept
  WHERE vocabulary_id='RxNorm'
    AND concept_class_id IN ('Brand Name','Clinical Drug','Branded Drug','Branded Pack','Clinical Pack')
    AND lower(concept_name) SIMILAR TO
    -- Brand examples (non-exhaustive)
    '%(glucophage|glumetza|riomet|fortamet|glucotrol|diabeta|micronase|glynase|amaryl|actos|avandia|januvia|onglyza|tradjenta|nesina|jardiance|invokana|farxiga|steglatro|ozempic|rybelsus|victoza|saxenda|trulicity|byetta|bydureon|mounjaro|lantus|toujeo|basaglar|levemir|tresiba|humalog|novolog|apidra)%'
),
-- Expand to all descendant RxNorm drug concepts that map to exposures
antihyperglycemic_rxnorm AS (
  SELECT descendant_concept_id AS concept_id
  FROM public.concept_ancestor
  WHERE ancestor_concept_id IN (
    SELECT concept_id FROM rxnorm_ingredients
    UNION
    SELECT concept_id FROM rxnorm_brands
  )
),
-- Optional separation of insulin vs non-insulin for rule safeguards
insulin_rxnorm AS (
  SELECT descendant_concept_id AS concept_id
  FROM public.concept_ancestor
  WHERE ancestor_concept_id IN (
    SELECT concept_id FROM public.concept
     WHERE vocabulary_id='RxNorm'
       AND concept_class_id='Ingredient'
       AND lower(concept_name) IN ('insulin glargine','insulin detemir','insulin degludec','insulin lispro','insulin aspart','insulin glulisine','insulin human')
  )
),
non_insulin_rxnorm AS (
  SELECT concept_id FROM antihyperglycemic_rxnorm
  EXCEPT
  SELECT concept_id FROM insulin_rxnorm
),

-- ---------------------------------------------------------
-- D) DIAGNOSIS EVIDENCE
-- ---------------------------------------------------------
t2dm_dx AS (
  SELECT
    co.person_id,
    co.condition_start_date AS dx_date
  FROM public.condition_occurrence co
  JOIN public.concept csrc
    ON csrc.concept_id = co.condition_source_concept_id
  WHERE csrc.concept_id IN (SELECT concept_id FROM t2dm_dx_icd)
),
exclude_dx AS (
  SELECT DISTINCT co.person_id
  FROM public.condition_occurrence co
  JOIN public.concept csrc
    ON csrc.concept_id = co.condition_source_concept_id
  WHERE csrc.concept_id IN (
    SELECT concept_id FROM exclude_t1dm_icd
    UNION SELECT concept_id FROM exclude_secondary_icd
    UNION SELECT concept_id FROM exclude_gestational_icd
  )
),

-- ---------------------------------------------------------
-- E) LAB EVIDENCE (unit assumptions: A1c percent; glucose mg/dL)
-- ---------------------------------------------------------
abnl_a1c AS (
  SELECT m.person_id, m.measurement_date AS lab_date
  FROM public.measurement m
  WHERE m.measurement_concept_id IN (SELECT concept_id FROM lab_concepts)
    AND EXISTS (
      SELECT 1 FROM public.concept lc
      WHERE lc.concept_id = m.measurement_concept_id
        AND lc.vocabulary_id='LOINC'
        AND lc.concept_code IN ('4548-4','17856-6','41995-2')
    )
    AND m.value_as_number IS NOT NULL
    AND m.value_as_number >= 6.5  -- %
),
abnl_fpg AS (
  SELECT m.person_id, m.measurement_date AS lab_date
  FROM public.measurement m
  WHERE m.measurement_concept_id IN (SELECT concept_id FROM lab_concepts)
    AND EXISTS (
      SELECT 1 FROM public.concept lc
      WHERE lc.concept_id = m.measurement_concept_id
        AND lc.vocabulary_id='LOINC'
        AND lc.concept_code IN ('1558-6','14771-0','83208-7')
    )
    AND m.value_as_number IS NOT NULL
    AND m.value_as_number >= 126  -- mg/dL
),
abnl_ogtt AS (
  SELECT m.person_id, m.measurement_date AS lab_date
  FROM public.measurement m
  WHERE m.measurement_concept_id IN (SELECT concept_id FROM lab_concepts)
    AND EXISTS (
      SELECT 1 FROM public.concept lc
      WHERE lc.concept_id = m.measurement_concept_id
        AND lc.vocabulary_id='LOINC'
        AND lc.concept_code IN ('20436-2','1518-0')
    )
    AND m.value_as_number IS NOT NULL
    AND m.value_as_number >= 200 -- mg/dL
),
abnl_labs AS (
  SELECT person_id, lab_date FROM abnl_a1c
  UNION ALL
  SELECT person_id, lab_date FROM abnl_fpg
  UNION ALL
  SELECT person_id, lab_date FROM abnl_ogtt
),

-- ---------------------------------------------------------
-- F) MEDICATION EVIDENCE (RxNorm standard)
-- ---------------------------------------------------------
any_antihyperglycemic AS (
  SELECT de.person_id, de.drug_exposure_start_date AS rx_date
  FROM public.drug_exposure de
  WHERE de.drug_concept_id IN (SELECT concept_id FROM antihyperglycemic_rxnorm)
),
any_non_insulin AS (
  SELECT de.person_id, de.drug_exposure_start_date AS rx_date
  FROM public.drug_exposure de
  WHERE de.drug_concept_id IN (SELECT concept_id FROM non_insulin_rxnorm)
),
any_insulin AS (
  SELECT de.person_id, de.drug_exposure_start_date AS rx_date
  FROM public.drug_exposure de
  WHERE de.drug_concept_id IN (SELECT concept_id FROM insulin_rxnorm)
),

-- ---------------------------------------------------------
-- G) RULES
-- ---------------------------------------------------------
rule1_two_dx AS (
  SELECT person_id,
         MIN(dx_date) AS index_date,
         'RULE1_TWO_DX'::text AS rule_hit
  FROM (
    SELECT DISTINCT person_id, dx_date
    FROM t2dm_dx
  ) s
  GROUP BY person_id
  HAVING COUNT(*) FILTER (WHERE dx_date IS NOT NULL) >= 2
),

rule2_dx_plus_rx AS (
  SELECT t.person_id,
         LEAST(MIN(t.dx_date), MIN(r.rx_date)) AS index_date,
         'RULE2_DX_PLUS_RX'::text AS rule_hit
  FROM t2dm_dx t
  JOIN any_antihyperglycemic r
    ON r.person_id = t.person_id
  GROUP BY t.person_id
),

rule3_two_labs AS (
  SELECT person_id,
         MIN(lab_date) AS index_date,
         'RULE3_TWO_ABNL_LABS'::text AS rule_hit
  FROM (
    SELECT DISTINCT person_id, lab_date FROM abnl_labs
  ) s
  GROUP BY person_id
  HAVING COUNT(*) >= 2
),

rule4_lab_plus_rx AS (
  SELECT l.person_id,
         LEAST(MIN(l.lab_date), MIN(r.rx_date)) AS index_date,
         'RULE4_LAB_PLUS_RX'::text AS rule_hit
  FROM abnl_labs l
  JOIN any_antihyperglycemic r
    ON r.person_id = l.person_id
  GROUP BY l.person_id
),

-- ---------------------------------------------------------
-- H) UNION RULES, APPLY NOT-EXCLUSIONS AND AGE >= 18
-- ---------------------------------------------------------
all_hits AS (
  SELECT * FROM rule1_two_dx
  UNION ALL SELECT * FROM rule2_dx_plus_rx
  UNION ALL SELECT * FROM rule3_two_labs
  UNION ALL SELECT * FROM rule4_lab_plus_rx
),
first_hit AS (
  -- get earliest qualifying rule per person
  SELECT person_id,
         MIN(index_date) AS index_date
  FROM all_hits
  GROUP BY person_id
),
age_ok AS (
  SELECT p.person_id, fh.index_date
  FROM public.person p
  JOIN first_hit fh
    ON fh.person_id = p.person_id
  WHERE
    -- age >= 18 at index_date
    DATE_PART('year', age(fh.index_date, p.birth_datetime)) >= 18
),
exclude_people AS (
  SELECT DISTINCT person_id FROM exclude_dx
),
final_cases AS (
  SELECT ah.person_id,
         ah.index_date,
         -- which rule(s) hit on/earliest index
         STRING_AGG(h.rule_hit, ' | ' ORDER BY h.rule_hit) AS rules_met
  FROM age_ok ah
  JOIN all_hits h
    ON h.person_id = ah.person_id
   AND h.index_date = (
        SELECT MIN(index_date) FROM all_hits h2 WHERE h2.person_id = ah.person_id
       )
  WHERE ah.person_id NOT IN (SELECT person_id FROM exclude_people)
  GROUP BY ah.person_id, ah.index_date
)

SELECT *
INTO public.t2dm_cases
FROM final_cases;
