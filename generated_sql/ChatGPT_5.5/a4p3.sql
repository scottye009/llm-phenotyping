WITH
/* -----------------------------
   1) ICD diagnosis concept sets
   ----------------------------- */

/* ICD10CM E11 = type 2 diabetes.
   ICD9CM 250.x0 / 250.x2 = type 2 or unspecified type, not stated as type 1. */
t2_icd_source_concepts AS (
    SELECT
        concept_id
    FROM public.concept
    WHERE
        (
            vocabulary_id = 'ICD10CM'
            AND UPPER(concept_code) LIKE 'E11%'
        )
        OR (
            vocabulary_id = 'ICD9CM'
            AND REPLACE(concept_code, '.', '') ~ '^250[0-9][02]$'
        )
),

/* Exclusion diagnoses:
   ICD10CM E10 = type 1 diabetes
   ICD10CM E08/E09/E13 = secondary/other specified diabetes
   ICD10CM O24 = diabetes in pregnancy/gestational diabetes
   ICD9CM 250.x1 / 250.x3 = type 1 diabetes */
exclusion_icd_source_concepts AS (
    SELECT
        concept_id
    FROM public.concept
    WHERE
        (
            vocabulary_id = 'ICD10CM'
            AND (
                UPPER(concept_code) LIKE 'E10%'
                OR UPPER(concept_code) LIKE 'E08%'
                OR UPPER(concept_code) LIKE 'E09%'
                OR UPPER(concept_code) LIKE 'E13%'
                OR UPPER(concept_code) LIKE 'O24%'
            )
        )
        OR (
            vocabulary_id = 'ICD9CM'
            AND REPLACE(concept_code, '.', '') ~ '^250[0-9][13]$'
        )
),

/* Map source ICD concepts to standard OMOP concepts before matching condition_concept_id. */
t2_mapped_condition_concepts AS (
    SELECT DISTINCT
        cr.concept_id_2 AS condition_concept_id
    FROM t2_icd_source_concepts s
    JOIN public.concept_relationship cr
        ON cr.concept_id_1 = s.concept_id
       AND cr.relationship_id = 'Maps to'
),

exclusion_mapped_condition_concepts AS (
    SELECT DISTINCT
        cr.concept_id_2 AS condition_concept_id
    FROM exclusion_icd_source_concepts s
    JOIN public.concept_relationship cr
        ON cr.concept_id_1 = s.concept_id
       AND cr.relationship_id = 'Maps to'
),

/* -----------------------------
   2) Clinical diagnosis events
   ----------------------------- */

t2_dx_events AS (
    SELECT
        co.person_id,
        co.condition_start_date AS event_date,
        't2_diagnosis' AS evidence_type
    FROM public.condition_occurrence co
    JOIN t2_mapped_condition_concepts t2
        ON co.condition_concept_id = t2.condition_concept_id
    WHERE
        co.condition_start_date IS NOT NULL
),

exclusion_dx_events AS (
    SELECT
        co.person_id,
        co.condition_start_date AS event_date
    FROM public.condition_occurrence co
    JOIN exclusion_mapped_condition_concepts ex
        ON co.condition_concept_id = ex.condition_concept_id
    WHERE
        co.condition_start_date IS NOT NULL
),

/* -----------------------------
   3) Non-insulin diabetes medication evidence
   ----------------------------- */

diabetes_drug_seed_concepts AS (
    SELECT
        concept_id
    FROM public.concept
    WHERE
        domain_id = 'Drug'
        AND (
            /* Generic names */
            LOWER(concept_name) ~
            '(metformin|glyburide|glipizide|glimepiride|pioglitazone|rosiglitazone|sitagliptin|saxagliptin|linagliptin|alogliptin|empagliflozin|dapagliflozin|canagliflozin|ertugliflozin|liraglutide|semaglutide|dulaglutide|exenatide|tirzepatide|acarbose|miglitol|repaglinide|nateglinide)'

            /* Common brand names */
            OR LOWER(concept_name) ~
            '(glucophage|fortamet|glumetza|glyburide|diabeta|glynase|glucotrol|amaryl|actos|avandia|januvia|onglyza|tradjenta|nesina|jardiance|farxiga|invokana|steglatro|victoza|ozempic|rybelsus|trulicity|byetta|bydureon|mounjaro|precose|glyset|prandin|starlix)'
        )
),

diabetes_drug_concepts AS (
    SELECT DISTINCT
        concept_id AS drug_concept_id
    FROM diabetes_drug_seed_concepts

    UNION

    SELECT DISTINCT
        ca.descendant_concept_id AS drug_concept_id
    FROM diabetes_drug_seed_concepts s
    JOIN public.concept_ancestor ca
        ON ca.ancestor_concept_id = s.concept_id
),

