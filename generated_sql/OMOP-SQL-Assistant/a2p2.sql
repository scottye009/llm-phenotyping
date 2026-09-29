/* ============================================================================
Type 2 Diabetes Mellitus (T2DM) phenotyping algorithm for OMOP CDM v5.4 (Postgres)
Schema: public
Output: person_id + index_date (earliest qualifying evidence date)

STEP 1 (Critical criteria):
  A) Diagnosis evidence (ICD9CM/ICD10CM codes) for T2DM
  B) Laboratory evidence consistent with diabetes (HbA1c / glucose thresholds)
  C) Medication evidence (non-insulin anti-hyperglycemics)
  D) Exclusions: Type 1 DM, gestational DM, secondary diabetes
  E) (Optional but recommended) Confirmation via 2 occurrences on different dates

STEP 2 (How criteria are combined):
  CASE if:
    (
      (Dx_T2_confirmed)
      OR (Lab_diabetes_confirmed)
      OR (Dx_T2 AND NonInsulin_Antidiabetic)
    )
    AND NOT (Exclusion_Type1_without_T2_override)
    AND NOT (Gestational_DM)
    AND NOT (Secondary_DM)

  Where:
    Dx_T2_confirmed = >=2 T2DM dx dates (separated by >=1 day)
    Lab_diabetes_confirmed = (>=1 HbA1c>=6.5) OR (>=1 fasting glucose>=126) OR (>=1 random/2hr>=200)
    T2 override for Type1 = allow if strong T2 evidence exists (e.g., T2 dx confirmed or non-insulin meds)

STEP 3 (Final algorithm in SQL style):
============================================================================ */

WITH
/* -------------------------------
1) ICD concept sets (source diagnosis concepts)
   We use ICD9CM/ICD10CM codes and match to CONDITION_OCCURRENCE.condition_source_concept_id.
-------------------------------- */

/* T2DM ICD9CM/ICD10CM codes (core set)
   ICD9CM: 250.x0, 250.x2 (exclude 250.x1, 250.x3 which are Type 1)
   ICD10CM: E11.* (Type 2), plus some common “Type 2 with complications” are covered by E11.*
*/
t2dm_icd AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
      /* ICD10CM Type 2 */
      (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E11%')
      OR
      /* ICD9CM Type 2 patterns: 250.x0 or 250.x2 */
      (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~ '^250\.[0-9][02]$')
    )
),

/* Type 1 DM ICD codes
   ICD9CM: 250.x1, 250.x3
   ICD10CM: E10.*
*/
t1dm_icd AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
      (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E10%')
      OR
      (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~ '^250\.[0-9][13]$')
    )
),

/* Gestational DM ICD codes
   ICD9CM: 648.8*
   ICD10CM: O24.4*, O24.9* (gestational and unspecified diabetes in pregnancy; adjust as needed)
*/
gdm_icd AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
      (c.vocabulary_id = 'ICD9CM' AND c.concept_code LIKE '6488%')
      OR
      (c.vocabulary_id = 'ICD10CM' AND (c.concept_code LIKE 'O244%' OR c.concept_code LIKE 'O249%'))
    )
),

/* Secondary diabetes (drug/other cause) ICD codes
   ICD10CM: E08.*, E09.*
   ICD9CM: 249.*
*/
secondary_dm_icd AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
      (c.vocabulary_id = 'ICD10CM' AND (c.concept_code LIKE 'E08%' OR c.concept_code LIKE 'E09%'))
      OR
      (c.vocabulary_id = 'ICD9CM' AND c.concept_code LIKE '249%')
    )
),

/* -------------------------------
2) Diagnosis events from CONDITION_OCCURRENCE using source concept id (ICD)
-------------------------------- */
t2dm_dx AS (
  SELECT
    co.person_id,
    co.condition_start_date AS dx_date
  FROM public.condition_occurrence co
  JOIN t2dm_icd s ON s.concept_id = co.condition_source_concept_id
),
t1dm_dx AS (
  SELECT
    co.person_id,
    co.condition_start_date AS dx_date
  FROM public.condition_occurrence co
  JOIN t1dm_icd s ON s.concept_id = co.condition_source_concept_id
),
gdm_dx AS (
  SELECT
    co.person_id,
    co.condition_start_date AS dx_date
  FROM public.condition_occurrence co
  JOIN gdm_icd s ON s.concept_id = co.condition_source_concept_id
),
secondary_dm_dx AS (
  SELECT
    co.person_id,
    co.condition_start_date AS dx_date
  FROM public.condition_occurrence co
  JOIN secondary_dm_icd s ON s.concept_id = co.condition_source_concept_id
),

/* Confirmed T2 dx: >=2 distinct dx dates separated by at least 1 day */
t2dm_dx_confirmed AS (
  SELECT
    person_id,
    MIN(dx_date) AS first_t2_dx_date
  FROM (
    SELECT
      person_id,
      dx_date
    FROM t2dm_dx
    GROUP BY person_id, dx_date
  ) d
  GROUP BY person_id
  HAVING COUNT(*) >= 2
),

