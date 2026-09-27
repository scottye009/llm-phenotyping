WITH dx AS (
    -- T2DM diagnosis codes from ICD9CM and ICD10CM
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE
        -- ICD-10-CM E11*
        condition_source_value ILIKE 'E11%' 
        OR
        -- ICD-9-CM 250.x0 or 250.x2
        regexp_matches(condition_source_value, '^250\.[0-9]0$')
        OR regexp_matches(condition_source_value, '^250\.[0-9]2$')
),

med AS (
    -- Antihyperglycemic medications (generic + brand names)
    SELECT person_id
    FROM drug_exposure
    WHERE
        drug_source_value ILIKE '%metformin%' OR
        drug_source_value ILIKE '%glucophage%' OR
        drug_source_value ILIKE '%glumetza%' OR
        drug_source_value ILIKE '%riomet%' OR

        drug_source_value ILIKE '%glyburide%' OR
        drug_source_value ILIKE '%glipizide%' OR
        drug_source_value ILIKE '%glimepiride%' OR

        drug_source_value ILIKE '%pioglitazone%' OR
        drug_source_value ILIKE '%rosiglitazone%' OR

        drug_source_value ILIKE '%sitagliptin%' OR
        drug_source_value ILIKE '%linagliptin%' OR
        drug_source_value ILIKE '%saxagliptin%' OR
        drug_source_value ILIKE '%alogliptin%' OR

        drug_source_value ILIKE '%liraglutide%' OR
        drug_source_value ILIKE '%semaglutide%' OR
        drug_source_value ILIKE '%dulaglutide%' OR

        drug_source_value ILIKE '%empagliflozin%' OR
        drug_source_value ILIKE '%dapagliflozin%' OR
        drug_source_value ILIKE '%canagliflozin%' OR

        drug_source_value ILIKE '%insulin%'
    GROUP BY person_id
    HAVING COUNT(DISTINCT drug_exposure_start_date) >= 2
),

labs AS (
    -- Abnormal glucose labs
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
            measurement_source_value ILIKE '%fasting%' 
            AND measurement_source_value ILIKE '%glucose%' 
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
