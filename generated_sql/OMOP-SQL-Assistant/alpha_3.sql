/* =====================================================================
Type 2 Diabetes (T2D) Phenotype — OMOP CDM v5.4 (PostgreSQL)
Schema: public
Output: person_id + index_date (earliest qualifying evidence date)

High-level definition:
  CASE if (
      A) >=2 T2D diagnoses on distinct dates
   OR B) 1 T2D diagnosis AND >=1 non-insulin antihyperglycemic drug exposure
   OR C) >=2 abnormal diabetes labs on distinct dates
   OR D) 1 abnormal diabetes lab AND >=1 non-insulin antihyperglycemic drug exposure
  )
  AND NOT (gestational diabetes)
  AND NOT (Type 1 diabetes without any T2D diagnosis)
  AND NOT (secondary/other diabetes codes if you choose to exclude them; left as optional)
===================================================================== */

WITH
/* -----------------------------
1) DIAGNOSIS CONCEPT SETS (ICD9CM/ICD10CM)
----------------------------- */
t2_dx_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
      /* ICD-10-CM: E11.* (Type 2 diabetes mellitus) */
      (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E11%')

      /* ICD-9-CM: 250.x0 or 250.x2 (Type II or unspecified type, not stated as uncontrolled / uncontrolled) */
      OR (c.vocabulary_id = 'ICD9CM' AND c.concept_code LIKE '250%0')
      OR (c.vocabulary_id = 'ICD9CM' AND c.concept_code LIKE '250%2')
    )
),
t1_dx_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
      /* ICD-10-CM: E10.* (Type 1 diabetes mellitus) */
      (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E10%')

      /* ICD-9-CM: 250.x1 or 250.x3 (Type I) */
      OR (c.vocabulary_id = 'ICD9CM' AND c.concept_code LIKE '250%1')
      OR (c.vocabulary_id = 'ICD9CM' AND c.concept_code LIKE '250%3')
    )
),
gestational_dx_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
      /* ICD-10-CM: O24.* (Diabetes mellitus in pregnancy); includes gestational and pre-existing */
      (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'O24%')

      /* ICD-9-CM: 648.8* (Abnormal glucose tolerance / gestational diabetes) */
      OR (c.vocabulary_id = 'ICD9CM' AND c.concept_code LIKE '6488%')
    )
),

/* OPTIONAL: if you want to exclude “secondary diabetes” (E08/E09) or “other specified” (E13)
secondary_other_dx_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id='ICD10CM'
    AND (c.concept_code LIKE 'E08%' OR c.concept_code LIKE 'E09%' OR c.concept_code LIKE 'E13%')
),
*/

/* -----------------------------
2) MEDICATION CONCEPT SETS (RxNorm) — include generic + brand
   We build ingredient/brand seed sets, then expand to descendants via concept_ancestor
----------------------------- */

/* Non-insulin antihyperglycemics: common classes (add more as needed) */
noninsulin_seed_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id = 'RxNorm'
    AND c.invalid_reason IS NULL
    AND (
      /* --- Biguanide --- */
      c.concept_name ILIKE 'metformin%' OR c.concept_name ILIKE 'Glucophage%'

      /* --- Sulfonylureas --- */
      OR c.concept_name ILIKE 'glipizide%' OR c.concept_name ILIKE 'Glucotrol%'
      OR c.concept_name ILIKE 'glyburide%' OR c.concept_name ILIKE 'Diabeta%'
      OR c.concept_name ILIKE 'glimepiride%' OR c.concept_name ILIKE 'Amaryl%'

      /* --- DPP-4 inhibitors --- */
      OR c.concept_name ILIKE 'sitagliptin%' OR c.concept_name ILIKE 'Januvia%'
      OR c.concept_name ILIKE 'linagliptin%' OR c.concept_name ILIKE 'Tradjenta%'
      OR c.concept_name ILIKE 'saxagliptin%' OR c.concept_name ILIKE 'Onglyza%'
      OR c.concept_name ILIKE 'alogliptin%' OR c.concept_name ILIKE 'Nesina%'

      /* --- GLP-1 receptor agonists --- */
      OR c.concept_name ILIKE 'liraglutide%' OR c.concept_name ILIKE 'Victoza%'
      OR c.concept_name ILIKE 'semaglutide%' OR c.concept_name ILIKE 'Ozempic%'
      OR c.concept_name ILIKE 'dulaglutide%' OR c.concept_name ILIKE 'Trulicity%'
      OR c.concept_name ILIKE 'exenatide%' OR c.concept_name ILIKE 'Byetta%'
      OR c.concept_name ILIKE 'Bydureon%'

      /* --- SGLT2 inhibitors --- */
      OR c.concept_name ILIKE 'empagliflozin%' OR c.concept_name ILIKE 'Jardiance%'
      OR c.concept_name ILIKE 'canagliflozin%' OR c.concept_name ILIKE 'Invokana%'
      OR c.concept_name ILIKE 'dapagliflozin%' OR c.concept_name ILIKE 'Farxiga%'
      OR c.concept_name ILIKE 'ertugliflozin%' OR c.concept_name ILIKE 'Steglatro%'

      /* --- Thiazolidinediones --- */
      OR c.concept_name ILIKE 'pioglitazone%' OR c.concept_name ILIKE 'Actos%'
      OR c.concept_name ILIKE 'rosiglitazone%' OR c.concept_name ILIKE 'Avandia%'

      /* --- Meglitinides --- */
      OR c.concept_name ILIKE 'repaglinide%' OR c.concept_name ILIKE 'Prandin%'
      OR c.concept_name ILIKE 'nateglinide%' OR c.concept_name ILIKE 'Starlix%'

      /* --- Alpha-glucosidase inhibitors --- */
      OR c.concept_name ILIKE 'acarbose%' OR c.concept_name ILIKE 'Precose%'
      OR c.concept_name ILIKE 'miglitol%' OR c.concept_name ILIKE 'Glyset%'
    )
),
noninsulin_descendant_concepts AS (
  /* Expand ingredients/brands to all related clinical drugs / branded drugs */
  SELECT DISTINCT ca.descendant_concept_id AS concept_id
  FROM public.concept_ancestor ca
  JOIN noninsulin_seed_concepts s
    ON s.concept_id = ca.ancestor_concept_id
),

