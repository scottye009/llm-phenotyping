/* ============================================================================
Type 2 Diabetes (T2DM) Phenotype (OMOP CDM v5.4, PostgreSQL, schema: public)

STEP 1) Build concept sets
  - Diagnoses: ICD9CM/ICD10CM for T2DM (include) and T1DM/gestational/secondary (exclude)
  - Drugs: RxNorm ingredients (include descendants to capture brands & generics)
  - Labs: LOINC for HbA1c and glucose

STEP 2) Create evidence tables (dx, drugs, labs) at person-date level

STEP 3) Case rules (combine with AND/OR/NOT) + exclusions
  CASE if:
    (A) >= 2 T2DM diagnosis dates
    OR
    (B) 1 T2DM diagnosis date AND >= 1 antidiabetic (non-insulin) exposure
    OR
    (C) >= 2 abnormal diabetes labs on different dates
    OR
    (D) 1 abnormal lab date AND 1 T2DM diagnosis date
  AND NOT (any T1DM dx OR gestational dx OR secondary/other diabetes dx)

NOTES:
  - ICD9 T2DM: 250.xx where last digit in (0,2)
  - ICD9 T1DM: 250.xx where last digit in (1,3)
  - ICD10 T2DM: E11.*
  - ICD10 T1DM: E10.*
  - ICD10 gestational: O24.4*
  - ICD10 secondary/other: E08.*, E09.*, E13.*
  - ICD9 gestational: 648.8*
  - ICD9 secondary: 249.*
  - Labs use value_as_number thresholds (units not harmonized here).
============================================================================ */

/* -----------------------------
1) CONCEPT SETS
------------------------------*/
WITH
/* --- Diagnosis concepts (ICD9CM / ICD10CM) --- */
t2dm_dx_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE
    (
      /* ICD10CM: E11.* (Type 2 diabetes mellitus) */
      (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E11%')
      OR
      /* ICD9CM: 250.xx with last digit 0 or 2 (Type II or unspecified type, not stated as uncontrolled/controlled variants) */
      (c.vocabulary_id = 'ICD9CM' AND c.concept_code LIKE '250.%' AND RIGHT(c.concept_code, 1) IN ('0','2'))
    )
),

t1dm_dx_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE
    (
      /* ICD10CM: E10.* (Type 1 diabetes mellitus) */
      (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E10%')
      OR
      /* ICD9CM: 250.xx with last digit 1 or 3 */
      (c.vocabulary_id = 'ICD9CM' AND c.concept_code LIKE '250.%' AND RIGHT(c.concept_code, 1) IN ('1','3'))
    )
),

gestational_dx_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE
    (
      /* ICD10CM: O24.4* (Gestational diabetes) */
      (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'O24.4%')
      OR
      /* ICD9CM: 648.8* (Abnormal glucose tolerance / gestational diabetes) */
      (c.vocabulary_id = 'ICD9CM' AND c.concept_code LIKE '648.8%')
    )
),

secondary_other_dm_dx_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE
    (
      /* ICD10CM: diabetes due to underlying condition / drug-induced / other specified */
      (c.vocabulary_id = 'ICD10CM' AND (c.concept_code LIKE 'E08%' OR c.concept_code LIKE 'E09%' OR c.concept_code LIKE 'E13%'))
      OR
      /* ICD9CM: secondary diabetes mellitus */
      (c.vocabulary_id = 'ICD9CM' AND c.concept_code LIKE '249%')
    )
),

/* --- Drug ingredients (RxNorm) ---
   We match ingredient names to avoid needing hard-coded concept_ids.
   Then use concept_ancestor to include all descendant clinical drugs/brands. */
