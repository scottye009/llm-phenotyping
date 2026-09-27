WITH condition_norm AS (
    SELECT
        person_id,
        CAST(condition_start_date AS DATE) AS event_date,
        UPPER(REPLACE(COALESCE(condition_source_value, ''), '.', '')) AS src_code_compact,
        LOWER(COALESCE(condition_source_value, '')) AS src_code_raw,
        LOWER(COALESCE(condition_source_concept_name, '')) AS src_name,
        LOWER(COALESCE(condition_concept_name, '')) AS concept_name
    FROM condition_occurrence
),

t2dm_dx AS (
    SELECT DISTINCT
        person_id,
        event_date
    FROM condition_norm
    WHERE
        -- ICD-10-CM E11.* = type 2 diabetes mellitus
        regexp_matches(src_code_compact, '^E11[A-Z0-9]*$')

        -- ICD-9-CM 250.x0 or 250.x2 = type 2 or unspecified type
        OR regexp_matches(src_code_compact, '^250[0-9][02]$')

        -- Text fallback from SHIRE source/concept names
        OR src_name ILIKE '%type 2 diabetes%'
        OR src_name ILIKE '%type ii diabetes%'
        OR src_name ILIKE '%diabetes mellitus type 2%'
        OR src_name ILIKE '%diabetes mellitus type ii%'
        OR src_name ILIKE '%t2dm%'
        OR src_name ILIKE '%non-insulin dependent diabetes%'
        OR concept_name ILIKE '%type 2 diabetes%'
        OR concept_name ILIKE '%type ii diabetes%'
        OR concept_name ILIKE '%diabetes mellitus type 2%'
        OR concept_name ILIKE '%t2dm%'
),

exclusion_dx AS (
    SELECT DISTINCT
        person_id
    FROM condition_norm
    WHERE
        -- Type 1 diabetes
        regexp_matches(src_code_compact, '^E10[A-Z0-9]*$')
        OR regexp_matches(src_code_compact, '^250[0-9][13]$')
        OR src_name ILIKE '%type 1 diabetes%'
        OR src_name ILIKE '%type i diabetes%'
        OR src_name ILIKE '%diabetes mellitus type 1%'
        OR src_name ILIKE '%diabetes mellitus type i%'
        OR src_name ILIKE '%t1dm%'
        OR concept_name ILIKE '%type 1 diabetes%'
        OR concept_name ILIKE '%type i diabetes%'
        OR concept_name ILIKE '%t1dm%'

        -- Gestational diabetes
        OR regexp_matches(src_code_compact, '^O244[A-Z0-9]*$')
        OR src_name ILIKE '%gestational diabetes%'
        OR concept_name ILIKE '%gestational diabetes%'

        -- Secondary, drug-induced, or other specified diabetes
        OR regexp_matches(src_code_compact, '^E08[A-Z0-9]*$')
        OR regexp_matches(src_code_compact, '^E09[A-Z0-9]*$')
        OR regexp_matches(src_code_compact, '^E13[A-Z0-9]*$')
        OR src_name ILIKE '%secondary diabetes%'
        OR src_name ILIKE '%drug-induced diabetes%'
        OR src_name ILIKE '%postpancreatectomy diabetes%'
        OR concept_name ILIKE '%secondary diabetes%'
        OR concept_name ILIKE '%drug-induced diabetes%'
        OR concept_name ILIKE '%postpancreatectomy diabetes%'
),

med_keywords AS (
    SELECT *
    FROM (
        VALUES
            ('metformin'), ('glucophage'), ('fortamet'), ('glumetza'), ('riomet'),

            ('glipizide'), ('glucotrol'),
            ('glyburide'), ('glibenclamide'), ('diabeta'), ('glynase'), ('micronase'),
            ('glimepiride'), ('amaryl'),
            ('chlorpropamide'), ('tolbutamide'), ('tolazamide'),

            ('pioglitazone'), ('actos'),
            ('rosiglitazone'), ('avandia'),

            ('sitagliptin'), ('januvia'),
            ('saxagliptin'), ('onglyza'),
            ('linagliptin'), ('tradjenta'),
            ('alogliptin'), ('nesina'),

            ('exenatide'), ('byetta'), ('bydureon'),
            ('liraglutide'), ('victoza'),
            ('dulaglutide'), ('trulicity'),
            ('semaglutide'), ('ozempic'), ('rybelsus'),
            ('lixisenatide'), ('adlyxin'),
            ('tirzepatide'), ('mounjaro'),

            ('canagliflozin'), ('invokana'),
            ('dapagliflozin'), ('farxiga'),
            ('empagliflozin'), ('jardiance'),
            ('ertugliflozin'), ('steglatro'),

            ('repaglinide'), ('prandin'),
            ('nateglinide'), ('starlix'),

            ('acarbose'), ('precose'),
            ('miglitol'), ('glyset'),

            ('janumet'), ('kombiglyze'), ('jentadueto'),
            ('synjardy'), ('xigduo'), ('invokamet'),
            ('glyxambi'), ('segluromet')
    ) AS t(keyword)
),

