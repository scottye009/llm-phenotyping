WITH
/* -----------------------------
   1) ICD diagnosis concept sets
   ----------------------------- */

t2d_icd_source_concepts AS (
    SELECT
        concept_id
    FROM public.concept
    WHERE vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (
            /* ICD10CM Type 2 diabetes mellitus */
            (vocabulary_id = 'ICD10CM' AND concept_code ~ '^E11(\.|$)')

            OR

            /* ICD9CM diabetes codes where 5th digit 0 or 2 = type II or unspecified type */
            (vocabulary_id = 'ICD9CM' AND concept_code ~ '^250(\.[0-9][02]|[0-9][02])$')
          )
),

t2d_mapped_condition_concepts AS (
    SELECT DISTINCT
        cr.concept_id_2 AS condition_concept_id
    FROM t2d_icd_source_concepts src
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = src.concept_id
     AND cr.relationship_id = 'Maps to'
),

exclusion_icd_source_concepts AS (
    SELECT
        concept_id
    FROM public.concept
    WHERE vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (
            /* Type 1 diabetes */
            (vocabulary_id = 'ICD10CM' AND concept_code ~ '^E10(\.|$)')
         OR (vocabulary_id = 'ICD9CM'  AND concept_code ~ '^250(\.[0-9][13]|[0-9][13])$')

            /* Diabetes due to underlying condition, drug/chemical induced, other specified */
         OR (vocabulary_id = 'ICD10CM' AND concept_code ~ '^E0[89](\.|$)')
         OR (vocabulary_id = 'ICD10CM' AND concept_code ~ '^E13(\.|$)')
         OR (vocabulary_id = 'ICD9CM'  AND concept_code ~ '^249(\.|$|[0-9])')

            /* Gestational diabetes */
         OR (vocabulary_id = 'ICD10CM' AND concept_code ~ '^O24\.4')
         OR (vocabulary_id = 'ICD9CM'  AND concept_code ~ '^648\.8')
          )
),

exclusion_mapped_condition_concepts AS (
    SELECT DISTINCT
        cr.concept_id_2 AS condition_concept_id
    FROM exclusion_icd_source_concepts src
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = src.concept_id
     AND cr.relationship_id = 'Maps to'
),

/* -----------------------------
   2) Diagnosis evidence
   ----------------------------- */

t2d_dx_events AS (
    SELECT
        co.person_id,
        co.condition_start_date AS evidence_date
    FROM public.condition_occurrence co
    JOIN t2d_mapped_condition_concepts dx
      ON co.condition_concept_id = dx.condition_concept_id
    WHERE co.condition_start_date IS NOT NULL
),

exclusion_dx_events AS (
    SELECT
        co.person_id,
        co.condition_start_date AS evidence_date
    FROM public.condition_occurrence co
    JOIN exclusion_mapped_condition_concepts ex
      ON co.condition_concept_id = ex.condition_concept_id
    WHERE co.condition_start_date IS NOT NULL
),

/* -----------------------------
   3) Medication concept sets
   ----------------------------- */

non_insulin_med_seed_concepts AS (
    SELECT
        concept_id
    FROM public.concept
    WHERE domain_id = 'Drug'
      AND concept_name ~* (
            'metformin|glucophage|fortamet|glumetza|riomet|'
         || 'sitagliptin|januvia|janumet|linagliptin|tradjenta|saxagliptin|onglyza|alogliptin|nesina|'
         || 'empagliflozin|jardiance|dapagliflozin|farxiga|canagliflozin|invokana|ertugliflozin|steglatro|'
         || 'semaglutide|ozempic|rybelsus|liraglutide|victoza|dulaglutide|trulicity|exenatide|byetta|bydureon|tirzepatide|mounjaro|'
         || 'pioglitazone|actos|rosiglitazone|avandia|'
         || 'glipizide|glucotrol|glyburide|diabeta|glynase|micronase|glimepiride|amaryl|'
         || 'repaglinide|prandin|nateglinide|starlix|'
         || 'acarbose|precose|miglitol|glyset'
      )
),

non_insulin_med_concepts AS (
    SELECT DISTINCT
        descendant_concept_id AS drug_concept_id
    FROM public.concept_ancestor ca
    JOIN non_insulin_med_seed_concepts s
      ON ca.ancestor_concept_id = s.concept_id

    UNION

    SELECT DISTINCT
        concept_id AS drug_concept_id
    FROM non_insulin_med_seed_concepts
),

insulin_med_seed_concepts AS (
    SELECT
        concept_id
    FROM public.concept
    WHERE domain_id = 'Drug'
      AND concept_name ~* (
            'insulin|lantus|humalog|novolog|levemir|tresiba|basaglar|toujeo|apidra'
      )
),

insulin_med_concepts AS (
    SELECT DISTINCT
        descendant_concept_id AS drug_concept_id
    FROM public.concept_ancestor ca
    JOIN insulin_med_seed_concepts s
      ON ca.ancestor_concept_id = s.concept_id

    UNION

    SELECT DISTINCT
        concept_id AS drug_concept_id
    FROM insulin_med_seed_concepts
),

non_insulin_med_events AS (
    SELECT
        de.person_id,
        de.drug_exposure_start_date AS evidence_date
    FROM public.drug_exposure de
    JOIN non_insulin_med_concepts dm
      ON de.drug_concept_id = dm.drug_concept_id
    WHERE de.drug_exposure_start_date IS NOT NULL
),

