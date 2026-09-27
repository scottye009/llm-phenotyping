WITH
/* 1) ICD9CM / ICD10CM source concepts for type 2 diabetes */
t2dm_icd_source AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND c.invalid_reason IS NULL
      AND (
            /* ICD10CM E11.* = type 2 diabetes mellitus */
            (c.vocabulary_id = 'ICD10CM' AND c.concept_code ~* '^E11(\.|$)')
            OR
            /* ICD9CM 250.x0 / 250.x2 = type 2 or unspecified type, not uncontrolled/controlled pattern */
            (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~* '^250\.?[0-9][02]$')
          )
),

/* 2) Map ICD concepts to OMOP standard condition concepts */
t2dm_condition_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS condition_concept_id
    FROM t2dm_icd_source s
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = s.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
),

/* 3) T2DM diagnosis evidence from condition_occurrence */
t2dm_dx AS (
    SELECT
        co.person_id,
        co.condition_start_date AS event_date
    FROM public.condition_occurrence co
    JOIN t2dm_condition_concepts cs
      ON cs.condition_concept_id = co.condition_concept_id
    WHERE co.condition_start_date IS NOT NULL
),

t2dm_dx_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS t2dm_dx_dates,
        MIN(event_date) AS first_t2dm_dx_date
    FROM t2dm_dx
    GROUP BY person_id
),

/* 4) Non-insulin type 2 diabetes medication concepts, generic + common brand names */
t2dm_med_seed AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Drug'
      AND c.standard_concept = 'S'
      AND c.invalid_reason IS NULL
      AND c.concept_name ~* (
            'metformin|glucophage|fortamet|glumetza|riomet|' ||
            'glyburide|glibenclamide|glipizide|glimepiride|chlorpropamide|tolazamide|tolbutamide|' ||
            'diabeta|micronase|glynase|glucotrol|amaryl|' ||
            'pioglitazone|rosiglitazone|actos|avandia|' ||
            'sitagliptin|saxagliptin|linagliptin|alogliptin|januvia|onglyza|tradjenta|nesina|' ||
            'canagliflozin|dapagliflozin|empagliflozin|ertugliflozin|invokana|farxiga|jardiance|steglatro|' ||
            'liraglutide|semaglutide|dulaglutide|exenatide|lixisenatide|tirzepatide|' ||
            'victoza|ozempic|rybelsus|trulicity|byetta|bydureon|mounjaro|' ||
            'acarbose|miglitol|precose|glyset|' ||
            'repaglinide|nateglinide|prandin|starlix|' ||
            'bromocriptine|cycloset|colesevelam|welchol'
          )
      AND c.concept_name !~* 'insulin'
),

t2dm_med_concepts AS (
    SELECT concept_id AS drug_concept_id
    FROM t2dm_med_seed

    UNION

    SELECT ca.descendant_concept_id AS drug_concept_id
    FROM public.concept_ancestor ca
    JOIN t2dm_med_seed s
      ON s.concept_id = ca.ancestor_concept_id
),

/* 5) Medication evidence */
t2dm_med AS (
    SELECT
        de.person_id,
        de.drug_exposure_start_date AS event_date
    FROM public.drug_exposure de
    JOIN t2dm_med_concepts mc
      ON mc.drug_concept_id = de.drug_concept_id
    WHERE de.drug_exposure_start_date IS NOT NULL
),

t2dm_med_summary AS (
    SELECT
        person_id,
        COUNT(*) AS t2dm_med_count,
        MIN(event_date) AS first_t2dm_med_date
    FROM t2dm_med
    GROUP BY person_id
),

/* 6) Lab measurement concept sets using LOINC codes and OMOP names */
lab_concepts AS (
    SELECT
        c.concept_id AS measurement_concept_id,
        CASE
            WHEN c.concept_code IN ('4548-4', '17856-6', '4549-2', '17855-8', '41995-2', '59261-8')
              OR c.concept_name ~* 'hemoglobin A1c|HbA1c|glycohemoglobin'
                THEN 'A1C'

            WHEN c.concept_code IN ('1558-6', '1557-8', '14770-2')
              OR c.concept_name ~* 'glucose.*fasting|fasting.*glucose'
                THEN 'FASTING_GLUCOSE'

            WHEN c.concept_code IN ('1518-0', '20436-2')
              OR c.concept_name ~* 'glucose.*2 hour|2 hour.*glucose|oral glucose tolerance|OGTT'
                THEN 'TWO_HOUR_GLUCOSE'

            WHEN c.concept_code IN ('2345-7', '2339-0')
              OR (
                    c.concept_name ~* 'glucose'
                AND c.concept_name !~* 'urine'
                AND c.concept_name !~* 'fasting|2 hour|two hour|OGTT|tolerance'
              )
                THEN 'RANDOM_GLUCOSE'
        END AS lab_type
    FROM public.concept c
    WHERE c.domain_id = 'Measurement'
      AND c.standard_concept = 'S'
      AND c.invalid_reason IS NULL
      AND (
            c.concept_code IN (
                '4548-4', '17856-6', '4549-2', '17855-8', '41995-2', '59261-8',
                '1558-6', '1557-8', '14770-2',
                '1518-0', '20436-2',
                '2345-7', '2339-0'
            )
            OR c.concept_name ~* 'hemoglobin A1c|HbA1c|glycohemoglobin|glucose'
          )
),

