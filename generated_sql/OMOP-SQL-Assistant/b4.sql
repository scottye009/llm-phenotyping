WITH
/* 1) ICD9CM / ICD10CM source concepts for Type 2 diabetes */
t2dm_icd_source AS (
    SELECT
        c.concept_id AS source_concept_id
    FROM public.concept c
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND c.invalid_reason IS NULL
      AND (
            /* ICD10CM E11.* = Type 2 diabetes mellitus */
            (
                c.vocabulary_id = 'ICD10CM'
                AND replace(c.concept_code, '.', '') LIKE 'E11%'
            )

            OR

            /* ICD9CM 250.x0 / 250.x2 = Type II or unspecified type */
            (
                c.vocabulary_id = 'ICD9CM'
                AND replace(c.concept_code, '.', '') ~ '^250[0-9][02]$'
            )
          )
),

/* 2) Map ICD source diagnosis concepts to OMOP standard condition concepts */
t2dm_condition_concepts AS (
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
    JOIN t2dm_condition_concepts tc
      ON tc.condition_concept_id = co.condition_concept_id
    WHERE co.condition_start_date IS NOT NULL
),

/* 4) Person-level T2DM diagnosis summary */
t2dm_dx_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS t2dm_dx_dates,
        MIN(event_date) AS first_t2dm_dx_date
    FROM t2dm_dx
    GROUP BY person_id
),

/* 5) ICD9CM / ICD10CM source concepts for non-T2DM diabetes exclusions */
exclusion_icd_source AS (
    SELECT
        c.concept_id AS source_concept_id,
        CASE
            WHEN c.vocabulary_id = 'ICD10CM'
             AND replace(c.concept_code, '.', '') LIKE 'E10%'
                THEN 'T1DM'

            WHEN c.vocabulary_id = 'ICD9CM'
             AND replace(c.concept_code, '.', '') ~ '^250[0-9][13]$'
                THEN 'T1DM'

            WHEN c.vocabulary_id = 'ICD10CM'
             AND (
                    replace(c.concept_code, '.', '') LIKE 'E08%'
                 OR replace(c.concept_code, '.', '') LIKE 'E09%'
                 OR replace(c.concept_code, '.', '') LIKE 'E13%'
                 )
                THEN 'SECONDARY_OTHER'

            WHEN c.vocabulary_id = 'ICD10CM'
             AND replace(c.concept_code, '.', '') LIKE 'O24%'
                THEN 'GESTATIONAL_PREGNANCY'

            WHEN c.vocabulary_id = 'ICD9CM'
             AND replace(c.concept_code, '.', '') LIKE '6488%'
                THEN 'GESTATIONAL_PREGNANCY'

            WHEN c.vocabulary_id = 'ICD10CM'
             AND replace(c.concept_code, '.', '') LIKE 'P702%'
                THEN 'NEONATAL'
        END AS exclusion_type
    FROM public.concept c
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND c.invalid_reason IS NULL
),

/* 6) Map exclusion ICD concepts to OMOP standard condition concepts */
exclusion_condition_concepts AS (
    SELECT DISTINCT
        cr.concept_id_2 AS condition_concept_id,
        s.exclusion_type
    FROM exclusion_icd_source s
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = s.source_concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
    WHERE s.exclusion_type IS NOT NULL
),

/* 7) Exclusion diagnosis events */
exclusion_dx AS (
    SELECT DISTINCT
        co.person_id,
        ecc.exclusion_type,
        co.condition_start_date AS event_date
    FROM public.condition_occurrence co
    JOIN exclusion_condition_concepts ecc
      ON ecc.condition_concept_id = co.condition_concept_id
    WHERE co.condition_start_date IS NOT NULL
),

