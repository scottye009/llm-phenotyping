WITH t2dm_dx AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date AS event_date
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
            AND c.concept_code LIKE '250.%'
            AND (
                c.concept_code LIKE '250.%0'
                OR c.concept_code LIKE '250.%2'
            )
        )
),

diabetes_labs AS (
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
            AND LOWER(c.concept_name) LIKE '%2 hour%'
            AND m.value_as_number >= 200
        )
        OR
        (
            LOWER(c.concept_name) LIKE '%glucose%'
            AND LOWER(c.concept_name) LIKE '%random%'
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
        LOWER(c.concept_name) LIKE ANY (ARRAY[
            '%metformin%', '%glucophage%', '%fortamet%', '%glumetza%', '%riomet%',
            '%glipizide%', '%glucotrol%',
            '%glyburide%', '%diabeta%', '%micronase%', '%glynase%',
            '%glimepiride%', '%amaryl%',
            '%sitagliptin%', '%januvia%',
            '%saxagliptin%', '%onglyza%',
            '%linagliptin%', '%tradjenta%',
            '%alogliptin%', '%nesina%',
            '%semaglutide%', '%ozempic%', '%rybelsus%',
            '%liraglutide%', '%victoza%',
            '%dulaglutide%', '%trulicity%',
            '%exenatide%', '%byetta%', '%bydureon%',
            '%empagliflozin%', '%jardiance%',
            '%dapagliflozin%', '%farxiga%',
            '%canagliflozin%', '%invokana%',
            '%ertugliflozin%', '%steglatro%',
            '%pioglitazone%', '%actos%',
            '%rosiglitazone%', '%avandia%',
            '%repaglinide%', '%prandin%',
            '%nateglinide%', '%starlix%',
            '%acarbose%', '%precose%',
            '%miglitol%', '%glyset%'
        ])
),

type1_dx AS (
    SELECT DISTINCT
        co.person_id
    FROM condition_occurrence co
    JOIN concept c
        ON co.condition_source_concept_id = c.concept_id
    WHERE
        (
            c.vocabulary_id = 'ICD10CM'
            AND c.concept_code LIKE 'E10%'
        )
        OR
        (
            c.vocabulary_id = 'ICD9CM'
            AND c.concept_code LIKE '250.%'
            AND (
                c.concept_code LIKE '250.%1'
                OR c.concept_code LIKE '250.%3'
            )
        )
),

gestational_or_secondary_dx AS (
    SELECT DISTINCT
        co.person_id
    FROM condition_occurrence co
    JOIN concept c
        ON co.condition_source_concept_id = c.concept_id
    WHERE
        (
            c.vocabulary_id = 'ICD10CM'
            AND (
                c.concept_code LIKE 'O24.4%'
                OR c.concept_code LIKE 'E08%'
                OR c.concept_code LIKE 'E09%'
                OR c.concept_code LIKE 'E13%'
            )
        )
        OR
        (
            c.vocabulary_id = 'ICD9CM'
            AND (
                c.concept_code LIKE '648.8%'
                OR c.concept_code LIKE '249%'
            )
        )
),

candidate_t2dm AS (
    SELECT
        person_id,
        MIN(event_date) AS index_date
    FROM (
        SELECT person_id, event_date FROM t2dm_dx

        UNION ALL

        SELECT l.person_id, l.event_date
        FROM diabetes_labs l
        JOIN t2dm_meds m
            ON l.person_id = m.person_id

        UNION ALL

        SELECT d.person_id, d.event_date
        FROM t2dm_dx d
        JOIN diabetes_labs l
            ON d.person_id = l.person_id

        UNION ALL

        SELECT d.person_id, d.event_date
        FROM t2dm_dx d
        JOIN t2dm_meds m
            ON d.person_id = m.person_id
    ) evidence
    GROUP BY person_id
)

SELECT DISTINCT
    c.person_id,
    c.index_date
FROM candidate_t2dm c
LEFT JOIN type1_dx t1
    ON c.person_id = t1.person_id
LEFT JOIN gestational_or_secondary_dx excl
    ON c.person_id = excl.person_id
WHERE
    t1.person_id IS NULL
    AND excl.person_id IS NULL;