non_insulin_antidiabetic_ingredients AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id = 'RxNorm'
    AND c.concept_class_id = 'Ingredient'
    AND (
      /* Biguanide */
      c.concept_name ILIKE 'metformin%'

      /* Sulfonylureas (generic + commonly known brands covered via descendants) */
      OR c.concept_name ILIKE 'glipizide%'
      OR c.concept_name ILIKE 'glyburide%'
      OR c.concept_name ILIKE 'glimepiride%'
      OR c.concept_name ILIKE 'chlorpropamide%'
      OR c.concept_name ILIKE 'tolbutamide%'
      OR c.concept_name ILIKE 'tolazamide%'

      /* Thiazolidinediones */
      OR c.concept_name ILIKE 'pioglitazone%'
      OR c.concept_name ILIKE 'rosiglitazone%'

      /* DPP-4 inhibitors */
      OR c.concept_name ILIKE 'sitagliptin%'
      OR c.concept_name ILIKE 'linagliptin%'
      OR c.concept_name ILIKE 'saxagliptin%'
      OR c.concept_name ILIKE 'alogliptin%'

      /* GLP-1 receptor agonists */
      OR c.concept_name ILIKE 'exenatide%'
      OR c.concept_name ILIKE 'liraglutide%'
      OR c.concept_name ILIKE 'dulaglutide%'
      OR c.concept_name ILIKE 'semaglutide%'
      OR c.concept_name ILIKE 'lixisenatide%'

      /* SGLT2 inhibitors */
      OR c.concept_name ILIKE 'canagliflozin%'
      OR c.concept_name ILIKE 'dapagliflozin%'
      OR c.concept_name ILIKE 'empagliflozin%'
      OR c.concept_name ILIKE 'ertugliflozin%'

      /* Meglitinides */
      OR c.concept_name ILIKE 'repaglinide%'
      OR c.concept_name ILIKE 'nateglinide%'

      /* Alpha-glucosidase inhibitors */
      OR c.concept_name ILIKE 'acarbose%'
      OR c.concept_name ILIKE 'miglitol%'

      /* Amylin analog */
      OR c.concept_name ILIKE 'pramlintide%'

      /* Common fixed-dose combos (ingredients) */
      OR c.concept_name ILIKE 'metformin / sitagliptin%'
      OR c.concept_name ILIKE 'metformin / linagliptin%'
      OR c.concept_name ILIKE 'metformin / saxagliptin%'
      OR c.concept_name ILIKE 'metformin / alogliptin%'
      OR c.concept_name ILIKE 'metformin / canagliflozin%'
      OR c.concept_name ILIKE 'metformin / dapagliflozin%'
      OR c.concept_name ILIKE 'metformin / empagliflozin%'
    )
),

/* Descendants capture both generics and brands (e.g., Glucophage, Januvia, Victoza, Ozempic, Jardiance, etc.) */
non_insulin_antidiabetic_drug_concepts AS (
  SELECT DISTINCT ca.descendant_concept_id AS concept_id
  FROM public.concept_ancestor ca
  JOIN non_insulin_antidiabetic_ingredients i
    ON i.concept_id = ca.ancestor_concept_id
),

/* Insulin ingredients (for exclusion logic if you want to detect “insulin-only” patterns) */
insulin_ingredients AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id = 'RxNorm'
    AND c.concept_class_id = 'Ingredient'
    AND (
      c.concept_name ILIKE 'insulin%'
      OR c.concept_name ILIKE 'insulin glargine%'
      OR c.concept_name ILIKE 'insulin lispro%'
      OR c.concept_name ILIKE 'insulin aspart%'
      OR c.concept_name ILIKE 'insulin detemir%'
      OR c.concept_name ILIKE 'insulin degludec%'
      OR c.concept_name ILIKE 'regular insulin%'
      OR c.concept_name ILIKE 'NPH insulin%'
    )
),
insulin_drug_concepts AS (
  SELECT DISTINCT ca.descendant_concept_id AS concept_id
  FROM public.concept_ancestor ca
  JOIN insulin_ingredients i
    ON i.concept_id = ca.ancestor_concept_id
),

/* --- Lab test concepts (LOINC) --- */
a1c_lab_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id = 'LOINC'
    AND c.concept_code IN (
      /* HbA1c */
      '4548-4',  /* Hemoglobin A1c/Hemoglobin.total in Blood */
      '17856-6', /* Hemoglobin A1c/Hemoglobin.total in Blood by HPLC */
      '41995-2'  /* Hemoglobin A1c/Hemoglobin.total in Blood (alternate) */
    )
),
glucose_lab_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id = 'LOINC'
    AND c.concept_code IN (
      /* Plasma/serum glucose (fasting/random often not perfectly encoded) */
      '2345-7',  /* Glucose [Mass/volume] in Serum or Plasma */
      '1558-6',  /* Glucose [Mass/volume] in Serum or Plasma -- fasting */
      '14749-6'  /* Glucose [Mass/volume] in Blood */
    )
),

/* -----------------------------
2) EVIDENCE (person-date level)
------------------------------*/
t2dm_dx_dates AS (
  SELECT
    co.person_id,
    co.condition_start_date::date AS evidence_date
  FROM public.condition_occurrence co
  JOIN t2dm_dx_concepts dx
    ON dx.concept_id = co.condition_source_concept_id
  WHERE co.condition_start_date IS NOT NULL
),

exclusion_dx_people AS (
  SELECT DISTINCT person_id
  FROM (
    SELECT co.person_id
    FROM public.condition_occurrence co
    JOIN t1dm_dx_concepts x ON x.concept_id = co.condition_source_concept_id

    UNION
    SELECT co.person_id
    FROM public.condition_occurrence co
    JOIN gestational_dx_concepts x ON x.concept_id = co.condition_source_concept_id

    UNION
    SELECT co.person_id
    FROM public.condition_occurrence co
    JOIN secondary_other_dm_dx_concepts x ON x.concept_id = co.condition_source_concept_id
  ) z
),

