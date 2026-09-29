/* ============================================================
Type 2 Diabetes Mellitus (T2DM) Phenotyping Algorithm (OMOP CDM v5.4)
- PostgreSQL (pgAdmin), schema = public
- Uses ICD9CM + ICD10CM for diagnoses (condition_occurrence)
- Uses RxNorm/RxNorm Extension for meds (drug_exposure) via name-based concept lookup
- Uses LOINC for labs (measurement)

OUTPUT:
- One row per person classified as T2DM case
- index_date = earliest qualifying evidence date among the rules

NOTES:
- Adjust concept lists (ICD codes, LOINC codes, drug names) to your local vocabulary coverage.
============================================================ */

WITH
/* -----------------------------
1) DIAGNOSIS CONCEPT SETS (ICD9CM / ICD10CM)
------------------------------*/
dx_t2 AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
    AND c.invalid_reason IS NULL
    AND (
      /* ICD-10-CM: Type 2 diabetes mellitus */
      c.concept_code LIKE 'E11%'

      /* ICD-9-CM: 250.x0 or 250.x2 (type 2 / unspecified, not stated as uncontrolled / uncontrolled)
         Use last digit rule: 0 or 2 => type 2 (classic ICD-9 DM 5th digit semantics) */
      OR (
        c.vocabulary_id = 'ICD9CM'
        AND c.concept_code LIKE '250%'
        AND RIGHT(REPLACE(c.concept_code,'.',''), 1) IN ('0','2')
      )
    )
),
dx_t1 AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
    AND c.invalid_reason IS NULL
    AND (
      /* ICD-10-CM: Type 1 diabetes mellitus */
      c.concept_code LIKE 'E10%'

      /* ICD-9-CM: 250.x1 or 250.x3 => type 1 */
      OR (
        c.vocabulary_id = 'ICD9CM'
        AND c.concept_code LIKE '250%'
        AND RIGHT(REPLACE(c.concept_code,'.',''), 1) IN ('1','3')
      )
    )
),
dx_gestational AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
    AND c.invalid_reason IS NULL
    AND (
      /* ICD-10-CM: Gestational diabetes mellitus */
      c.concept_code LIKE 'O24.4%'

      /* ICD-9-CM: Gestational diabetes */
      OR c.concept_code LIKE '648.8%'
    )
),
dx_secondary AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
    AND c.invalid_reason IS NULL
    AND (
      /* ICD-10-CM: Diabetes due to underlying condition / drug or chemical induced */
      c.concept_code LIKE 'E08%'
      OR c.concept_code LIKE 'E09%'

      /* ICD-9-CM: Secondary diabetes mellitus */
      OR c.concept_code LIKE '249%'
    )
),

/* -----------------------------
2) LAB CONCEPT SETS (LOINC)
   - HbA1c >= 6.5 %
   - Glucose (fasting/plasma) >= 126 mg/dL
   - Random glucose >= 200 mg/dL (we use generic glucose LOINCs as proxy)
------------------------------*/
loinc_a1c AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id = 'LOINC'
    AND c.invalid_reason IS NULL
    AND c.concept_code IN (
      /* Common HbA1c LOINCs */
      '4548-4',   -- Hemoglobin A1c/Hemoglobin.total in Blood
      '17856-6',  -- HbA1c/Hb.total in Blood by HPLC
      '41995-2',  -- HbA1c in Blood
      '59261-8'   -- HbA1c in Blood by IFCC
    )
),
loinc_glucose AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id = 'LOINC'
    AND c.invalid_reason IS NULL
    AND c.concept_code IN (
      /* Common glucose LOINCs (plasma/serum; fasting or unspecified) */
      '2345-7',  -- Glucose [Mass/volume] in Serum or Plasma
      '1558-6',  -- Glucose [Mass/volume] in Serum or Plasma -- fasting
      '14743-9', -- Glucose [Moles/volume] in Serum or Plasma
      '2339-0'   -- Glucose [Mass/volume] in Blood
    )
),
unit_mgdl AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id IN ('UCUM','OMOP')
    AND invalid_reason IS NULL
    AND concept_code IN ('mg/dL')  -- UCUM
),
unit_percent AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id IN ('UCUM','OMOP')
    AND invalid_reason IS NULL
    AND concept_code IN ('%')      -- UCUM
),

