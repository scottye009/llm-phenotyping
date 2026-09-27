WITH t2dm_dx AS (
    SELECT DISTINCT co.person_id
    FROM condition_occurrence co
    JOIN concept c
        ON co.condition_concept_id = c.concept_id
    WHERE
        (
            c.vocabulary_id = 'ICD9CM'
            AND c.concept_code IN (
                '25000', '25002', '25010', '25012', '25020', '25022',
                '25030', '25032', '25040', '25042', '25050', '25052',
                '25060', '25062', '25070', '25072', '25080', '25082',
                '25090', '25092'
            )
        )
        OR
        (
            c.vocabulary_id = 'ICD10CM'
            AND c.concept_code LIKE 'E11%'
        )
),

repeated_t2dm_dx AS (
    SELECT co.person_id
    FROM condition_occurrence co
    JOIN concept c
        ON co.condition_concept_id = c.concept_id
    WHERE
        (
            c.vocabulary_id = 'ICD9CM'
            AND c.concept_code IN (
                '25000', '25002', '25010', '25012', '25020', '25022',
                '25030', '25032', '25040', '25042', '25050', '25052',
                '25060', '25062', '25070', '25072', '25080', '25082',
                '25090', '25092'
            )
        )
        OR
        (
            c.vocabulary_id = 'ICD10CM'
            AND c.concept_code LIKE 'E11%'
        )
    GROUP BY co.person_id
    HAVING COUNT(DISTINCT co.condition_start_date) >= 2
),

diabetes_labs AS (
    SELECT DISTINCT m.person_id
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
            AND m.value_as_number >= 200
        )
        OR
        (
            LOWER(c.concept_name) LIKE '%oral glucose tolerance%'
            AND m.value_as_number >= 200
        )
),

t2dm_meds AS (
    SELECT DISTINCT de.person_id
    FROM drug_exposure de
    JOIN concept c
        ON de.drug_concept_id = c.concept_id
    WHERE
        LOWER(c.concept_name) SIMILAR TO
        '%(metformin|glucophage|glumetza|fortamet|riomet|
           glipizide|glucotrol|glyburide|diabeta|glynase|micronase|
           glimepiride|amaryl|
           sitagliptin|januvia|saxagliptin|onglyza|linagliptin|tradjenta|alogliptin|nesina|
           exenatide|byetta|bydureon|liraglutide|victoza|semaglutide|ozempic|rybelsus|dulaglutide|trulicity|
           canagliflozin|invokana|dapagliflozin|farxiga|empagliflozin|jardiance|ertugliflozin|steglatro|
           pioglitazone|actos|rosiglitazone|avandia|
           repaglinide|prandin|nateglinide|starlix|
           acarbose|precose|miglitol|glyset|
           janumet|synjardy|xigduo|glyxambi|jentadueto|kombiglyze)%'
),

exclusions AS (
    SELECT DISTINCT co.person_id
    FROM condition_occurrence co
    JOIN concept c
        ON co.condition_concept_id = c.concept_id
    WHERE
        (
            c.vocabulary_id = 'ICD10CM'
            AND (
                c.concept_code LIKE 'E10%'
                OR c.concept_code LIKE 'O244%'
                OR c.concept_code LIKE 'E08%'
                OR c.concept_code LIKE 'E09%'
                OR c.concept_code LIKE 'E13%'
            )
        )
        OR
        (
            c.vocabulary_id = 'ICD9CM'
            AND c.concept_code IN (
                '25001', '25003', '25011', '25013', '25021', '25023',
                '25031', '25033', '25041', '25043', '25051', '25053',
                '25061', '25063', '25071', '25073', '25081', '25083',
                '25091', '25093'
            )
        )
)

SELECT DISTINCT p.person_id
FROM person p
WHERE
    p.person_id IN (
        SELECT person_id FROM t2dm_dx
    )
    AND
    (
        p.person_id IN (SELECT person_id FROM repeated_t2dm_dx)
        OR p.person_id IN (SELECT person_id FROM diabetes_labs)
        OR p.person_id IN (SELECT person_id FROM t2dm_meds)
    )
    AND NOT EXISTS (
        SELECT 1
        FROM exclusions e
        WHERE e.person_id = p.person_id
    );