/* Insulin (for exclusion logic) */
insulin_seed_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id = 'RxNorm'
    AND c.invalid_reason IS NULL
    AND (
      c.concept_name ILIKE 'insulin%'         /* ingredient strings */
      OR c.concept_name ILIKE 'Humalog%'      /* lispro */
      OR c.concept_name ILIKE 'Novolog%'      /* aspart */
      OR c.concept_name ILIKE 'Apidra%'       /* glulisine */
      OR c.concept_name ILIKE 'Lantus%'       /* glargine */
      OR c.concept_name ILIKE 'Toujeo%'
      OR c.concept_name ILIKE 'Levemir%'      /* detemir */
      OR c.concept_name ILIKE 'Tresiba%'      /* degludec */
      OR c.concept_name ILIKE 'Humulin%'      /* human insulins */
      OR c.concept_name ILIKE 'Novolin%'
    )
),
insulin_descendant_concepts AS (
  SELECT DISTINCT ca.descendant_concept_id AS concept_id
  FROM public.concept_ancestor ca
  JOIN insulin_seed_concepts s
    ON s.concept_id = ca.ancestor_concept_id
),

/* -----------------------------
3) LAB CONCEPT SETS (LOINC) + THRESHOLDS
   Notes:
     - OMOP stores labs in MEASUREMENT.
     - Units can vary; this is a pragmatic phenotype assuming standard units.
----------------------------- */
hba1c_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id = 'LOINC'
    AND c.invalid_reason IS NULL
    AND c.concept_code IN (
      '4548-4',   /* Hemoglobin A1c/Hemoglobin.total in Blood */
      '17856-6'   /* Hemoglobin A1c/Hemoglobin.total in Blood by HPLC (common) */
    )
),
glucose_concepts_any AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id = 'LOINC'
    AND c.invalid_reason IS NULL
    AND c.concept_code IN (
      '2345-7',   /* Glucose [Mass/volume] in Serum or Plasma */
      '2339-0',   /* Glucose [Mass/volume] in Blood */
      '41653-7'   /* Glucose [Mass/volume] in Capillary blood */
    )
),
glucose_concepts_fasting AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id = 'LOINC'
    AND c.invalid_reason IS NULL
    AND c.concept_code IN (
      '1558-6'    /* Glucose [Mass/volume] in Serum or Plasma -- fasting */
    )
),

/* -----------------------------
4) EVIDENCE TABLES
----------------------------- */
t2_dx_events AS (
  SELECT
    co.person_id,
    co.condition_start_date AS event_date
  FROM public.condition_occurrence co
  JOIN t2_dx_concepts dx
    ON dx.concept_id = co.condition_source_concept_id
),
t1_dx_events AS (
  SELECT
    co.person_id,
    co.condition_start_date AS event_date
  FROM public.condition_occurrence co
  JOIN t1_dx_concepts dx
    ON dx.concept_id = co.condition_source_concept_id
),
gestational_dx_events AS (
  SELECT
    co.person_id,
    co.condition_start_date AS event_date
  FROM public.condition_occurrence co
  JOIN gestational_dx_concepts dx
    ON dx.concept_id = co.condition_source_concept_id
),