/* -----------------------------
3) MEDICATION CONCEPT SETS (RxNorm / RxNorm Extension)
   Use BOTH generic and brand names (name-based match).
   - Antidiabetic agents (non-insulin + insulin)
------------------------------*/
drug_antidiabetic AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('RxNorm','RxNorm Extension')
    AND c.invalid_reason IS NULL
    AND (
      /* Biguanide */
      c.concept_name ILIKE '%metformin%' OR c.concept_name ILIKE '%glucophage%'

      /* Sulfonylureas */
      OR c.concept_name ILIKE '%glipizide%'   OR c.concept_name ILIKE '%glucotrol%'
      OR c.concept_name ILIKE '%glyburide%'   OR c.concept_name ILIKE '%diabeta%' OR c.concept_name ILIKE '%micronase%'
      OR c.concept_name ILIKE '%glimepiride%' OR c.concept_name ILIKE '%amaryl%'

      /* TZDs */
      OR c.concept_name ILIKE '%pioglitazone%' OR c.concept_name ILIKE '%actos%'
      OR c.concept_name ILIKE '%rosiglitazone%' OR c.concept_name ILIKE '%avandia%'

      /* DPP-4 inhibitors */
      OR c.concept_name ILIKE '%sitagliptin%' OR c.concept_name ILIKE '%januvia%'
      OR c.concept_name ILIKE '%linagliptin%' OR c.concept_name ILIKE '%tradjenta%'
      OR c.concept_name ILIKE '%saxagliptin%' OR c.concept_name ILIKE '%onglyza%'
      OR c.concept_name ILIKE '%alogliptin%'  OR c.concept_name ILIKE '%nesina%'

      /* GLP-1 receptor agonists */
      OR c.concept_name ILIKE '%liraglutide%' OR c.concept_name ILIKE '%victoza%'
      OR c.concept_name ILIKE '%semaglutide%' OR c.concept_name ILIKE '%ozempic%' OR c.concept_name ILIKE '%rybelsus%'
      OR c.concept_name ILIKE '%dulaglutide%' OR c.concept_name ILIKE '%trulicity%'
      OR c.concept_name ILIKE '%exenatide%'   OR c.concept_name ILIKE '%byetta%' OR c.concept_name ILIKE '%bydureon%'

      /* SGLT2 inhibitors */
      OR c.concept_name ILIKE '%canagliflozin%' OR c.concept_name ILIKE '%invokana%'
      OR c.concept_name ILIKE '%dapagliflozin%' OR c.concept_name ILIKE '%farxiga%'
      OR c.concept_name ILIKE '%empagliflozin%' OR c.concept_name ILIKE '%jardiance%'
      OR c.concept_name ILIKE '%ertugliflozin%' OR c.concept_name ILIKE '%steglatro%'

      /* Meglitinides */
      OR c.concept_name ILIKE '%repaglinide%' OR c.concept_name ILIKE '%prandin%'
      OR c.concept_name ILIKE '%nateglinide%' OR c.concept_name ILIKE '%starlix%'

      /* Alpha-glucosidase inhibitors */
      OR c.concept_name ILIKE '%acarbose%' OR c.concept_name ILIKE '%precose%'
      OR c.concept_name ILIKE '%miglitol%' OR c.concept_name ILIKE '%glyset%'

      /* Insulins (include common brands/generics) */
      OR c.concept_name ILIKE '%insulin%'
      OR c.concept_name ILIKE '%humalog%' OR c.concept_name ILIKE '%novolog%' OR c.concept_name ILIKE '%apidra%'
      OR c.concept_name ILIKE '%lantus%'  OR c.concept_name ILIKE '%levemir%' OR c.concept_name ILIKE '%tresiba%'
      OR c.concept_name ILIKE '%basaglar%' OR c.concept_name ILIKE '%toujeo%'
    )
),

/* -----------------------------
4) EVIDENCE TABLES (person-level)
------------------------------*/
t2_dx_events AS (
  /* All T2DM diagnosis events */
  SELECT co.person_id,
         co.condition_start_date AS event_date
  FROM public.condition_occurrence co
  JOIN dx_t2 d ON d.concept_id = co.condition_source_concept_id
),
t1_dx_any AS (
  /* Any Type 1 diagnosis ever */
  SELECT DISTINCT co.person_id
  FROM public.condition_occurrence co
  JOIN dx_t1 d ON d.concept_id = co.condition_source_concept_id
),
gest_dx_any AS (
  /* Any gestational diabetes diagnosis ever */
  SELECT DISTINCT co.person_id
  FROM public.condition_occurrence co
  JOIN dx_gestational d ON d.concept_id = co.condition_source_concept_id
),
secondary_dx_any AS (
  /* Any secondary diabetes diagnosis ever */
  SELECT DISTINCT co.person_id
  FROM public.condition_occurrence co
  JOIN dx_secondary d ON d.concept_id = co.condition_source_concept_id
),
t2_dx_distinct_dates AS (
  /* Count distinct T2DM dx dates; used for ">=2 on different dates" */
  SELECT person_id,
         COUNT(DISTINCT event_date) AS t2_dx_date_cnt,
         MIN(event_date) AS first_t2_dx_date
  FROM t2_dx_events
  GROUP BY person_id
),

drug_events AS (
  /* Any antidiabetic drug exposure */
  SELECT de.person_id,
         de.drug_exposure_start_date AS event_date
  FROM public.drug_exposure de
  JOIN drug_antidiabetic d ON d.concept_id = de.drug_concept_id
),
drug_any AS (
  SELECT person_id,
         MIN(event_date) AS first_drug_date
  FROM drug_events
  GROUP BY person_id
),