non_insulin_drug_dates AS (
  SELECT
    de.person_id,
    de.drug_exposure_start_date::date AS evidence_date
  FROM public.drug_exposure de
  JOIN non_insulin_antidiabetic_drug_concepts d
    ON d.concept_id = de.drug_concept_id
  WHERE de.drug_exposure_start_date IS NOT NULL
),

/* Abnormal labs:
   - A1c >= 6.5 (%)
   - Glucose >= 126 (mg/dL) as fasting proxy (if fasting LOINC present, great)
   - Glucose >= 200 (mg/dL) as random/diagnostic proxy
   NOTE: Units not enforced here; if your data mixes mmol/L, add unit filtering via unit_concept_id. */
abnormal_lab_dates AS (
  SELECT
    m.person_id,
    m.measurement_date::date AS evidence_date
  FROM public.measurement m
  WHERE m.measurement_date IS NOT NULL
    AND m.value_as_number IS NOT NULL
    AND (
      (m.measurement_concept_id IN (SELECT concept_id FROM a1c_lab_concepts) AND m.value_as_number >= 6.5)
      OR
      (m.measurement_concept_id IN (SELECT concept_id FROM glucose_lab_concepts) AND m.value_as_number >= 200)
      OR
      (m.measurement_concept_id IN (SELECT concept_id FROM glucose_lab_concepts) AND m.value_as_number >= 126)
    )
),

/* -----------------------------
3) AGGREGATE & APPLY RULES
------------------------------*/
dx_agg AS (
  SELECT
    person_id,
    COUNT(DISTINCT evidence_date) AS t2dm_dx_date_count,
    MIN(evidence_date) AS first_t2dm_dx_date
  FROM t2dm_dx_dates
  GROUP BY person_id
),
drug_agg AS (
  SELECT
    person_id,
    COUNT(DISTINCT evidence_date) AS non_insulin_drug_date_count,
    MIN(evidence_date) AS first_non_insulin_drug_date
  FROM non_insulin_drug_dates
  GROUP BY person_id
),
lab_agg AS (
  SELECT
    person_id,
    COUNT(DISTINCT evidence_date) AS abnormal_lab_date_count,
    MIN(evidence_date) AS first_abnormal_lab_date
  FROM abnormal_lab_dates
  GROUP BY person_id
),

/* Determine index date as earliest evidence among qualifying criteria */
case_candidates AS (
  SELECT
    p.person_id,

    /* Evidence counts */
    COALESCE(dxa.t2dm_dx_date_count, 0) AS t2dm_dx_date_count,
    COALESCE(dra.non_insulin_drug_date_count, 0) AS non_insulin_drug_date_count,
    COALESCE(la.abnormal_lab_date_count, 0) AS abnormal_lab_date_count,

    /* Candidate dates */
    dxa.first_t2dm_dx_date,
    dra.first_non_insulin_drug_date,
    la.first_abnormal_lab_date

  FROM public.person p
  LEFT JOIN dx_agg dxa ON dxa.person_id = p.person_id
  LEFT JOIN drug_agg dra ON dra.person_id = p.person_id
  LEFT JOIN lab_agg la ON la.person_id = p.person_id
)

SELECT
  c.person_id,

  /* Index date: earliest of the first qualifying evidence dates */
  LEAST(
    COALESCE(c.first_t2dm_dx_date, DATE '9999-12-31'),
    COALESCE(c.first_non_insulin_drug_date, DATE '9999-12-31'),
    COALESCE(c.first_abnormal_lab_date, DATE '9999-12-31')
  ) AS index_date

FROM case_candidates c
LEFT JOIN exclusion_dx_people x
  ON x.person_id = c.person_id

WHERE
  /* -----------------------------
     FINAL PHENOTYPE LOGIC (AND/OR/NOT)
     ------------------------------*/

  /* EXCLUSIONS */
  x.person_id IS NULL

  AND
  (
    /* (A) >= 2 T2DM diagnosis dates */
    (c.t2dm_dx_date_count >= 2)

    OR

    /* (B) 1 T2DM dx date AND >= 1 non-insulin antidiabetic drug date */
    (c.t2dm_dx_date_count >= 1 AND c.non_insulin_drug_date_count >= 1)

    OR

    /* (C) >= 2 abnormal lab dates */
    (c.abnormal_lab_date_count >= 2)

    OR

    /* (D) 1 abnormal lab date AND 1 T2DM dx date */
    (c.abnormal_lab_date_count >= 1 AND c.t2dm_dx_date_count >= 1)
  )
;