noninsulin_drug_events AS (
  SELECT
    de.person_id,
    de.drug_exposure_start_date AS event_date
  FROM public.drug_exposure de
  JOIN noninsulin_descendant_concepts nd
    ON nd.concept_id = de.drug_concept_id
  WHERE de.drug_exposure_start_date IS NOT NULL
),
insulin_drug_events AS (
  SELECT
    de.person_id,
    de.drug_exposure_start_date AS event_date
  FROM public.drug_exposure de
  JOIN insulin_descendant_concepts idc
    ON idc.concept_id = de.drug_concept_id
  WHERE de.drug_exposure_start_date IS NOT NULL
),

abnormal_lab_events AS (
  SELECT
    m.person_id,
    m.measurement_date AS event_date
  FROM public.measurement m
  WHERE m.measurement_date IS NOT NULL
    AND m.value_as_number IS NOT NULL
    AND (
      /* A1c >= 6.5% */
      (m.measurement_concept_id IN (SELECT concept_id FROM hba1c_concepts)
       AND m.value_as_number >= 6.5)

      /* Fasting glucose >= 126 mg/dL */
      OR (m.measurement_concept_id IN (SELECT concept_id FROM glucose_concepts_fasting)
          AND m.value_as_number >= 126)

      /* Random/any glucose >= 200 mg/dL (pragmatic) */
      OR (m.measurement_concept_id IN (SELECT concept_id FROM glucose_concepts_any)
          AND m.value_as_number >= 200)
    )
),

/* -----------------------------
5) CRITERIA COUNTS (distinct dates)
----------------------------- */
t2_dx_2dates AS (
  SELECT person_id, MIN(event_date) AS first_t2_dx_date
  FROM t2_dx_events
  GROUP BY person_id
  HAVING COUNT(DISTINCT event_date) >= 2
),
abnl_lab_2dates AS (
  SELECT person_id, MIN(event_date) AS first_abnl_lab_date
  FROM abnormal_lab_events
  GROUP BY person_id
  HAVING COUNT(DISTINCT event_date) >= 2
),

t2_dx_1plus_med AS (
  SELECT
    d.person_id,
    MIN(LEAST(d.event_date, m.event_date)) AS first_support_date
  FROM t2_dx_events d
  JOIN noninsulin_drug_events m
    ON m.person_id = d.person_id
  GROUP BY d.person_id
),
lab_1plus_med AS (
  SELECT
    l.person_id,
    MIN(LEAST(l.event_date, m.event_date)) AS first_support_date
  FROM abnormal_lab_events l
  JOIN noninsulin_drug_events m
    ON m.person_id = l.person_id
  GROUP BY l.person_id
),

/* -----------------------------
6) EXCLUSIONS
----------------------------- */
excluded_gestational AS (
  SELECT DISTINCT person_id
  FROM gestational_dx_events
),
excluded_t1_only AS (
  /* Exclude people who have T1 diagnosis and NEVER have any T2 diagnosis */
  SELECT DISTINCT t1.person_id
  FROM t1_dx_events t1
  LEFT JOIN t2_dx_events t2
    ON t2.person_id = t1.person_id
  WHERE t2.person_id IS NULL
),

/* Optional stricter exclusion: T1 dx + insulin, no T2 dx, no noninsulin meds
excluded_t1_insulin_only AS (
  SELECT DISTINCT t1.person_id
  FROM t1_dx_events t1
  JOIN insulin_drug_events ins
    ON ins.person_id = t1.person_id
  LEFT JOIN t2_dx_events t2
    ON t2.person_id = t1.person_id
  LEFT JOIN noninsulin_drug_events nonins
    ON nonins.person_id = t1.person_id
  WHERE t2.person_id IS NULL AND nonins.person_id IS NULL
),
*/

/* -----------------------------
7) CASE ASSEMBLY + INDEX DATE
----------------------------- */
case_candidates AS (
  SELECT person_id, first_t2_dx_date AS index_date
  FROM t2_dx_2dates

  UNION ALL
  SELECT person_id, first_abnl_lab_date AS index_date
  FROM abnl_lab_2dates

  UNION ALL
  SELECT person_id, first_support_date AS index_date
  FROM t2_dx_1plus_med

  UNION ALL
  SELECT person_id, first_support_date AS index_date
  FROM lab_1plus_med
),
case_index AS (
  /* Pick earliest qualifying date across any satisfied rule */
  SELECT person_id, MIN(index_date) AS index_date
  FROM case_candidates
  GROUP BY person_id
),

/* -----------------------------
8) Require index_date within an observation_period
----------------------------- */
case_in_observation AS (
  SELECT ci.person_id, ci.index_date
  FROM case_index ci
  JOIN public.observation_period op
    ON op.person_id = ci.person_id
   AND ci.index_date BETWEEN op.observation_period_start_date AND op.observation_period_end_date
)

SELECT
  c.person_id,
  c.index_date
FROM case_in_observation c
LEFT JOIN excluded_gestational eg
  ON eg.person_id = c.person_id
LEFT JOIN excluded_t1_only et1
  ON et1.person_id = c.person_id
WHERE eg.person_id IS NULL
  AND et1.person_id IS NULL
ORDER BY c.person_id;



