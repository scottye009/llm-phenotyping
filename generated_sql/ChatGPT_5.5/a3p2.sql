-- Type 2 diabetes phenotype for SHIRE / DuckDB
-- Evidence hierarchy:
-- 1) Type 2 diabetes diagnosis by ICD9CM/ICD10CM source codes or source text
-- 2) Repeated diabetes-range labs
-- 3) Non-insulin type 2 diabetes medication plus supporting diagnosis/lab evidence
-- Exclude lab/med-only cases with clear type 1, gestational, or secondary diabetes signals.

WITH condition_text AS (
    SELECT
        person_id,
        LOWER(COALESCE(condition_source_value, '')) AS src_code,
        LOWER(COALESCE(condition_source_concept_vocabulary_id, '')) AS src_vocab,
        LOWER(COALESCE(condition_source_concept_name, '')) AS src_name,
        LOWER(COALESCE(condition_concept_name, '')) AS concept_name
    FROM condition_occurrence
),

t2dm_dx AS (
    SELECT DISTINCT person_id
    FROM condition_text
    WHERE
        -- ICD10CM type 2 diabetes: E11.*
        regexp_matches(src_code, '^e11(\.|[0-9]|$)')
        OR (
            src_vocab ILIKE '%ICD10%'
            AND regexp_matches(src_code, '^e11(\.|[0-9]|$)')
        )

        -- ICD9CM diabetes with fifth digit 0 or 2 = type 2 / unspecified type, not uncontrolled or uncontrolled variants included
        OR regexp_matches(src_code, '^250(\.[0-9][02]|[0-9][02])$')

        -- Source/concept names when source codes are not standardized
        OR src_name ILIKE '%type 2 diabetes%'
        OR src_name ILIKE '%type ii diabetes%'
        OR src_name ILIKE '%diabetes mellitus type 2%'
        OR concept_name ILIKE '%type 2 diabetes%'
        OR concept_name ILIKE '%type ii diabetes%'
        OR concept_name ILIKE '%diabetes mellitus type 2%'
),

exclusion_dx AS (
    SELECT DISTINCT person_id
    FROM condition_text
    WHERE
        -- Type 1 diabetes
        regexp_matches(src_code, '^e10(\.|[0-9]|$)')
        OR regexp_matches(src_code, '^250(\.[0-9][13]|[0-9][13])$')
        OR src_name ILIKE '%type 1 diabetes%'
        OR src_name ILIKE '%type i diabetes%'
        OR concept_name ILIKE '%type 1 diabetes%'
        OR concept_name ILIKE '%type i diabetes%'

        -- Gestational diabetes
        OR regexp_matches(src_code, '^o24\.4')
        OR src_name ILIKE '%gestational diabetes%'
        OR concept_name ILIKE '%gestational diabetes%'

        -- Secondary diabetes
        OR regexp_matches(src_code, '^e08(\.|[0-9]|$)')
        OR regexp_matches(src_code, '^e09(\.|[0-9]|$)')
        OR src_name ILIKE '%secondary diabetes%'
        OR concept_name ILIKE '%secondary diabetes%'
),

med_keyword AS (
    SELECT * FROM (
        VALUES
            ('metformin'), ('glucophage'), ('fortamet'), ('glumetza'), ('riomet'),
            ('glipizide'), ('glyburide'), ('glimepiride'), ('tolbutamide'), ('tolazamide'),
            ('chlorpropamide'), ('diabeta'), ('micronase'), ('amaryl'), ('glucotrol'),
            ('pioglitazone'), ('rosiglitazone'), ('actos'), ('avandia'),
            ('sitagliptin'), ('saxagliptin'), ('linagliptin'), ('alogliptin'),
            ('januvia'), ('onglyza'), ('tradjenta'), ('nesina'),
            ('exenatide'), ('liraglutide'), ('semaglutide'), ('dulaglutide'),
            ('lixisenatide'), ('tirzepatide'), ('byetta'), ('bydureon'), ('victoza'),
            ('ozempic'), ('rybelsus'), ('trulicity'), ('adlyxin'), ('mounjaro'),
            ('canagliflozin'), ('dapagliflozin'), ('empagliflozin'), ('ertugliflozin'),
            ('invokana'), ('farxiga'), ('jardiance'), ('steglatro'),
            ('repaglinide'), ('nateglinide'), ('prandin'), ('starlix'),
            ('acarbose'), ('miglitol'), ('precose'), ('glyset'),
            ('janumet'), ('kombiglyze'), ('jentadueto'), ('synjardy'), ('xigduo'),
            ('invokamet'), ('glyxambi'), ('segluromet')
    ) AS t(keyword)
),

