WITH t2d_dx AS (
    SELECT DISTINCT
        person_id,
        CAST(condition_start_date AS DATE) AS event_date
    FROM condition_occurrence
    WHERE
        -- ICD10CM Type 2 diabetes: E11.*
        regexp_matches(
            UPPER(COALESCE(condition_source_value, '')),
            '(^|[^A-Z0-9])E11(\.|$|[^A-Z0-9])'
        )
        OR
        -- ICD9CM Type 2 diabetes: 250.x0 or 250.x2
        regexp_matches(
            UPPER(COALESCE(condition_source_value, '')),
            '(^|[^0-9])250(\.)?[0-9][02]($|[^0-9])'
        )
        OR
        (
            -- fallback to source diagnosis text when code is unavailable
            COALESCE(condition_source_concept_name, '') ILIKE '%type 2 diabetes%'
            OR COALESCE(condition_source_concept_name, '') ILIKE '%type ii diabetes%'
            OR COALESCE(condition_source_concept_name, '') ILIKE '%diabetes mellitus type 2%'
            OR COALESCE(condition_source_concept_name, '') ILIKE '%diabetes mellitus type ii%'
        )
),

t1d_dx AS (
    SELECT DISTINCT
        person_id,
        CAST(condition_start_date AS DATE) AS event_date
    FROM condition_occurrence
    WHERE
        -- ICD10CM Type 1 diabetes: E10.*
        regexp_matches(
            UPPER(COALESCE(condition_source_value, '')),
            '(^|[^A-Z0-9])E10(\.|$|[^A-Z0-9])'
        )
        OR
        -- ICD9CM Type 1 diabetes: 250.x1 or 250.x3
        regexp_matches(
            UPPER(COALESCE(condition_source_value, '')),
            '(^|[^0-9])250(\.)?[0-9][13]($|[^0-9])'
        )
        OR
        (
            COALESCE(condition_source_concept_name, '') ILIKE '%type 1 diabetes%'
            OR COALESCE(condition_source_concept_name, '') ILIKE '%type i diabetes%'
            OR COALESCE(condition_source_concept_name, '') ILIKE '%diabetes mellitus type 1%'
            OR COALESCE(condition_source_concept_name, '') ILIKE '%diabetes mellitus type i%'
        )
),

gestational_dx AS (
    SELECT DISTINCT
        person_id
    FROM condition_occurrence
    WHERE
        -- ICD10CM gestational diabetes: O24.4*
        regexp_matches(
            UPPER(COALESCE(condition_source_value, '')),
            '(^|[^A-Z0-9])O24\.?4'
        )
        OR
        COALESCE(condition_source_concept_name, '') ILIKE '%gestational diabetes%'
),

t2d_med AS (
    SELECT DISTINCT
        person_id,
        CAST(drug_exposure_start_date AS DATE) AS event_date
    FROM drug_exposure
    WHERE EXISTS (
        SELECT 1
        FROM (
            VALUES
                ('metformin'), ('glucophage'), ('fortamet'), ('glumetza'), ('riomet'),
                ('sulfonylurea'), ('glipizide'), ('glucotrol'), ('glyburide'), ('diabeta'), ('glynase'),
                ('glimepiride'), ('amaryl'),
                ('pioglitazone'), ('actos'), ('rosiglitazone'), ('avandia'),
                ('sitagliptin'), ('januvia'), ('saxagliptin'), ('onglyza'),
                ('linagliptin'), ('tradjenta'), ('alogliptin'), ('nesina'),
                ('empagliflozin'), ('jardiance'), ('dapagliflozin'), ('farxiga'),
                ('canagliflozin'), ('invokana'), ('ertugliflozin'), ('steglatro'),
                ('liraglutide'), ('victoza'), ('semaglutide'), ('ozempic'), ('rybelsus'),
                ('dulaglutide'), ('trulicity'), ('exenatide'), ('byetta'), ('bydureon'),
                ('tirzepatide'), ('mounjaro'),
                ('acarbose'), ('precose'), ('miglitol'), ('glyset'),
                ('repaglinide'), ('prandin'), ('nateglinide'), ('starlix')
        ) AS meds(keyword)
        WHERE
            COALESCE(drug_source_value, '') ILIKE '%' || keyword || '%'
            OR COALESCE(drug_concept_name, '') ILIKE '%' || keyword || '%'
            OR COALESCE(drug_source_concept_code, '') ILIKE '%' || keyword || '%'
    )
),

