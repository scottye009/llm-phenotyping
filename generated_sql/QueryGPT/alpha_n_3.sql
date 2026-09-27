-- =====================================================================
-- T2DM Phenotype (OMOP CDM, PostgreSQL, schema: public)
-- Produces one row per person who meets T2DM criteria with index_date.
-- =====================================================================

-- 0) PARAMETERS (tune windows here)
WITH params AS (
  SELECT
    INTERVAL '2 years' AS lab_confirm_window
),

-- 1) CONCEPT SETS -------------------------------------------------------

-- 1a) T2DM diagnosis concepts (ICD9CM 250.x0/250.x2, ICD10CM E11*)
t2dm_dx AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
          (c.vocabulary_id='ICD10CM' AND c.concept_code LIKE 'E11%')
       OR (c.vocabulary_id='ICD9CM'  AND (
              (c.concept_code LIKE '250.%0') OR (c.concept_code LIKE '250.%2')
           ))
        )
    AND c.invalid_reason IS NULL
),

-- 1b) Type 1 DM diagnosis concepts (exclusion)
t1dm_dx AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
          (c.vocabulary_id='ICD10CM' AND c.concept_code LIKE 'E10%')
       OR (c.vocabulary_id='ICD9CM'  AND (
              (c.concept_code LIKE '250.%1') OR (c.concept_code LIKE '250.%3')
           ))
        )
    AND c.invalid_reason IS NULL
),

-- 1c) Secondary diabetes (exclusion)
secondary_dm_dx AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE (c.vocabulary_id='ICD10CM' AND c.concept_code LIKE 'E0_ %' ESCAPE '_') -- E08*, E09*
     OR (c.vocabulary_id='ICD10CM' AND (c.concept_code LIKE 'E08%' OR c.concept_code LIKE 'E09%'))
     OR (c.vocabulary_id='ICD9CM'  AND c.concept_code LIKE '249%')
    AND c.invalid_reason IS NULL
),

-- 1d) Gestational DM (exclusion)
gestational_dm_dx AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE (c.vocabulary_id='ICD10CM' AND c.concept_code LIKE 'O24.4%')
     OR (c.vocabulary_id='ICD9CM'  AND c.concept_code LIKE '648.8%')
    AND c.invalid_reason IS NULL
),

-- 1e) Prediabetes / abnormal glucose (soft exclusion unless other evidence)
prediabetes_dx AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE (c.vocabulary_id='ICD10CM' AND c.concept_code LIKE 'R73%')
     OR (c.vocabulary_id='ICD9CM'  AND c.concept_code LIKE '790.2%')
    AND c.invalid_reason IS NULL
),

-- 1f) Lab test concepts (LOINC → standard measurement concepts through relationships)
--     We grab both source LOINC and mapped STANDARD measurement concepts.
loinc_raw AS (
  SELECT * FROM (
    VALUES
      ('4548-4'), ('17856-6'), ('41995-2'), ('59261-8'), ('62388-4'), -- HbA1c
      ('1558-6'), ('14771-0'), ('35217-9'),                            -- fasting glucose
      ('1518-0'), ('20436-2'), ('14763-7'),                            -- 2h OGTT glucose
      ('2345-7'), ('2339-0')                                           -- random glucose
  ) AS v(code)
),
lab_concepts AS (
  -- Source LOINC concepts
  SELECT c.concept_id
  FROM public.concept c
  JOIN loinc_raw l ON c.vocabulary_id='LOINC' AND c.concept_code=l.code
  WHERE c.invalid_reason IS NULL
  UNION
  -- Their standard mapped measurement concepts (if any)
  SELECT cr.concept_id_2
  FROM public.concept c
  JOIN loinc_raw l ON c.vocabulary_id='LOINC' AND c.concept_code=l.code
  JOIN public.concept_relationship cr
    ON cr.concept_id_1=c.concept_id AND cr.relationship_id='Maps to'
  JOIN public.concept cs ON cs.concept_id=cr.concept_id_2 AND cs.domain_id='Measurement'
  WHERE c.invalid_reason IS NULL AND cr.invalid_reason IS NULL
),

