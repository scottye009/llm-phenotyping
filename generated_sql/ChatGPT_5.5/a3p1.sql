WITH adult_person AS (
    SELECT
        person_id
    FROM person
    WHERE
        year_of_birth IS NULL
        OR (EXTRACT(YEAR FROM CURRENT_DATE) - year_of_birth) >= 18
),

t2dm_dx AS (
    SELECT DISTINCT
        person_id,
        CAST(condition_start_date AS DATE) AS dx_date
    FROM condition_occurrence
    WHERE
        condition_source_value IS NOT NULL
        AND (
            -- ICD10CM type 2 diabetes mellitus
            UPPER(REPLACE(condition_source_value, '.', '')) LIKE 'E11%'

            -- ICD9CM diabetes codes with fifth digit 0 or 2 indicate type 2 / unspecified type
            OR regexp_matches(REPLACE(condition_source_value, '.', ''), '^250[0-9]{2}[02]$')
            OR regexp_matches(REPLACE(condition_source_value, '.', ''), '^250[02]$')
        )
),

t1dm_dx AS (
    SELECT DISTINCT
        person_id
    FROM condition_occurrence
    WHERE
        condition_source_value IS NOT NULL
        AND (
            -- ICD10CM type 1 diabetes mellitus
            UPPER(REPLACE(condition_source_value, '.', '')) LIKE 'E10%'

            -- ICD9CM diabetes codes with fifth digit 1 or 3 indicate type 1 / juvenile type
            OR regexp_matches(REPLACE(condition_source_value, '.', ''), '^250[0-9]{2}[13]$')
            OR regexp_matches(REPLACE(condition_source_value, '.', ''), '^250[13]$')
        )
),

t2dm_dx_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT dx_date) AS t2dm_dx_dates
    FROM t2dm_dx
    WHERE dx_date IS NOT NULL
    GROUP BY person_id
),

t2dm_med AS (
    SELECT DISTINCT
        de.person_id
    FROM drug_exposure de
    WHERE EXISTS (
        SELECT 1
        FROM (
            VALUES
                -- Biguanide
                ('metformin'), ('glucophage'), ('fortamet'), ('glumetza'), ('riomet'),

                -- Sulfonylureas
                ('glipizide'), ('glucotrol'),
                ('glyburide'), ('glibenclamide'), ('diabeta'), ('glynase'), ('micronase'),
                ('glimepiride'), ('amaryl'),

                -- Thiazolidinediones
                ('pioglitazone'), ('actos'),
                ('rosiglitazone'), ('avandia'),

                -- DPP-4 inhibitors
                ('sitagliptin'), ('januvia'),
                ('saxagliptin'), ('onglyza'),
                ('linagliptin'), ('tradjenta'),
                ('alogliptin'), ('nesina'),

                -- GLP-1 receptor agonists
                ('exenatide'), ('byetta'), ('bydureon'),
                ('liraglutide'), ('victoza'),
                ('dulaglutide'), ('trulicity'),
                ('semaglutide'), ('ozempic'), ('rybelsus'),
                ('lixisenatide'), ('adlyxin'),

                -- SGLT2 inhibitors
                ('canagliflozin'), ('invokana'),
                ('dapagliflozin'), ('farxiga'),
                ('empagliflozin'), ('jardiance'),
                ('ertugliflozin'), ('steglatro'),

                -- Meglitinides
                ('repaglinide'), ('prandin'),
                ('nateglinide'), ('starlix'),

                -- Alpha-glucosidase inhibitors
                ('acarbose'), ('precose'),
                ('miglitol'), ('glyset')
        ) AS kw(term)
        WHERE
            de.drug_source_value ILIKE '%' || kw.term || '%'
            OR de.drug_concept_name ILIKE '%' || kw.term || '%'
            OR de.drug_source_concept_code ILIKE '%' || kw.term || '%'
    )
),

