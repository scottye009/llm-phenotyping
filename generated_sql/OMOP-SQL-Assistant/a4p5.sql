WITH
/* 1) ICD9CM / ICD10CM source concepts indicating type 2 diabetes */
t2dm_icd_source AS (
    SELECT
        c.concept_id AS source_concept_id
    FROM public.concept c
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND c.invalid_reason IS NULL
      AND (
            /* ICD9CM: 250.x0 or 250.x2 = type II or unspecified type */
            (c.vocabulary_id = 'ICD9CM'
             AND c.concept_code ~ '^250\.?[0-9][02]$')

            OR

            /* ICD10CM: E11.* = type 2 diabetes mellitus */
            (c.vocabulary_id = 'ICD10CM'
             AND c.concept_code ~ '^E11(\.|$)')
          )
),

/* 2) Map ICD source concepts to standard OMOP condition concepts */
t2dm_standard_conditions AS (
    SELECT DISTINCT
        cr.concept_id_2 AS condition_concept_id
    FROM t2dm_icd_source s
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = s.source_concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
),

/* 3) Type 2 diabetes diagnosis events */
t2dm_dx AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date AS event_date
    FROM public.condition_occurrence co
    JOIN t2dm_standard_conditions t2
      ON t2.condition_concept_id = co.condition_concept_id
    WHERE co.condition_start_date IS NOT NULL
),

/* 4) Exclusion concepts: type 1, gestational, secondary, neonatal, or pregnancy-related diabetes */
exclusion_icd_source AS (
    SELECT
        c.concept_id AS source_concept_id
    FROM public.concept c
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND c.invalid_reason IS NULL
      AND (
            /* ICD9CM type 1 diabetes: 250.x1 or 250.x3 */
            (c.vocabulary_id = 'ICD9CM'
             AND c.concept_code ~ '^250\.?[0-9][13]$')

            OR

            /* ICD10CM exclusions */
            (c.vocabulary_id = 'ICD10CM'
             AND (
                    c.concept_code ~ '^E10(\.|$)'   -- type 1 diabetes
                 OR c.concept_code ~ '^E08(\.|$)'   -- diabetes due to underlying condition
                 OR c.concept_code ~ '^E09(\.|$)'   -- drug/chemical induced diabetes
                 OR c.concept_code ~ '^E13(\.|$)'   -- other specified diabetes
                 OR c.concept_code ~ '^O24(\.|$)'   -- diabetes in pregnancy
                 OR c.concept_code ~ '^P70\.2$'     -- neonatal diabetes
                 )
            )
          )
),

/* 5) Map exclusion ICD concepts to standard OMOP condition concepts */
exclusion_standard_conditions AS (
    SELECT DISTINCT
        cr.concept_id_2 AS condition_concept_id
    FROM exclusion_icd_source s
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = s.source_concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
),

/* 6) Exclusion diagnosis events */
exclusion_dx AS (
    SELECT DISTINCT
        co.person_id
    FROM public.condition_occurrence co
    JOIN exclusion_standard_conditions e
      ON e.condition_concept_id = co.condition_concept_id
),

/* 7) Non-insulin type 2 diabetes medication seed concepts, using generic and brand names */
t2dm_drug_seeds AS (
    SELECT DISTINCT
        c.concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Drug'
      AND c.invalid_reason IS NULL
      AND (
            c.concept_name ~* 'metformin|glucophage|fortamet|glumetza|riomet'
         OR c.concept_name ~* 'glyburide|glibenclamide|glipizide|glimepiride|chlorpropamide|tolbutamide|tolazamide|glynase|diabeta|micronase|glucotrol|amaryl'
         OR c.concept_name ~* 'pioglitazone|rosiglitazone|actos|avandia'
         OR c.concept_name ~* 'sitagliptin|saxagliptin|linagliptin|alogliptin|januvia|onglyza|tradjenta|nesina'
         OR c.concept_name ~* 'canagliflozin|dapagliflozin|empagliflozin|ertugliflozin|invokana|farxiga|jardiance|steglatro'
         OR c.concept_name ~* 'exenatide|liraglutide|dulaglutide|semaglutide|lixisenatide|byetta|bydureon|victoza|trulicity|ozempic|rybelsus|adlyxin'
         OR c.concept_name ~* 'acarbose|miglitol|precose|glyset'
         OR c.concept_name ~* 'repaglinide|nateglinide|prandin|starlix'
         OR c.concept_name ~* 'colesevelam|bromocriptine|welchol|cycloset'
          )
      AND c.concept_name !~* 'insulin'
),

