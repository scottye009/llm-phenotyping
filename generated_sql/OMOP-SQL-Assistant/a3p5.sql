-- Type 2 Diabetes Mellitus phenotype
-- Returns person_id

WITH t2dm_dx AS (
    -- T2DM diagnoses from source codes and source text
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE
        (
            -- ICD-10-CM Type 2 DM
            condition_source_value ILIKE 'E11%'
            
            -- ICD-9-CM Type 2 DM
            OR regexp_matches(condition_source_value, '^250\\.[0-9]*0$')
            OR regexp_matches(condition_source_value, '^250\\.[0-9]*2$')

            -- Diagnosis text
            OR condition_source_concept_name ILIKE '%type 2 diabetes%'
            OR condition_source_concept_name ILIKE '%type ii diabetes%'
            OR condition_source_concept_name ILIKE '%t2dm%'
            OR condition_source_concept_name ILIKE '%non-insulin dependent diabetes%'
        )
),

t1dm_dx AS (
    -- Potential Type 1 DM exclusion
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE
        (
            condition_source_value ILIKE 'E10%'

            OR regexp_matches(condition_source_value, '^250\\.[0-9]*1$')
            OR regexp_matches(condition_source_value, '^250\\.[0-9]*3$')

            OR condition_source_concept_name ILIKE '%type 1 diabetes%'
            OR condition_source_concept_name ILIKE '%type i diabetes%'
            OR condition_source_concept_name ILIKE '%juvenile diabetes%'
        )
),

dm_med AS (
    -- Diabetes medications using source drug fields
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
                ('mounjaro')
        ) AS meds(term)
        WHERE
            d.drug_source_value ILIKE '%' || term || '%'
            OR d.drug_concept_name ILIKE '%' || term || '%'
            OR d.drug_source_concept_code ILIKE '%' || term || '%'
    )
),

dm_lab AS (
    -- Laboratory evidence of diabetes
    SELECT DISTINCT person_id
    FROM measurement
    WHERE value_as_number IS NOT NULL
      AND (
            -- Hemoglobin A1c >= 6.5%
            (
                (
                    measurement_source_value ILIKE '%a1c%'
                    OR measurement_source_value ILIKE '%hba1c%'
                    OR measurement_source_value ILIKE '%hemoglobin a1c%'
                )
                AND value_as_number >= 6.5
            )

            OR

            -- Fasting glucose >= 126 mg/dL
            (
                (
                    measurement_source_value ILIKE '%fasting glucose%'
                    OR measurement_source_value ILIKE '%fasting blood glucose%'
                    OR measurement_source_value ILIKE '%fpg%'
                )
                AND value_as_number >= 126
            )

            OR

            -- Random glucose >= 200 mg/dL
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
    -- Diagnosis OR (medication + laboratory evidence)
    SELECT person_id
    FROM t2dm_dx

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