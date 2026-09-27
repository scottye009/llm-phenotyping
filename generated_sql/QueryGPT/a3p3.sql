WITH
-- Generic and brand names used as supportive type 2 diabetes medication evidence.
medication_keywords(keyword) AS (
    VALUES
        ('metformin'), ('glucophage'), ('fortamet'), ('glumetza'),
        ('glipizide'), ('glucotrol'),
        ('glyburide'), ('glibenclamide'), ('diabeta'), ('micronase'), ('glynase'),
        ('glimepiride'), ('amaryl'),
        ('pioglitazone'), ('actos'),
        ('rosiglitazone'), ('avandia'),
        ('sitagliptin'), ('januvia'), ('janumet'),
        ('saxagliptin'), ('onglyza'), ('kombiglyze'),
        ('linagliptin'), ('tradjenta'), ('jentadueto'),
        ('alogliptin'), ('nesina'), ('kazano'),
        ('empagliflozin'), ('jardiance'), ('synjardy'), ('glyxambi'), ('trijardy'),
        ('dapagliflozin'), ('farxiga'), ('xigduo'), ('qtern'),
        ('canagliflozin'), ('invokana'), ('invokamet'),
        ('ertugliflozin'), ('steglatro'), ('segluromet'),
        ('semaglutide'), ('ozempic'), ('rybelsus'),
        ('liraglutide'), ('victoza'),
        ('dulaglutide'), ('trulicity'),
        ('exenatide'), ('byetta'), ('bydureon'),
        ('tirzepatide'), ('mounjaro'),
        ('acarbose'), ('precose'),
        ('repaglinide'), ('prandin'),
        ('nateglinide'), ('starlix')
),

-- Normalize diagnosis source values so codes match with or without punctuation.
condition_normalized AS (
    SELECT
        person_id,
        CAST(condition_start_date AS DATE) AS condition_date,
        upper(
            regexp_replace(
                coalesce(condition_source_value, ''),
                '[^A-Za-z0-9]',
                '',
                'g'
            )
        ) AS diagnosis_code,
        lower(coalesce(condition_source_concept_name, '')) AS diagnosis_name
    FROM condition_occurrence
),

-- Explicit type 2 diabetes diagnoses: ICD-10-CM E11* or ICD-9-CM 250.x0 / 250.x2.
t2dm_diagnosis_dates AS (
    SELECT DISTINCT
        person_id,
        condition_date
    FROM condition_normalized
    WHERE
        regexp_matches(diagnosis_code, '^E11[A-Z0-9]*$')
        OR regexp_matches(diagnosis_code, '^250[0-9][02]$')
        OR diagnosis_name ILIKE '%type 2 diabetes%'
        OR diagnosis_name ILIKE '%type ii diabetes%'
        OR diagnosis_name ILIKE '%diabetes mellitus type 2%'
        OR diagnosis_name ILIKE '%t2dm%'
),

-- Strong competing diagnoses: type 1, secondary, drug-induced, or other specified diabetes.
competing_diabetes_persons AS (
    SELECT DISTINCT
        person_id
    FROM condition_normalized
    WHERE
        regexp_matches(diagnosis_code, '^E10[A-Z0-9]*$')
        OR regexp_matches(diagnosis_code, '^E08[A-Z0-9]*$')
        OR regexp_matches(diagnosis_code, '^E09[A-Z0-9]*$')
        OR regexp_matches(diagnosis_code, '^E13[A-Z0-9]*$')
        OR regexp_matches(diagnosis_code, '^250[0-9][13]$')
        OR diagnosis_name ILIKE '%type 1 diabetes%'
        OR diagnosis_name ILIKE '%type i diabetes%'
        OR diagnosis_name ILIKE '%diabetes mellitus type 1%'
        OR diagnosis_name ILIKE '%t1dm%'
        OR diagnosis_name ILIKE '%secondary diabetes%'
        OR diagnosis_name ILIKE '%drug-induced diabetes%'
        OR diagnosis_name ILIKE '%drug induced diabetes%'
),

-- Gestational diabetes is relevant only when classifying from labs plus medication.
gestational_diabetes_persons AS (
    SELECT DISTINCT
        person_id
    FROM condition_normalized
    WHERE
        regexp_matches(diagnosis_code, '^O24[A-Z0-9]*$')
        OR diagnosis_name ILIKE '%gestational diabetes%'
),

-- Prepare laboratory source text and units.
measurement_normalized AS (
    SELECT
        person_id,
        CAST(measurement_date AS DATE) AS measurement_date,
        lower(coalesce(measurement_source_value, '')) AS test_name,
        value_as_number,
        lower(
            coalesce(unit_source_value, '') || ' ' ||
            coalesce(unit_concept_name, '')
        ) AS unit_text
    FROM measurement
    WHERE value_as_number IS NOT NULL
),

