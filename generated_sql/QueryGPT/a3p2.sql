WITH
-- Normalize diagnosis source codes and retain source diagnosis text.
condition_base AS (
    SELECT
        person_id,
        condition_occurrence_id,
        CAST(condition_start_date AS DATE) AS condition_date,
        regexp_replace(
            upper(trim(coalesce(condition_source_value, ''))),
            '[^A-Z0-9]',
            '',
            'g'
        ) AS code_norm,
        lower(coalesce(condition_source_concept_name, '')) AS source_name
    FROM condition_occurrence
),

-- Identify type 2, type 1, and gestational diabetes diagnosis rows.
condition_flags AS (
    SELECT
        person_id,
        condition_occurrence_id,
        condition_date,

        (
            -- ICD-10-CM E11.*
            regexp_matches(code_norm, '(^|ICD10CM)E11[0-9A-Z]*$')

            -- ICD-9-CM 250.x0 or 250.x2
            OR regexp_matches(code_norm, '(^|ICD9CM)250[0-9][02]$')

            -- Text fallback when source codes are absent or malformed
            OR source_name ILIKE '%type 2 diabetes%'
            OR source_name ILIKE '%type ii diabetes%'
            OR source_name ILIKE '%t2dm%'
            OR source_name ILIKE '%non-insulin-dependent diabetes%'
            OR source_name ILIKE '%non insulin dependent diabetes%'
        ) AS is_t2_dx,

        (
            -- ICD-10-CM E10.*
            regexp_matches(code_norm, '(^|ICD10CM)E10[0-9A-Z]*$')

            -- ICD-9-CM 250.x1 or 250.x3
            OR regexp_matches(code_norm, '(^|ICD9CM)250[0-9][13]$')

            -- Text fallback
            OR source_name ILIKE '%type 1 diabetes%'
            OR source_name ILIKE '%type i diabetes%'
            OR source_name ILIKE '%t1dm%'
        ) AS is_t1_dx,

        (
            -- ICD-10-CM O24.*
            regexp_matches(code_norm, '(^|ICD10CM)O24[0-9A-Z]*$')
            OR source_name ILIKE '%gestational diabetes%'
        ) AS is_gestational_dx
    FROM condition_base
),

-- Count diagnosis evidence. Distinct source rows are used if dates are missing.
diagnosis_summary AS (
    SELECT
        person_id,
        COUNT(
            DISTINCT CASE
                WHEN is_t2_dx THEN coalesce(
                    CAST(condition_date AS VARCHAR),
                    CAST(condition_occurrence_id AS VARCHAR)
                )
            END
        ) AS t2_dx_count,
        COUNT(
            DISTINCT CASE
                WHEN is_t1_dx THEN coalesce(
                    CAST(condition_date AS VARCHAR),
                    CAST(condition_occurrence_id AS VARCHAR)
                )
            END
        ) AS t1_dx_count,
        COUNT(
            DISTINCT CASE
                WHEN is_gestational_dx THEN coalesce(
                    CAST(condition_date AS VARCHAR),
                    CAST(condition_occurrence_id AS VARCHAR)
                )
            END
        ) AS gestational_dx_count
    FROM condition_flags
    GROUP BY person_id
),

-- Generic and brand names for non-insulin glucose-lowering medications.
medication_terms(term) AS (
    VALUES
        ('metformin'), ('glucophage'), ('fortamet'), ('glumetza'), ('riomet'),
        ('glipizide'), ('glucotrol'),
        ('glyburide'), ('glibenclamide'), ('diabeta'), ('micronase'), ('glynase'),
        ('glimepiride'), ('amaryl'),
        ('pioglitazone'), ('actos'),
        ('rosiglitazone'), ('avandia'),
        ('sitagliptin'), ('januvia'),
        ('saxagliptin'), ('onglyza'),
        ('linagliptin'), ('tradjenta'),
        ('alogliptin'), ('nesina'),
        ('empagliflozin'), ('jardiance'),
        ('dapagliflozin'), ('farxiga'),
        ('canagliflozin'), ('invokana'),
        ('ertugliflozin'), ('steglatro'),
        ('exenatide'), ('byetta'), ('bydureon'),
        ('liraglutide'), ('victoza'),
        ('dulaglutide'), ('trulicity'),
        ('semaglutide'), ('ozempic'), ('rybelsus'),
        ('tirzepatide'), ('mounjaro'),
        ('repaglinide'), ('prandin'),
        ('nateglinide'), ('starlix'),
        ('acarbose'), ('precose'),
        ('miglitol'), ('glyset')
),

-- Search medication source fields and available medication names.
drug_base AS (
    SELECT
        person_id,
        lower(
            concat_ws(
                ' ',
                coalesce(drug_source_value, ''),
                coalesce(drug_concept_name, ''),
                coalesce(drug_source_concept_code, '')
            )
        ) AS drug_text
    FROM drug_exposure
),

drug_summary AS (
    SELECT
        person_id,
        MAX(
            CASE
                WHEN EXISTS (
                    SELECT 1
                    FROM medication_terms mt
                    WHERE drug_text ILIKE '%' || mt.term || '%'
                )
                THEN 1
                ELSE 0
            END
        ) AS has_non_insulin_diabetes_drug
    FROM drug_base
    GROUP BY person_id
),

