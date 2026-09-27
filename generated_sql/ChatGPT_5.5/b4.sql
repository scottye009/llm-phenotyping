WITH
/* -----------------------------
   1) T2DM ICD source diagnosis concepts
   ICD10CM E11 = type 2 diabetes
   ICD9CM 250.x0 / 250.x2 = type 2 or unspecified type
   ----------------------------- */
t2dm_icd_source_concepts AS (
    SELECT
        c.concept_id
    FROM public.concept c
    WHERE
        (
            c.vocabulary_id = 'ICD10CM'
            AND UPPER(c.concept_code) ~ '^E11(\.|$)'
        )
        OR (
            c.vocabulary_id = 'ICD9CM'
            AND REPLACE(c.concept_code, '.', '') ~ '^250[0-9][02]$'
        )
),

/* Map ICD source concepts to standard OMOP condition concepts */
t2dm_condition_concepts AS (
    SELECT DISTINCT
        cr.concept_id_2 AS condition_concept_id
    FROM t2dm_icd_source_concepts src
    JOIN public.concept_relationship cr
        ON src.concept_id = cr.concept_id_1
    WHERE
        cr.relationship_id = 'Maps to'
),

t2dm_diagnosis AS (
    SELECT
        co.person_id,
        MIN(co.condition_start_date) AS first_t2dm_dx_date
    FROM public.condition_occurrence co
    JOIN t2dm_condition_concepts t2
        ON co.condition_concept_id = t2.condition_concept_id
    WHERE
        co.condition_start_date IS NOT NULL
    GROUP BY
        co.person_id
),

/* -----------------------------
   2) Exclusion diagnosis concepts
   Type 1, secondary/other specified, gestational/pregnancy-related,
   and neonatal diabetes
   ----------------------------- */
exclusion_icd_source_concepts AS (
    SELECT
        c.concept_id
    FROM public.concept c
    WHERE
        (
            c.vocabulary_id = 'ICD10CM'
            AND (
                UPPER(c.concept_code) ~ '^E10(\.|$)'
                OR UPPER(c.concept_code) ~ '^E08(\.|$)'
                OR UPPER(c.concept_code) ~ '^E09(\.|$)'
                OR UPPER(c.concept_code) ~ '^E13(\.|$)'
                OR UPPER(c.concept_code) ~ '^O24'
                OR UPPER(c.concept_code) ~ '^P70\.2'
            )
        )
        OR (
            c.vocabulary_id = 'ICD9CM'
            AND (
                REPLACE(c.concept_code, '.', '') ~ '^250[0-9][13]$'
                OR REPLACE(c.concept_code, '.', '') ~ '^249'
                OR REPLACE(c.concept_code, '.', '') ~ '^6488'
                OR REPLACE(c.concept_code, '.', '') ~ '^7751'
            )
        )
),

exclusion_condition_concepts AS (
    SELECT DISTINCT
        cr.concept_id_2 AS condition_concept_id
    FROM exclusion_icd_source_concepts src
    JOIN public.concept_relationship cr
        ON src.concept_id = cr.concept_id_1
    WHERE
        cr.relationship_id = 'Maps to'
),

exclusion_diagnosis AS (
    SELECT
        co.person_id,
        MIN(co.condition_start_date) AS first_exclusion_dx_date
    FROM public.condition_occurrence co
    JOIN exclusion_condition_concepts ex
        ON co.condition_concept_id = ex.condition_concept_id
    WHERE
        co.condition_start_date IS NOT NULL
    GROUP BY
        co.person_id
),

/* -----------------------------
   3) Non-insulin diabetes medication evidence
   Uses generic and common brand names, then expands descendants.
   ----------------------------- */
diabetes_drug_seed_concepts AS (
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
            OR c.concept_name ~* 'empagliflozin|jardiance|synjardy'
            OR c.concept_name ~* 'dapagliflozin|farxiga|xigduo'
            OR c.concept_name ~* 'canagliflozin|invokana|invokamet'
            OR c.concept_name ~* 'ertugliflozin|steglatro'
            OR c.concept_name ~* 'liraglutide|victoza'
            OR c.concept_name ~* 'semaglutide|ozempic|rybelsus'
            OR c.concept_name ~* 'dulaglutide|trulicity'
            OR c.concept_name ~* 'exenatide|byetta|bydureon'
            OR c.concept_name ~* 'lixisenatide|adlyxin'
            OR c.concept_name ~* 'tirzepatide|mounjaro'
            OR c.concept_name ~* 'acarbose|precose'
            OR c.concept_name ~* 'miglitol|glyset'
            OR c.concept_name ~* 'repaglinide|prandin'
            OR c.concept_name ~* 'nateglinide|starlix'
        )
),

diabetes_drug_concepts AS (
    SELECT DISTINCT
        concept_id AS drug_concept_id
    FROM diabetes_drug_seed_concepts

    UNION

    SELECT DISTINCT
        ca.descendant_concept_id AS drug_concept_id
    FROM diabetes_drug_seed_concepts seed
    JOIN public.concept_ancestor ca
        ON seed.concept_id = ca.ancestor_concept_id
),