t2dm_med AS (
    SELECT DISTINCT d.person_id
    FROM drug_exposure d
    WHERE
        EXISTS (
            SELECT 1
            FROM med_keyword k
            WHERE
                LOWER(COALESCE(d.drug_source_value, '')) ILIKE '%' || k.keyword || '%'
                OR LOWER(COALESCE(d.drug_concept_name, '')) ILIKE '%' || k.keyword || '%'
                OR LOWER(COALESCE(d.drug_source_concept_code, '')) ILIKE '%' || k.keyword || '%'
        )
        -- Avoid insulin-only evidence as a type 2 diabetes-defining medication signal.
        AND LOWER(COALESCE(d.drug_source_value, '') || ' ' || COALESCE(d.drug_concept_name, '')) NOT ILIKE '%insulin%'
),

abnormal_labs AS (
    SELECT DISTINCT
        person_id,
        CAST(measurement_date AS DATE) AS lab_date
    FROM measurement
    WHERE
        value_as_number IS NOT NULL
        AND (
            -- HbA1c >= 6.5%
            (
                (
                    LOWER(COALESCE(measurement_source_value, '')) ILIKE '%a1c%'
                    OR LOWER(COALESCE(measurement_source_value, '')) ILIKE '%hba1c%'
                    OR LOWER(COALESCE(measurement_source_value, '')) ILIKE '%hemoglobin a1c%'
                    OR LOWER(COALESCE(measurement_concept_name, '')) ILIKE '%a1c%'
                    OR LOWER(COALESCE(measurement_concept_name, '')) ILIKE '%hemoglobin a1c%'
                )
                AND value_as_number >= 6.5
                AND value_as_number < 25
            )

            OR

            -- Fasting plasma glucose >= 126 mg/dL or >= 7.0 mmol/L
            (
                (
                    LOWER(COALESCE(measurement_source_value, '')) ILIKE '%glucose%'
                    OR LOWER(COALESCE(measurement_concept_name, '')) ILIKE '%glucose%'
                )
                AND (
                    LOWER(COALESCE(measurement_source_value, '')) ILIKE '%fasting%'
                    OR LOWER(COALESCE(measurement_source_value, '')) ILIKE '%fpg%'
                    OR LOWER(COALESCE(measurement_source_value, '')) ILIKE '%fast%'
                )
                AND (
                    (
                        (LOWER(COALESCE(unit_source_value, '')) ILIKE '%mg/dl%'
                         OR LOWER(COALESCE(unit_concept_name, '')) ILIKE '%mg/dl%'
                         OR COALESCE(unit_source_value, '') = '')
                        AND value_as_number >= 126
                    )
                    OR
                    (
                        (LOWER(COALESCE(unit_source_value, '')) ILIKE '%mmol%'
                         OR LOWER(COALESCE(unit_concept_name, '')) ILIKE '%mmol%')
                        AND value_as_number >= 7.0
                    )
                )
            )

            OR

            -- Random glucose >= 200 mg/dL or >= 11.1 mmol/L
            (
                (
                    LOWER(COALESCE(measurement_source_value, '')) ILIKE '%glucose%'
                    OR LOWER(COALESCE(measurement_concept_name, '')) ILIKE '%glucose%'
                )
                AND (
                    (
                        (LOWER(COALESCE(unit_source_value, '')) ILIKE '%mg/dl%'
                         OR LOWER(COALESCE(unit_concept_name, '')) ILIKE '%mg/dl%'
                         OR COALESCE(unit_source_value, '') = '')
                        AND value_as_number >= 200
                    )
                    OR
                    (
                        (LOWER(COALESCE(unit_source_value, '')) ILIKE '%mmol%'
                         OR LOWER(COALESCE(unit_concept_name, '')) ILIKE '%mmol%')
                        AND value_as_number >= 11.1
                    )
                )
            )
        )
),

lab_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT lab_date) AS abnormal_lab_days
    FROM abnormal_labs
    GROUP BY person_id
),

evidence AS (
    SELECT
        p.person_id,
        CASE WHEN dx.person_id IS NOT NULL THEN 1 ELSE 0 END AS has_t2dm_dx,
        CASE WHEN med.person_id IS NOT NULL THEN 1 ELSE 0 END AS has_t2dm_med,
        COALESCE(lab.abnormal_lab_days, 0) AS abnormal_lab_days,
        CASE WHEN ex.person_id IS NOT NULL THEN 1 ELSE 0 END AS has_exclusion_dx
    FROM person p
    LEFT JOIN t2dm_dx dx
        ON p.person_id = dx.person_id
    LEFT JOIN t2dm_med med
        ON p.person_id = med.person_id
    LEFT JOIN lab_summary lab
        ON p.person_id = lab.person_id
    LEFT JOIN exclusion_dx ex
        ON p.person_id = ex.person_id
)

SELECT DISTINCT person_id
FROM evidence
WHERE
    -- Direct type 2 diabetes diagnosis is sufficient.
    has_t2dm_dx = 1

    -- Repeated diabetes-range labs are sufficient unless clear exclusion diagnosis exists.
    OR (
        abnormal_lab_days >= 2
        AND has_exclusion_dx = 0
    )

    -- Medication evidence requires supporting lab evidence unless direct T2DM diagnosis exists.
    OR (
        has_t2dm_med = 1
        AND abnormal_lab_days >= 1
        AND has_exclusion_dx = 0
    )