-- 1g) Non-insulin antihyperglycemics (RxNorm ingredient/brand)
--     Seed with ingredient + brand names; expand to descendants (clinical drugs) via concept_ancestor.
drug_seed AS (
  SELECT * FROM (
    VALUES
      -- Biguanide
      ('metformin'), ('glucophage'), ('glumetza'), ('fortamet'), ('riomet'),
      -- Sulfonylureas
      ('glipizide'), ('glucotrol'), ('glyburide'), ('micronase'), ('diabeta'), ('glynase'),
      ('glimepiride'), ('amaryl'),
      -- Meglitinides
      ('repaglinide'), ('prandin'), ('nateglinide'), ('starlix'),
      -- TZDs
      ('pioglitazone'), ('actos'), ('rosiglitazone'), ('avandia'),
      -- DPP-4 inhibitors
      ('sitagliptin'), ('januvia'), ('saxagliptin'), ('onglyza'),
      ('linagliptin'), ('tradjenta'), ('alogliptin'), ('nesina'),
      -- GLP-1 RAs
      ('exenatide'), ('byetta'), ('bydureon'),
      ('liraglutide'), ('victoza'),
      ('dulaglutide'), ('trulicity'),
      ('semaglutide'), ('ozempic'), ('rybelsus'),
      ('lixisenatide'), ('adlyxin'),
      -- SGLT2 inhibitors
      ('canagliflozin'), ('invokana'),
      ('dapagliflozin'), ('farxiga'),
      ('empagliflozin'), ('jardiance'),
      ('ertugliflozin'), ('steglatro'),
      -- Others
      ('acarbose'), ('precose'), ('miglitol'), ('glyset'),
      ('colesevelam'), ('welchol'),
      ('bromocriptine'), ('cycloset'),
      ('pramlintide'), ('symlin')
  ) AS s(term)
),
non_insulin_drug_concepts AS (
  -- Find RxNorm concepts by name (ingredient, brand, clinical drug forms)
  SELECT DISTINCT c.concept_id
  FROM public.concept c
  JOIN drug_seed s
    ON c.vocabulary_id='RxNorm'
   AND LOWER(c.concept_name) LIKE '%'||s.term||'%'
   AND c.invalid_reason IS NULL
),
non_insulin_drug_all AS (
  -- Expand to descendants (clinical drug + packs)
  SELECT DISTINCT
         COALESCE(ca.descendant_concept_id, c.concept_id) AS concept_id
  FROM non_insulin_drug_concepts c
  LEFT JOIN public.concept_ancestor ca
         ON ca.ancestor_concept_id = c.concept_id
),

-- 1h) Insulin concepts (to help T1 exclusion)
insulin_seed AS (
  SELECT * FROM (
    VALUES ('insulin'), ('humalog'), ('novolog'),
           ('lantus'), ('levemir'), ('tresiba'), ('toujeo'),
           ('nph'), ('regular'), ('aspart'), ('lispro'), ('glargine'), ('detemir'), ('degludec')
  ) AS s(term)
),
insulin_concepts AS (
  SELECT DISTINCT COALESCE(ca.descendant_concept_id, c.concept_id) AS concept_id
  FROM public.concept c
  JOIN insulin_seed s
    ON c.vocabulary_id='RxNorm'
   AND LOWER(c.concept_name) LIKE '%'||s.term||'%'
   AND c.invalid_reason IS NULL
  LEFT JOIN public.concept_ancestor ca
    ON ca.ancestor_concept_id=c.concept_id
),

-- 2) EVIDENCE EXTRACTION -----------------------------------------------

