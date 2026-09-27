WITH
-- Normalize source diagnosis codes and retain source diagnosis text.
condition_clean AS (
    SELECT
        person_id,
        COALESCE(
            CAST(condition_start_date AS DATE),
            CAST(condition_start_datetime AS DATE)
        ) AS event_date,
        UPPER(
            regexp_replace(
                COALESCE(condition_source_value, ''),
                '[^A-Za-z0-9]',
                '',
                'g'
            )
        ) AS source_code,
        LOWER(COALESCE(condition_source_concept_name, '')) AS source_name
    FROM condition_occurrence
),

-- Explicit type 2 diabetes diagnosis evidence.
t2_diagnoses AS (
    SELECT DISTINCT
        person_id,
        event_date
    FROM condition_clean
    WHERE
        -- ICD-10-CM E11*
        regexp_matches(source_code, '^E11[A-Z0-9]*$')

        -- ICD-9-CM 250.x0 or 250.x2
        OR regexp_matches(source_code, '^250[0-9][02]$')

        -- Explicit source diagnosis text fallback
        OR source_name ILIKE '%type 2 diabetes%'
        OR source_name ILIKE '%type ii diabetes%'
        OR source_name ILIKE '%type 2 diabetes mellitus%'
        OR source_name ILIKE '%non-insulin-dependent diabetes%'
        OR source_name ILIKE '%non insulin dependent diabetes%'
),

-- Competing diabetes-type evidence.
competing_diagnoses AS (
    SELECT DISTINCT
        person_id,
        event_date
    FROM condition_clean
    WHERE
        -- ICD-10-CM type 1, secondary, drug-induced, or other specified diabetes
        regexp_matches(source_code, '^E10[A-Z0-9]*$')
        OR regexp_matches(source_code, '^E08[A-Z0-9]*$')
        OR regexp_matches(source_code, '^E09[A-Z0-9]*$')
        OR regexp_matches(source_code, '^E13[A-Z0-9]*$')

        -- ICD-9-CM type 1 diabetes: 250.x1 or 250.x3
        OR regexp_matches(source_code, '^250[0-9][13]$')

        -- Explicit source diagnosis text fallback
        OR source_name ILIKE '%type 1 diabetes%'
        OR source_name ILIKE '%type i diabetes%'
        OR source_name ILIKE '%insulin-dependent diabetes%'
        OR source_name ILIKE '%insulin dependent diabetes%'
),

-- Normalize laboratory source names, units, dates, and numeric values.
measurement_clean AS (
    SELECT
        person_id,
        COALESCE(
            CAST(measurement_date AS DATE),
            CAST(measurement_datetime AS DATE)
        ) AS event_date,
        LOWER(COALESCE(measurement_source_value, '')) AS lab_name,
        LOWER(
            CONCAT_WS(
                ' ',
                COALESCE(unit_source_value, ''),
                COALESCE(unit_concept_name, '')
            )
        ) AS unit_text,
        value_as_number
    FROM measurement
    WHERE value_as_number IS NOT NULL
),

-- Convert glucose values to mg/dL where units permit conversion.
measurement_normalized AS (
    SELECT
        person_id,
        event_date,
        lab_name,
        unit_text,
        value_as_number,
        CASE
            WHEN unit_text ILIKE '%mmol/l%'
              OR unit_text ILIKE '%mmol per l%'
              OR unit_text ILIKE '%mmol l%'
                THEN value_as_number * 18.0182

            WHEN unit_text = ''
              OR unit_text ILIKE '%mg/dl%'
              OR unit_text ILIKE '%mg per dl%'
              OR unit_text ILIKE '%mg dl%'
                THEN value_as_number

            ELSE NULL
        END AS glucose_mg_dl
    FROM measurement_clean
),

-- ADA-aligned abnormal laboratory evidence.
qualifying_labs AS (
    SELECT DISTINCT
        person_id,
        event_date
    FROM measurement_normalized
    WHERE
        -- HbA1c >= 6.5% or >= 48 mmol/mol
        (
            (
                lab_name ILIKE '%hemoglobin a1c%'
                OR lab_name ILIKE '%haemoglobin a1c%'
                OR lab_name ILIKE '%hba1c%'
                OR lab_name ILIKE '%glycohemoglobin%'
                OR lab_name ILIKE '%glycated hemoglobin%'
                OR lab_name ILIKE '%a1c%'
            )
            AND
            (
                (
                    unit_text ILIKE '%mmol/mol%'
                    AND value_as_number >= 48
                )
                OR
                (
                    unit_text NOT ILIKE '%mmol/mol%'
                    AND value_as_number >= 6.5
                    AND value_as_number <= 30
                )
            )
        )

        -- Fasting plasma glucose >= 126 mg/dL
        OR
        (
            (
                lab_name ILIKE '%fasting glucose%'
                OR lab_name ILIKE '%glucose fasting%'
                OR lab_name ILIKE '%fasting plasma glucose%'
                OR lab_name ILIKE '%glucose, fasting%'
            )
            AND glucose_mg_dl >= 126
        )

        -- 2-hour oral glucose tolerance test >= 200 mg/dL
        OR
        (
            (
                lab_name ILIKE '%2 hour glucose%'
                OR lab_name ILIKE '%2-hour glucose%'
                OR lab_name ILIKE '%2 hr glucose%'
                OR lab_name ILIKE '%120 min glucose%'
                OR lab_name ILIKE '%glucose tolerance 2 hour%'
                OR lab_name ILIKE '%glucose tolerance, 2 hour%'
                OR lab_name ILIKE '%ogtt 2 hour%'
                OR lab_name ILIKE '%post load glucose%'
                OR lab_name ILIKE '%post-load glucose%'
            )
            AND glucose_mg_dl >= 200
        )
),