abnormal_labs AS (
    SELECT DISTINCT
        person_id,
        CAST(measurement_date AS DATE) AS event_date
    FROM measurement
    WHERE
        value_as_number IS NOT NULL
        AND (
            -- HbA1c diagnostic threshold
            (
                (
                    measurement_source_value ILIKE '%a1c%'
                    OR measurement_source_value ILIKE '%hba1c%'
                    OR measurement_source_value ILIKE '%hemoglobin a1c%'
                    OR measurement_source_value ILIKE '%glycohemoglobin%'
                )
                AND value_as_number >= 6.5
                AND value_as_number < 25
            )

            OR

            -- Fasting plasma glucose threshold, assumed mg/dL
            (
                (
                    measurement_source_value ILIKE '%fasting glucose%'
                    OR measurement_source_value ILIKE '%fasting blood glucose%'
                    OR measurement_source_value ILIKE '%fpg%'
                )
                AND value_as_number >= 126
                AND value_as_number < 1000
            )

            OR

            -- Random glucose diagnostic threshold, assumed mg/dL
            (
                (
                    measurement_source_value ILIKE '%random glucose%'
                    OR measurement_source_value ILIKE '%random blood glucose%'
                    OR measurement_source_value ILIKE '%glucose random%'
                )
                AND value_as_number >= 200
                AND value_as_number < 1000
            )

            OR

            -- 2-hour OGTT glucose diagnostic threshold, assumed mg/dL
            (
                (
                    measurement_source_value ILIKE '%ogtt%'
                    OR measurement_source_value ILIKE '%oral glucose tolerance%'
                    OR measurement_source_value ILIKE '%2 hour glucose%'
                    OR measurement_source_value ILIKE '%2-hour glucose%'
                    OR measurement_source_value ILIKE '%two hour glucose%'
                )
                AND value_as_number >= 200
                AND value_as_number < 1000
            )
        )
),

evidence_summary AS (
    SELECT
        p.person_id,

        COUNT(DISTINCT t2d_dx.event_date) AS t2d_dx_dates,
        COUNT(DISTINCT t1d_dx.event_date) AS t1d_dx_dates,
        COUNT(DISTINCT t2d_med.event_date) AS t2d_med_dates,
        COUNT(DISTINCT abnormal_labs.event_date) AS abnormal_lab_dates,

        MAX(CASE WHEN gestational_dx.person_id IS NOT NULL THEN 1 ELSE 0 END) AS has_gestational_dx

    FROM person p
    LEFT JOIN t2d_dx
        ON p.person_id = t2d_dx.person_id
    LEFT JOIN t1d_dx
        ON p.person_id = t1d_dx.person_id
    LEFT JOIN t2d_med
        ON p.person_id = t2d_med.person_id
    LEFT JOIN abnormal_labs
        ON p.person_id = abnormal_labs.person_id
    LEFT JOIN gestational_dx
        ON p.person_id = gestational_dx.person_id
    GROUP BY
        p.person_id
)

SELECT DISTINCT
    person_id
FROM evidence_summary
WHERE
    (
        -- Strong diagnosis evidence
        t2d_dx_dates >= 2

        -- Diagnosis plus supporting evidence
        OR (
            t2d_dx_dates >= 1
            AND (
                t2d_med_dates >= 1
                OR abnormal_lab_dates >= 1
            )
        )

        -- Treatment plus laboratory evidence
        OR (
            t2d_med_dates >= 1
            AND abnormal_lab_dates >= 1
        )

        -- Repeated abnormal laboratory evidence
        OR abnormal_lab_dates >= 2
    )

    -- Guard against likely type 1-only cases without any T2D diagnosis
    AND NOT (
        t1d_dx_dates > 0
        AND t2d_dx_dates = 0
    )

    -- Guard against gestational-only diabetes without any T2D diagnosis
    AND NOT (
        has_gestational_dx = 1
        AND t2d_dx_dates = 0
    )