med_events AS (
    SELECT
        de.person_id,
        de.drug_exposure_start_date AS event_date,
        'diabetes_medication' AS evidence_type
    FROM public.drug_exposure de
    JOIN diabetes_drug_concepts dc
        ON de.drug_concept_id = dc.drug_concept_id
    WHERE
        de.drug_exposure_start_date IS NOT NULL
),

/* -----------------------------
   4) Diabetes-range lab evidence
   ----------------------------- */

lab_events AS (
    SELECT
        m.person_id,
        m.measurement_date AS event_date,
        'abnormal_diabetes_lab' AS evidence_type
    FROM public.measurement m
    LEFT JOIN public.concept c
        ON m.measurement_concept_id = c.concept_id
    WHERE
        m.measurement_date IS NOT NULL
        AND m.value_as_number IS NOT NULL
        AND (
            /* A1c >= 6.5% */
            (
                (
                    LOWER(COALESCE(c.concept_name, '')) ~ '(a1c|hba1c|hemoglobin a1c|glycated hemoglobin)'
                    OR m.measurement_source_value IN ('4548-4', '17856-6', '59261-8')
                    OR COALESCE(c.concept_code, '') IN ('4548-4', '17856-6', '59261-8')
                )
                AND m.value_as_number >= 6.5
            )

            OR

            /* Fasting glucose >= 126 mg/dL */
            (
                (
                    LOWER(COALESCE(c.concept_name, '')) ~ '(fasting).*glucose|glucose.*(fasting)'
                    OR m.measurement_source_value IN ('1558-6', '1556-0', '14771-0')
                    OR COALESCE(c.concept_code, '') IN ('1558-6', '1556-0', '14771-0')
                )
                AND m.value_as_number >= 126
            )

            OR

            /* 2-hour OGTT glucose >= 200 mg/dL */
            (
                (
                    LOWER(COALESCE(c.concept_name, '')) ~ '(2 hour|2-hour|two hour|oral glucose tolerance|ogtt)'
                    OR m.measurement_source_value IN ('1518-0', '20436-2')
                    OR COALESCE(c.concept_code, '') IN ('1518-0', '20436-2')
                )
                AND m.value_as_number >= 200
            )

            OR

            /* Random/general serum or plasma glucose >= 200 mg/dL */
            (
                (
                    LOWER(COALESCE(c.concept_name, '')) ~ 'glucose'
                    OR m.measurement_source_value IN ('2345-7')
                    OR COALESCE(c.concept_code, '') IN ('2345-7')
                )
                AND m.value_as_number >= 200
            )
        )
),

/* -----------------------------
   5) Combine evidence
   ----------------------------- */

person_evidence_summary AS (
    SELECT
        p.person_id,

        COUNT(DISTINCT dx.event_date) AS t2_dx_dates,
        MIN(dx.event_date) AS first_t2_dx_date,

        COUNT(DISTINCT med.event_date) AS med_dates,
        MIN(med.event_date) AS first_med_date,

        COUNT(DISTINCT lab.event_date) AS abnormal_lab_dates,
        MIN(lab.event_date) AS first_abnormal_lab_date
    FROM public.person p
    LEFT JOIN t2_dx_events dx
        ON p.person_id = dx.person_id
    LEFT JOIN med_events med
        ON p.person_id = med.person_id
    LEFT JOIN lab_events lab
        ON p.person_id = lab.person_id
    GROUP BY
        p.person_id
),

candidate_cohort AS (
    SELECT
        person_id,
        CASE
            WHEN t2_dx_dates >= 1
                THEN first_t2_dx_date
            WHEN med_dates >= 1 AND abnormal_lab_dates >= 1
                THEN LEAST(first_med_date, first_abnormal_lab_date)
            WHEN abnormal_lab_dates >= 2
                THEN first_abnormal_lab_date
        END AS index_date,
        t2_dx_dates,
        med_dates,
        abnormal_lab_dates
    FROM person_evidence_summary
    WHERE
        t2_dx_dates >= 1
        OR (med_dates >= 1 AND abnormal_lab_dates >= 1)
        OR abnormal_lab_dates >= 2
),

/* Exclude lab/med-only cases that have only exclusion diabetes diagnoses before/on index date. */
final_cohort AS (
    SELECT
        c.person_id,
        c.index_date
    FROM candidate_cohort c
    WHERE
        NOT (
            c.t2_dx_dates = 0
            AND EXISTS (
                SELECT 1
                FROM exclusion_dx_events ex
                WHERE
                    ex.person_id = c.person_id
                    AND ex.event_date <= c.index_date
            )
            AND NOT EXISTS (
                SELECT 1
                FROM t2_dx_events dx
                WHERE
                    dx.person_id = c.person_id
                    AND dx.event_date <= c.index_date
            )
        )
)

SELECT
    person_id,
    index_date
FROM final_cohort
ORDER BY
    person_id;