-- Generic and brand-name supportive medication keywords.
t2_medication_keywords(keyword) AS (
    VALUES
        ('metformin'),
        ('glucophage'),
        ('glumetza'),
        ('fortamet'),

        ('glyburide'),
        ('glibenclamide'),
        ('diabeta'),
        ('glynase'),
        ('micronase'),
        ('glipizide'),
        ('glucotrol'),
        ('glimepiride'),
        ('amaryl'),

        ('pioglitazone'),
        ('actos'),
        ('rosiglitazone'),
        ('avandia'),

        ('sitagliptin'),
        ('januvia'),
        ('saxagliptin'),
        ('onglyza'),
        ('linagliptin'),
        ('tradjenta'),
        ('alogliptin'),
        ('nesina'),

        ('empagliflozin'),
        ('jardiance'),
        ('dapagliflozin'),
        ('farxiga'),
        ('canagliflozin'),
        ('invokana'),
        ('ertugliflozin'),
        ('steglatro'),

        ('semaglutide'),
        ('ozempic'),
        ('rybelsus'),
        ('dulaglutide'),
        ('trulicity'),
        ('liraglutide'),
        ('victoza'),
        ('exenatide'),
        ('byetta'),
        ('bydureon'),
        ('lixisenatide'),
        ('adlyxin'),
        ('tirzepatide'),
        ('mounjaro'),

        ('repaglinide'),
        ('prandin'),
        ('nateglinide'),
        ('starlix'),

        ('acarbose'),
        ('precose'),
        ('miglitol'),
        ('glyset'),

        ('janumet'),
        ('synjardy'),
        ('xigduo'),
        ('invokamet'),
        ('trijardy'),
        ('glyxambi'),
        ('qtern')
),

-- Search multiple available medication source fields.
medication_clean AS (
    SELECT
        person_id,
        COALESCE(
            CAST(drug_exposure_start_date AS DATE),
            CAST(drug_exposure_start_datetime AS DATE)
        ) AS event_date,
        LOWER(
            CONCAT_WS(
                ' ',
                COALESCE(drug_source_value, ''),
                COALESCE(drug_concept_name, ''),
                COALESCE(drug_source_concept_code, '')
            )
        ) AS medication_text
    FROM drug_exposure
),

-- Supportive type 2 medication evidence.
t2_medications AS (
    SELECT DISTINCT
        m.person_id,
        m.event_date
    FROM medication_clean AS m
    WHERE EXISTS (
        SELECT 1
        FROM t2_medication_keywords AS k
        WHERE m.medication_text ILIKE '%' || k.keyword || '%'
    )
),

-- Count distinct dates to reduce duplicate-row effects.
t2_diagnosis_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS t2_diagnosis_dates
    FROM t2_diagnoses
    GROUP BY person_id
),

competing_diagnosis_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS competing_diagnosis_dates
    FROM competing_diagnoses
    GROUP BY person_id
),

lab_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS qualifying_lab_dates
    FROM qualifying_labs
    GROUP BY person_id
),

medication_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS t2_medication_dates
    FROM t2_medications
    GROUP BY person_id
)

-- Final conservative type 2 diabetes phenotype.
SELECT DISTINCT
    p.person_id
FROM person AS p
LEFT JOIN t2_diagnosis_summary AS d
    ON p.person_id = d.person_id
LEFT JOIN competing_diagnosis_summary AS c
    ON p.person_id = c.person_id
LEFT JOIN lab_summary AS l
    ON p.person_id = l.person_id
LEFT JOIN medication_summary AS m
    ON p.person_id = m.person_id
WHERE
    (
        -- Rule A: repeated explicit type 2 diagnoses
        COALESCE(d.t2_diagnosis_dates, 0) >= 2

        -- Rule B: one type 2 diagnosis plus supporting evidence
        OR
        (
            COALESCE(d.t2_diagnosis_dates, 0) >= 1
            AND
            (
                COALESCE(l.qualifying_lab_dates, 0) >= 1
                OR COALESCE(m.t2_medication_dates, 0) >= 1
            )
        )

        -- Rule C: repeated diagnostic labs plus medication support
        OR
        (
            COALESCE(l.qualifying_lab_dates, 0) >= 2
            AND COALESCE(m.t2_medication_dates, 0) >= 1
        )
    )

    -- Exclude unresolved competing diabetes classifications.
    AND
    (
        COALESCE(c.competing_diagnosis_dates, 0) = 0
        OR COALESCE(d.t2_diagnosis_dates, 0)
           > COALESCE(c.competing_diagnosis_dates, 0)
    )
ORDER BY p.person_id;