t2dm_med AS (
    SELECT DISTINCT
        d.person_id,
        CAST(d.drug_exposure_start_date AS DATE) AS event_date
    FROM drug_exposure d
    WHERE
        EXISTS (
            SELECT 1
            FROM med_keywords k
            WHERE
                COALESCE(d.drug_source_value, '') ILIKE '%' || k.keyword || '%'
                OR COALESCE(d.drug_concept_name, '') ILIKE '%' || k.keyword || '%'
                OR COALESCE(d.drug_source_concept_code, '') ILIKE '%' || k.keyword || '%'
        )
        -- Do not let insulin-only rows define T2DM medication evidence.
        AND NOT (
            COALESCE(d.drug_source_value, '') ILIKE '%insulin%'
            OR COALESCE(d.drug_concept_name, '') ILIKE '%insulin%'
            OR COALESCE(d.drug_source_concept_code, '') ILIKE '%insulin%'
        )
),

measurement_norm AS (
    SELECT
        person_id,
        CAST(measurement_date AS DATE) AS event_date,
        LOWER(COALESCE(measurement_source_value, '')) AS meas_src,
        LOWER(COALESCE(measurement_concept_name, '')) AS meas_name,
        LOWER(COALESCE(unit_source_value, '')) AS unit_src,
        LOWER(COALESCE(unit_concept_name, '')) AS unit_name,
        value_as_number
    FROM measurement
    WHERE value_as_number IS NOT NULL
),

abnormal_labs AS (
    SELECT DISTINCT
        person_id,
        event_date
    FROM measurement_norm
    WHERE
        -- HbA1c >= 6.5% or >= 48 mmol/mol.
        (
            (
                meas_src ILIKE '%a1c%'
                OR meas_src ILIKE '%hba1c%'
                OR meas_src ILIKE '%hemoglobin a1c%'
                OR meas_src ILIKE '%glycohemoglobin%'
                OR meas_name ILIKE '%a1c%'
                OR meas_name ILIKE '%hba1c%'
                OR meas_name ILIKE '%hemoglobin a1c%'
            )
            AND (
                (
                    (
                        unit_src = ''
                        OR unit_src ILIKE '%percent%'
                        OR unit_src ILIKE '%/%'
                        OR unit_name ILIKE '%percent%'
                    )
                    AND value_as_number >= 6.5
                    AND value_as_number < 25
                )
                OR (
                    (
                        unit_src ILIKE '%mmol/mol%'
                        OR unit_name ILIKE '%mmol/mol%'
                    )
                    AND value_as_number >= 48
                    AND value_as_number < 200
                )
            )
        )

        OR

        -- Fasting glucose >= 126 mg/dL or >= 7.0 mmol/L.
        (
            (
                meas_src ILIKE '%fasting%glucose%'
                OR meas_src ILIKE '%glucose%fasting%'
                OR meas_src ILIKE '%fasting blood glucose%'
                OR meas_src ILIKE '%fasting plasma glucose%'
                OR meas_src ILIKE '%fpg%'
                OR meas_name ILIKE '%fasting%glucose%'
                OR meas_name ILIKE '%glucose%fasting%'
                OR meas_name ILIKE '%fpg%'
            )
            AND NOT (
                meas_src ILIKE '%urine%'
                OR meas_name ILIKE '%urine%'
            )
            AND (
                (
                    (
                        unit_src = ''
                        OR unit_src ILIKE '%mg/dl%'
                        OR unit_src ILIKE '%mg/dL%'
                        OR unit_name ILIKE '%mg/dl%'
                        OR unit_name ILIKE '%milligram per deciliter%'
                    )
                    AND value_as_number >= 126
                    AND value_as_number < 1000
                )
                OR (
                    (
                        unit_src ILIKE '%mmol%'
                        OR unit_name ILIKE '%mmol%'
                    )
                    AND value_as_number >= 7.0
                    AND value_as_number < 60
                )
            )
        )

        OR

        -- Random glucose >= 200 mg/dL or >= 11.1 mmol/L.
        -- Require random/glucose context to avoid capturing unrelated glucose tests too broadly.
        (
            (
                meas_src ILIKE '%random%glucose%'
                OR meas_src ILIKE '%glucose%random%'
                OR meas_src ILIKE '%random blood glucose%'
                OR meas_name ILIKE '%random%glucose%'
                OR meas_name ILIKE '%glucose%random%'
            )
            AND NOT (
                meas_src ILIKE '%urine%'
                OR meas_name ILIKE '%urine%'
            )
            AND (
                (
                    (
                        unit_src = ''
                        OR unit_src ILIKE '%mg/dl%'
                        OR unit_name ILIKE '%mg/dl%'
                        OR unit_name ILIKE '%milligram per deciliter%'
                    )
                    AND value_as_number >= 200
                    AND value_as_number < 1000
                )
                OR (
                    (
                        unit_src ILIKE '%mmol%'
                        OR unit_name ILIKE '%mmol%'
                    )
                    AND value_as_number >= 11.1
                    AND value_as_number < 60
                )
            )
        )

        OR

        -- 2-hour OGTT glucose >= 200 mg/dL or >= 11.1 mmol/L.
        (
            (
                meas_src ILIKE '%ogtt%'
                OR meas_src ILIKE '%oral glucose tolerance%'
                OR meas_src ILIKE '%2 hour%glucose%'
                OR meas_src ILIKE '%2-hour%glucose%'
                OR meas_src ILIKE '%two hour%glucose%'
                OR meas_name ILIKE '%ogtt%'
                OR meas_name ILIKE '%oral glucose tolerance%'
                OR meas_name ILIKE '%2 hour%glucose%'
                OR meas_name ILIKE '%2-hour%glucose%'
                OR meas_name ILIKE '%two hour%glucose%'
            )
            AND NOT (
                meas_src ILIKE '%urine%'
                OR meas_name ILIKE '%urine%'
            )
            AND (
                (
                    (
                        unit_src = ''
                        OR unit_src ILIKE '%mg/dl%'
                        OR unit_name ILIKE '%mg/dl%'
                        OR unit_name ILIKE '%milligram per deciliter%'
                    )
                    AND value_as_number >= 200
                    AND value_as_number < 1000
                )
                OR (
                    (
                        unit_src ILIKE '%mmol%'
                        OR unit_name ILIKE '%mmol%'
                    )
                    AND value_as_number >= 11.1
                    AND value_as_number < 60
                )
            )
        )
),

