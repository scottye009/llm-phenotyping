/*----------------------------------------------------------------------------
Type 2 Diabetes Mellitus (T2DM) Phenotype (OMOP CDM v5.4) - SQL Style
Schema: public
Core tables: person, condition_occurrence, drug_exposure, measurement, concept
----------------------------------------------------------------------------*/

/*========================
  1) CONCEPT SETS (ICD + LOINC + RxNorm by name patterns)
=========================*/
WITH
/*--- ICD diagnosis concepts for T2DM (Type 2) ---*/
t2dm_dx_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
      /* ICD10CM: E11.* */
      (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E11%')
      OR
      /* ICD9CM: 250.x0 or 250.x2 => Type 2 */
      (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~ '^250\..*[02]$')
    )
),

/*--- ICD diagnosis concepts for exclusions: T1DM, gestational, secondary ---*/
t1dm_dx_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
      /* ICD10CM: E10.* */
      (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E10%')
      OR
      /* ICD9CM: 250.x1 or 250.x3 => Type 1 */
      (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~ '^250\..*[13]$')
    )
),
gestational_dx_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
      /* ICD10CM gestational diabetes: O24.4* (site may also use other O24.*) */
      (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'O24.4%')
      OR
      /* ICD9CM: 648.8* */
      (c.vocabulary_id = 'ICD9CM' AND c.concept_code LIKE '648.8%')
    )
),
secondary_dx_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
    AND (
      /* ICD10CM: E08.*, E09.*, E13.* */
      (c.vocabulary_id = 'ICD10CM' AND (c.concept_code LIKE 'E08%' OR c.concept_code LIKE 'E09%' OR c.concept_code LIKE 'E13%'))
      OR
      /* ICD9CM: 249.* */
      (c.vocabulary_id = 'ICD9CM' AND c.concept_code LIKE '249%')
    )
),

/*--- LOINC measurement concepts (expand as needed per site) ---*/
a1c_loinc_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id = 'LOINC'
    AND c.concept_code IN (
      /* HbA1c */
      '4548-4',  -- Hemoglobin A1c/Hemoglobin.total in Blood
      '17856-6', -- HbA1c in Blood by HPLC (example)
      '59261-8'  -- HbA1c in Blood (example)
    )
),
glucose_loinc_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id = 'LOINC'
    AND c.concept_code IN (
      /* Common glucose LOINCs (site variation is large; add local-used ones) */
      '2345-7',  -- Glucose [Mass/volume] in Serum or Plasma
      '1558-6',  -- Glucose [Mass/volume] in Serum or Plasma -- fasting (commonly used)
      '14771-0'  -- Glucose [Mass/volume] in Blood -- fasting (example)
    )
),

