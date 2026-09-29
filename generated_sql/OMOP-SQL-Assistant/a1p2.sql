/* ============================================================================
Phenotyping algorithm: Type 2 Diabetes Mellitus (T2DM) — OMOP CDM v5.4 (PostgreSQL)

High-level logic (CASE):
  (A OR B OR C OR D) AND NOT (EXCLUSIONS)

Where:
  A = ≥2 T2DM diagnosis codes (ICD9CM/ICD10CM) on different dates
  B = ≥1 T2DM diagnosis code AND ≥1 antidiabetic medication exposure
  C = ≥2 abnormal diabetes labs (HbA1c/glucose) on different dates
  D = ≥1 abnormal diabetes lab AND ≥1 antidiabetic medication exposure
EXCLUSIONS:
  Any Type 1 diabetes OR gestational diabetes OR secondary diabetes diagnosis codes (ICD9CM/ICD10CM)

Notes:
  - Diagnoses use CONDITION_OCCURRENCE.condition_source_concept_id (preferred) and fallback to condition_source_value.
  - Meds use DRUG_EXPOSURE.drug_concept_id (RxNorm/RxNorm Extension).
  - Labs use MEASUREMENT.measurement_concept_id (LOINC) and value_as_number thresholds.
============================================================================ */

WITH
/* -----------------------------
1) ICD code concept sets (source vocabularies)
------------------------------*/
t2dm_icd AS (
  SELECT c.concept_id, c.vocabulary_id, c.concept_code
  FROM public.concept c
  WHERE (c.vocabulary_id = 'ICD9CM'  AND (
           c.concept_code LIKE '250.%0' OR c.concept_code LIKE '250.%2'  -- DM type II or unspecified, not stated uncontrolled/controlled
        OR c.concept_code IN ('250.00','250.02','250.10','250.12','250.20','250.22','250.30','250.32','250.40','250.42',
                              '250.50','250.52','250.60','250.62','250.70','250.72','250.80','250.82','250.90','250.92')
       ))
     OR (c.vocabulary_id = 'ICD10CM' AND (
           c.concept_code LIKE 'E11%'   -- Type 2 diabetes mellitus
        OR c.concept_code LIKE 'E13%'   -- Other specified diabetes mellitus (often treated like T2DM in claims; keep if you want broader net)
       ))
),
t1dm_icd AS (
  SELECT c.concept_id, c.vocabulary_id, c.concept_code
  FROM public.concept c
  WHERE (c.vocabulary_id = 'ICD9CM'  AND (c.concept_code LIKE '250.%1' OR c.concept_code LIKE '250.%3')) -- Type I DM
     OR (c.vocabulary_id = 'ICD10CM' AND  c.concept_code LIKE 'E10%')  -- Type 1 DM
),
gestational_dm_icd AS (
  SELECT c.concept_id, c.vocabulary_id, c.concept_code
  FROM public.concept c
  WHERE (c.vocabulary_id = 'ICD9CM'  AND (c.concept_code LIKE '648.8%')) -- abnormal glucose tolerance/gestational DM family
     OR (c.vocabulary_id = 'ICD10CM' AND (c.concept_code LIKE 'O24.4%' OR c.concept_code LIKE 'O24.9%')) -- gestational/unspecified diabetes in pregnancy
),
secondary_dm_icd AS (
  SELECT c.concept_id, c.vocabulary_id, c.concept_code
  FROM public.concept c
  WHERE (c.vocabulary_id = 'ICD9CM'  AND (c.concept_code LIKE '249%'))  -- secondary diabetes mellitus
     OR (c.vocabulary_id = 'ICD10CM' AND (c.concept_code LIKE 'E08%' OR c.concept_code LIKE 'E09%')) -- due to underlying condition/drug
),

