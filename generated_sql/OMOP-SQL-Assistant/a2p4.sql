/*===========================================================================
  Type 2 Diabetes Mellitus (T2DM) Phenotyping Algorithm (OMOP CDM v5.4)
  - Target DB: PostgreSQL (pgAdmin4)
  - Schema: public
  - Uses OMOP vocab tables to build concept sets from:
      * ICD9CM / ICD10CM for diagnoses
      * RxNorm for medications (generic + brand via descendants)
      * LOINC / SNOMED / OMOP Extension for labs (MEASUREMENT)
  - Produces: one row per person with an index_date (earliest qualifying date)
===========================================================================*/

WITH
/*---------------------------------------------------------------------------
  1) DIAGNOSIS CONCEPT SETS (ICD9CM + ICD10CM)
---------------------------------------------------------------------------*/

/* T2DM diagnosis codes:
   - ICD-9-CM: 250.x0 or 250.x2 (type II or unspecified, not stated as uncontrolled/controlled)
   - ICD-10-CM: E11.* (Type 2 diabetes mellitus)
*/
t2dm_dx_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
      /* ICD-9-CM 250.x0 or 250.x2 */
      (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~ '^250\.[0-9][02]$')
      OR
      /* ICD-10-CM E11.* */
      (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E11%')
    )
),

/* EXCLUSIONS: Type 1 diabetes (strong exclusion) */
t1dm_dx_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
      /* ICD-9-CM 250.x1 or 250.x3 */
      (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~ '^250\.[0-9][13]$')
      OR
      /* ICD-10-CM E10.* */
      (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E10%')
    )
),

/* EXCLUSIONS: Gestational diabetes (pregnancy-related diabetes) */
gestational_dx_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
      /* ICD-9-CM gestational diabetes: 648.8x */
      (c.vocabulary_id = 'ICD9CM' AND c.concept_code LIKE '648.8%')
      OR
      /* ICD-10-CM gestational diabetes: O24.4* (and related) */
      (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'O24.4%')
    )
),

/* OPTIONAL EXCLUSIONS: Secondary diabetes due to other conditions (ICD-10 E08, E09, E13) */
secondary_dm_dx_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id = 'ICD10CM'
    AND (c.concept_code LIKE 'E08%' OR c.concept_code LIKE 'E09%' OR c.concept_code LIKE 'E13%')
),

/*---------------------------------------------------------------------------
  2) MEDICATION CONCEPT SETS (RxNorm)
     We build ingredient concepts (generic) and include brand names for clarity.
     Then we expand to all descendant drug concepts via concept_ancestor.
---------------------------------------------------------------------------*/

