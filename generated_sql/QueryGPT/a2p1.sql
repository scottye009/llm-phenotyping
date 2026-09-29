
-- ============================================================
-- T2DM Phenotype (OMOP CDM v5/v6) - PostgreSQL
-- Output: public.t2dm_cohort(person_id, index_date, evidence_rule)
-- ============================================================

-- Clean slate (optional)
DROP TABLE IF EXISTS public.t2dm_cohort;

WITH
-- ---------------------------
-- 1) CONCEPT SETS
-- ---------------------------

-- T2DM ICD9/10 (source codes)
t2_icd_source AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
      concept_code LIKE 'E11%'  -- ICD10CM Type 2
      OR (
        concept_code LIKE '250.%' -- ICD9CM diabetes
        AND (concept_name ILIKE '%type 2%' OR concept_name ILIKE '%type II%')
      )
    )
),

-- Map ICD to STANDARD condition concepts (SNOMED) via 'Maps to'
t2_standard AS (
  SELECT DISTINCT cr.concept_id_2 AS concept_id
  FROM public.concept_relationship cr
  JOIN t2_icd_source s ON s.concept_id = cr.concept_id_1
  WHERE cr.relationship_id = 'Maps to'
),

-- Type 1 diabetes (exclusion) ICD source
t1_icd_source AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
      concept_code LIKE 'E10%' -- ICD10CM Type 1
      OR (
        concept_code LIKE '250.%' -- ICD9CM diabetes
        AND (concept_name ILIKE '%type 1%' OR concept_name ILIKE '%type I%')
      )
    )
),
t1_standard AS (
  SELECT DISTINCT cr.concept_id_2 AS concept_id
  FROM public.concept_relationship cr
  JOIN t1_icd_source s ON s.concept_id = cr.concept_id_1
  WHERE cr.relationship_id = 'Maps to'
),

-- Gestational diabetes (exclusion)
gest_icd_source AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
      (concept_code LIKE 'O24%') OR (concept_code LIKE '648.8%')
      OR concept_name ILIKE '%gestational diabetes%'
    )
),
gest_standard AS (
  SELECT DISTINCT cr.concept_id_2 AS concept_id
  FROM public.concept_relationship cr
  JOIN gest_icd_source s ON s.concept_id = cr.concept_id_1
  WHERE cr.relationship_id = 'Maps to'
),

-- Secondary/other specified diabetes (exclusion)
secondary_icd_source AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
      concept_code LIKE 'E08%' OR concept_code LIKE 'E09%' OR concept_code LIKE 'E13%'
      OR concept_code LIKE '249%'
    )
),
secondary_standard AS (
  SELECT DISTINCT cr.concept_id_2 AS concept_id
  FROM public.concept_relationship cr
  JOIN secondary_icd_source s ON s.concept_id = cr.concept_id_1
  WHERE cr.relationship_id = 'Maps to'
),

-- LOINC measurement concept sets
loinc_hba1c AS (
  SELECT concept_id FROM public.concept
  WHERE vocabulary_id = 'LOINC' AND concept_code IN ('4548-4','17856-6','41995-2')
),
loinc_glu_fasting AS (
  SELECT concept_id FROM public.concept
  WHERE vocabulary_id = 'LOINC' AND concept_code IN ('1558-6','14771-0')
),
loinc_glu_random AS (
  SELECT concept_id FROM public.concept
  WHERE vocabulary_id = 'LOINC' AND concept_code IN ('2345-7')
),
loinc_ogtt_2h AS (
  SELECT concept_id FROM public.concept
  WHERE vocabulary_id = 'LOINC' AND concept_code IN ('20436-2')
),

-- RxNorm antihyperglycemic ingredients (include brands/clinical drugs via descendants)
rx_ingr AS (
  SELECT concept_id, concept_name
  FROM public.concept
  WHERE vocabulary_id = 'RxNorm'
    AND concept_class_id = 'Ingredient'
    AND concept_name IN (
      -- Biguanide
      'Metformin',
      -- Sulfonylureas
      'Glipizide','Glyburide','Glimepiride',
      -- Meglitinides
      'Repaglinide','Nateglinide',
      -- TZDs
      'Pioglitazone','Rosiglitazone',
      -- DPP-4 inhibitors
      'Sitagliptin','Saxagliptin','Linagliptin','Alogliptin',
      -- GLP-1 receptor agonists
      'Semaglutide','Liraglutide','Dulaglutide','Exenatide','Lixisenatide',
      -- SGLT2 inhibitors
      'Empagliflozin','Canagliflozin','Dapagliflozin','Ertugliflozin'
    )
),
rx_any_descendants AS (
  -- all branded/clinical drug descendants of the above ingredients
  SELECT DISTINCT ca.descendant_concept_id AS drug_concept_id
  FROM public.concept_ancestor ca
  JOIN rx_ingr i ON i.concept_id = ca.ancestor_concept_id
),

-- ---------------------------
-- 2) EVIDENCE (DX, LAB, MEDS)
-- ---------------------------