/* 7) Diabetes-range lab evidence */
diabetes_labs AS (
    SELECT
        m.person_id,
        m.measurement_date AS event_date
    FROM public.measurement m
    JOIN lab_concepts lc
      ON lc.measurement_concept_id = m.measurement_concept_id
    WHERE m.measurement_date IS NOT NULL
      AND m.value_as_number IS NOT NULL
      AND (
            /* HbA1c diagnostic threshold */
            (lc.lab_type = 'A1C' AND m.value_as_number >= 6.5)

            /* Plasma/serum glucose diagnostic thresholds in mg/dL */
            OR (lc.lab_type = 'FASTING_GLUCOSE' AND m.value_as_number >= 126)
            OR (lc.lab_type = 'TWO_HOUR_GLUCOSE' AND m.value_as_number >= 200)
            OR (lc.lab_type = 'RANDOM_GLUCOSE' AND m.value_as_number >= 200)
          )
),

diabetes_lab_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS abnormal_lab_dates,
        MIN(event_date) AS first_abnormal_lab_date
    FROM diabetes_labs
    GROUP BY person_id
),

/* 8) Exclusion diagnosis concepts: type 1, gestational, secondary, neonatal, malnutrition-related diabetes */
exclusion_icd_source AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND c.invalid_reason IS NULL
      AND (
            /* Type 1 diabetes */
            (c.vocabulary_id = 'ICD10CM' AND c.concept_code ~* '^E10(\.|$)')
            OR (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~* '^250\.?[0-9][13]$')

            /* Secondary / drug-induced / other specified diabetes */
            OR (c.vocabulary_id = 'ICD10CM' AND c.concept_code ~* '^E0[89](\.|$)|^E13(\.|$)')
            OR (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~* '^249\.?')

            /* Gestational diabetes */
            OR (c.vocabulary_id = 'ICD10CM' AND c.concept_code ~* '^O24\.4')
            OR (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~* '^648\.?8')

            /* Neonatal diabetes */
            OR (c.vocabulary_id = 'ICD10CM' AND c.concept_code ~* '^P70\.2')
          )
),

exclusion_condition_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS condition_concept_id
    FROM exclusion_icd_source s
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = s.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
),

exclusion_dx AS (
    SELECT
        co.person_id,
        COUNT(DISTINCT co.condition_start_date) AS exclusion_dx_dates
    FROM public.condition_occurrence co
    JOIN exclusion_condition_concepts ec
      ON ec.condition_concept_id = co.condition_concept_id
    WHERE co.condition_start_date IS NOT NULL
    GROUP BY co.person_id
),

/* 9) Candidate persons satisfying evidence combinations */
candidate_summary AS (
    SELECT
        p.person_id,
        COALESCE(dx.t2dm_dx_dates, 0) AS t2dm_dx_dates,
        COALESCE(med.t2dm_med_count, 0) AS t2dm_med_count,
        COALESCE(lab.abnormal_lab_dates, 0) AS abnormal_lab_dates,
        LEAST(
            COALESCE(dx.first_t2dm_dx_date, DATE '9999-12-31'),
            COALESCE(med.first_t2dm_med_date, DATE '9999-12-31'),
            COALESCE(lab.first_abnormal_lab_date, DATE '9999-12-31')
        ) AS index_date,
        COALESCE(excl.exclusion_dx_dates, 0) AS exclusion_dx_dates
    FROM public.person p
    LEFT JOIN t2dm_dx_summary dx
      ON dx.person_id = p.person_id
    LEFT JOIN t2dm_med_summary med
      ON med.person_id = p.person_id
    LEFT JOIN diabetes_lab_summary lab
      ON lab.person_id = p.person_id
    LEFT JOIN exclusion_dx excl
      ON excl.person_id = p.person_id
)

SELECT DISTINCT cs.person_id
FROM candidate_summary cs
JOIN public.person p
  ON p.person_id = cs.person_id
WHERE
    /* Adult phenotype: at least 18 years old at first qualifying evidence */
    cs.index_date >= (
        COALESCE(
            p.birth_datetime::date,
            make_date(
                p.year_of_birth,
                COALESCE(NULLIF(p.month_of_birth, 0), 1),
                COALESCE(NULLIF(p.day_of_birth, 0), 1)
            )
        ) + INTERVAL '18 years'
    )

    AND
    (
        /* High-specificity diagnosis rule */
        cs.t2dm_dx_dates >= 2

        /* Diagnosis plus treatment */
        OR (cs.t2dm_dx_dates >= 1 AND cs.t2dm_med_count >= 1)

        /* Diagnosis plus diabetes-range lab */
        OR (cs.t2dm_dx_dates >= 1 AND cs.abnormal_lab_dates >= 1)

        /* Repeated diabetes-range labs */
        OR cs.abnormal_lab_dates >= 2
    )

    /* Exclude likely non-T2DM diabetes when exclusion evidence exists without T2DM diagnosis support */
    AND NOT (
        cs.exclusion_dx_dates >= 1
        AND cs.t2dm_dx_dates = 0
    )
ORDER BY cs.person_id;