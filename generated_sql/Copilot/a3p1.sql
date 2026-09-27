-- ============================================================
-- TYPE 2 DIABETES MELLITUS PHENOTYPE (SHIRE / DuckDB)
-- Returns: person_id
-- ============================================================

WITH dx AS (
    -- T2DM diagnosis codes from ICD9/ICD10 source fields
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE
        -- ICD-10-CM E11*
        condition_source_value ILIKE 'E11%' 
        OR
        -- ICD-9-CM 250.xx where 5th digit indicates Type 2
        regexp_matches(condition_source_value, '^250\.(0[02]|1[02]|2[02]|3[02]|4[02]|5[02]|6[02]|7[02]|8[02]|9[02])$')
),

med AS (
    -- Antihyperglycemic medications using source fields
    SELECT DISTINCT person_id
    FROM drug_exposure
    WHERE
        drug_source_value ILIKE '%metformin%' OR
        drug_source_value ILIKE '%glipizide%' OR
        drug_source_value ILIKE '%glyburide%' OR
        drug_source_value ILIKE '%glimepiride%' OR
        drug_source_value ILIKE '%pioglitazone%' OR
        drug_source_value ILIKE '%rosiglitazone%' OR
        drug_source_value ILIKE '%sitagliptin%' OR
        drug_source_value ILIKE '%linagliptin%' OR
        drug_source_value ILIKE '%alogliptin%' OR
        drug_source_value ILIKE '%empagliflozin%' OR
        drug_source_value ILIKE '%dapagliflozin%' OR
        drug_source_value ILIKE '%canagliflozin%' OR
        drug_source_value ILIKE '%semaglutide%' OR
        drug_source_value ILIKE '%liraglutide%' OR
        drug_source_value ILIKE '%dulaglutide%' OR
        drug_source_value ILIKE '%exenatide%' OR
        drug_source_value ILIKE '%insulin%'  -- included but not required alone
),

labs AS (
    -- Abnormal glucose labs using measurement_source_value + numeric thresholds
    SELECT DISTINCT person_id
    FROM measurement
    WHERE
        (
            -- HbA1c >= 6.5%
            measurement_source_value ILIKE '%a1c%' 
            AND value_as_number >= 6.5
        )
        OR
        (
            -- Fasting glucose >= 126 mg/dL
            (measurement_source_value ILIKE '%fasting%' 
             AND measurement_source_value ILIKE '%glucose%')
            AND value_as_number >= 126
        )
        OR
        (
            -- Random glucose >= 200 mg/dL
            measurement_source_value ILIKE '%glucose%'
            AND value_as_number >= 200
        )
)

SELECT DISTINCT person_id
FROM (
    SELECT person_id FROM dx
    UNION
    SELECT person_id FROM med
    UNION
    SELECT person_id FROM labs
);
