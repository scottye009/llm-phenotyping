WITH t2d_icd_source_concepts AS (
    -- ICD9CM: type 2 diabetes is 250.x0 or 250.x2
    -- ICD10CM: type 2 diabetes is E11.*
    SELECT
        c.concept_id
    FROM public.concept c
    WHERE
        (
            c.vocabulary_id = 'ICD9CM'
            AND c.concept_code ~ '^250\.[0-9][02]$'
        )
        OR (
            c.vocabulary_id = 'ICD10CM'
            AND c.concept_code ~ '^E11(\.|$)'
        )
),

t2d_standard_condition_concepts AS (
    -- Map source ICD diagnosis concepts to standard OMOP condition concepts.
    -- Do not compare ICD concept_id directly to condition_concept_id.
    SELECT DISTINCT
        cr.concept_id_2 AS condition_concept_id
    FROM t2d_icd_source_concepts src
    JOIN public.concept_relationship cr
        ON src.concept_id = cr.concept_id_1
    WHERE
        cr.relationship_id = 'Maps to'
),

t2d_diagnoses AS (
    SELECT
        co.person_id,
        co.condition_start_date AS event_date,
        't2d_diagnosis' AS evidence_type
    FROM public.condition_occurrence co
    JOIN t2d_standard_condition_concepts t2d
        ON co.condition_concept_id = t2d.condition_concept_id
    WHERE
        co.condition_start_date IS NOT NULL
),

diabetes_med_seed_concepts AS (
    -- Generic and common brand names for non-insulin diabetes medications.
    -- These are searched in OMOP drug concepts, then expanded through concept_ancestor.
    SELECT
        c.concept_id
    FROM public.concept c
    WHERE
        c.domain_id = 'Drug'
        AND (
            c.concept_name ~* 'metformin|glucophage|fortamet|glumetza|riomet'
            OR c.concept_name ~* 'glyburide|glibenclamide|diabeta|glynase|micronase'
            OR c.concept_name ~* 'glipizide|glucotrol'
            OR c.concept_name ~* 'glimepiride|amaryl'
            OR c.concept_name ~* 'pioglitazone|actos'
            OR c.concept_name ~* 'rosiglitazone|avandia'
            OR c.concept_name ~* 'sitagliptin|januvia|janumet'
            OR c.concept_name ~* 'saxagliptin|onglyza|kombiglyze'
            OR c.concept_name ~* 'linagliptin|tradjenta|jentadueto'
            OR c.concept_name ~* 'alogliptin|nesina|kazano|oseni'
            OR c.concept_name ~* 'liraglutide|victoza'
            OR c.concept_name ~* 'semaglutide|ozempic|rybelsus'
            OR c.concept_name ~* 'dulaglutide|trulicity'
            OR c.concept_name ~* 'exenatide|byetta|bydureon'
            OR c.concept_name ~* 'lixisenatide|adlyxin'
            OR c.concept_name ~* 'tirzepatide|mounjaro'
            OR c.concept_name ~* 'empagliflozin|jardiance|synjardy'
            OR c.concept_name ~* 'dapagliflozin|farxiga|xigduo'
            OR c.concept_name ~* 'canagliflozin|invokana|invokamet'
            OR c.concept_name ~* 'ertugliflozin|steglatro|seguro'
            OR c.concept_name ~* 'acarbose|precose'
            OR c.concept_name ~* 'miglitol|glyset'
            OR c.concept_name ~* 'repaglinide|prandin'
            OR c.concept_name ~* 'nateglinide|starlix'
        )
),

diabetes_med_concepts AS (
    SELECT DISTINCT
        concept_id AS drug_concept_id
    FROM diabetes_med_seed_concepts

    UNION

    SELECT DISTINCT
        ca.descendant_concept_id AS drug_concept_id
    FROM diabetes_med_seed_concepts seed
    JOIN public.concept_ancestor ca
        ON seed.concept_id = ca.ancestor_concept_id
),

diabetes_meds AS (
    SELECT
        de.person_id,
        de.drug_exposure_start_date AS event_date,
        'diabetes_medication' AS evidence_type
    FROM public.drug_exposure de
    JOIN diabetes_med_concepts meds
        ON de.drug_concept_id = meds.drug_concept_id
    WHERE
        de.drug_exposure_start_date IS NOT NULL
),

lab_concepts AS (
    -- Use OMOP/LOINC concept codes or names when possible.
    SELECT
        c.concept_id AS measurement_concept_id,
        CASE
            WHEN c.concept_code IN ('4548-4', '4549-2', '17856-6')
                 OR c.concept_name ~* 'hemoglobin A1c|HbA1c|A1c'
                THEN 'a1c'
            WHEN c.concept_code IN ('1558-6', '2345-7', '14771-0', '14749-6', '2339-0')
                 OR c.concept_name ~* 'glucose'
                THEN 'glucose'
        END AS lab_type
    FROM public.concept c
    WHERE
        c.domain_id = 'Measurement'
        AND (
            c.concept_code IN ('4548-4', '4549-2', '17856-6', '1558-6', '2345-7', '14771-0', '14749-6', '2339-0')
            OR c.concept_name ~* 'hemoglobin A1c|HbA1c|A1c|glucose'
        )
),