/* -----------------------------
2) Drug concept sets (RxNorm)
   Include generics + common brand names (concept_name search).
   This is a *pragmatic* set for phenotyping; expand as needed.
------------------------------*/
antidiabetic_drug_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('RxNorm','RxNorm Extension')
    AND c.concept_class_id IN ('Ingredient','Branded Drug','Clinical Drug','Branded Drug Comp','Clinical Drug Comp')
    AND (
      /* Biguanide */
      c.concept_name ILIKE '%metformin%' OR c.concept_name ILIKE '%glucophage%'

      /* Sulfonylureas */
      OR c.concept_name ILIKE '%glipizide%' OR c.concept_name ILIKE '%glucotrol%'
      OR c.concept_name ILIKE '%glyburide%' OR c.concept_name ILIKE '%diabeta%' OR c.concept_name ILIKE '%micronase%'
      OR c.concept_name ILIKE '%glimepiride%' OR c.concept_name ILIKE '%amaryl%'

      /* Thiazolidinediones */
      OR c.concept_name ILIKE '%pioglitazone%' OR c.concept_name ILIKE '%actos%'
      OR c.concept_name ILIKE '%rosiglitazone%' OR c.concept_name ILIKE '%avandia%'

      /* DPP-4 inhibitors */
      OR c.concept_name ILIKE '%sitagliptin%' OR c.concept_name ILIKE '%januvia%'
      OR c.concept_name ILIKE '%linagliptin%' OR c.concept_name ILIKE '%tradjenta%'
      OR c.concept_name ILIKE '%saxagliptin%' OR c.concept_name ILIKE '%onglyza%'
      OR c.concept_name ILIKE '%alogliptin%' OR c.concept_name ILIKE '%nesina%'

      /* GLP-1 receptor agonists */
      OR c.concept_name ILIKE '%liraglutide%' OR c.concept_name ILIKE '%victoza%'
      OR c.concept_name ILIKE '%semaglutide%' OR c.concept_name ILIKE '%ozempic%' OR c.concept_name ILIKE '%rybelsus%'
      OR c.concept_name ILIKE '%dulaglutide%' OR c.concept_name ILIKE '%trulicity%'
      OR c.concept_name ILIKE '%exenatide%' OR c.concept_name ILIKE '%byetta%' OR c.concept_name ILIKE '%bydureon%'

      /* SGLT2 inhibitors */
      OR c.concept_name ILIKE '%empagliflozin%' OR c.concept_name ILIKE '%jardiance%'
      OR c.concept_name ILIKE '%dapagliflozin%' OR c.concept_name ILIKE '%farxiga%'
      OR c.concept_name ILIKE '%canagliflozin%' OR c.concept_name ILIKE '%invokana%'
      OR c.concept_name ILIKE '%ertugliflozin%' OR c.concept_name ILIKE '%steglatro%'

      /* Other */
      OR c.concept_name ILIKE '%acarbose%' OR c.concept_name ILIKE '%precose%'
      OR c.concept_name ILIKE '%miglitol%' OR c.concept_name ILIKE '%glyset%'
      OR c.concept_name ILIKE '%repaglinide%' OR c.concept_name ILIKE '%prandin%'
      OR c.concept_name ILIKE '%nateglinide%' OR c.concept_name ILIKE '%starlix%'
    )
),
/* Optional: insulin set (kept separate in case you want insulin-only rules) */
insulin_drug_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('RxNorm','RxNorm Extension')
    AND c.concept_name ILIKE '%insulin%'
),

/* -----------------------------
3) Lab concept sets (LOINC via MEASUREMENT.measurement_concept_id)
   If your site stores glucose/a1c under different standard concepts, add them here.
------------------------------*/
a1c_loinc AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id = 'LOINC'
    AND c.concept_code IN (
      '4548-4',  -- Hemoglobin A1c/Hemoglobin.total in Blood
      '17856-6'  -- Hemoglobin A1c/Hemoglobin.total in Blood by HPLC (common)
    )
),
glucose_loinc AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id = 'LOINC'
    AND c.concept_code IN (
      '2345-7',  -- Glucose [Mass/volume] in Serum or Plasma
      '2339-0',  -- Glucose [Mass/volume] in Blood
      '1558-6'   -- Glucose [Mass/volume] in Serum or Plasma -- fasting (often used; sites vary)
    )
),