a1c_abnormal AS (
  /* HbA1c >= 6.5 % */
  SELECT m.person_id,
         m.measurement_date AS event_date
  FROM public.measurement m
  JOIN loinc_a1c a ON a.concept_id = m.measurement_concept_id
  WHERE m.value_as_number IS NOT NULL
    AND m.value_as_number >= 6.5
    AND (
      m.unit_concept_id IS NULL
      OR m.unit_concept_id IN (SELECT concept_id FROM unit_percent)
    )
),
glucose_abnormal AS (
  /* Glucose >= 126 mg/dL (fasting/unspecified LOINCs used as proxy) */
  SELECT m.person_id,
         m.measurement_date AS event_date
  FROM public.measurement m
  JOIN loinc_glucose g ON g.concept_id = m.measurement_concept_id
  WHERE m.value_as_number IS NOT NULL
    AND m.value_as_number >= 126
    AND (
      m.unit_concept_id IS NULL
      OR m.unit_concept_id IN (SELECT concept_id FROM unit_mgdl)
    )
),
abnl_lab_events AS (
  /* Combine abnormal lab events */
  SELECT person_id, event_date FROM a1c_abnormal
  UNION ALL
  SELECT person_id, event_date FROM glucose_abnormal
),
abnl_lab_distinct_dates AS (
  /* Count distinct abnormal lab dates */
  SELECT person_id,
         COUNT(DISTINCT event_date) AS abnl_lab_date_cnt,
         MIN(event_date) AS first_abnl_lab_date
  FROM abnl_lab_events
  GROUP BY person_id
),

/* -----------------------------
5) RULES (combine criteria with AND / OR / NOT)
   CASE definition (OR across rules):
   Rule A: >= 2 distinct T2 dx dates
   Rule B: >= 1 T2 dx AND >= 1 antidiabetic drug
   Rule C: >= 2 distinct abnormal lab dates
   Rule D: >= 1 abnormal lab AND >= 1 T2 dx

   Exclusions (NOT):
   - Type 1 ONLY: any T1 dx AND no T2 dx  (keeps mixed/possible miscoding)
   - Gestational ONLY: any gestational dx AND no T2 dx
   - Secondary ONLY: any secondary dx AND no T2 dx
------------------------------*/
eligible_cases AS (
  SELECT
    p.person_id,

    /* earliest date among qualifying rule evidence used as index_date */
    LEAST(
      /* Rule A index: first T2 dx */
      CASE WHEN d.t2_dx_date_cnt >= 2 THEN d.first_t2_dx_date END,

      /* Rule B index: earliest of first T2 dx or first drug (often prefer dx date; we take earliest evidence) */
      CASE WHEN d.t2_dx_date_cnt >= 1 AND da.first_drug_date IS NOT NULL
           THEN LEAST(d.first_t2_dx_date, da.first_drug_date) END,

      /* Rule C index: first abnormal lab */
      CASE WHEN l.abnl_lab_date_cnt >= 2 THEN l.first_abnl_lab_date END,

      /* Rule D index: earliest of first lab or first dx */
      CASE WHEN l.abnl_lab_date_cnt >= 1 AND d.t2_dx_date_cnt >= 1
           THEN LEAST(l.first_abnl_lab_date, d.first_t2_dx_date) END
    ) AS index_date

  FROM public.person p
  LEFT JOIN t2_dx_distinct_dates d ON d.person_id = p.person_id
  LEFT JOIN drug_any da            ON da.person_id = p.person_id
  LEFT JOIN abnl_lab_distinct_dates l ON l.person_id = p.person_id

  WHERE
    /* ------------------ INCLUSION: Rule A OR Rule B OR Rule C OR Rule D ------------------ */
    (
      (d.t2_dx_date_cnt >= 2)
      OR (d.t2_dx_date_cnt >= 1 AND da.first_drug_date IS NOT NULL)
      OR (l.abnl_lab_date_cnt >= 2)
      OR (l.abnl_lab_date_cnt >= 1 AND d.t2_dx_date_cnt >= 1)
    )

    /* ------------------ EXCLUSIONS: NOT(Type1-only) AND NOT(Gestational-only) AND NOT(Secondary-only) ------------------ */
    AND NOT (
      /* Type 1 present AND no evidence of T2 at all */
      p.person_id IN (SELECT person_id FROM t1_dx_any)
      AND COALESCE(d.t2_dx_date_cnt, 0) = 0
    )
    AND NOT (
      /* Gestational present AND no evidence of T2 at all */
      p.person_id IN (SELECT person_id FROM gest_dx_any)
      AND COALESCE(d.t2_dx_date_cnt, 0) = 0
    )
    AND NOT (
      /* Secondary present AND no evidence of T2 at all */
      p.person_id IN (SELECT person_id FROM secondary_dx_any)
      AND COALESCE(d.t2_dx_date_cnt, 0) = 0
    )
)

SELECT
  person_id,
  index_date
FROM eligible_cases
WHERE index_date IS NOT NULL
ORDER BY person_id;