abnormal_diabetes_labs AS (
    SELECT
        m.person_id,
        m.measurement_date AS event_date,
        'abnormal_diabetes_lab' AS evidence_type
    FROM public.measurement m
    JOIN lab_concepts lc
        ON m.measurement_concept_id = lc.measurement_concept_id
    WHERE
        m.measurement_date IS NOT NULL
        AND m.value_as_number IS NOT NULL
        AND (
            -- HbA1c diagnostic threshold.
            (
                lc.lab_type = 'a1c'
                AND m.value_as_number >= 6.5
            )

            OR

            -- Fasting glucose diagnostic threshold.
            (
                lc.lab_type = 'glucose'
                AND m.value_as_number >= 126
                AND (
                    m.measurement_source_value IN ('1558-6', '14771-0')
                    OR lc.measurement_concept_id IN (
                        SELECT concept_id
                        FROM public.concept
                        WHERE concept_name ~* 'fasting.*glucose|glucose.*fasting'
                    )
                    OR m.value_source_value ~* 'fasting'
                )
            )

            OR

            -- Random/non-fasting glucose diagnostic threshold.
            (
                lc.lab_type = 'glucose'
                AND m.value_as_number >= 200
            )
        )
),

candidate_summary AS (
    SELECT
        p.person_id,

        COUNT(DISTINCT dx.event_date) AS t2d_dx_dates,
        COUNT(DISTINCT med.event_date) AS med_dates,
        COUNT(DISTINCT lab.event_date) AS abnormal_lab_dates,

        MIN(dx.event_date) AS first_dx_date,
        MIN(med.event_date) AS first_med_date,
        MIN(lab.event_date) AS first_lab_date
    FROM public.person p
    LEFT JOIN t2d_diagnoses dx
        ON p.person_id = dx.person_id
    LEFT JOIN diabetes_meds med
        ON p.person_id = med.person_id
    LEFT JOIN abnormal_diabetes_labs lab
        ON p.person_id = lab.person_id
    GROUP BY
        p.person_id
),

candidate_t2d AS (
    SELECT
        person_id,
        LEAST(
            COALESCE(first_dx_date, DATE '9999-12-31'),
            COALESCE(first_med_date, DATE '9999-12-31'),
            COALESCE(first_lab_date, DATE '9999-12-31')
        ) AS index_date,
        t2d_dx_dates,
        med_dates,
        abnormal_lab_dates
    FROM candidate_summary
    WHERE
        (
            t2d_dx_dates >= 2
            OR (t2d_dx_dates >= 1 AND med_dates >= 1)
            OR (t2d_dx_dates >= 1 AND abnormal_lab_dates >= 1)
            OR abnormal_lab_dates >= 2
        )
),

exclusion_icd_source_concepts AS (
    -- Exclude likely type 1 diabetes, gestational diabetes, secondary diabetes, and neonatal diabetes.
    SELECT
        c.concept_id
    FROM public.concept c
    WHERE
        (
            c.vocabulary_id = 'ICD9CM'
            AND (
                c.concept_code ~ '^250\.[0-9][13]$'  -- type 1 diabetes
                OR c.concept_code ~ '^648\.8'        -- gestational diabetes / diabetes in pregnancy
                OR c.concept_code ~ '^775\.1'        -- neonatal diabetes
            )
        )
        OR (
            c.vocabulary_id = 'ICD10CM'
            AND (
                c.concept_code ~ '^E10(\.|$)'        -- type 1 diabetes
                OR c.concept_code ~ '^O24\.4'        -- gestational diabetes
                OR c.concept_code ~ '^E08(\.|$)'     -- diabetes due to underlying condition
                OR c.concept_code ~ '^E09(\.|$)'     -- drug or chemical induced diabetes
                OR c.concept_code ~ '^E13(\.|$)'     -- other specified diabetes
                OR c.concept_code ~ '^P70\.2'        -- neonatal diabetes mellitus
            )
        )
),

exclusion_standard_condition_concepts AS (
    SELECT DISTINCT
        cr.concept_id_2 AS condition_concept_id
    FROM exclusion_icd_source_concepts src
    JOIN public.concept_relationship cr
        ON src.concept_id = cr.concept_id_1
    WHERE
        cr.relationship_id = 'Maps to'
),

exclusion_diagnoses AS (
    SELECT
        co.person_id,
        co.condition_start_date AS exclusion_date
    FROM public.condition_occurrence co
    JOIN exclusion_standard_condition_concepts exc
        ON co.condition_concept_id = exc.condition_concept_id
    WHERE
        co.condition_start_date IS NOT NULL
)

SELECT
    c.person_id,
    c.index_date
FROM candidate_t2d c
WHERE
    c.index_date < DATE '9999-12-31'
    AND NOT EXISTS (
        SELECT
            1
        FROM exclusion_diagnoses e
        WHERE
            e.person_id = c.person_id
            AND e.exclusion_date <= c.index_date
    )
ORDER BY
    c.person_id;