/* -------------------------------
3) Laboratory evidence (MEASUREMENT)
   Use LOINC codes via MEASUREMENT.measurement_concept_id (standard) OR source.
   Here we use measurement_concept_id with LOINC concepts; many CDMs map LOINC to measurement_concept_id.
-------------------------------- */

/* LOINC concept sets (minimal, common; add local codes as needed)
   HbA1c:
     4548-4 (Hemoglobin A1c/Hemoglobin.total in Blood)
     17856-6 (HbA1c/Hemoglobin.total in Blood by HPLC)
     41995-2 (HbA1c [Mass/Vol] in Blood)
   Glucose:
     1558-6 (Glucose [Mass/Vol] in Serum or Plasma)
     2345-7 (Glucose [Mass/Vol] in Serum or Plasma - fasting commonly mapped; sites vary)
     2339-0 (Glucose [Mass/Vol] in Blood)
*/
hba1c_loinc AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id = 'LOINC'
    AND concept_code IN ('4548-4','17856-6','41995-2')
),
glucose_loinc AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id = 'LOINC'
    AND concept_code IN ('1558-6','2345-7','2339-0')
),

/* Diabetes-range labs (single hit qualifies; you can require 2 abnormal labs if you prefer) */
diabetes_labs AS (
  SELECT
    m.person_id,
    m.measurement_date AS lab_date,
    CASE
      WHEN m.measurement_concept_id IN (SELECT concept_id FROM hba1c_loinc)
           AND m.value_as_number IS NOT NULL
           AND m.value_as_number >= 6.5
        THEN 'HBA1C_GE_6_5'
      WHEN m.measurement_concept_id IN (SELECT concept_id FROM glucose_loinc)
           AND m.value_as_number IS NOT NULL
           /* If you have fasting status, split thresholds; here we allow either:
              - fasting >=126
              - random/other >=200 (conservative: you may want to require context)
           */
           AND (m.value_as_number >= 200 OR m.value_as_number >= 126)
        THEN 'GLUCOSE_DIABETES_RANGE'
      ELSE NULL
    END AS lab_flag
  FROM public.measurement m
  WHERE m.measurement_concept_id IN (
    SELECT concept_id FROM hba1c_loinc
    UNION
    SELECT concept_id FROM glucose_loinc
  )
),

lab_diabetes_confirmed AS (
  SELECT
    person_id,
    MIN(lab_date) AS first_lab_date
  FROM diabetes_labs
  WHERE lab_flag IS NOT NULL
  GROUP BY person_id
),

/* -------------------------------
4) Medication evidence (DRUG_EXPOSURE)
   Include generic + common brand names. Use RxNorm Ingredients + Brand Names.
   We pull concept_ids by concept_name to avoid hard-coding IDs, then expand via CONCEPT_ANCESTOR.
-------------------------------- */

/* Anti-diabetic ingredients (non-insulin) */
antidiabetic_ingredients AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id IN ('RxNorm','RxNorm Extension')
    AND concept_class_id = 'Ingredient'
    AND concept_name IN (
      /* Biguanide */
      'metformin',

      /* Sulfonylureas */
      'glipizide','glyburide','glimepiride','tolbutamide','chlorpropamide',

      /* Thiazolidinediones */
      'pioglitazone','rosiglitazone',

      /* DPP-4 inhibitors */
      'sitagliptin','saxagliptin','linagliptin','alogliptin',

      /* GLP-1 receptor agonists */
      'liraglutide','semaglutide','dulaglutide','exenatide','lixisenatide',

      /* SGLT2 inhibitors */
      'canagliflozin','dapagliflozin','empagliflozin','ertugliflozin',

      /* Other common non-insulin agents */
      'acarbose','miglitol','pramlintide'
    )
),

/* Brand names (non-exhaustive; include common US brands; add site-specific brands if needed) */
antidiabetic_brands AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id IN ('RxNorm','RxNorm Extension')
    AND concept_class_id IN ('Brand Name')
    AND concept_name IN (
      /* metformin */
      'Glucophage','Glucophage XR','Fortamet','Glumetza','Riomet',

      /* sulfonylureas */
      'Glucotrol','Glucotrol XL','Diabeta','Micronase','Glynase','Amaryl',

      /* TZDs */
      'Actos','Avandia',

      /* DPP-4 */
      'Januvia','Onglyza','Tradjenta','Nesina',

      /* GLP-1 */
      'Victoza','Ozempic','Rybelsus','Trulicity','Byetta','Bydureon','Adlyxin',

      /* SGLT2 */
      'Invokana','Farxiga','Jardiance','Steglatro'
    )
),