/*--- RxNorm anti-diabetic drug concepts (ingredient/brand matched by name patterns) ---*/
antidiabetic_rxnorm_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id = 'RxNorm'
    AND c.standard_concept = 'S'
    AND (
      /* Biguanide */
      c.concept_name ILIKE '%metformin%' OR c.concept_name ILIKE '%glucophage%' OR c.concept_name ILIKE '%glumetza%'
      OR c.concept_name ILIKE '%fortamet%' OR c.concept_name ILIKE '%riomet%'

      /* Sulfonylureas */
      OR c.concept_name ILIKE '%glipizide%' OR c.concept_name ILIKE '%glucotrol%'
      OR c.concept_name ILIKE '%glyburide%' OR c.concept_name ILIKE '%diabeta%' OR c.concept_name ILIKE '%micronase%' OR c.concept_name ILIKE '%glynase%'
      OR c.concept_name ILIKE '%glimepiride%' OR c.concept_name ILIKE '%amaryl%'

      /* TZDs */
      OR c.concept_name ILIKE '%pioglitazone%' OR c.concept_name ILIKE '%actos%'
      OR c.concept_name ILIKE '%rosiglitazone%' OR c.concept_name ILIKE '%avandia%'

      /* DPP-4 */
      OR c.concept_name ILIKE '%sitagliptin%' OR c.concept_name ILIKE '%januvia%'
      OR c.concept_name ILIKE '%saxagliptin%' OR c.concept_name ILIKE '%onglyza%'
      OR c.concept_name ILIKE '%linagliptin%' OR c.concept_name ILIKE '%tradjenta%'
      OR c.concept_name ILIKE '%alogliptin%' OR c.concept_name ILIKE '%nesina%'

      /* GLP-1 */
      OR c.concept_name ILIKE '%liraglutide%' OR c.concept_name ILIKE '%victoza%'
      OR c.concept_name ILIKE '%semaglutide%' OR c.concept_name ILIKE '%ozempic%' OR c.concept_name ILIKE '%rybelsus%'
      OR c.concept_name ILIKE '%dulaglutide%' OR c.concept_name ILIKE '%trulicity%'
      OR c.concept_name ILIKE '%exenatide%' OR c.concept_name ILIKE '%byetta%' OR c.concept_name ILIKE '%bydureon%'

      /* SGLT2 */
      OR c.concept_name ILIKE '%empagliflozin%' OR c.concept_name ILIKE '%jardiance%'
      OR c.concept_name ILIKE '%canagliflozin%' OR c.concept_name ILIKE '%invokana%'
      OR c.concept_name ILIKE '%dapagliflozin%' OR c.concept_name ILIKE '%farxiga%'
      OR c.concept_name ILIKE '%ertugliflozin%' OR c.concept_name ILIKE '%steglatro%'

      /* Others */
      OR c.concept_name ILIKE '%repaglinide%' OR c.concept_name ILIKE '%prandin%'
      OR c.concept_name ILIKE '%nateglinide%' OR c.concept_name ILIKE '%starlix%'
      OR c.concept_name ILIKE '%acarbose%' OR c.concept_name ILIKE '%precose%'
      OR c.concept_name ILIKE '%miglitol%' OR c.concept_name ILIKE '%glyset%'

      /* Insulins (keep; T1/T2 separated via exclusion logic) */
      OR c.concept_name ILIKE '%insulin%' OR c.concept_name ILIKE '%lantus%' OR c.concept_name ILIKE '%basaglar%'
      OR c.concept_name ILIKE '%humalog%' OR c.concept_name ILIKE '%novolog%' OR c.concept_name ILIKE '%levemir%'
    )
),

/*========================
  2) EVIDENCE EXTRACTION (minimal columns; keep it narrow)
=========================*/

/*--- T2DM diagnosis events ---*/
t2dm_dx_events AS (
  SELECT co.person_id,
         co.condition_start_date AS event_date
  FROM public.condition_occurrence co
  WHERE co.condition_concept_id IN (SELECT concept_id FROM t2dm_dx_concepts)
),

/*--- Exclusion diagnosis events ---*/
t1dm_dx_events AS (
  SELECT co.person_id,
         co.condition_start_date AS event_date
  FROM public.condition_occurrence co
  WHERE co.condition_concept_id IN (SELECT concept_id FROM t1dm_dx_concepts)
),
gestational_dx_events AS (
  SELECT co.person_id,
         co.condition_start_date AS event_date
  FROM public.condition_occurrence co
  WHERE co.condition_concept_id IN (SELECT concept_id FROM gestational_dx_concepts)
),
secondary_dx_events AS (
  SELECT co.person_id,
         co.condition_start_date AS event_date
  FROM public.condition_occurrence co
  WHERE co.condition_concept_id IN (SELECT concept_id FROM secondary_dx_concepts)
),

/*--- Anti-diabetic medication exposure events ---*/
antidiabetic_drug_events AS (
  SELECT de.person_id,
         de.drug_exposure_start_date AS event_date
  FROM public.drug_exposure de
  WHERE de.drug_concept_id IN (SELECT concept_id FROM antidiabetic_rxnorm_concepts)
),

