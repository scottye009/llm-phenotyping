WITH
/* 1) Type 2 diabetes diagnosis codes from source diagnosis fields */
t2dm_dx AS (
    SELECT DISTINCT
        person_id
    FROM condition_occurrence
    WHERE
        (
            -- ICD-10-CM E11.*
            condition_source_concept_vocabulary_id ILIKE '%ICD10%'
            AND regexp_matches(
                UPPER(REPLACE(condition_source_value, '.', '')),
                '^E11[A-Z0-9]*$'
            )
        )
        OR (
            -- ICD-9-CM 250.xx0 or 250.xx2 = type 2 / unspecified type, not type 1
            condition_source_concept_vocabulary_id ILIKE '%ICD9%'
            AND regexp_matches(
                UPPER(REPLACE(condition_source_value, '.', '')),
                '^250[0-9]{2}[02]$'
            )
        )
        OR (
            -- Backup text match when vocabulary/code formatting is inconsistent
            condition_source_concept_name ILIKE '%type 2 diabetes%'
            OR condition_source_concept_name ILIKE '%type ii diabetes%'
            OR condition_source_concept_name ILIKE '%t2dm%'
            OR condition_concept_name ILIKE '%type 2 diabetes%'
            OR condition_concept_name ILIKE '%type ii diabetes%'
            OR condition_concept_name ILIKE '%t2dm%'
        )
),

/* 2) Exclusion diagnoses: type 1, gestational, secondary, or drug-induced diabetes */
exclusion_dx AS (
    SELECT DISTINCT
        person_id
    FROM condition_occurrence
    WHERE
        (
            -- ICD-10-CM type 1 / secondary / other specified / gestational diabetes
            condition_source_concept_vocabulary_id ILIKE '%ICD10%'
            AND (
                regexp_matches(UPPER(REPLACE(condition_source_value, '.', '')), '^E10[A-Z0-9]*$')
                OR regexp_matches(UPPER(REPLACE(condition_source_value, '.', '')), '^E08[A-Z0-9]*$')
                OR regexp_matches(UPPER(REPLACE(condition_source_value, '.', '')), '^E09[A-Z0-9]*$')
                OR regexp_matches(UPPER(REPLACE(condition_source_value, '.', '')), '^E13[A-Z0-9]*$')
                OR regexp_matches(UPPER(REPLACE(condition_source_value, '.', '')), '^O24[A-Z0-9]*$')
            )
        )
        OR (
            -- ICD-9-CM 250.xx1 or 250.xx3 = type 1 diabetes
            condition_source_concept_vocabulary_id ILIKE '%ICD9%'
            AND regexp_matches(
                UPPER(REPLACE(condition_source_value, '.', '')),
                '^250[0-9]{2}[13]$'
            )
        )
        OR (
            condition_source_concept_name ILIKE '%type 1 diabetes%'
            OR condition_source_concept_name ILIKE '%type i diabetes%'
            OR condition_source_concept_name ILIKE '%t1dm%'
            OR condition_source_concept_name ILIKE '%gestational diabetes%'
            OR condition_source_concept_name ILIKE '%secondary diabetes%'
            OR condition_source_concept_name ILIKE '%drug-induced diabetes%'
            OR condition_concept_name ILIKE '%type 1 diabetes%'
            OR condition_concept_name ILIKE '%type i diabetes%'
            OR condition_concept_name ILIKE '%t1dm%'
            OR condition_concept_name ILIKE '%gestational diabetes%'
            OR condition_concept_name ILIKE '%secondary diabetes%'
            OR condition_concept_name ILIKE '%drug-induced diabetes%'
        )
),