diabetes_lab AS (
    SELECT DISTINCT
        person_id
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
                    OR measurement_concept_name ILIKE '%a1c%'
                    OR measurement_concept_name ILIKE '%hba1c%'
                    OR measurement_concept_name ILIKE '%hemoglobin a1c%'
                )
                AND value_as_number >= 6.5
            )

            OR

            -- Fasting glucose diagnostic threshold, assumed mg/dL when unit is absent or compatible
            (
                (
                    measurement_source_value ILIKE '%fasting%glucose%'
                    OR measurement_source_value ILIKE '%glucose%fasting%'
                    OR measurement_concept_name ILIKE '%fasting%glucose%'
                    OR measurement_concept_name ILIKE '%glucose%fasting%'
                )
                AND value_as_number >= 126
                AND (
                    unit_source_value IS NULL
                    OR unit_source_value ILIKE '%mg/dl%'
                    OR unit_source_value ILIKE '%mg/dL%'
                    OR unit_concept_name ILIKE '%milligram per deciliter%'
                )
            )

            OR

            -- Random glucose diagnostic threshold, assumed mg/dL when unit is absent or compatible
            (
                (
                    measurement_source_value ILIKE '%random%glucose%'
                    OR measurement_source_value ILIKE '%glucose%random%'
                    OR measurement_concept_name ILIKE '%random%glucose%'
                    OR measurement_concept_name ILIKE '%glucose%random%'
                )
                AND value_as_number >= 200
                AND (
                    unit_source_value IS NULL
                    OR unit_source_value ILIKE '%mg/dl%'
                    OR unit_source_value ILIKE '%mg/dL%'
                    OR unit_concept_name ILIKE '%milligram per deciliter%'
                )
            )

            OR

            -- 2-hour / OGTT glucose diagnostic threshold, assumed mg/dL when unit is absent or compatible
            (
                (
                    measurement_source_value ILIKE '%ogtt%'
                    OR measurement_source_value ILIKE '%oral glucose tolerance%'
                    OR measurement_source_value ILIKE '%2 hour%glucose%'
                    OR measurement_source_value ILIKE '%2-hour%glucose%'
                    OR measurement_source_value ILIKE '%two hour%glucose%'
                    OR measurement_concept_name ILIKE '%ogtt%'
                    OR measurement_concept_name ILIKE '%oral glucose tolerance%'
                    OR measurement_concept_name ILIKE '%2 hour%glucose%'
                    OR measurement_concept_name ILIKE '%2-hour%glucose%'
                    OR measurement_concept_name ILIKE '%two hour%glucose%'
                )
                AND value_as_number >= 200
                AND (
                    unit_source_value IS NULL
                    OR unit_source_value ILIKE '%mg/dl%'
                    OR unit_source_value ILIKE '%mg/dL%'
                    OR unit_concept_name ILIKE '%milligram per deciliter%'
                )
            )
        )
),

evidence AS (
    SELECT
        ap.person_id,
        COALESCE(dx.t2dm_dx_dates, 0) AS t2dm_dx_dates,
        CASE WHEN med.person_id IS NOT NULL THEN 1 ELSE 0 END AS has_t2dm_med,
        CASE WHEN lab.person_id IS NOT NULL THEN 1 ELSE 0 END AS has_diabetes_lab,
        CASE WHEN t1.person_id IS NOT NULL THEN 1 ELSE 0 END AS has_t1dm_dx
    FROM adult_person ap
    LEFT JOIN t2dm_dx_summary dx
        ON ap.person_id = dx.person_id
    LEFT JOIN t2dm_med med
        ON ap.person_id = med.person_id
    LEFT JOIN diabetes_lab lab
        ON ap.person_id = lab.person_id
    LEFT JOIN t1dm_dx t1
        ON ap.person_id = t1.person_id
)

SELECT DISTINCT
    person_id
FROM evidence
WHERE
    (
        t2dm_dx_dates >= 2
        OR (t2dm_dx_dates >= 1 AND has_t2dm_med = 1)
        OR (t2dm_dx_dates >= 1 AND has_diabetes_lab = 1)
        OR (has_t2dm_med = 1 AND has_diabetes_lab = 1)
    )
    -- Exclude likely pure type 1 diabetes without any T2DM diagnosis evidence
    AND NOT (has_t1dm_dx = 1 AND t2dm_dx_dates = 0)
ORDER BY person_id;