-- Retain source laboratory names, numeric values, and source units.
measurement_base AS (
    SELECT
        person_id,
        CAST(measurement_date AS DATE) AS measurement_date,
        lower(trim(coalesce(measurement_source_value, ''))) AS lab_name,
        value_as_number,
        lower(
            trim(
                concat_ws(
                    ' ',
                    coalesce(unit_source_value, ''),
                    coalesce(unit_concept_name, '')
                )
            )
        ) AS unit_text
    FROM measurement
    WHERE value_as_number IS NOT NULL
),

-- Apply diagnostic-range diabetes laboratory thresholds.
abnormal_labs AS (
    SELECT
        person_id,
        measurement_date
    FROM measurement_base
    WHERE
        -- HbA1c threshold
        (
            (
                lab_name ILIKE '%hba1c%'
                OR lab_name ILIKE '%hb a1c%'
                OR lab_name ILIKE '%hemoglobin a1c%'
                OR lab_name ILIKE '%glycated hemoglobin%'
                OR lab_name ILIKE '%glycosylated hemoglobin%'
            )
            AND value_as_number >= 6.5
        )

        OR

        -- Fasting glucose threshold
        (
            lab_name ILIKE '%glucose%'
            AND (
                lab_name ILIKE '%fasting%'
                OR lab_name ILIKE '%fast%'
            )
            AND lab_name NOT ILIKE '%urine%'
            AND lab_name NOT ILIKE '%csf%'
            AND lab_name NOT ILIKE '%fluid%'
            AND (
                (
                    (
                        unit_text ILIKE '%mg/dl%'
                        OR unit_text ILIKE '%mg dl%'
                        OR unit_text ILIKE '%mgdl%'
                        OR unit_text = ''
                    )
                    AND value_as_number >= 126
                )
                OR
                (
                    (
                        unit_text ILIKE '%mmol/l%'
                        OR unit_text ILIKE '%mmol l%'
                        OR unit_text ILIKE '%mmol%'
                    )
                    AND value_as_number >= 7.0
                )
            )
        )

        OR

        -- Serum, plasma, or blood glucose threshold
        (
            lab_name ILIKE '%glucose%'
            AND lab_name NOT ILIKE '%urine%'
            AND lab_name NOT ILIKE '%csf%'
            AND lab_name NOT ILIKE '%fluid%'
            AND (
                (
                    (
                        unit_text ILIKE '%mg/dl%'
                        OR unit_text ILIKE '%mg dl%'
                        OR unit_text ILIKE '%mgdl%'
                        OR unit_text = ''
                    )
                    AND value_as_number >= 200
                )
                OR
                (
                    (
                        unit_text ILIKE '%mmol/l%'
                        OR unit_text ILIKE '%mmol l%'
                        OR unit_text ILIKE '%mmol%'
                    )
                    AND value_as_number >= 11.1
                )
            )
        )
),

-- Count abnormal laboratory dates rather than individual test rows.
lab_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT measurement_date) AS abnormal_lab_date_count
    FROM abnormal_labs
    WHERE measurement_date IS NOT NULL
    GROUP BY person_id
),

-- Collect every person with at least one relevant evidence source.
evidence_persons AS (
    SELECT person_id FROM diagnosis_summary
    UNION
    SELECT person_id FROM drug_summary
    UNION
    SELECT person_id FROM lab_summary
),

-- Assemble a single evidence record per person.
phenotype_evidence AS (
    SELECT
        ep.person_id,
        coalesce(ds.t2_dx_count, 0) AS t2_dx_count,
        coalesce(ds.t1_dx_count, 0) AS t1_dx_count,
        coalesce(ds.gestational_dx_count, 0) AS gestational_dx_count,
        coalesce(dr.has_non_insulin_diabetes_drug, 0) AS has_non_insulin_diabetes_drug,
        coalesce(ls.abnormal_lab_date_count, 0) AS abnormal_lab_date_count
    FROM evidence_persons ep
    LEFT JOIN diagnosis_summary ds
        ON ep.person_id = ds.person_id
    LEFT JOIN drug_summary dr
        ON ep.person_id = dr.person_id
    LEFT JOIN lab_summary ls
        ON ep.person_id = ls.person_id
)

-- Final conservative type 2 diabetes phenotype.
SELECT DISTINCT
    person_id
FROM phenotype_evidence
WHERE
    (
        -- Route 1: repeated type 2 diagnosis evidence
        t2_dx_count >= 2

        -- Route 2: diagnosis plus medication or laboratory support
        OR (
            t2_dx_count >= 1
            AND (
                has_non_insulin_diabetes_drug = 1
                OR abnormal_lab_date_count >= 1
            )
        )

        -- Route 3: repeated laboratory evidence plus type-2-compatible therapy
        OR (
            abnormal_lab_date_count >= 2
            AND has_non_insulin_diabetes_drug = 1
        )
    )

    -- Remove records dominated by type 1 diagnosis evidence.
    AND t1_dx_count <= t2_dx_count

    -- Remove gestational-only cases.
    AND NOT (
        gestational_dx_count > 0
        AND t2_dx_count = 0
    )
ORDER BY person_id;