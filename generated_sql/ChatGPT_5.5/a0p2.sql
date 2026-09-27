WITH t2dm_dx AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date AS event_date
    FROM condition_occurrence co
    JOIN concept c
        ON co.condition_concept_id = c.concept_id
    WHERE
        (
            c.vocabulary_id = 'ICD9CM'
            AND c.concept_code IN (
                '250.00','250.02',
                '250.10','250.12',
                '250.20','250.22',
                '250.30','250.32',
                '250.40','250.42',
                '250.50','250.52',
                '250.60','250.62',
                '250.70','250.72',
                '250.80','250.82',
                '250.90','250.92'
            )
        )
        OR
        (
            c.vocabulary_id = 'ICD10CM'
            AND (
                c.concept_code = 'E11'
                OR c.concept_code LIKE 'E11.%'
            )
        )
),

abnormal_diabetes_labs AS (
    SELECT DISTINCT
        m.person_id,
        m.measurement_date AS event_date
    FROM measurement m
    JOIN concept c
        ON m.measurement_concept_id = c.concept_id
    WHERE
        (
            LOWER(c.concept_name) LIKE '%hemoglobin a1c%'
            AND m.value_as_number >= 6.5
        )
        OR
        (
            LOWER(c.concept_name) LIKE '%glucose%'
            AND LOWER(c.concept_name) LIKE '%fasting%'
            AND m.value_as_number >= 126
        )
        OR
        (
            LOWER(c.concept_name) LIKE '%glucose%'
            AND LOWER(c.concept_name) LIKE '%random%'
            AND m.value_as_number >= 200
        )
        OR
        (
            LOWER(c.concept_name) LIKE '%glucose tolerance%'
            AND m.value_as_number >= 200
        )
),

t2dm_meds AS (
    SELECT DISTINCT
        de.person_id,
        de.drug_exposure_start_date AS event_date
    FROM drug_exposure de
    JOIN concept c
        ON de.drug_concept_id = c.concept_id
    WHERE
        LOWER(c.concept_name) IN (
            'metformin',
            'glucophage',
            'glipizide',
            'glucotrol',
            'glyburide',
            'diabeta',
            'glimepiride',
            'amaryl',
            'pioglitazone',
            'actos',
            'rosiglitazone',
            'avandia',
            'sitagliptin',
            'januvia',
            'saxagliptin',
            'onglyza',
            'linagliptin',
            'tradjenta',
            'alogliptin',
            'nesina',
            'empagliflozin',
            'jardiance',
            'dapagliflozin',
            'farxiga',
            'canagliflozin',
            'invokana',
            'ertugliflozin',
            'steglatro',
            'liraglutide',
            'victoza',
            'semaglutide',
            'ozempic',
            'rybelsus',
            'dulaglutide',
            'trulicity',
            'exenatide',
            'byetta',
            'bydureon',
            'tirzepatide',
            'mounjaro',
            'zepbound',
            'acarbose',
            'precose',
            'miglitol',
            'glyset',
            'repaglinide',
            'prandin',
            'nateglinide',
            'starlix'
        )
),

type1_dx AS (
    SELECT DISTINCT
        co.person_id
    FROM condition_occurrence co
    JOIN concept c
        ON co.condition_concept_id = c.concept_id
    WHERE
        (
            c.vocabulary_id = 'ICD9CM'
            AND c.concept_code IN ('250.01','250.03')
        )
        OR
        (
            c.vocabulary_id = 'ICD10CM'
            AND (
                c.concept_code = 'E10'
                OR c.concept_code LIKE 'E10.%'
            )
        )
),

gestational_or_secondary_dm AS (
    SELECT DISTINCT
        co.person_id
    FROM condition_occurrence co
    JOIN concept c
        ON co.condition_concept_id = c.concept_id
    WHERE
        (
            c.vocabulary_id = 'ICD10CM'
            AND (
                c.concept_code LIKE 'O24.4%'
                OR c.concept_code LIKE 'E08.%'
                OR c.concept_code LIKE 'E09.%'
                OR c.concept_code LIKE 'E13.%'
                OR c.concept_code LIKE 'R73.%'
            )
        )
        OR
        (
            c.vocabulary_id = 'ICD9CM'
            AND (
                c.concept_code LIKE '648.8%'
                OR c.concept_code = '775.1'
            )
        )
),

dx_counts AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS n_t2dm_dx_dates
    FROM t2dm_dx
    GROUP BY person_id
),

lab_counts AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS n_abnormal_lab_dates
    FROM abnormal_diabetes_labs
    GROUP BY person_id
),

med_counts AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS n_t2dm_med_dates
    FROM t2dm_meds
    GROUP BY person_id
),

candidate_t2dm AS (
    SELECT DISTINCT person_id
    FROM (
        SELECT person_id FROM t2dm_dx
        UNION
        SELECT person_id FROM abnormal_diabetes_labs
        UNION
        SELECT person_id FROM t2dm_meds
    ) x
)

SELECT DISTINCT
    c.person_id
FROM candidate_t2dm c
LEFT JOIN dx_counts dx
    ON c.person_id = dx.person_id
LEFT JOIN lab_counts lab
    ON c.person_id = lab.person_id
LEFT JOIN med_counts med
    ON c.person_id = med.person_id
LEFT JOIN type1_dx t1
    ON c.person_id = t1.person_id
LEFT JOIN gestational_or_secondary_dm ex
    ON c.person_id = ex.person_id
WHERE
    (
        COALESCE(dx.n_t2dm_dx_dates, 0) >= 2

        OR (
            COALESCE(dx.n_t2dm_dx_dates, 0) >= 1
            AND COALESCE(med.n_t2dm_med_dates, 0) >= 1
        )

        OR (
            COALESCE(dx.n_t2dm_dx_dates, 0) >= 1
            AND COALESCE(lab.n_abnormal_lab_dates, 0) >= 1
        )

        OR COALESCE(lab.n_abnormal_lab_dates, 0) >= 2

        OR (
            COALESCE(lab.n_abnormal_lab_dates, 0) >= 1
            AND COALESCE(med.n_t2dm_med_dates, 0) >= 1
        )
    )
    AND t1.person_id IS NULL
    AND ex.person_id IS NULL;