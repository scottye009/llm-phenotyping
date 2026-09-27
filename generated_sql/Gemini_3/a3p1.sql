-- Define lists of search patterns for diagnoses and medications
WITH diag_codes AS (
    SELECT pattern
    FROM (
        VALUES 
            ('250.00'), ('250.02'), ('250.10'), ('250.12'),
            ('250.20'), ('250.22'), ('250.30'), ('250.32'),
            ('250.40'), ('250.42'), ('250.50'), ('250.52'),
            ('250.60'), ('250.62'), ('250.70'), ('250.72'),
            ('250.80'), ('250.82'), ('250.90'), ('250.92'),
            ('E11%')
    ) AS t(pattern)
),

med_names AS (
    SELECT name
    FROM (
        VALUES 
            ('%metformin%'), ('%glucophage%'),
            ('%glipizide%'), ('%glucotrol%'),
            ('%glyburide%'), ('%micronase%'),
            ('%glimepiride%'), ('%amaryl%'),
            ('%sitagliptin%'), ('%januvia%'),
            ('%saxagliptin%'), ('%onglyza%'),
            ('%linagliptin%'), ('%tradjenta%'),
            ('%empagliflozin%'), ('%jardiance%'),
            ('%canagliflozin%'), ('%invokana%'),
            ('%dapagliflozin%'), ('%farxiga%'),
            ('%liraglutide%'), ('%victoza%'),
            ('%exenatide%'), ('%byetta%'),
            ('%pioglitazone%'), ('%actos%'),
            ('%rosiglitazone%'), ('%avandia%')
    ) AS t(name)
),

-- 1. Identify patients by diagnosis codes or names
t2dm_dx AS (
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE 
        EXISTS (
            SELECT 1
            FROM diag_codes
            WHERE condition_source_value ILIKE pattern
        )
        OR condition_source_value ILIKE '%Type 2 diabetes%'
        OR condition_source_concept_name ILIKE '%Type 2 diabetes%'
        OR condition_source_concept_name ILIKE '%T2DM%'
        OR condition_concept_name ILIKE '%Type 2 diabetes%'
        OR condition_concept_name ILIKE '%T2DM%'
),

-- 2. Identify patients by T2DM-specific medications
t2dm_rx AS (
    SELECT DISTINCT person_id
    FROM drug_exposure
    WHERE EXISTS (
        SELECT 1
        FROM med_names
        WHERE drug_source_value ILIKE name
    )
       OR EXISTS (
        SELECT 1
        FROM med_names
        WHERE drug_concept_name ILIKE name
    )
),

-- 3. Identify patients by laboratory criteria
t2dm_lab AS (
    SELECT DISTINCT person_id
    FROM measurement
    WHERE (
            measurement_source_value ILIKE '%A1c%'
            OR measurement_source_value ILIKE '%HbA1c%'
            OR measurement_concept_name ILIKE '%Hemoglobin A1c%'
          )
      AND value_as_number >= 6.5
)

-- Combine all criteria into final cohort
SELECT person_id FROM t2dm_dx
UNION
SELECT person_id FROM t2dm_rx
UNION
SELECT person_id FROM t2dm_lab;