t2dm_medication AS (
    SELECT
        de.person_id,
        MIN(de.drug_exposure_start_date) AS first_t2dm_med_date
    FROM public.drug_exposure de
    JOIN diabetes_drug_concepts d
        ON de.drug_concept_id = d.drug_concept_id
    WHERE
        de.drug_exposure_start_date IS NOT NULL
    GROUP BY
        de.person_id
),

/* -----------------------------
   4) Diabetes-range lab evidence
   HbA1c >= 6.5%
   fasting glucose >= 126 mg/dL
   random/non-fasting blood glucose >= 200 mg/dL
   ----------------------------- */
hba1c_concepts AS (
    SELECT
        c.concept_id AS measurement_concept_id
    FROM public.concept c
    WHERE
        c.domain_id = 'Measurement'
        AND (
            c.concept_code IN ('4548-4', '4549-2', '17856-6', '59261-8')
            OR c.concept_name ~* 'hemoglobin A1c|HbA1c|A1c|glycated hemoglobin|glycohemoglobin'
        )
),

glucose_concepts AS (
    SELECT
        c.concept_id AS measurement_concept_id,
        c.concept_name,
        c.concept_code
    FROM public.concept c
    WHERE
        c.domain_id = 'Measurement'
        AND (
            c.concept_code IN ('1558-6', '1557-8', '2345-7', '14749-6', '14771-0', '2339-0')
            OR c.concept_name ~* 'glucose'
        )
        AND c.concept_name !~* 'urine'
),

diabetic_labs AS (
    SELECT
        m.person_id,
        MIN(m.measurement_date) AS first_diabetic_lab_date
    FROM public.measurement m
    LEFT JOIN hba1c_concepts a1c
        ON m.measurement_concept_id = a1c.measurement_concept_id
    LEFT JOIN glucose_concepts glu
        ON m.measurement_concept_id = glu.measurement_concept_id
    WHERE
        m.measurement_date IS NOT NULL
        AND m.value_as_number IS NOT NULL
        AND (
            (
                a1c.measurement_concept_id IS NOT NULL
                AND m.value_as_number >= 6.5
            )
            OR
            (
                glu.measurement_concept_id IS NOT NULL
                AND m.value_as_number >= 126
                AND (
                    glu.concept_code IN ('1558-6', '1557-8')
                    OR m.measurement_source_value IN ('1558-6', '1557-8')
                    OR COALESCE(glu.concept_name, '') ~* 'fasting'
                    OR COALESCE(m.measurement_source_value, '') ~* 'fasting|fast'
                    OR COALESCE(m.value_source_value, '') ~* 'fasting|fast'
                )
            )
            OR
            (
                glu.measurement_concept_id IS NOT NULL
                AND m.value_as_number >= 200
            )
        )
    GROUP BY
        m.person_id
),

/* -----------------------------
   5) Combine evidence
   Include:
   - T2DM diagnosis, or
   - non-insulin diabetes medication plus diabetic-range lab.
   Exclude non-T2DM diabetes phenotypes only when no direct T2DM diagnosis exists.
   ----------------------------- */
candidate_cohort AS (
    SELECT
        p.person_id,
        dx.first_t2dm_dx_date,
        med.first_t2dm_med_date,
        lab.first_diabetic_lab_date,
        ex.first_exclusion_dx_date,
        CASE WHEN dx.person_id IS NOT NULL THEN 1 ELSE 0 END AS has_t2dm_diagnosis,
        CASE WHEN med.person_id IS NOT NULL THEN 1 ELSE 0 END AS has_t2dm_medication,
        CASE WHEN lab.person_id IS NOT NULL THEN 1 ELSE 0 END AS has_diabetic_lab,
        CASE WHEN ex.person_id IS NOT NULL THEN 1 ELSE 0 END AS has_exclusion_diagnosis
    FROM public.person p
    LEFT JOIN t2dm_diagnosis dx
        ON p.person_id = dx.person_id
    LEFT JOIN t2dm_medication med
        ON p.person_id = med.person_id
    LEFT JOIN diabetic_labs lab
        ON p.person_id = lab.person_id
    LEFT JOIN exclusion_diagnosis ex
        ON p.person_id = ex.person_id
)

SELECT
    person_id,
    LEAST(
        COALESCE(first_t2dm_dx_date, DATE '9999-12-31'),
        COALESCE(first_t2dm_med_date, DATE '9999-12-31'),
        COALESCE(first_diabetic_lab_date, DATE '9999-12-31')
    ) AS index_date,
    has_t2dm_diagnosis,
    has_t2dm_medication,
    has_diabetic_lab,
    has_exclusion_diagnosis
FROM candidate_cohort
WHERE
    (
        has_t2dm_diagnosis = 1
        OR (
            has_t2dm_medication = 1
            AND has_diabetic_lab = 1
        )
    )
    AND NOT (
        has_t2dm_diagnosis = 0
        AND has_exclusion_diagnosis = 1
    )
ORDER BY
    person_id;