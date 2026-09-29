/*------------------------------------------------------------------------------
Type 2 Diabetes (T2DM) Phenotype - OMOP CDM v5.4 (PostgreSQL)
Schema: public

CASE definition (high level):
  CASE if (
      ( (>=2 outpatient T2DM dx on different dates) OR (>=1 inpatient/ED T2DM dx) )
      OR (>=1 T2DM dx AND >=1 non-insulin antihyperglycemic exposure)
      OR (>=2 abnormal diabetes labs on different dates)
    )
    AND NOT (any Type 1 diabetes dx)
    AND NOT (any gestational diabetes dx)
------------------------------------------------------------------------------*/

WITH
/*----------------------------------------------------------
1) ICD-coded T2DM diagnoses (ICD9CM / ICD10CM) from CONDITION
   - Uses condition_source_concept_id (ICD vocab required)
----------------------------------------------------------*/
t2dm_dx AS (
  SELECT
      co.person_id,
      co.condition_start_date AS dx_date,
      co.visit_occurrence_id,
      c.vocabulary_id,
      c.concept_code
  FROM public.condition_occurrence co
  JOIN public.concept c
    ON c.concept_id = co.condition_source_concept_id
  WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
    AND (
      /* ICD10CM T2DM: E11.* */
      (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E11%')

      /* Optional broader diabetes bucket: uncomment if desired
      OR (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E13%')
      */

      /* ICD9CM T2DM: 250xx where last digit NOT IN (1,3) */
      OR (
        c.vocabulary_id = 'ICD9CM'
        AND c.concept_code LIKE '250%'
        AND RIGHT(REGEXP_REPLACE(c.concept_code, '[^0-9]', '', 'g'), 1) NOT IN ('1','3')
      )
    )
),

/*----------------------------------------------------------
2) ICD-coded Type 1 diabetes diagnoses (for exclusion)
----------------------------------------------------------*/
t1dm_dx AS (
  SELECT DISTINCT
      co.person_id
  FROM public.condition_occurrence co
  JOIN public.concept c
    ON c.concept_id = co.condition_source_concept_id
  WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
    AND (
      /* ICD10CM T1DM: E10.* */
      (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E10%')
      /* ICD9CM T1DM: 250xx where last digit IN (1,3) */
      OR (
        c.vocabulary_id = 'ICD9CM'
        AND c.concept_code LIKE '250%'
        AND RIGHT(REGEXP_REPLACE(c.concept_code, '[^0-9]', '', 'g'), 1) IN ('1','3')
      )
    )
),

/*----------------------------------------------------------
3) Gestational diabetes diagnoses (for exclusion)
----------------------------------------------------------*/
gest_dm_dx AS (
  SELECT DISTINCT
      co.person_id
  FROM public.condition_occurrence co
  JOIN public.concept c
    ON c.concept_id = co.condition_source_concept_id
  WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
    AND (
      /* ICD10CM pregnancy-related diabetes: O24.* (broad exclusion) */
      (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'O24%')
      /* ICD9CM gestational diabetes: 648.8* */
      OR (c.vocabulary_id = 'ICD9CM' AND c.concept_code LIKE '6488%')
      OR (c.vocabulary_id = 'ICD9CM' AND c.concept_code LIKE '648.8%')
    )
),

/*----------------------------------------------------------
4) Identify inpatient/ED vs outpatient T2DM dx using VISIT
   - visit_concept_id:
       9201 = Inpatient Visit
       9203 = Emergency Room Visit
       9202 = Outpatient Visit
   (These are standard OMOP Visit concepts.)
----------------------------------------------------------*/
t2dm_dx_labeled AS (
  SELECT
      d.person_id,
      d.dx_date,
      vo.visit_concept_id,
      CASE
        WHEN vo.visit_concept_id IN (9201, 9203) THEN 1 ELSE 0
      END AS is_inpatient_or_ed,
      CASE
        WHEN vo.visit_concept_id = 9202 THEN 1 ELSE 0
      END AS is_outpatient
  FROM t2dm_dx d
  LEFT JOIN public.visit_occurrence vo
    ON vo.visit_occurrence_id = d.visit_occurrence_id
),

/*----------------------------------------------------------
5) Dx-based evidence counts
   - >=2 outpatient dx on different dates
   - OR >=1 inpatient/ED dx
----------------------------------------------------------*/
dx_evidence AS (
  SELECT
      person_id,
      /* distinct outpatient dates */
      COUNT(DISTINCT CASE WHEN is_outpatient = 1 THEN dx_date END) AS n_outpt_dx_dates,
      /* any inpatient/ED dx */
      MAX(is_inpatient_or_ed) AS has_inpt_or_ed_dx
  FROM t2dm_dx_labeled
  GROUP BY person_id
),

/*----------------------------------------------------------
6) Non-insulin antihyperglycemic exposures (supporting meds)
   - Uses drug_concept_id concept_name matching (portable baseline)
   - Replace with RxNorm concept_id sets for best accuracy/performance.
----------------------------------------------------------*/
t2dm_meds AS (
  SELECT DISTINCT
      de.person_id,
      de.drug_exposure_start_date AS drug_date,
      c.concept_name
  FROM public.drug_exposure de
  JOIN public.concept c
    ON c.concept_id = de.drug_concept_id
  WHERE
    /* Exclude device/procedure concepts if any weird mappings; keep drug domain */
    c.domain_id = 'Drug'
    AND (
      /* Biguanide */
      c.concept_name ILIKE '%metformin%' OR c.concept_name ILIKE '%glucophage%' OR
      c.concept_name ILIKE '%glumetza%' OR c.concept_name ILIKE '%fortamet%' OR c.concept_name ILIKE '%riomet%'

      /* Sulfonylureas */
      OR c.concept_name ILIKE '%glipizide%' OR c.concept_name ILIKE '%glucotrol%'
      OR c.concept_name ILIKE '%glyburide%' OR c.concept_name ILIKE '%diabeta%' OR c.concept_name ILIKE '%micronase%' OR c.concept_name ILIKE '%glynase%'
      OR c.concept_name ILIKE '%glimepiride%' OR c.concept_name ILIKE '%amaryl%'

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
      OR c.concept_name ILIKE '%canagliflozin%' OR c.concept_name ILIKE '%invokana%'
      OR c.concept_name ILIKE '%dapagliflozin%' OR c.concept_name ILIKE '%farxiga%'
      OR c.concept_name ILIKE '%ertugliflozin%' OR c.concept_name ILIKE '%steglatro%'

      /* TZDs */
      OR c.concept_name ILIKE '%pioglitazone%' OR c.concept_name ILIKE '%actos%'
      OR c.concept_name ILIKE '%rosiglitazone%' OR c.concept_name ILIKE '%avandia%'

      /* Other classes */
      OR c.concept_name ILIKE '%repaglinide%' OR c.concept_name ILIKE '%prandin%'
      OR c.concept_name ILIKE '%nateglinide%' OR c.concept_name ILIKE '%starlix%'
      OR c.concept_name ILIKE '%acarbose%' OR c.concept_name ILIKE '%precose%'
      OR c.concept_name ILIKE '%miglitol%' OR c.concept_name ILIKE '%glyset%'
      OR c.concept_name ILIKE '%pramlintide%' OR c.concept_name ILIKE '%symlin%'
    )
),

med_evidence AS (
  SELECT
      person_id,
      MIN(drug_date) AS first_med_date
  FROM t2dm_meds
  GROUP BY person_id
),

/*----------------------------------------------------------
7) Lab evidence (MEASUREMENT)
   - HbA1c >= 6.5 (%)
   - Glucose (fasting/random/OGTT) >= thresholds (mg/dL)
   - Portable approach: concept_name matching for test type.
   - Better approach: use LOINC concept_id sets (recommended if available).
----------------------------------------------------------*/
abnl_labs AS (
  SELECT
      m.person_id,
      m.measurement_date,
      m.value_as_number,
      m.unit_concept_id,
      c.concept_name AS measurement_name
  FROM public.measurement m
  JOIN public.concept c
    ON c.concept_id = m.measurement_concept_id
  WHERE m.value_as_number IS NOT NULL
    AND (
      /* HbA1c threshold */
      (c.concept_name ILIKE '%hemoglobin a1c%' AND m.value_as_number >= 6.5)

      /* Glucose thresholds - assumes mg/dL; adapt if mmol/L in your data */
      OR (
        c.concept_name ILIKE '%glucose%'
        AND (
          /* fasting plasma glucose */
          (c.concept_name ILIKE '%fasting%' AND m.value_as_number >= 126)
          /* 2-hour / OGTT */
          OR (c.concept_name ILIKE '%2 hour%' AND m.value_as_number >= 200)
          OR (c.concept_name ILIKE '%oral glucose tolerance%' AND m.value_as_number >= 200)
          /* random glucose */
          OR (c.concept_name NOT ILIKE '%fasting%' AND m.value_as_number >= 200)
        )
      )
    )
),

lab_evidence AS (
  SELECT
      person_id,
      COUNT(DISTINCT measurement_date) AS n_abnl_lab_dates,
      MIN(measurement_date) AS first_abnl_lab_date
  FROM abnl_labs
  GROUP BY person_id
),

/*----------------------------------------------------------
8) Combine evidence into a final CASE definition using AND/OR/NOT
----------------------------------------------------------*/
case_candidates AS (
  SELECT
      p.person_id,

      /* Dx evidence flags */
      COALESCE(d.n_outpt_dx_dates, 0) AS n_outpt_dx_dates,
      COALESCE(d.has_inpt_or_ed_dx, 0) AS has_inpt_or_ed_dx,

      /* Med evidence flag */
      CASE WHEN m.person_id IS NOT NULL THEN 1 ELSE 0 END AS has_t2dm_med,

      /* Lab evidence flag */
      COALESCE(l.n_abnl_lab_dates, 0) AS n_abnl_lab_dates

  FROM public.person p
  LEFT JOIN dx_evidence d ON d.person_id = p.person_id
  LEFT JOIN med_evidence m ON m.person_id = p.person_id
  LEFT JOIN lab_evidence l ON l.person_id = p.person_id
),

final_t2dm AS (
  SELECT
      c.person_id
  FROM case_candidates c
  WHERE
    (
      /*------------------------------------------------------
        CASE if:
          ( (>=2 outpatient dx dates) OR (>=1 inpatient/ED dx) )
          OR (>=1 dx evidence AND >=1 non-insulin med)
          OR (>=2 abnormal lab dates)
      ------------------------------------------------------*/
      (
        (c.n_outpt_dx_dates >= 2 OR c.has_inpt_or_ed_dx = 1)
        OR (
          (c.n_outpt_dx_dates >= 1 OR c.has_inpt_or_ed_dx = 1)
          AND c.has_t2dm_med = 1
        )
        OR (c.n_abnl_lab_dates >= 2)
      )
      /*------------------------------------------------------
        AND NOT Type 1 diabetes
        AND NOT Gestational diabetes
      ------------------------------------------------------*/
      AND NOT EXISTS (SELECT 1 FROM t1dm_dx t1 WHERE t1.person_id = c.person_id)
      AND NOT EXISTS (SELECT 1 FROM gest_dm_dx g  WHERE g.person_id  = c.person_id)
    )
)

SELECT
    person_id
FROM final_t2dm
ORDER BY person_id;

