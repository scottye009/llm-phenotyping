WITH t2dm_dx AS (
    SELECT
        person_id,
        condition_start_date
    FROM condition_occurrence
    WHERE
        condition_source_value ILIKE 'E11%'
        OR regexp_matches(
            coalesce(condition_source_value,''),
            '^250\\.[0-9][02]$'
        )
        OR (
            condition_source_concept_name IS NOT NULL
            AND (
                condition_source_concept_name ILIKE '%type 2 diabetes%'
                OR condition_source_concept_name ILIKE '%diabetes mellitus type 2%'
                OR condition_source_concept_name ILIKE '%type 2 dm%'
                OR condition_source_concept_name ILIKE '%dm2%'
                OR condition_source_concept_name ILIKE '%t2dm%'
                OR condition_source_concept_name ILIKE '%niddm%'
                OR condition_source_concept_name ILIKE '%non insulin dependent%'
            )
        )
),

dx_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT condition_start_date) AS dx_dates
    FROM t2dm_dx
    GROUP BY person_id
),

dm_med AS (
    SELECT DISTINCT d.person_id
    FROM drug_exposure d
    WHERE EXISTS (
        SELECT 1
        FROM (
            VALUES
                ('metformin'),
                ('glipizide'),
                ('glyburide'),
                ('glimepiride'),
                ('pioglitazone'),
                ('sitagliptin'),
                ('linagliptin'),
                ('alogliptin'),
                ('saxagliptin'),
                ('empagliflozin'),
                ('dapagliflozin'),
                ('canagliflozin'),
                ('ertugliflozin'),
                ('liraglutide'),
                ('semaglutide'),
                ('dulaglutide'),
                ('exenatide'),
                ('tirzepatide'),
                ('repaglinide'),
                ('nateglinide'),
                ('acarbose'),
                ('miglitol')
        ) k(term)
        WHERE
            d.drug_source_value ILIKE '%' || term || '%'
            OR d.drug_source_concept_code ILIKE '%' || term || '%'
            OR d.drug_concept_name ILIKE '%' || term || '%'
    )
),

dm_lab AS (
    SELECT
        person_id,
        measurement_date
    FROM measurement
    WHERE
        value_as_number IS NOT NULL
        AND (
            (
                (
                    measurement_source_value ILIKE '%a1c%'
                    OR measurement_source_value ILIKE '%hba1c%'
                    OR measurement_source_value ILIKE '%hemoglobin a1c%'
                    OR measurement_source_value ILIKE '%glycohemoglobin%'
                )
                AND value_as_number >= 6.5
            )
            OR
            (
                measurement_source_value ILIKE '%fasting%'
                AND measurement_source_value ILIKE '%glucose%'
                AND value_as_number >= 126
            )
            OR
            (
                measurement_source_value ILIKE '%glucose%'
                AND value_as_number >= 200
            )
        )
),

lab_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT measurement_date) AS diabetic_lab_dates
    FROM dm_lab
    GROUP BY person_id
),

t1_only AS (
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE
        condition_source_value ILIKE 'E10%'
        OR regexp_matches(
            coalesce(condition_source_value,''),
            '^250\\.[0-9][13]$'
        )
),

candidate_cases AS (

    SELECT person_id
    FROM dx_summary
    WHERE dx_dates >= 2

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
    INNER JOIN lab_summary l
        ON m.person_id = l.person_id
    WHERE l.diabetic_lab_dates >= 2
)

SELECT DISTINCT c.person_id
FROM candidate_cases c
LEFT JOIN t1_only t1
    ON c.person_id = t1.person_id
WHERE t1.person_id IS NULL
ORDER BY c.person_id;