-- 2a) Diagnosis occurrences grouped by date
dx AS (
  SELECT co.person_id,
         DATE(co.condition_start_date) AS dx_date,
         CASE
           WHEN co.condition_concept_id IN (SELECT concept_id FROM t2dm_dx) THEN 'T2'
           WHEN co.condition_concept_id IN (SELECT concept_id FROM t1dm_dx) THEN 'T1'
           WHEN co.condition_concept_id IN (SELECT concept_id FROM secondary_dm_dx) THEN 'SEC'
           WHEN co.condition_concept_id IN (SELECT concept_id FROM gestational_dm_dx) THEN 'GEST'
           WHEN co.condition_concept_id IN (SELECT concept_id FROM prediabetes_dx) THEN 'PREDM'
           ELSE 'OTHER'
         END AS dx_type
  FROM public.condition_occurrence co
),

dx_rollup AS (
  SELECT person_id,
         COUNT(*) FILTER (WHERE dx_type='T2') AS t2_count,
         COUNT(DISTINCT dx_date) FILTER (WHERE dx_type='T2') AS t2_distinct_dates,
         COUNT(*) FILTER (WHERE dx_type='T1') AS t1_count,
         MIN(dx_date) FILTER (WHERE dx_type IN ('T2','T1','SEC','GEST','PREDM')) AS first_dm_dx_date,
         BOOL_OR(dx_type='SEC') AS has_secondary,
         BOOL_OR(dx_type='GEST') AS has_gestational,
         BOOL_OR(dx_type='PREDM') AS has_predm
  FROM dx
  GROUP BY person_id
),

-- 2b) Abnormal measurements
--     Normalize thresholds by unit; keep a conservative mapping (mg/dL or mmol/mol or %).
abn_measure AS (
  SELECT m.person_id,
         DATE(m.measurement_date) AS meas_date,
         m.measurement_concept_id, m.unit_concept_id, m.value_as_number,
         CASE
           -- HbA1c
           WHEN m.measurement_concept_id IN (SELECT concept_id FROM lab_concepts)
                AND LOWER(m.measurement_source_value) LIKE '%a1c%'
                AND (
                     (m.unit_concept_id IN (SELECT concept_id FROM public.concept WHERE LOWER(concept_name) LIKE '%percent%') AND m.value_as_number >= 6.5)
                  OR (m.unit_concept_id IN (SELECT concept_id FROM public.concept WHERE LOWER(concept_name) LIKE '%mmol/mol%') AND m.value_as_number >= 48)
                )
             THEN 'A1C'
           -- Fasting glucose (mg/dL or mmol/L); prefer source_value contains 'fast'
           WHEN m.measurement_concept_id IN (SELECT concept_id FROM lab_concepts)
                AND (LOWER(COALESCE(m.measurement_source_value,'')) LIKE '%fast%' OR LOWER(COALESCE(m.unit_source_value,'')) LIKE '%fast%')
                AND (
                     (m.unit_concept_id IN (SELECT concept_id FROM public.concept WHERE LOWER(concept_name) LIKE '%mg/dl%') AND m.value_as_number >= 126)
                  OR (m.unit_concept_id IN (SELECT concept_id FROM public.concept WHERE LOWER(concept_name) LIKE '%mmol/l%') AND m.value_as_number >= 7.0)
                )
             THEN 'FPG'
           -- 2h OGTT
           WHEN m.measurement_concept_id IN (SELECT concept_id FROM lab_concepts)
                AND (LOWER(COALESCE(m.measurement_source_value,'')) LIKE '%2 h%' OR LOWER(COALESCE(m.measurement_source_value,'')) LIKE '%ogtt%')
                AND (
                     (m.unit_concept_id IN (SELECT concept_id FROM public.concept WHERE LOWER(concept_name) LIKE '%mg/dl%') AND m.value_as_number >= 200)
                  OR (m.unit_concept_id IN (SELECT concept_id FROM public.concept WHERE LOWER(concept_name) LIKE '%mmol/l%') AND m.value_as_number >= 11.1)
                )
             THEN 'OGTT'
           -- Random glucose ≥200 mg/dL (no unit conversion)
           WHEN m.measurement_concept_id IN (SELECT concept_id FROM lab_concepts)
                AND (
                     (m.unit_concept_id IN (SELECT concept_id FROM public.concept WHERE LOWER(concept_name) LIKE '%mg/dl%') AND m.value_as_number >= 200)
                  OR (m.unit_concept_id IN (SELECT concept_id FROM public.concept WHERE LOWER(concept_name) LIKE '%mmol/l%') AND m.value_as_number >= 11.1)
                )
             THEN 'RPG'
           ELSE NULL
         END AS flag
  FROM public.measurement m
  WHERE m.value_as_number IS NOT NULL
    AND m.measurement_concept_id IN (SELECT concept_id FROM lab_concepts)
),
abn_measure_clean AS (
  SELECT * FROM abn_measure WHERE flag IS NOT NULL
),
lab_rollup AS (
  SELECT person_id,
         COUNT(*) AS abn_count,
         COUNT(DISTINCT meas_date) AS abn_distinct_dates,
         MIN(meas_date) AS first_abn_date
  FROM abn_measure_clean
  GROUP BY person_id
),