/* 8) Non-insulin antidiabetic medication seed concepts using generic and brand names */
t2dm_med_seed AS (
    SELECT DISTINCT
        c.concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Drug'
      AND c.invalid_reason IS NULL
      AND c.concept_name ~* (
            'metformin|glucophage|fortamet|glumetza|riomet|' ||
            'glyburide|glibenclamide|glipizide|glimepiride|chlorpropamide|tolazamide|tolbutamide|' ||
            'diabeta|micronase|glynase|glucotrol|amaryl|' ||
            'pioglitazone|rosiglitazone|actos|avandia|' ||
            'sitagliptin|saxagliptin|linagliptin|alogliptin|januvia|janumet|onglyza|tradjenta|nesina|' ||
            'canagliflozin|dapagliflozin|empagliflozin|ertugliflozin|invokana|farxiga|jardiance|steglatro|' ||
            'liraglutide|semaglutide|dulaglutide|exenatide|lixisenatide|tirzepatide|' ||
            'victoza|ozempic|rybelsus|trulicity|byetta|bydureon|adlyxin|mounjaro|' ||
            'acarbose|miglitol|precose|glyset|' ||
            'repaglinide|nateglinide|prandin|starlix|' ||
            'bromocriptine|cycloset|colesevelam|welchol|pramlintide|symlin'
          )
      AND c.concept_name !~* 'insulin'
),

/* 9) Include descendant drug concepts where RxNorm ancestry is available */
t2dm_med_concepts AS (
    SELECT DISTINCT
        concept_id AS drug_concept_id
    FROM t2dm_med_seed

    UNION

    SELECT DISTINCT
        ca.descendant_concept_id AS drug_concept_id
    FROM public.concept_ancestor ca
    JOIN t2dm_med_seed s
      ON s.concept_id = ca.ancestor_concept_id
),

/* 10) Medication evidence from populated drug_concept_id */
t2dm_med AS (
    SELECT DISTINCT
        de.person_id,
        de.drug_exposure_start_date AS event_date
    FROM public.drug_exposure de
    JOIN t2dm_med_concepts mc
      ON mc.drug_concept_id = de.drug_concept_id
    WHERE de.drug_exposure_start_date IS NOT NULL
),

/* 11) Medication summary */
t2dm_med_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS t2dm_med_dates,
        MIN(event_date) AS first_t2dm_med_date
    FROM t2dm_med
    GROUP BY person_id
),

/* 12) HbA1c and glucose measurement concepts using LOINC codes and OMOP concept names */
diabetes_lab_concepts AS (
    SELECT
        c.concept_id AS measurement_concept_id,
        c.concept_name,
        CASE
            WHEN c.concept_code IN ('4548-4', '4549-2', '17856-6', '17855-8', '41995-2', '59261-8')
              OR c.concept_name ~* 'hemoglobin a1c|hba1c|glycohemoglobin|glycated hemoglobin'
                THEN 'A1C'

            WHEN c.concept_code IN ('1558-6', '1557-8', '14770-2', '14771-0')
              OR c.concept_name ~* 'fasting.*glucose|glucose.*fasting'
                THEN 'FASTING_GLUCOSE'

            WHEN c.concept_code IN ('1518-0', '20436-2')
              OR c.concept_name ~* '2 hour.*glucose|two hour.*glucose|glucose.*2 hour|oral glucose tolerance|ogtt'
                THEN 'TWO_HOUR_GLUCOSE'

            WHEN c.concept_code IN ('2345-7', '2339-0', '2340-8')
              OR (
                    c.concept_name ~* 'glucose'
                AND c.concept_name !~* 'urine'
                AND c.concept_name !~* 'fasting|2 hour|two hour|oral glucose tolerance|ogtt'
              )
                THEN 'RANDOM_GLUCOSE'
        END AS lab_type
    FROM public.concept c
    WHERE c.domain_id = 'Measurement'
      AND c.invalid_reason IS NULL
      AND (
            c.concept_code IN (
                '4548-4', '4549-2', '17856-6', '17855-8', '41995-2', '59261-8',
                '1558-6', '1557-8', '14770-2', '14771-0',
                '1518-0', '20436-2',
                '2345-7', '2339-0', '2340-8'
            )
            OR c.concept_name ~* 'hemoglobin a1c|hba1c|glycohemoglobin|glycated hemoglobin|glucose'
          )
),