/* Anti-diabetic medication ingredients (non-insulin), with examples of brand names.
   NOTE: This uses RxNorm concept_name matching so it works without hardcoding IDs.
   You can expand this list to match your local formulary.
*/
t2dm_drug_ingredient_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id = 'RxNorm'
    AND c.concept_class_id IN ('Ingredient','Clinical Drug Comp','Brand Name')  -- include brand concepts too
    AND (
      /* Biguanide */
      c.concept_name ILIKE 'metformin%' OR c.concept_name ILIKE 'glucophage%' OR c.concept_name ILIKE 'fortamet%' OR c.concept_name ILIKE 'glumetza%'
      OR
      /* Sulfonylureas */
      c.concept_name ILIKE 'glipizide%' OR c.concept_name ILIKE 'glucotrol%'
      OR c.concept_name ILIKE 'glyburide%' OR c.concept_name ILIKE 'diabeta%' OR c.concept_name ILIKE 'micronase%'
      OR c.concept_name ILIKE 'glimepiride%' OR c.concept_name ILIKE 'amaryl%'
      OR
      /* Thiazolidinediones */
      c.concept_name ILIKE 'pioglitazone%' OR c.concept_name ILIKE 'actos%'
      OR c.concept_name ILIKE 'rosiglitazone%' OR c.concept_name ILIKE 'avandia%'
      OR
      /* DPP-4 inhibitors */
      c.concept_name ILIKE 'sitagliptin%' OR c.concept_name ILIKE 'januvia%'
      OR c.concept_name ILIKE 'linagliptin%' OR c.concept_name ILIKE 'tradjenta%'
      OR c.concept_name ILIKE 'saxagliptin%' OR c.concept_name ILIKE 'onglyza%'
      OR c.concept_name ILIKE 'alogliptin%' OR c.concept_name ILIKE 'nesina%'
      OR
      /* GLP-1 receptor agonists */
      c.concept_name ILIKE 'liraglutide%' OR c.concept_name ILIKE 'victoza%'
      OR c.concept_name ILIKE 'semaglutide%' OR c.concept_name ILIKE 'ozempic%' OR c.concept_name ILIKE 'rybelsus%'
      OR c.concept_name ILIKE 'dulaglutide%' OR c.concept_name ILIKE 'trulicity%'
      OR c.concept_name ILIKE 'exenatide%' OR c.concept_name ILIKE 'byetta%' OR c.concept_name ILIKE 'bydureon%'
      OR
      /* SGLT2 inhibitors */
      c.concept_name ILIKE 'empagliflozin%' OR c.concept_name ILIKE 'jardiance%'
      OR c.concept_name ILIKE 'canagliflozin%' OR c.concept_name ILIKE 'invokana%'
      OR c.concept_name ILIKE 'dapagliflozin%' OR c.concept_name ILIKE 'farxiga%'
      OR c.concept_name ILIKE 'ertugliflozin%' OR c.concept_name ILIKE 'steglatro%'
      OR
      /* Meglitinides */
      c.concept_name ILIKE 'repaglinide%' OR c.concept_name ILIKE 'prandin%'
      OR c.concept_name ILIKE 'nateglinide%' OR c.concept_name ILIKE 'starlix%'
      OR
      /* Alpha-glucosidase inhibitors */
      c.concept_name ILIKE 'acarbose%' OR c.concept_name ILIKE 'precose%'
      OR c.concept_name ILIKE 'miglitol%' OR c.concept_name ILIKE 'glyset%'
    )
),

/* Expand ingredient/brand concepts to all drug_exposure drug_concept_ids */
t2dm_drug_concepts AS (
  SELECT DISTINCT ca.descendant_concept_id AS concept_id
  FROM public.concept_ancestor ca
  JOIN t2dm_drug_ingredient_concepts i
    ON ca.ancestor_concept_id = i.concept_id
),

/*---------------------------------------------------------------------------
  3) LAB CONCEPT SETS (MEASUREMENT)
     We capture common diabetes diagnostic labs:
       - Hemoglobin A1c (>= 6.5 %)
       - Fasting plasma glucose (>= 126 mg/dL)
       - Random plasma glucose (>= 200 mg/dL)
       - 2-hr OGTT glucose (>= 200 mg/dL)
---------------------------------------------------------------------------*/
dm_lab_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.domain_id = 'Measurement'
    AND (
      c.concept_name ILIKE '%hemoglobin a1c%' OR c.concept_name ILIKE '%hba1c%'
      OR c.concept_name ILIKE '%fasting%glucose%'         -- fasting plasma glucose
      OR c.concept_name ILIKE '%plasma glucose%'          -- general plasma glucose
      OR c.concept_name ILIKE '%glucose tolerance%'       -- OGTT
      OR c.concept_name ILIKE '%2 hour%glucose%'          -- 2-hr glucose
    )
),

/*---------------------------------------------------------------------------
  4) RAW EVENTS
---------------------------------------------------------------------------*/

/* T2DM diagnosis events */
t2dm_dx_events AS (
  SELECT
    co.person_id,
    co.condition_start_date AS event_date,
    co.visit_occurrence_id,
    co.condition_concept_id
  FROM public.condition_occurrence co
  JOIN t2dm_dx_concepts dx
    ON co.condition_source_concept_id = dx.concept_id
),

/* Type 1 diagnosis events (exclusion) */
t1dm_dx_events AS (
  SELECT
    co.person_id,
    MIN(co.condition_start_date) AS first_t1dm_date
  FROM public.condition_occurrence co
  JOIN t1dm_dx_concepts dx
    ON co.condition_source_concept_id = dx.concept_id
  GROUP BY co.person_id
),