insulin_med_events AS (
    SELECT
        de.person_id,
        de.drug_exposure_start_date AS evidence_date
    FROM public.drug_exposure de
    JOIN insulin_med_concepts im
      ON de.drug_concept_id = im.drug_concept_id
    WHERE de.drug_exposure_start_date IS NOT NULL
),

/* -----------------------------
   4) Lab concept sets
   ----------------------------- */

a1c_concepts AS (
    SELECT
        concept_id AS measurement_concept_id
    FROM public.concept
    WHERE domain_id = 'Measurement'
      AND (
            concept_code IN ('4548-4', '17856-6', '41995-2')
         OR concept_name ~* '(hemoglobin a1c|hba1c|glycated hemoglobin)'
      )
),

fasting_glucose_concepts AS (
    SELECT
        concept_id AS measurement_concept_id
    FROM public.concept
    WHERE domain_id = 'Measurement'
      AND (
            concept_code IN ('1558-6', '14749-6', '1557-8')
         OR concept_name ~* '(fasting.*glucose|glucose.*fasting)'
      )
),

blood_glucose_concepts AS (
    SELECT
        concept_id AS measurement_concept_id
    FROM public.concept
    WHERE domain_id = 'Measurement'
      AND concept_name ~* 'glucose'
      AND concept_name !~* 'urine|cerebrospinal|csf'
),

abnormal_lab_events AS (
    /* HbA1c >= 6.5% */
    SELECT
        m.person_id,
        m.measurement_date AS evidence_date,
        'a1c' AS lab_type
    FROM public.measurement m
    JOIN a1c_concepts c
      ON m.measurement_concept_id = c.measurement_concept_id
    WHERE m.measurement_date IS NOT NULL
      AND m.value_as_number IS NOT NULL
      AND m.value_as_number >= 6.5

    UNION ALL

    /* Fasting glucose >= 126 mg/dL */
    SELECT
        m.person_id,
        m.measurement_date AS evidence_date,
        'fasting_glucose' AS lab_type
    FROM public.measurement m
    JOIN fasting_glucose_concepts c
      ON m.measurement_concept_id = c.measurement_concept_id
    WHERE m.measurement_date IS NOT NULL
      AND m.value_as_number IS NOT NULL
      AND m.value_as_number >= 126

    UNION ALL

    /* Random or unspecified blood glucose >= 200 mg/dL */
    SELECT
        m.person_id,
        m.measurement_date AS evidence_date,
        'random_glucose' AS lab_type
    FROM public.measurement m
    JOIN blood_glucose_concepts c
      ON m.measurement_concept_id = c.measurement_concept_id
    WHERE m.measurement_date IS NOT NULL
      AND m.value_as_number IS NOT NULL
      AND m.value_as_number >= 200
),

/* -----------------------------
   5) Person-level evidence summary
   ----------------------------- */

all_candidate_evidence AS (
    SELECT person_id, evidence_date, 't2d_dx' AS evidence_type
    FROM t2d_dx_events

    UNION ALL

    SELECT person_id, evidence_date, 'non_insulin_med' AS evidence_type
    FROM non_insulin_med_events

    UNION ALL

    SELECT person_id, evidence_date, 'insulin_med' AS evidence_type
    FROM insulin_med_events

    UNION ALL

    SELECT person_id, evidence_date, 'abnormal_lab' AS evidence_type
    FROM abnormal_lab_events
),

person_summary AS (
    SELECT
        p.person_id,
        MIN(e.evidence_date) AS index_date,

        COUNT(DISTINCT CASE WHEN e.evidence_type = 't2d_dx' THEN e.evidence_date END) AS t2d_dx_dates,
        COUNT(DISTINCT CASE WHEN e.evidence_type = 'non_insulin_med' THEN e.evidence_date END) AS non_insulin_med_dates,
        COUNT(DISTINCT CASE WHEN e.evidence_type = 'insulin_med' THEN e.evidence_date END) AS insulin_med_dates,
        COUNT(DISTINCT CASE WHEN e.evidence_type = 'abnormal_lab' THEN e.evidence_date END) AS abnormal_lab_dates
    FROM public.person p
    JOIN all_candidate_evidence e
      ON p.person_id = e.person_id
    GROUP BY
        p.person_id
),

included_candidates AS (
    SELECT
        ps.*
    FROM person_summary ps
    WHERE
        /* Diagnosis-based phenotype */
        ps.t2d_dx_dates >= 1

        OR

        /* Treatment + biochemical evidence */
        (
            ps.non_insulin_med_dates >= 1
            AND ps.abnormal_lab_dates >= 1
        )

        OR

        /* Repeated abnormal labs on different dates */
        ps.abnormal_lab_dates >= 2
),

excluded_people AS (
    SELECT DISTINCT
        ic.person_id
    FROM included_candidates ic
    JOIN exclusion_dx_events ex
      ON ic.person_id = ex.person_id
     AND ex.evidence_date <= ic.index_date
)

/* -----------------------------
   Final T2D phenotype cohort
   ----------------------------- */

SELECT
    ic.person_id,
    ic.index_date,
    ic.t2d_dx_dates,
    ic.non_insulin_med_dates,
    ic.insulin_med_dates,
    ic.abnormal_lab_dates
FROM included_candidates ic
LEFT JOIN excluded_people ex
  ON ic.person_id = ex.person_id
WHERE ex.person_id IS NULL
ORDER BY
    ic.person_id;