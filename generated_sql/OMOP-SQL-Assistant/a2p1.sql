/* ============================================================================
Type 2 Diabetes Mellitus (T2DM) Phenotype — OMOP CDM v5.4 (public schema)
Core logic:
  CASE if (A OR B OR C OR D) AND NOT (Type1 OR Gestational OR Secondary/Other)
Where:
  A: >=2 T2DM dx on different dates
  B: >=1 T2DM dx AND >=1 non-insulin antidiabetic drug
  C: >=1 T2DM dx AND >=1 diabetes-range lab
  D: >=2 diabetes-range labs on different dates
============================================================================ */

WITH
/* --------------------------------------------------------------------------
1) Diagnosis concept sets using ICD9CM/ICD10CM codes (via concept table)
--------------------------------------------------------------------------- */
t2dm_dx_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE
    (c.vocabulary_id = 'ICD9CM'  AND c.concept_code LIKE '250.%' AND (RIGHT(c.concept_code, 1) IN ('0','2')))
    OR
    (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E11%')
),
t1dm_dx_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE
    (c.vocabulary_id = 'ICD9CM'  AND c.concept_code LIKE '250.%' AND (RIGHT(c.concept_code, 1) IN ('1','3')))
    OR
    (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E10%')
),
gestational_dx_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'O24%'
),
secondary_other_dm_dx_concepts AS (
  /* Optional exclusions often used to avoid non-T2DM diabetes types */
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id = 'ICD10CM'
    AND (
      c.concept_code LIKE 'E08%' OR  -- due to underlying condition
      c.concept_code LIKE 'E09%' OR  -- drug/chemical induced
      c.concept_code LIKE 'E13%'     -- other specified diabetes
    )
),

/* --------------------------------------------------------------------------
2) Drug concept set: non-insulin antidiabetic RxNorm concepts (generic + brand)
   - We match by RxNorm concept_name to capture ingredient and branded drugs.
   - Then expand to descendants using concept_ancestor.
--------------------------------------------------------------------------- */
antidiabetic_seed AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id = 'RxNorm'
    AND c.invalid_reason IS NULL
    AND (
      /* Big, practical coverage list (generic + brand terms) */
      c.concept_name ILIKE ANY (ARRAY[
        /* Metformin */
        '%metformin%', '%glucophage%', '%glumetza%', '%fortamet%', '%riomet%',

        /* Sulfonylureas */
        '%glipizide%', '%glucotrol%',
        '%glyburide%', '%diabeta%', '%glynase%',
        '%glimepiride%', '%amaryl%',

        /* TZDs */
        '%pioglitazone%', '%actos%',
        '%rosiglitazone%', '%avandia%',

        /* DPP-4 inhibitors */
        '%sitagliptin%', '%januvia%',
        '%saxagliptin%', '%onglyza%',
        '%linagliptin%', '%tradjenta%',
        '%alogliptin%', '%nesina%',

        /* GLP-1 receptor agonists */
        '%liraglutide%', '%victoza%',
        '%semaglutide%', '%ozempic%', '%rybelsus%',
        '%dulaglutide%', '%trulicity%',
        '%exenatide%', '%byetta%', '%bydureon%',

        /* SGLT2 inhibitors */
        '%empagliflozin%', '%jardiance%',
        '%canagliflozin%', '%invokana%',
        '%dapagliflozin%', '%farxiga%',
        '%ertugliflozin%', '%steglatro%',

        /* Others */
        '%acarbose%', '%precose%',
        '%miglitol%', '%glyset%',
        '%repaglinide%', '%prandin%',
        '%nateglinide%', '%starlix%'
      ])
    )
),
antidiabetic_descendants AS (
  /* Include all standard descendants (clinical drugs, branded drugs, etc.) */
  SELECT DISTINCT ca.descendant_concept_id AS concept_id
  FROM public.concept_ancestor ca
  JOIN antidiabetic_seed s
    ON ca.ancestor_concept_id = s.concept_id
),

/* --------------------------------------------------------------------------
3) Lab concepts (LOINC) and abnormal lab events
   - Use concept_code for common LOINC codes.
   - Values assumed in standard units (A1c %, glucose mg/dL).
--------------------------------------------------------------------------- */
a1c_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id = 'LOINC'
    AND c.concept_code IN ('4548-4','17856-6')  -- Hemoglobin A1c
),
glucose_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id = 'LOINC'
    AND c.concept_code IN (
      '1558-6',   -- Glucose [Moles/volume] / commonly mapped plasma glucose
      '2345-7',   -- Glucose [Mass/volume] in Serum or Plasma
      '14771-0',  -- Glucose fasting
      '20436-2'   -- Glucose 2 hour post dose (OGTT-related)
    )
),