/* Gestational diabetes events (exclusion) */
gestational_dx_events AS (
  SELECT
    co.person_id,
    MIN(co.condition_start_date) AS first_gdm_date
  FROM public.condition_occurrence co
  JOIN gestational_dx_concepts dx
    ON co.condition_source_concept_id = dx.concept_id
  GROUP BY co.person_id
),

/* Secondary diabetes events (optional exclusion) */
secondary_dm_dx_events AS (
  SELECT
    co.person_id,
    MIN(co.condition_start_date) AS first_secondary_dm_date
  FROM public.condition_occurrence co
  JOIN secondary_dm_dx_concepts dx
    ON co.condition_source_concept_id = dx.concept_id
  GROUP BY co.person_id
),

/* T2DM medication exposure events */
t2dm_drug_events AS (
  SELECT
    de.person_id,
    de.drug_exposure_start_date AS event_date,
    de.visit_occurrence_id,
    de.drug_concept_id
  FROM public.drug_exposure de
  JOIN t2dm_drug_concepts d
    ON de.drug_concept_id = d.concept_id
),

/* Diagnostic lab events meeting thresholds */
dm_lab_events AS (
  SELECT
    m.person_id,
    m.measurement_date AS event_date,
    m.measurement_concept_id,
    m.value_as_number,
    m.unit_concept_id,
    /* crude label for downstream logic */
    CASE
      WHEN m.measurement_concept_id IN (SELECT concept_id FROM dm_lab_concepts)
        AND (m.concept_id IS NULL) THEN 'DM_LAB'
      ELSE 'DM_LAB'
    END AS lab_group
  FROM public.measurement m
  JOIN dm_lab_concepts lc
    ON m.measurement_concept_id = lc.concept_id
  WHERE m.value_as_number IS NOT NULL
),

/*---------------------------------------------------------------------------
  5) LAB THRESHOLD FLAGS
     Because units vary by site, we apply typical thresholds assuming:
       - A1c in %
       - glucose in mg/dL
     You may need to tighten by unit_concept_id at your site.
---------------------------------------------------------------------------*/
dm_lab_positive AS (
  SELECT
    person_id,
    event_date,
    /* Positive if any diabetes-diagnostic threshold met */
    CASE
      WHEN ( /* HbA1c >= 6.5 (%) */
            (SELECT COUNT(*) FROM public.concept c WHERE c.concept_id = measurement_concept_id
             AND (c.concept_name ILIKE '%a1c%' OR c.concept_name ILIKE '%hemoglobin a1c%')) > 0
           AND value_as_number >= 6.5
           )
        THEN 1
      WHEN ( /* Glucose >= 200 (random/2hr), or >=126 (fasting) - heuristic by name */
            (SELECT COUNT(*) FROM public.concept c WHERE c.concept_id = measurement_concept_id
             AND c.concept_name ILIKE '%fasting%') > 0
           AND value_as_number >= 126
           )
        THEN 1
      WHEN ( /* Non-fasting glucose threshold */
            (SELECT COUNT(*) FROM public.concept c WHERE c.concept_id = measurement_concept_id
             AND (c.concept_name ILIKE '%glucose%' AND c.concept_name NOT ILIKE '%fasting%')) > 0
           AND value_as_number >= 200
           )
        THEN 1
      ELSE 0
    END AS is_positive
  FROM dm_lab_events
),

/*---------------------------------------------------------------------------
  6) VISIT CONTEXT: inpatient vs outpatient (for stronger single-diagnosis rule)
---------------------------------------------------------------------------*/
inpatient_visits AS (
  SELECT vo.visit_occurrence_id
  FROM public.visit_occurrence vo
  JOIN public.concept vc
    ON vo.visit_concept_id = vc.concept_id
  WHERE vc.concept_name ILIKE '%inpatient%' OR vc.concept_name ILIKE '%emergency room%'
),