dx_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS t2dm_dx_dates
    FROM t2dm_dx
    WHERE event_date IS NOT NULL
    GROUP BY person_id
),

med_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS t2dm_med_dates
    FROM t2dm_med
    WHERE event_date IS NOT NULL
    GROUP BY person_id
),

lab_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS abnormal_lab_dates
    FROM abnormal_labs
    WHERE event_date IS NOT NULL
    GROUP BY person_id
),

evidence AS (
    SELECT
        p.person_id,
        COALESCE(dx.t2dm_dx_dates, 0) AS t2dm_dx_dates,
        COALESCE(med.t2dm_med_dates, 0) AS t2dm_med_dates,
        COALESCE(lab.abnormal_lab_dates, 0) AS abnormal_lab_dates,
        CASE WHEN ex.person_id IS NOT NULL THEN 1 ELSE 0 END AS has_exclusion_dx
    FROM person p
    LEFT JOIN dx_summary dx
        ON p.person_id = dx.person_id
    LEFT JOIN med_summary med
        ON p.person_id = med.person_id
    LEFT JOIN lab_summary lab
        ON p.person_id = lab.person_id
    LEFT JOIN exclusion_dx ex
        ON p.person_id = ex.person_id
)

SELECT DISTINCT
    person_id
FROM evidence
WHERE
    (
        -- Strong diagnosis evidence.
        t2dm_dx_dates >= 2

        -- One T2DM diagnosis plus medication or lab support.
        OR (
            t2dm_dx_dates >= 1
            AND (
                t2dm_med_dates >= 1
                OR abnormal_lab_dates >= 1
            )
        )

        -- No explicit T2DM diagnosis: require treatment plus lab evidence.
        OR (
            t2dm_dx_dates = 0
            AND t2dm_med_dates >= 1
            AND abnormal_lab_dates >= 1
        )

        -- Repeated diabetes-range labs alone can identify likely diabetes,
        -- but not if there is a clear non-T2DM exclusion diagnosis.
        OR (
            t2dm_dx_dates = 0
            AND abnormal_lab_dates >= 2
            AND has_exclusion_dx = 0
        )
    )

    -- Exclude likely type 1, gestational-only, secondary, or drug-induced diabetes
    -- only when there is no T2DM diagnosis evidence.
    AND NOT (
        has_exclusion_dx = 1
        AND t2dm_dx_dates = 0
    )
ORDER BY person_id;