dx_all AS (
  SELECT co.person_id,
         co.condition_start_date::date AS cond_date,
         vo.visit_concept_id,
         CASE
           WHEN co.condition_source_concept_id IN (SELECT concept_id FROM t2_icd_source)
                 OR co.condition_concept_id IN (SELECT concept_id FROM t2_standard)
             THEN 'T2'
           WHEN co.condition_source_concept_id IN (SELECT concept_id FROM t1_icd_source)
                 OR co.condition_concept_id IN (SELECT concept_id FROM t1_standard)
             THEN 'T1'
           WHEN co.condition_source_concept_id IN (SELECT concept_id FROM gest_icd_source)
                 OR co.condition_concept_id IN (SELECT concept_id FROM gest_standard)
             THEN 'GEST'
           WHEN co.condition_source_concept_id IN (SELECT concept_id FROM secondary_icd_source)
                 OR co.condition_concept_id IN (SELECT concept_id FROM secondary_standard)
             THEN 'SEC'
           ELSE NULL
         END AS dx_flag
  FROM public.condition_occurrence co
  LEFT JOIN public.visit_occurrence vo
    ON vo.visit_occurrence_id = co.visit_occurrence_id
  WHERE co.condition_start_date IS NOT NULL
),
dx_t2 AS (
  SELECT * FROM dx_all WHERE dx_flag = 'T2'
),
dx_t1 AS (
  SELECT * FROM dx_all WHERE dx_flag = 'T1'
),
dx_gest AS (
  SELECT * FROM dx_all WHERE dx_flag = 'GEST'
),
dx_secondary AS (
  SELECT * FROM dx_all WHERE dx_flag = 'SEC'
),

-- Positive lab evidence with unit handling (mg/dL vs mmol/L; % for HbA1c)
lab_pos AS (
  SELECT m.person_id,
         m.measurement_date::date AS meas_date,
         CASE
           WHEN m.measurement_concept_id IN (SELECT concept_id FROM loinc_hba1c)
                AND m.value_as_number IS NOT NULL
                AND (
                  -- percent (e.g., '%', 'percent')
                  EXISTS (
                    SELECT 1 FROM public.concept u
                    WHERE u.concept_id = m.unit_concept_id
                      AND (u.concept_name ILIKE '%percent%' OR u.concept_code = '%')
                  )
                  AND m.value_as_number >= 6.5
                )
             THEN 'A1C>=6.5'
           WHEN m.measurement_concept_id IN (SELECT concept_id FROM loinc_glu_fasting)
                AND m.value_as_number IS NOT NULL
                AND (
                  -- mg/dL
                  EXISTS (
                    SELECT 1 FROM public.concept u
                    WHERE u.concept_id = m.unit_concept_id
                      AND (u.concept_name ILIKE '%mg/dL%' OR u.concept_code ILIKE '%mg/dL%')
                  )
                  AND m.value_as_number >= 126
                  OR
                  -- mmol/L
                  EXISTS (
                    SELECT 1 FROM public.concept u
                    WHERE u.concept_id = m.unit_concept_id
                      AND u.concept_name ILIKE '%mmol/L%'
                  )
                  AND m.value_as_number >= 7.0
                )
             THEN 'FPG>=126'
           WHEN m.measurement_concept_id IN (SELECT concept_id FROM loinc_ogtt_2h)
                AND m.value_as_number IS NOT NULL
                AND (
                  EXISTS (
                    SELECT 1 FROM public.concept u
                    WHERE u.concept_id = m.unit_concept_id
                      AND (u.concept_name ILIKE '%mg/dL%' OR u.concept_code ILIKE '%mg/dL%')
                  )
                  AND m.value_as_number >= 200
                  OR
                  EXISTS (
                    SELECT 1 FROM public.concept u
                    WHERE u.concept_id = m.unit_concept_id
                      AND u.concept_name ILIKE '%mmol/L%'
                  )
                  AND m.value_as_number >= 11.1
                )
             THEN 'OGTT2H>=200'
           WHEN m.measurement_concept_id IN (SELECT concept_id FROM loinc_glu_random)
                AND m.value_as_number IS NOT NULL
                AND (
                  EXISTS (
                    SELECT 1 FROM public.concept u
                    WHERE u.concept_id = m.unit_concept_id
                      AND (u.concept_name ILIKE '%mg/dL%' OR u.concept_code ILIKE '%mg/dL%')
                  )
                  AND m.value_as_number >= 200
                  OR
                  EXISTS (
                    SELECT 1 FROM public.concept u
                    WHERE u.concept_id = m.unit_concept_id
                      AND u.concept_name ILIKE '%mmol/L%'
                  )
                  AND m.value_as_number >= 11.1
                )
             THEN 'RPG>=200'
           ELSE NULL
         END AS lab_flag
  FROM public.measurement m
  WHERE m.measurement_concept_id IN (
          SELECT concept_id FROM loinc_hba1c
          UNION ALL SELECT concept_id FROM loinc_glu_fasting
          UNION ALL SELECT concept_id FROM loinc_glu_random
          UNION ALL SELECT concept_id FROM loinc_ogtt_2h
        )
),
lab_any AS (
  SELECT person_id, MIN(meas_date) AS first_lab_date
  FROM lab_pos
  WHERE lab_flag IS NOT NULL
  GROUP BY person_id
),