/* -----------------------------
4) Evidence extraction
------------------------------*/
t2dx AS (
  SELECT
    co.person_id,
    co.condition_start_date AS event_date
  FROM public.condition_occurrence co
  WHERE
    /* Preferred: source concept id points to ICD9CM/ICD10CM concept */
    co.condition_source_concept_id IN (SELECT concept_id FROM t2dm_icd)

    /* Fallback: source value looks like ICD code (useful when source_concept_id not populated) */
    OR (
      co.condition_source_value IS NOT NULL
      AND (
           co.condition_source_value LIKE '250.%0'
        OR co.condition_source_value LIKE '250.%2'
        OR co.condition_source_value LIKE 'E11%'
        OR co.condition_source_value LIKE 'E13%'
      )
    )
),
exclusion_dx AS (
  SELECT
    co.person_id,
    MIN(co.condition_start_date) AS first_exclusion_date
  FROM public.condition_occurrence co
  WHERE
    co.condition_source_concept_id IN (
      SELECT concept_id FROM t1dm_icd
      UNION
      SELECT concept_id FROM gestational_dm_icd
      UNION
      SELECT concept_id FROM secondary_dm_icd
    )
    OR (
      co.condition_source_value IS NOT NULL
      AND (
           co.condition_source_value LIKE '250.%1'
        OR co.condition_source_value LIKE '250.%3'
        OR co.condition_source_value LIKE 'E10%'
        OR co.condition_source_value LIKE 'O24.4%'
        OR co.condition_source_value LIKE 'O24.9%'
        OR co.condition_source_value LIKE '648.8%'
        OR co.condition_source_value LIKE '249%'
        OR co.condition_source_value LIKE 'E08%'
        OR co.condition_source_value LIKE 'E09%'
      )
    )
  GROUP BY co.person_id
),
abnl_labs AS (
  SELECT
    m.person_id,
    m.measurement_date AS event_date,
    /* Flag which criterion the lab meets */
    CASE
      WHEN m.measurement_concept_id IN (SELECT concept_id FROM a1c_loinc)
           AND m.value_as_number IS NOT NULL
           AND m.value_as_number >= 6.5
        THEN 'A1C>=6.5'
      WHEN m.measurement_concept_id IN (SELECT concept_id FROM glucose_loinc)
           AND m.value_as_number IS NOT NULL
           /* Pragmatic threshold for diabetes:
              - fasting plasma glucose >= 126 mg/dL
              - random plasma glucose >= 200 mg/dL
             If you can reliably distinguish fasting, split these.
           */
           AND m.value_as_number >= 200
        THEN 'GLU>=200'
      WHEN m.measurement_concept_id IN (SELECT concept_id FROM glucose_loinc)
           AND m.value_as_number IS NOT NULL
           AND m.value_as_number >= 126
        THEN 'GLU>=126'
      ELSE NULL
    END AS lab_flag
  FROM public.measurement m
  WHERE m.measurement_concept_id IN (
    SELECT concept_id FROM a1c_loinc
    UNION
    SELECT concept_id FROM glucose_loinc
  )
),
abnl_labs_filtered AS (
  SELECT person_id, event_date
  FROM abnl_labs
  WHERE lab_flag IS NOT NULL
),
antidiabetic_meds AS (
  SELECT
    de.person_id,
    de.drug_exposure_start_date AS event_date
  FROM public.drug_exposure de
  WHERE de.drug_concept_id IN (SELECT concept_id FROM antidiabetic_drug_concepts)
),

/* -----------------------------
5) Person-level rollups for criteria A/B/C/D
------------------------------*/
rollup AS (
  SELECT
    p.person_id,

    /* A: distinct dates of T2DM dx */
    (SELECT COUNT(DISTINCT d.event_date) FROM t2dx d WHERE d.person_id = p.person_id) AS t2dx_date_count,
    (SELECT MIN(d.event_date) FROM t2dx d WHERE d.person_id = p.person_id) AS first_t2dx_date,

    /* C: distinct dates of abnormal labs */
    (SELECT COUNT(DISTINCT l.event_date) FROM abnl_labs_filtered l WHERE l.person_id = p.person_id) AS abnl_lab_date_count,
    (SELECT MIN(l.event_date) FROM abnl_labs_filtered l WHERE l.person_id = p.person_id) AS first_abnl_lab_date,

    /* Med evidence */
    (SELECT COUNT(*) FROM antidiabetic_meds m WHERE m.person_id = p.person_id) AS antidiabetic_med_count,
    (SELECT MIN(m.event_date) FROM antidiabetic_meds m WHERE m.person_id = p.person_id) AS first_antidiabetic_med_date,

    /* Exclusions */
    (SELECT e.first_exclusion_date FROM exclusion_dx e WHERE e.person_id = p.person_id) AS first_exclusion_date
  FROM public.person p
),

/* -----------------------------
6) Final classification + index date
------------------------------*/
t2dm_cases AS (
  SELECT
    r.person_id,

    /* Index date: earliest evidence among the criteria that made them a case */
    LEAST(
      COALESCE(r.first_t2dx_date, DATE '9999-12-31'),
      COALESCE(r.first_abnl_lab_date, DATE '9999-12-31'),
      COALESCE(r.first_antidiabetic_med_date, DATE '9999-12-31')
    ) AS index_date

  FROM rollup r
  WHERE
    /* EXCLUSIONS */
    r.first_exclusion_date IS NULL

    AND
    (
      /* A: ≥2 T2DM dx dates */
      (r.t2dx_date_count >= 2)

      OR
      /* B: ≥1 T2DM dx + ≥1 antidiabetic med */
      (r.t2dx_date_count >= 1 AND r.antidiabetic_med_count >= 1)

      OR
      /* C: ≥2 abnormal lab dates */
      (r.abnl_lab_date_count >= 2)

      OR
      /* D: ≥1 abnormal lab + ≥1 antidiabetic med */
      (r.abnl_lab_date_count >= 1 AND r.antidiabetic_med_count >= 1)
    )
)

SELECT
  c.person_id,
  c.index_date
FROM t2dm_cases c
ORDER BY c.person_id;