/* 3) Diabetes-range laboratory evidence from measurement source names and numeric values */
diabetes_lab AS (
    SELECT DISTINCT
        person_id
    FROM measurement
    WHERE
        value_as_number IS NOT NULL
        AND (
            -- HbA1c >= 6.5%
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

            -- Fasting plasma/serum glucose >= 126 mg/dL
            (
                (
                    measurement_source_value ILIKE '%fasting glucose%'
                    OR measurement_source_value ILIKE '%fasting blood glucose%'
                    OR measurement_source_value ILIKE '%fasting plasma glucose%'
                    OR measurement_source_value ILIKE '%fpg%'
                    OR measurement_concept_name ILIKE '%fasting glucose%'
                    OR measurement_concept_name ILIKE '%fasting blood glucose%'
                    OR measurement_concept_name ILIKE '%fasting plasma glucose%'
                    OR measurement_concept_name ILIKE '%fpg%'
                )
                AND (
                    unit_source_value ILIKE '%mg/dl%'
                    OR unit_concept_name ILIKE '%mg/dl%'
                    OR unit_source_value IS NULL
                )
                AND value_as_number >= 126
            )

            OR

            -- Random/plasma/serum glucose >= 200 mg/dL
            (
                (
                    measurement_source_value ILIKE '%random glucose%'
                    OR measurement_source_value ILIKE '%random blood glucose%'
                    OR measurement_source_value ILIKE '%plasma glucose%'
                    OR measurement_source_value ILIKE '%serum glucose%'
                    OR measurement_source_value ILIKE '%blood glucose%'
                    OR measurement_concept_name ILIKE '%random glucose%'
                    OR measurement_concept_name ILIKE '%random blood glucose%'
                    OR measurement_concept_name ILIKE '%plasma glucose%'
                    OR measurement_concept_name ILIKE '%serum glucose%'
                    OR measurement_concept_name ILIKE '%blood glucose%'
                )
                AND NOT (
                    measurement_source_value ILIKE '%urine%'
                    OR measurement_concept_name ILIKE '%urine%'
                )
                AND (
                    unit_source_value ILIKE '%mg/dl%'
                    OR unit_concept_name ILIKE '%mg/dl%'
                    OR unit_source_value IS NULL
                )
                AND value_as_number >= 200
            )

            OR

            -- 2-hour OGTT glucose >= 200 mg/dL
            (
                (
                    measurement_source_value ILIKE '%ogtt%'
                    OR measurement_source_value ILIKE '%oral glucose tolerance%'
                    OR measurement_source_value ILIKE '%2 hour glucose%'
                    OR measurement_source_value ILIKE '%2-hour glucose%'
                    OR measurement_source_value ILIKE '%two hour glucose%'
                    OR measurement_concept_name ILIKE '%ogtt%'
                    OR measurement_concept_name ILIKE '%oral glucose tolerance%'
                    OR measurement_concept_name ILIKE '%2 hour glucose%'
                    OR measurement_concept_name ILIKE '%2-hour glucose%'
                    OR measurement_concept_name ILIKE '%two hour glucose%'
                )
                AND (
                    unit_source_value ILIKE '%mg/dl%'
                    OR unit_concept_name ILIKE '%mg/dl%'
                    OR unit_source_value IS NULL
                )
                AND value_as_number >= 200
            )
        )
),

/* 4) Non-insulin diabetes medication evidence using generic and brand names */
t2dm_med AS (
    SELECT DISTINCT
        d.person_id
    FROM drug_exposure d
    WHERE EXISTS (
        SELECT 1
        FROM (
            VALUES
                -- Biguanide
                ('metformin'), ('glucophage'), ('fortamet'), ('glumetza'), ('riomet'),

                -- Sulfonylureas
                ('glipizide'), ('glyburide'), ('glimepiride'),
                ('glucotrol'), ('diabeta'), ('glynase'), ('amaryl'),

                -- Thiazolidinediones
                ('pioglitazone'), ('rosiglitazone'), ('actos'), ('avandia'),

                -- DPP-4 inhibitors
                ('sitagliptin'), ('saxagliptin'), ('linagliptin'), ('alogliptin'),
                ('januvia'), ('onglyza'), ('tradjenta'), ('nesina'),

                -- SGLT2 inhibitors
                ('empagliflozin'), ('canagliflozin'), ('dapagliflozin'), ('ertugliflozin'),
                ('jardiance'), ('invokana'), ('farxiga'), ('steglatro'),

                -- GLP-1 receptor agonists / incretin therapies
                ('semaglutide'), ('liraglutide'), ('dulaglutide'), ('exenatide'), ('lixisenatide'),
                ('ozempic'), ('rybelsus'), ('victoza'), ('trulicity'), ('byetta'), ('bydureon'), ('adlyxin'),

                -- Meglitinides
                ('repaglinide'), ('nateglinide'), ('prandin'), ('starlix'),

                -- Alpha-glucosidase inhibitors
                ('acarbose'), ('miglitol'), ('precose'), ('glyset')
        ) AS med(keyword)
        WHERE
            d.drug_source_value ILIKE '%' || med.keyword || '%'
            OR d.drug_concept_name ILIKE '%' || med.keyword || '%'
            OR d.drug_source_concept_code ILIKE '%' || med.keyword || '%'
            OR d.drug_type_concept_name ILIKE '%' || med.keyword || '%'
    )
),

/* 5) Combine evidence:
      - explicit T2DM diagnosis is sufficient
      - otherwise require diabetes-range lab evidence plus T2DM medication evidence
      - exclude likely non-T2DM diabetes unless explicit T2DM diagnosis exists */
phenotype AS (
    SELECT person_id
    FROM t2dm_dx

    UNION

    SELECT l.person_id
    FROM diabetes_lab l
    INNER JOIN t2dm_med m
        ON l.person_id = m.person_id
    LEFT JOIN exclusion_dx e
        ON l.person_id = e.person_id
    LEFT JOIN t2dm_dx t
        ON l.person_id = t.person_id
    WHERE
        e.person_id IS NULL
        OR t.person_id IS NOT NULL
)

SELECT DISTINCT
    person_id
FROM phenotype
ORDER BY person_id