/*---------------------------------------------------------------------------
  7) INCLUSION LOGIC (STEP 2: Combine criteria)
     Case if ANY of the following is true:

     A) (>=2 T2DM dx on distinct dates) OR (>=1 inpatient T2DM dx)
     OR
     B) (>=1 T2DM medication exposure) AND ( (>=1 T2DM dx) OR (>=1 positive lab) )
     OR
     C) (>=2 positive labs on distinct dates)

     AND NOT excluded by:
       - any T1DM diagnosis
       - any gestational diabetes diagnosis
       - optional: any secondary diabetes diagnosis
---------------------------------------------------------------------------*/
t2dm_dx_counts AS (
  SELECT
    person_id,
    COUNT(DISTINCT event_date) AS n_t2dm_dx_dates,
    MIN(event_date) AS first_t2dm_dx_date,
    MIN(CASE WHEN visit_occurrence_id IN (SELECT visit_occurrence_id FROM inpatient_visits) THEN event_date END) AS first_inpatient_t2dm_dx_date
  FROM t2dm_dx_events
  GROUP BY person_id
),

t2dm_drug_counts AS (
  SELECT
    person_id,
    COUNT(DISTINCT event_date) AS n_t2dm_drug_dates,
    MIN(event_date) AS first_t2dm_drug_date
  FROM t2dm_drug_events
  GROUP BY person_id
),

dm_lab_positive_counts AS (
  SELECT
    person_id,
    COUNT(DISTINCT event_date) FILTER (WHERE is_positive = 1) AS n_pos_lab_dates,
    MIN(event_date) FILTER (WHERE is_positive = 1) AS first_pos_lab_date
  FROM dm_lab_positive
  GROUP BY person_id
),

/* Apply the boolean logic with AND / OR / NOT explicitly */
t2dm_candidates AS (
  SELECT
    p.person_id,

    /* Candidate index date = earliest date among the qualifying path */
    LEAST(
      COALESCE(dx.first_t2dm_dx_date, DATE '9999-12-31'),
      COALESCE(dr.first_t2dm_drug_date, DATE '9999-12-31'),
      COALESCE(lb.first_pos_lab_date, DATE '9999-12-31')
    ) AS index_date,

    /* Inclusion flags */
    (
      /* A) Diagnosis-based */
      (
        (dx.n_t2dm_dx_dates >= 2)
        OR
        (dx.first_inpatient_t2dm_dx_date IS NOT NULL)
      )
      OR
      /* B) Medication + (Dx OR Lab) */
      (
        (dr.n_t2dm_drug_dates >= 1)
        AND
        (
          (dx.n_t2dm_dx_dates >= 1)
          OR
          (lb.n_pos_lab_dates >= 1)
        )
      )
      OR
      /* C) Lab-based */
      (
        (lb.n_pos_lab_dates >= 2)
      )
    ) AS meets_inclusion,

    /* Exclusion flags */
    (t1.first_t1dm_date IS NOT NULL) AS has_t1dm,
    (gdm.first_gdm_date IS NOT NULL) AS has_gdm,
    (sec.first_secondary_dm_date IS NOT NULL) AS has_secondary_dm

  FROM public.person p
  LEFT JOIN t2dm_dx_counts dx
    ON p.person_id = dx.person_id
  LEFT JOIN t2dm_drug_counts dr
    ON p.person_id = dr.person_id
  LEFT JOIN dm_lab_positive_counts lb
    ON p.person_id = lb.person_id
  LEFT JOIN t1dm_dx_events t1
    ON p.person_id = t1.person_id
  LEFT JOIN gestational_dx_events gdm
    ON p.person_id = gdm.person_id
  LEFT JOIN secondary_dm_dx_events sec
    ON p.person_id = sec.person_id
),

/*---------------------------------------------------------------------------
  8) FINAL COHORT: INCLUSION AND NOT(EXCLUSIONS)
---------------------------------------------------------------------------*/
final_t2dm AS (
  SELECT
    person_id,
    index_date
  FROM t2dm_candidates
  WHERE
    meets_inclusion = TRUE
    AND NOT (has_t1dm = TRUE)
    AND NOT (has_gdm = TRUE)
    AND NOT (has_secondary_dm = TRUE)  -- set to FALSE/remove if you don't want this exclusion
)

SELECT
  person_id,
  index_date
FROM final_t2dm
ORDER BY person_id;