/* 13) Diabetes-range lab evidence */
abnormal_labs AS (
    SELECT DISTINCT
        m.person_id,
        m.measurement_date AS event_date
    FROM public.measurement m
    JOIN diabetes_lab_concepts lc
      ON lc.measurement_concept_id = m.measurement_concept_id
    WHERE m.measurement_date IS NOT NULL
      AND m.value_as_number IS NOT NULL
      AND (
            /* HbA1c >= 6.5 percent */
            (
                lc.lab_type = 'A1C'
                AND m.value_as_number >= 6.5
            )

            OR

            /* Fasting plasma glucose >= 126 mg/dL */
            (
                lc.lab_type = 'FASTING_GLUCOSE'
                AND m.value_as_number >= 126
                AND (
                       m.unit_concept_id = 8840
                    OR m.unit_source_value ~* 'mg/dl'
                    OR m.unit_source_value IS NULL
                )
            )

            OR

            /* 2-hour glucose or random glucose >= 200 mg/dL */
            (
                lc.lab_type IN ('TWO_HOUR_GLUCOSE', 'RANDOM_GLUCOSE')
                AND m.value_as_number >= 200
                AND (
                       m.unit_concept_id = 8840
                    OR m.unit_source_value ~* 'mg/dl'
                    OR m.unit_source_value IS NULL
                )
            )
          )
),

/* 14) Lab summary */
abnormal_lab_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS abnormal_lab_dates,
        MIN(event_date) AS first_abnormal_lab_date
    FROM abnormal_labs
    GROUP BY person_id
),

/* 15) Combine independent evidence summaries without multiplying rows */
person_evidence AS (
    SELECT
        p.person_id,

        COALESCE(dx.t2dm_dx_dates, 0) AS t2dm_dx_dates,
        dx.first_t2dm_dx_date,

        COALESCE(med.t2dm_med_dates, 0) AS t2dm_med_dates,
        med.first_t2dm_med_date,

        COALESCE(lab.abnormal_lab_dates, 0) AS abnormal_lab_dates,
        lab.first_abnormal_lab_date,

        LEAST(
            COALESCE(dx.first_t2dm_dx_date, DATE '9999-12-31'),
            COALESCE(med.first_t2dm_med_date, DATE '9999-12-31'),
            COALESCE(lab.first_abnormal_lab_date, DATE '9999-12-31')
        ) AS index_date
    FROM public.person p
    LEFT JOIN t2dm_dx_summary dx
      ON dx.person_id = p.person_id
    LEFT JOIN t2dm_med_summary med
      ON med.person_id = p.person_id
    LEFT JOIN abnormal_lab_summary lab
      ON lab.person_id = p.person_id
)

/* Final T2DM cohort */
SELECT DISTINCT
    pe.person_id
FROM person_evidence pe
WHERE
    /* Require at least one mapped T2DM diagnosis */
    pe.t2dm_dx_dates >= 1

    AND (
           /* High-specificity diagnosis rule */
           pe.t2dm_dx_dates >= 2

           /* Single T2DM diagnosis supported by non-insulin diabetes medication */
        OR pe.t2dm_med_dates >= 1

           /* Single T2DM diagnosis supported by diabetes-range lab */
        OR pe.abnormal_lab_dates >= 1
    )

    /* Exclude stronger evidence of non-T2DM diabetes before or at phenotype index */
    AND NOT EXISTS (
        SELECT 1
        FROM exclusion_dx ex
        WHERE ex.person_id = pe.person_id
          AND ex.event_date <= pe.index_date
          AND (
                ex.exclusion_type IN ('GESTATIONAL_PREGNANCY', 'SECONDARY_OTHER', 'NEONATAL')

                OR (
                    ex.exclusion_type = 'T1DM'
                    AND pe.t2dm_dx_dates < 2
                )
          )
    )
ORDER BY pe.person_id;