/* 8) Expand medication concepts through OMOP ancestry where available */
t2dm_drug_concepts AS (
    SELECT concept_id AS drug_concept_id
    FROM t2dm_drug_seeds

    UNION

    SELECT ca.descendant_concept_id AS drug_concept_id
    FROM t2dm_drug_seeds s
    JOIN public.concept_ancestor ca
      ON ca.ancestor_concept_id = s.concept_id
),

/* 9) Medication evidence */
t2dm_med AS (
    SELECT DISTINCT
        de.person_id,
        de.drug_exposure_start_date AS event_date
    FROM public.drug_exposure de
    JOIN t2dm_drug_concepts dc
      ON dc.drug_concept_id = de.drug_concept_id
    WHERE de.drug_exposure_start_date IS NOT NULL
),

/* 10) Lab concept identification using OMOP/LOINC concept names and codes */
lab_concepts AS (
    SELECT
        c.concept_id AS measurement_concept_id,
        CASE
            WHEN c.concept_code IN ('4548-4', '4549-2', '17856-6', '59261-8')
              OR c.concept_name ~* 'hemoglobin A1c|HbA1c|glycohemoglobin'
            THEN 'A1C'

            WHEN c.concept_code IN ('2345-7', '1558-6', '14749-6', '14995-5', '2339-0', '41653-7')
              OR c.concept_name ~* 'glucose'
            THEN 'GLUCOSE'
        END AS lab_type
    FROM public.concept c
    WHERE c.domain_id = 'Measurement'
      AND c.invalid_reason IS NULL
      AND (
            c.concept_code IN (
                '4548-4', '4549-2', '17856-6', '59261-8',
                '2345-7', '1558-6', '14749-6', '14995-5', '2339-0', '41653-7'
            )
         OR c.concept_name ~* 'hemoglobin A1c|HbA1c|glycohemoglobin|glucose'
          )
),

/* 11) Abnormal lab evidence consistent with diabetes */
t2dm_lab AS (
    SELECT DISTINCT
        m.person_id,
        m.measurement_date AS event_date
    FROM public.measurement m
    JOIN lab_concepts lc
      ON lc.measurement_concept_id = m.measurement_concept_id
    WHERE m.measurement_date IS NOT NULL
      AND m.value_as_number IS NOT NULL
      AND (
            /* HbA1c >= 6.5% */
            (lc.lab_type = 'A1C'
             AND m.value_as_number >= 6.5)

            OR

            /* Glucose >= 200 mg/dL, or fasting glucose >= 126 mg/dL if concept name/code indicates fasting */
            (lc.lab_type = 'GLUCOSE'
             AND (
                    m.value_as_number >= 200
                 OR (
                        m.value_as_number >= 126
                    AND EXISTS (
                        SELECT 1
                        FROM public.concept gc
                        WHERE gc.concept_id = m.measurement_concept_id
                          AND gc.concept_name ~* 'fasting'
                    )
                 )
             )
             AND (
                    m.unit_concept_id = 8840
                 OR m.unit_source_value ~* 'mg/dL'
                 OR m.unit_source_value IS NULL
                 )
            )
          )
),

/* 12) Count independent evidence types per person */
person_evidence AS (
    SELECT
        p.person_id,

        COUNT(DISTINCT d.event_date) AS t2dm_dx_dates,

        MAX(CASE WHEN m.person_id IS NOT NULL THEN 1 ELSE 0 END) AS has_t2dm_med,

        MAX(CASE WHEN l.person_id IS NOT NULL THEN 1 ELSE 0 END) AS has_diabetes_lab
    FROM public.person p
    LEFT JOIN t2dm_dx d
      ON d.person_id = p.person_id
    LEFT JOIN t2dm_med m
      ON m.person_id = p.person_id
    LEFT JOIN t2dm_lab l
      ON l.person_id = p.person_id
    GROUP BY p.person_id
)

/* Final phenotype:
   Include patients with repeated T2DM diagnosis OR diagnosis plus medication/lab evidence.
   Exclude patients with mapped type 1, gestational, secondary, neonatal, or pregnancy-related diabetes codes. */
SELECT
    pe.person_id
FROM person_evidence pe
WHERE (
        pe.t2dm_dx_dates >= 2
     OR (pe.t2dm_dx_dates >= 1 AND pe.has_t2dm_med = 1)
     OR (pe.t2dm_dx_dates >= 1 AND pe.has_diabetes_lab = 1)
      )
  AND NOT EXISTS (
        SELECT 1
        FROM exclusion_dx ex
        WHERE ex.person_id = pe.person_id
      )
ORDER BY pe.person_id;