/*--- Abnormal lab events: A1c and glucose ---*/
abnormal_lab_events AS (
  SELECT m.person_id,
         m.measurement_date AS event_date,
         CASE
           WHEN m.measurement_concept_id IN (SELECT concept_id FROM a1c_loinc_concepts)
                AND m.value_as_number >= 6.5
             THEN 1
           WHEN m.measurement_concept_id IN (SELECT concept_id FROM glucose_loinc_concepts)
                AND m.value_as_number >= 200
             THEN 1
           /* Optional: if you reliably know fasting vs random, add fasting >=126 here */
           ELSE 0
         END AS is_abnormal
  FROM public.measurement m
  WHERE m.measurement_concept_id IN (
    SELECT concept_id FROM a1c_loinc_concepts
    UNION
    SELECT concept_id FROM glucose_loinc_concepts
  )
  AND m.value_as_number IS NOT NULL
),

/* Keep only abnormal labs */
abnormal_labs AS (
  SELECT person_id, event_date
  FROM abnormal_lab_events
  WHERE is_abnormal = 1
),

/*========================
  3) RULE LOGIC (AND / OR / NOT)
=========================*/

/* Rule A: >=2 T2DM dx on different dates */
rule_a AS (
  SELECT person_id
  FROM t2dm_dx_events
  GROUP BY person_id
  HAVING COUNT(DISTINCT event_date) >= 2
),

/* Rule B: 1+ T2DM dx AND 1+ anti-diabetic drug */
rule_b AS (
  SELECT DISTINCT d.person_id
  FROM t2dm_dx_events d
  JOIN antidiabetic_drug_events rx
    ON rx.person_id = d.person_id
),

/* Rule C: 1+ abnormal lab AND 1+ anti-diabetic drug */
rule_c AS (
  SELECT DISTINCT l.person_id
  FROM abnormal_labs l
  JOIN antidiabetic_drug_events rx
    ON rx.person_id = l.person_id
),

/* Optional Rule D: >=2 abnormal labs on different dates (lab-only capture) */
rule_d AS (
  SELECT person_id
  FROM abnormal_labs
  GROUP BY person_id
  HAVING COUNT(DISTINCT event_date) >= 2
),

/* Combine inclusion rules (OR) */
included_candidates AS (
  SELECT person_id FROM rule_a
  UNION
  SELECT person_id FROM rule_b
  UNION
  SELECT person_id FROM rule_c
  UNION
  SELECT person_id FROM rule_d
),

/* Exclusion flags */
exclusions AS (
  SELECT p.person_id,
         CASE WHEN EXISTS (SELECT 1 FROM gestational_dx_events g WHERE g.person_id = p.person_id) THEN 1 ELSE 0 END AS has_gestational,
         CASE WHEN EXISTS (SELECT 1 FROM secondary_dx_events s WHERE s.person_id = p.person_id) THEN 1 ELSE 0 END AS has_secondary,
         CASE WHEN EXISTS (SELECT 1 FROM t1dm_dx_events t1 WHERE t1.person_id = p.person_id) THEN 1 ELSE 0 END AS has_t1,
         CASE WHEN EXISTS (SELECT 1 FROM t2dm_dx_events t2 WHERE t2.person_id = p.person_id) THEN 1 ELSE 0 END AS has_t2
  FROM public.person p
),

/* Apply NOT exclusions:
   - Exclude gestational-only
   - Exclude secondary diabetes-only
   - Exclude “T1 without T2 evidence” (simple dominance rule)
*/
final_t2dm_cases AS (
  SELECT c.person_id
  FROM included_candidates c
  JOIN exclusions e
    ON e.person_id = c.person_id
  WHERE
    /* NOT gestational diabetes */
    e.has_gestational = 0
    /* NOT secondary diabetes */
    AND e.has_secondary = 0
    /* NOT (T1 present AND no T2 evidence) */
    AND NOT (e.has_t1 = 1 AND e.has_t2 = 0)
),

/* Index date: earliest evidence among (T2 dx, abnormal lab, antidiabetic drug) */
index_events AS (
  SELECT person_id, event_date FROM t2dm_dx_events
  UNION ALL
  SELECT person_id, event_date FROM abnormal_labs
  UNION ALL
  SELECT person_id, event_date FROM antidiabetic_drug_events
),
index_date AS (
  SELECT person_id, MIN(event_date) AS index_date
  FROM index_events
  GROUP BY person_id
)

SELECT f.person_id,
       i.index_date
FROM final_t2dm_cases f
JOIN index_date i
  ON i.person_id = f.person_id
ORDER BY f.person_id;