-- Medication evidence: 2+ fills >=30 days apart for any non-insulin antihyperglycemic
med_fills AS (
  SELECT de.person_id, de.drug_exposure_start_date::date AS fill_date
  FROM public.drug_exposure de
  WHERE de.drug_concept_id IN (SELECT drug_concept_id FROM rx_any_descendants)
),
med_2fills AS (
  SELECT person_id,
         MIN(fill_date) AS first_fill,
         MAX(fill_date) AS last_fill,
         COUNT(*) AS n_fills
  FROM med_fills
  GROUP BY person_id
  HAVING COUNT(*) >= 2
     AND (MAX(fill_date) - MIN(fill_date)) >= 30
),

-- ---------------------------
-- 3) APPLY INCLUSION RULES
-- ---------------------------

-- A) DX-only rule: 2+ OP/ER >=30d apart OR 1 IP
dx_rule AS (
  SELECT person_id,
         MIN(cond_date) AS index_date,
         'A:DX' AS rule_label
  FROM (
    -- inpatient >=1
    SELECT person_id, MIN(cond_date) AS cond_date
    FROM dx_t2
    WHERE visit_concept_id = 9201
    GROUP BY person_id

    UNION ALL

    -- outpatient/ER >=2 separated by >=30d
    SELECT person_id, MIN(d1.cond_date) AS cond_date
    FROM (
      SELECT person_id, cond_date
      FROM dx_t2
      WHERE visit_concept_id IN (9202,9203) OR visit_concept_id IS NULL
      GROUP BY person_id, cond_date
    ) d1
    JOIN (
      SELECT person_id, cond_date
      FROM dx_t2
      WHERE visit_concept_id IN (9202,9203) OR visit_concept_id IS NULL
      GROUP BY person_id, cond_date
    ) d2
      ON d1.person_id = d2.person_id
     AND d2.cond_date >= d1.cond_date + INTERVAL '30 day'
    GROUP BY person_id
  ) z
  GROUP BY person_id
),

-- B) DX + LAB rule
dx_lab_rule AS (
  SELECT DISTINCT d.person_id,
         LEAST(MIN(d.cond_date), l.first_lab_date) AS index_date,
         'B:DX+LAB' AS rule_label
  FROM dx_t2 d
  JOIN lab_any l ON l.person_id = d.person_id
  GROUP BY d.person_id, l.first_lab_date
),

-- C) MEDS rule: 2+ fills >=30d apart
med_rule AS (
  SELECT person_id,
         first_fill AS index_date,
         'C:MEDS' AS rule_label
  FROM med_2fills
),

-- Combine inclusion
included AS (
  SELECT * FROM dx_rule
  UNION ALL
  SELECT * FROM dx_lab_rule
  UNION ALL
  SELECT * FROM med_rule
),

-- ---------------------------
-- 4) EXCLUSIONS
-- ---------------------------

-- Exclusion windows:
gest_window AS (
  SELECT g.person_id, g.cond_date
  FROM dx_gest g
),
secondary_any AS (
  SELECT s.person_id FROM dx_secondary s GROUP BY s.person_id
),
-- "Type 1 only" patients: any T1 but no T2 anywhere
type1_only AS (
  SELECT t1.person_id
  FROM dx_t1 t1
  LEFT JOIN dx_t2 t2 ON t2.person_id = t1.person_id
  WHERE t2.person_id IS NULL
  GROUP BY t1.person_id
),

-- Age at index >=18
age_ok AS (
  SELECT i.person_id, i.index_date,
         DATE_PART('year', AGE(i.index_date, p.birth_datetime)) AS age_yrs
  FROM included i
  JOIN public.person p ON p.person_id = i.person_id
  WHERE p.birth_datetime IS NOT NULL
)

-- ---------------------------
-- 5) FINAL COHORT
-- ---------------------------
SELECT i.person_id,
       MIN(i.index_date) AS index_date,
       STRING_AGG(DISTINCT i.rule_label, '|') AS evidence_rule
INTO public.t2dm_cohort
FROM included i
JOIN age_ok a
  ON a.person_id = i.person_id
 AND a.index_date = i.index_date
LEFT JOIN gest_window gw
  ON gw.person_id = i.person_id
 AND gw.cond_date BETWEEN (i.index_date - INTERVAL '270 day') AND (i.index_date + INTERVAL '270 day')
LEFT JOIN secondary_any sec
  ON sec.person_id = i.person_id
LEFT JOIN type1_only t1o
  ON t1o.person_id = i.person_id
WHERE gw.person_id IS NULL        -- NOT gestational in ±270d window
  AND sec.person_id IS NULL       -- NOT secondary diabetes ever
  AND t1o.person_id IS NULL       -- NOT type 1 only
GROUP BY i.person_id;