-- 2c) Medications
non_insulin_rx AS (
  SELECT de.person_id, DATE(de.drug_exposure_start_date) AS rx_date
  FROM public.drug_exposure de
  WHERE de.drug_concept_id IN (SELECT concept_id FROM non_insulin_drug_all)
),
insulin_rx AS (
  SELECT de.person_id, DATE(de.drug_exposure_start_date) AS rx_date
  FROM public.drug_exposure de
  WHERE de.drug_concept_id IN (SELECT concept_id FROM insulin_concepts)
),
med_rollup AS (
  SELECT p.person_id,
         COUNT(*) FILTER (WHERE ni.person_id IS NOT NULL) AS non_insulin_count,
         COUNT(DISTINCT ni.rx_date) AS non_insulin_distinct_dates,
         MIN(ni.rx_date) AS first_non_insulin_date,
         COUNT(*) FILTER (WHERE ins.person_id IS NOT NULL) AS insulin_count,
         COUNT(DISTINCT ins.rx_date) AS insulin_distinct_dates,
         MIN(ins.rx_date) AS first_insulin_date
  FROM (SELECT DISTINCT person_id FROM public.person) p
  LEFT JOIN non_insulin_rx ni ON ni.person_id=p.person_id
  LEFT JOIN insulin_rx ins ON ins.person_id=p.person_id
  GROUP BY p.person_id
),

-- 2d) Age at first diabetes signal
first_signal AS (
  SELECT
    p.person_id,
    LEAST(
      COALESCE(dr.first_dm_dx_date, DATE '9999-12-31'),
      COALESCE(mr.first_non_insulin_date, DATE '9999-12-31'),
      COALESCE(mr.first_insulin_date, DATE '9999-12-31'),
      COALESCE(lr.first_abn_date, DATE '9999-12-31')
    ) AS index_date
  FROM public.person p
  LEFT JOIN dx_rollup dr ON dr.person_id=p.person_id
  LEFT JOIN med_rollup mr ON mr.person_id=p.person_id
  LEFT JOIN lab_rollup lr ON lr.person_id=p.person_id
),
age_at_index AS (
  SELECT f.person_id,
         f.index_date,
         DATE_PART('year', AGE(f.index_date, p.birth_datetime))::int AS age_index
  FROM first_signal f
  JOIN public.person p ON p.person_id=f.person_id
),

-- 3) APPLY LOGIC --------------------------------------------------------