-- ADA diagnostic-range laboratory results.
abnormal_diabetes_lab_dates AS (
    SELECT DISTINCT
        person_id,
        measurement_date
    FROM measurement_normalized
    WHERE
        -- HbA1c in percent or mmol/mol.
        (
            (
                test_name ILIKE '%hba1c%'
                OR test_name ILIKE '%a1c%'
                OR test_name ILIKE '%hemoglobin a1c%'
                OR test_name ILIKE '%haemoglobin a1c%'
                OR test_name ILIKE '%glycohemoglobin%'
                OR test_name ILIKE '%glycated hemoglobin%'
            )
            AND
            (
                (
                    (
                        unit_text ILIKE '%\%%'
                        OR unit_text ILIKE '%percent%'
                        OR unit_text = ' '
                    )
                    AND value_as_number >= 6.5
                    AND value_as_number <= 25
                )
                OR
                (
                    unit_text ILIKE '%mmol/mol%'
                    AND value_as_number >= 48
                )
            )
        )

        OR

        -- Fasting plasma glucose.
        (
            test_name ILIKE '%glucose%'
            AND
            (
                test_name ILIKE '%fasting%'
                OR test_name ILIKE '%fasted%'
                OR test_name ILIKE '%fpg%'
            )
            AND
            (
                (
                    (
                        unit_text ILIKE '%mg/dl%'
                        OR unit_text ILIKE '%mg per dl%'
                        OR unit_text = ' '
                    )
                    AND value_as_number >= 126
                )
                OR
                (
                    unit_text ILIKE '%mmol/l%'
                    AND value_as_number >= 7.0
                )
            )
        )

        OR

        -- Two-hour oral glucose tolerance test.
        (
            test_name ILIKE '%glucose%'
            AND
            (
                test_name ILIKE '%ogtt%'
                OR test_name ILIKE '%oral glucose tolerance%'
                OR test_name ILIKE '%2 hour%'
                OR test_name ILIKE '%2-hour%'
                OR test_name ILIKE '%two hour%'
                OR test_name ILIKE '%post load%'
                OR test_name ILIKE '%post-load%'
            )
            AND
            (
                (
                    (
                        unit_text ILIKE '%mg/dl%'
                        OR unit_text ILIKE '%mg per dl%'
                        OR unit_text = ' '
                    )
                    AND value_as_number >= 200
                )
                OR
                (
                    unit_text ILIKE '%mmol/l%'
                    AND value_as_number >= 11.1
                )
            )
        )

        OR

        -- Random or casual glucose.
        (
            test_name ILIKE '%glucose%'
            AND
            (
                test_name ILIKE '%random%'
                OR test_name ILIKE '%casual%'
            )
            AND
            (
                (
                    (
                        unit_text ILIKE '%mg/dl%'
                        OR unit_text ILIKE '%mg per dl%'
                        OR unit_text = ' '
                    )
                    AND value_as_number >= 200
                )
                OR
                (
                    unit_text ILIKE '%mmol/l%'
                    AND value_as_number >= 11.1
                )
            )
        )
),

-- Match supportive medications using source-oriented text fields.
t2dm_medication_persons AS (
    SELECT DISTINCT
        d.person_id
    FROM drug_exposure AS d
    WHERE EXISTS (
        SELECT 1
        FROM medication_keywords AS k
        WHERE
            lower(
                coalesce(d.drug_source_value, '') || ' ' ||
                coalesce(d.drug_concept_name, '') || ' ' ||
                coalesce(d.drug_source_concept_code, '')
            ) ILIKE '%' || k.keyword || '%'
    )
),

-- Count diagnosis and laboratory evidence on distinct dates.
person_evidence AS (
    SELECT
        p.person_id,
        count(DISTINCT t.condition_date) AS t2dm_diagnosis_dates,
        count(DISTINCT l.measurement_date) AS abnormal_lab_dates,
        max(CASE WHEN m.person_id IS NOT NULL THEN 1 ELSE 0 END) AS has_t2dm_medication,
        max(CASE WHEN c.person_id IS NOT NULL THEN 1 ELSE 0 END) AS has_competing_diabetes,
        max(CASE WHEN g.person_id IS NOT NULL THEN 1 ELSE 0 END) AS has_gestational_diabetes
    FROM person AS p
    LEFT JOIN t2dm_diagnosis_dates AS t
        ON p.person_id = t.person_id
    LEFT JOIN abnormal_diabetes_lab_dates AS l
        ON p.person_id = l.person_id
    LEFT JOIN t2dm_medication_persons AS m
        ON p.person_id = m.person_id
    LEFT JOIN competing_diabetes_persons AS c
        ON p.person_id = c.person_id
    LEFT JOIN gestational_diabetes_persons AS g
        ON p.person_id = g.person_id
    GROUP BY p.person_id
)

-- Final conservative type 2 diabetes phenotype.
SELECT person_id
FROM person_evidence
WHERE
    has_competing_diabetes = 0
    AND
    (
        -- Repeated explicit type 2 diagnosis codes.
        t2dm_diagnosis_dates >= 2

        OR

        -- One explicit type 2 diagnosis plus corroborating evidence.
        (
            t2dm_diagnosis_dates >= 1
            AND
            (
                abnormal_lab_dates >= 1
                OR has_t2dm_medication = 1
            )
        )

        OR

        -- Repeated abnormal labs plus medication, without gestational diabetes.
        (
            abnormal_lab_dates >= 2
            AND has_t2dm_medication = 1
            AND has_gestational_diabetes = 0
        )
    )
ORDER BY person_id;