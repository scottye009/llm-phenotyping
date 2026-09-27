-- Type 2 Diabetes Mellitus phenotype
-- Returns person_id

WITH t2dm_dx AS (
    SELECT
        person_id,
        COUNT(*) AS dx_count
    FROM condition_occurrence
    WHERE
        (
            -- ICD-10-CM T2DM
            condition_source_value ILIKE 'E11%'

            -- ICD-9-CM T2DM
            OR regexp_matches(condition_source_value, '^250\\..*[02]$')

            -- Diagnosis text
            OR (
                condition_source_concept_name IS NOT NULL
                AND (
                    condition_source_concept_name ILIKE '%type 2 diabetes%'
                    OR condition_source_concept_name ILIKE '%type ii diabetes%'
                    OR condition_source_concept_name ILIKE '%t2dm%'
                )
            )
        )
    GROUP BY person_id
),

t1dm_dx AS (
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE
        (
            condition_source_value ILIKE 'E10%'
            OR regexp_matches(condition_source_value, '^250\\..*[13]$')
            OR (
                condition_source_concept_name IS NOT NULL
                AND (
                    condition_source_concept_name ILIKE '%type 1 diabetes%'
                    OR condition_source_concept_name ILIKE '%type i diabetes%'
                    OR condition_source_concept_name ILIKE '%t1dm%'
                )
            )
        )
),

dm_med AS (
    SELECT DISTINCT person_id
    FROM drug_exposure d
    WHERE EXISTS (
        SELECT 1
        FROM (
            VALUES
                ('metformin'),
                ('glucophage'),
                ('glipizide'),
                ('glucotrol'),
                ('glyburide'),
                ('diabeta'),
                ('micronase'),
                ('glynase'),
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
                ('liraglutide'),
                ('victoza'),
                ('dulaglutide'),
                ('trulicity'),
                ('exenatide'),
                ('byetta'),
                ('bydureon'),
                ('tirzepatide'),
                ('mounjaro'),
                ('acarbose'),
                ('precose'),
                ('miglitol'),
                ('glyset'),
                ('repaglinide'),
                ('prandin'),
                ('nateglinide'),
                ('starlix')
        ) k(keyword)
        WHERE
            d.drug_source_value ILIKE '%' || k.keyword || '%'
            OR d.drug_concept_name ILIKE '%' || k.keyword || '%'
            OR d.drug_source_concept_code ILIKE '%' || k.keyword || '%'
    )
),

dm_lab AS (
    SELECT DISTINCT person_id
    FROM measurement
    WHERE value_as_number IS NOT NULL
      AND (
            -- HbA1c >= 6.5%
            (
                (
                    measurement_source_value ILIKE '%a1c%'
                    OR measurement_source_value ILIKE '%hba1c%'
                    OR measurement_source_value ILIKE '%hemoglobin a1c%'
                    OR measurement_source_value ILIKE '%glycated hemoglobin%'
                )
                AND value_as_number >= 6.5
            )

            OR

            -- Fasting glucose >=126 mg/dL
            (
                (
                    measurement_source_value ILIKE '%fasting glucose%'
                    OR measurement_source_value ILIKE '%fasting blood glucose%'
                    OR measurement_source_value ILIKE '%fpg%'
                )
                AND value_as_number >= 126
            )

            OR

            -- Random glucose >=200 mg/dL
            (
                (
                    measurement_source_value ILIKE '%glucose%'
                    OR measurement_source_value ILIKE '%blood glucose%'
                )
                AND measurement_source_value NOT ILIKE '%fasting%'
                AND value_as_number >= 200
            )
      )
),

t2dm_case AS (
    SELECT person_id
    FROM t2dm_dx
    WHERE dx_count >= 2

    UNION

    SELECT d.person_id
    FROM t2dm_dx d
    INNER JOIN dm_med m
        ON d.person_id = m.person_id

    UNION

    SELECT d.person_id
    FROM t2dm_dx d
    INNER JOIN dm_lab l
        ON d.person_id = l.person_id

    UNION

    SELECT m.person_id
    FROM dm_med m
    INNER JOIN dm_lab l
        ON m.person_id = l.person_id
)

SELECT DISTINCT c.person_id
FROM t2dm_case c
LEFT JOIN t1dm_dx t1
    ON c.person_id = t1.person_id
WHERE t1.person_id IS NULL;