-- Inclusion components
incl_dx AS (
  SELECT person_id,
         (t2_distinct_dates >= 2) AS incl_dx_only,
         (t2_distinct_dates >= 1) AS has_t2_dx
  FROM dx_rollup
),
incl_dx_med AS (
  SELECT mr.person_id,
         (COALESCE(d.has_t2_dx,false) AND mr.non_insulin_distinct_dates >= 1) AS incl_dx_plus_med
  FROM med_rollup mr
  LEFT JOIN incl_dx d ON d.person_id=mr.person_id
),
incl_labs AS (
  SELECT person_id,
         (abn_distinct_dates >= 2) AS incl_labs_only
  FROM lab_rollup
),
incl_med_only AS (
  SELECT person_id,
         (non_insulin_distinct_dates >= 2) AS incl_med_only
  FROM med_rollup
),

-- Exclusions
exclusions AS (
  SELECT
    p.person_id,
    COALESCE(dr.has_secondary,false) AS has_secondary,
    COALESCE(dr.has_gestational,false) AS has_gestational,
    COALESCE(dr.has_predm,false) AS has_predm_only,
    COALESCE(dr.t1_count,0) AS t1_count,
    COALESCE(dr.t2_count,0) AS t2_count,
    COALESCE(mr.non_insulin_count,0) AS non_insulin_count,
    COALESCE(mr.insulin_count,0) AS insulin_count,
    a.age_index
  FROM (SELECT DISTINCT person_id FROM public.person) p
  LEFT JOIN dx_rollup dr ON dr.person_id=p.person_id
  LEFT JOIN med_rollup mr ON mr.person_id=p.person_id
  LEFT JOIN age_at_index a ON a.person_id=p.person_id
),
likely_t1 AS (
  SELECT person_id,
         (age_index IS NOT NULL AND age_index < 30
          AND non_insulin_count = 0
          AND t1_count >= t2_count
         ) AS is_likely_t1
  FROM exclusions
),

-- Final assembly with AND/OR/NOT
final_flags AS (
  SELECT
    p.person_id,
    a.index_date,
    -- Inclusion OR:
    COALESCE(dx.incl_dx_only,false)
    OR COALESCE(dxm.incl_dx_plus_med,false)
    OR COALESCE(l.incl_labs_only,false)
    OR COALESCE(mo.incl_med_only,false) AS meets_inclusion,
    -- Exclusions:
    COALESCE(e.has_secondary,false) AS ex_secondary,
    COALESCE(e.has_gestational,false) AS ex_gestational,
    COALESCE(t1.is_likely_t1,false) AS ex_likely_t1,
    -- Prediabetes-only (no other positive)
    (COALESCE(e.has_predm_only,false)
     AND NOT (COALESCE(dx.incl_dx_only,false)
              OR COALESCE(dxm.incl_dx_plus_med,false)
              OR COALESCE(l.incl_labs_only,false)
              OR COALESCE(mo.incl_med_only,false))) AS ex_predm_only
  FROM (SELECT DISTINCT person_id FROM public.person) p
  LEFT JOIN age_at_index a ON a.person_id=p.person_id
  LEFT JOIN incl_dx dx ON dx.person_id=p.person_id
  LEFT JOIN incl_dx_med dxm ON dxm.person_id=p.person_id
  LEFT JOIN incl_labs l ON l.person_id=p.person_id
  LEFT JOIN incl_med_only mo ON mo.person_id=p.person_id
  LEFT JOIN exclusions e ON e.person_id=p.person_id
  LEFT JOIN likely_t1 t1 ON t1.person_id=p.person_id
)

-- OUTPUT
SELECT
  person_id,
  index_date,
  CASE
    WHEN meets_inclusion
         AND NOT ex_secondary
         AND NOT ex_gestational
         AND NOT ex_likely_t1
         AND NOT ex_predm_only
      THEN 1 ELSE 0
  END AS t2dm_flag,
  -- Helpful provenance flags:
  meets_inclusion,
  ex_secondary,
  ex_gestational,
  ex_likely_t1,
  ex_predm_only
FROM final_flags
WHERE meets_inclusion
   OR ex_secondary OR ex_gestational OR ex_likely_t1 OR ex_predm_only
ORDER BY t2dm_flag DESC, index_date NULLS LAST;