/* Expand to all descendant drug concepts (clinical drugs, branded drugs, etc.) */
noninsulin_antidiabetic_drug_concepts AS (
  SELECT ca.descendant_concept_id AS concept_id
  FROM public.concept_ancestor ca
  WHERE ca.ancestor_concept_id IN (
    SELECT concept_id FROM antidiabetic_ingredients
    UNION
    SELECT concept_id FROM antidiabetic_brands
  )
),

/* Insulin concepts (for potential Type1 exclusion logic; keep separate) */
insulin_ingredient AS (
  SELECT concept_id
  FROM public.concept
  WHERE vocabulary_id IN ('RxNorm','RxNorm Extension')
    AND concept_class_id = 'Ingredient'
    AND concept_name = 'insulin'
),
insulin_drug_concepts AS (
  SELECT ca.descendant_concept_id AS concept_id
  FROM public.concept_ancestor ca
  WHERE ca.ancestor_concept_id IN (SELECT concept_id FROM insulin_ingredient)
),

noninsulin_antidiabetic_exposure AS (
  SELECT
    de.person_id,
    de.drug_exposure_start_date AS drug_date
  FROM public.drug_exposure de
  JOIN noninsulin_antidiabetic_drug_concepts d
    ON d.concept_id = de.drug_concept_id
),

insulin_exposure AS (
  SELECT
    de.person_id,
    de.drug_exposure_start_date AS drug_date
  FROM public.drug_exposure de
  JOIN insulin_drug_concepts d
    ON d.concept_id = de.drug_concept_id
),

/* -------------------------------
5) Exclusions and evidence combination
-------------------------------- */

/* Any evidence of strong T2 (dx confirmed OR lab confirmed OR non-insulin meds) */
strong_t2_evidence AS (
  SELECT person_id, MIN(evidence_date) AS first_strong_t2_date
  FROM (
    SELECT person_id, first_t2_dx_date AS evidence_date FROM t2dm_dx_confirmed
    UNION ALL
    SELECT person_id, first_lab_date AS evidence_date FROM lab_diabetes_confirmed
    UNION ALL
    SELECT person_id, MIN(drug_date) AS evidence_date
    FROM noninsulin_antidiabetic_exposure
    GROUP BY person_id
  ) x
  GROUP BY person_id
),

/* Type1 exclusion: exclude if Type1 dx exists AND no strong T2 evidence */
type1_exclusion AS (
  SELECT DISTINCT t1.person_id
  FROM t1dm_dx t1
  LEFT JOIN strong_t2_evidence t2 ON t2.person_id = t1.person_id
  WHERE t2.person_id IS NULL
),

gestational_exclusion AS (
  SELECT DISTINCT person_id FROM gdm_dx
),
secondary_exclusion AS (
  SELECT DISTINCT person_id FROM secondary_dm_dx
),

/* -------------------------------
6) Case definition logic (AND / OR / NOT)
   - Case if:
       (Dx_T2_confirmed OR Lab_diabetes_confirmed OR (Any_T2_dx AND Noninsulin_med))
     AND NOT type1_exclusion
     AND NOT gestational_exclusion
     AND NOT secondary_exclusion
-------------------------------- */

any_t2_dx AS (
  SELECT person_id, MIN(dx_date) AS first_any_t2_dx_date
  FROM t2dm_dx
  GROUP BY person_id
),

dx_plus_med AS (
  SELECT
    d.person_id,
    LEAST(d.first_any_t2_dx_date, m.first_med_date) AS first_dx_or_med_date
  FROM any_t2_dx d
  JOIN (
    SELECT person_id, MIN(drug_date) AS first_med_date
    FROM noninsulin_antidiabetic_exposure
    GROUP BY person_id
  ) m
    ON m.person_id = d.person_id
),

/* Final cases with index_date = earliest qualifying evidence among satisfied pathways */
t2dm_cases AS (
  SELECT
    p.person_id,
    MIN(p.index_date) AS index_date
  FROM (
    /* Pathway 1: confirmed T2 diagnosis */
    SELECT person_id, first_t2_dx_date AS index_date
    FROM t2dm_dx_confirmed

    UNION ALL

    /* Pathway 2: diabetes-range labs */
    SELECT person_id, first_lab_date AS index_date
    FROM lab_diabetes_confirmed

    UNION ALL

    /* Pathway 3: any T2 dx + non-insulin antidiabetic */
    SELECT person_id, first_dx_or_med_date AS index_date
    FROM dx_plus_med
  ) p
  GROUP BY p.person_id
)

SELECT
  c.person_id,
  c.index_date
FROM t2dm_cases c
/* AND / OR / NOT exclusions applied here */
WHERE c.person_id NOT IN (SELECT person_id FROM type1_exclusion)
  AND c.person_id NOT IN (SELECT person_id FROM gestational_exclusion)
  AND c.person_id NOT IN (SELECT person_id FROM secondary_exclusion)
ORDER BY c.person_id;

