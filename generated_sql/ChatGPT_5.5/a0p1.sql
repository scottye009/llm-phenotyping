WITH t2dm_diagnosis AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date AS evidence_date,
        'T2DM_DIAGNOSIS' AS evidence_type
    FROM condition_occurrence co
    JOIN concept c
        ON co.condition_source_concept_id = c.concept_id
    WHERE
        (
            c.vocabulary_id = 'ICD10CM'
            AND c.concept_code LIKE 'E11%'
        )
        OR
        (
            c.vocabulary_id = 'ICD9CM'
            AND c.concept_code LIKE '250%'
            AND RIGHT(c.concept_code, 1) IN ('0', '2')
        )
),

diabetes_labs AS (
    SELECT DISTINCT
        m.person_id,
        m.measurement_date AS evidence_date,
        'DIABETES_LAB' AS evidence_type
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
            LOWER(c.concept_name) LIKE '%fasting glucose%'
            AND m.value_as_number >= 126
        )
        OR
        (
            LOWER(c.concept_name) LIKE '%glucose%'
            AND LOWER(c.concept_name) LIKE '%oral glucose tolerance%'
            AND m.value_as_number >= 200
        )
        OR
        (
            LOWER(c.concept_name) LIKE '%glucose%'
            AND m.value_as_number >= 200
        )
),

t2dm_medications AS (
    SELECT DISTINCT
        de.person_id,
        de.drug_exposure_start_date AS evidence_date,
        'T2DM_MEDICATION' AS evidence_type
    FROM drug_exposure de
    JOIN concept c
        ON de.drug_concept_id = c.concept_id
    WHERE
        LOWER(c.concept_name) IN (
            'metformin', 'glucophage', 'fortamet', 'glumetza', 'riomet',
            'sitagliptin', 'januvia',
            'saxagliptin', 'onglyza',
            'linagliptin', 'tradjenta',
            'alogliptin', 'nesina',
            'empagliflozin', 'jardiance',
            'dapagliflozin', 'farxiga',
            'canagliflozin', 'invokana',
            'ertugliflozin', 'steglatro',
            'semaglutide', 'ozempic', 'rybelsus',
            'dulaglutide', 'trulicity',
            'liraglutide', 'victoza',
            'exenatide', 'byetta', 'bydureon',
            'tirzepatide', 'mounjaro',
            'glipizide', 'glucotrol',
            'glyburide', 'diabeta', 'glynase',
            'glimepiride', 'amaryl',
            'pioglitazone', 'actos',
            'rosiglitazone', 'avandia',
            'repaglinide', 'prandin',
            'nateglinide', 'starlix',
            'acarbose', 'precose',
            'miglitol', 'glyset'
        )
),

exclusion_evidence AS (
    SELECT DISTINCT
        co.person_id
    FROM condition_occurrence co
    JOIN concept c
        ON co.condition_source_concept_id = c.concept_id
    WHERE
        (
            c.vocabulary_id = 'ICD10CM'
            AND (
                c.concept_code LIKE 'E10%'
                OR c.concept_code LIKE 'E08%'
                OR c.concept_code LIKE 'E09%'
                OR c.concept_code LIKE 'E13%'
                OR c.concept_code LIKE 'O24.4%'
            )
        )
        OR
        (
            c.vocabulary_id = 'ICD9CM'
            AND c.concept_code LIKE '250%'
            AND RIGHT(c.concept_code, 1) IN ('1', '3')
        )
),

all_evidence AS (
    SELECT * FROM t2dm_diagnosis
    UNION ALL
    SELECT * FROM diabetes_labs
    UNION ALL
    SELECT * FROM t2dm_medications
),

evidence_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT CASE WHEN evidence_type = 'T2DM_DIAGNOSIS' THEN evidence_date END) AS t2dm_dx_dates,
        COUNT(DISTINCT CASE WHEN evidence_type = 'DIABETES_LAB' THEN evidence_date END) AS abnormal_lab_dates,
        COUNT(DISTINCT CASE WHEN evidence_type = 'T2DM_MEDICATION' THEN evidence_date END) AS t2dm_med_dates
    FROM all_evidence
    GROUP BY person_id
)

SELECT DISTINCT
    es.person_id
FROM evidence_summary es
WHERE
    (
        es.t2dm_dx_dates >= 2
        OR
        (
            es.t2dm_dx_dates >= 1
            AND es.t2dm_med_dates >= 1
        )
        OR
        es.abnormal_lab_dates >= 2
        OR
        (
            es.abnormal_lab_dates >= 1
            AND es.t2dm_med_dates >= 1
        )
    )
    AND NOT EXISTS (
        SELECT 1
        FROM exclusion_evidence ex
        WHERE ex.person_id = es.person_id
    );