abnormal_dm_labs AS (
  SELECT
    m.person_id,
    m.measurement_date AS event_date
  FROM public.measurement m
  WHERE
    (
      /* A1c >= 6.5 % */
      (m.measurement_concept_id IN (SELECT concept_id FROM a1c_concepts)
       AND m.value_as_number IS NOT NULL
       AND m.value_as_number >= 6.5
      )
      OR
      /* Glucose thresholds (mg/dL) */
      (m.measurement_concept_id IN (SELECT concept_id FROM glucose_concepts)
       AND m.value_as_number IS NOT NULL
       AND m.value_as_number >= 200
      )
      OR
      /* Fasting glucose >=126 (best effort: if concept indicates fasting) */
      (m.measurement_concept_id IN (SELECT concept_id FROM glucose_concepts)
       AND m.value_as_number IS NOT NULL
       AND m.value_as_number >= 126
      )
    )
),

/* --------------------------------------------------------------------------
4) Evidence extraction: diagnoses, drugs
--------------------------------------------------------------------------- */
t2dm_dx_events AS (
  SELECT
    co.person_id,
    co.condition_start_date AS event_date
  FROM public.condition_occurrence co
  WHERE co.condition_concept_id IN (SELECT concept_id FROM t2dm_dx_concepts)
),
t1dm_dx_events AS (
  SELECT DISTINCT co.person_id
  FROM public.condition_occurrence co
  WHERE co.condition_concept_id IN (SELECT concept_id FROM t1dm_dx_concepts)
),
gestational_dx_events AS (
  SELECT DISTINCT co.person_id
  FROM public.condition_occurrence co
  WHERE co.condition_concept_id IN (SELECT concept_id FROM gestational_dx_concepts)
),
secondary_other_dm_dx_events AS (
  SELECT DISTINCT co.person_id
  FROM public.condition_occurrence co
  WHERE co.condition_concept_id IN (SELECT concept_id FROM secondary_other_dm_dx_concepts)
),
antidiabetic_drug_events AS (
  SELECT
    de.person_id,
    de.drug_exposure_start_date AS event_date
  FROM public.drug_exposure de
  WHERE de.drug_concept_id IN (SELECT concept_id FROM antidiabetic_descendants)
),

/* --------------------------------------------------------------------------
5) Aggregate counts on distinct dates to enforce ">=2 dates"
--------------------------------------------------------------------------- */
t2dm_dx_by_person AS (
  SELECT
    person_id,
    COUNT(DISTINCT event_date) AS dx_date_count,
    MIN(event_date) AS first_t2dm_dx_date
  FROM t2dm_dx_events
  GROUP BY person_id
),
abnl_labs_by_person AS (
  SELECT
    person_id,
    COUNT(DISTINCT event_date) AS lab_date_count,
    MIN(event_date) AS first_abnl_lab_date
  FROM abnormal_dm_labs
  GROUP BY person_id
),
drug_by_person AS (
  SELECT
    person_id,
    COUNT(DISTINCT event_date) AS drug_date_count,
    MIN(event_date) AS first_drug_date
  FROM antidiabetic_drug_events
  GROUP BY person_id
),

/* --------------------------------------------------------------------------
6) Apply phenotype logic (A OR B OR C OR D) AND NOT exclusions
--------------------------------------------------------------------------- */
candidate_cases AS (
  SELECT
    p.person_id,

    /* Determine an index date as the earliest supporting event among criteria */
    LEAST(
      COALESCE(dx.first_t2dm_dx_date, DATE '9999-12-31'),
      COALESCE(lab.first_abnl_lab_date, DATE '9999-12-31'),
      COALESCE(drug.first_drug_date, DATE '9999-12-31')
    ) AS index_date,

    dx.dx_date_count,
    lab.lab_date_count,
    drug.drug_date_count

  FROM public.person p
  LEFT JOIN t2dm_dx_by_person dx  ON p.person_id = dx.person_id
  LEFT JOIN abnl_labs_by_person lab ON p.person_id = lab.person_id
  LEFT JOIN drug_by_person drug ON p.person_id = drug.person_id

  WHERE
    (
      /* A: >=2 T2DM dx dates */
      (COALESCE(dx.dx_date_count, 0) >= 2)

      OR

      /* B: >=1 T2DM dx AND >=1 antidiabetic drug */
      (COALESCE(dx.dx_date_count, 0) >= 1 AND COALESCE(drug.drug_date_count, 0) >= 1)

      OR

      /* C: >=1 T2DM dx AND >=1 abnormal diabetes lab */
      (COALESCE(dx.dx_date_count, 0) >= 1 AND COALESCE(lab.lab_date_count, 0) >= 1)

      OR

      /* D: >=2 abnormal diabetes labs on different dates */
      (COALESCE(lab.lab_date_count, 0) >= 2)
    )

    /* Exclusions */
    AND NOT EXISTS (SELECT 1 FROM t1dm_dx_events t1 WHERE t1.person_id = p.person_id)
    AND NOT EXISTS (SELECT 1 FROM gestational_dx_events g WHERE g.person_id = p.person_id)
    AND NOT EXISTS (SELECT 1 FROM secondary_other_dm_dx_events s WHERE s.person_id = p.person_id)
)

/* --------------------------------------------------------------------------
Final output: a simple cohort-like result set
--------------------------------------------------------------------------- */
SELECT
  person_id,
  index_date,
  dx_date_count,
  lab_date_count,
  drug_date_count
FROM candidate_cases
WHERE index_date < DATE '9999-12-31'
ORDER BY person_id;

