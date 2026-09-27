WITH dx AS (
    -- Type 2 diabetes diagnosis codes
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE
        -- ICD-9-CM 250.x0 or 250.x2
        condition_source_value ILIKE '250.%0'
        OR condition_source_value ILIKE '250.%2'
        -- ICD-10-CM E11*
        OR condition_source_value ILIKE 'E11%'
),

meds AS (
    -- Non-insulin diabetes medications
    SELECT DISTINCT person_id
    FROM drug_exposure
    WHERE
        drug_source_value ILIKE '%metformin%'
        OR drug_source_value ILIKE '%glucophage%'
        OR drug_source_value ILIKE '%fortamet%'
        OR drug_source_value ILIKE '%glumetza%'
        OR drug_source_value ILIKE '%riomet%'
        OR drug_source_value ILIKE '%glipizide%'
        OR drug_source_value ILIKE '%glyburide%'
        OR drug_source_value ILIKE '%glimepiride%'
        OR drug_source_value ILIKE '%pioglitazone%'
        OR drug_source_value ILIKE '%rosiglitazone%'
        OR drug_source_value ILIKE '%sitagliptin%'
        OR drug_source_value ILIKE '%saxagliptin%'
        OR drug_source_value ILIKE '%linagliptin%'
        OR drug_source_value ILIKE '%alogliptin%'
        OR drug_source_value ILIKE '%liraglutide%'
        OR drug_source_value ILIKE '%semaglutide%'
        OR drug_source_value ILIKE '%dulaglutide%'
        OR drug_source_value ILIKE '%exenatide%'
        OR drug_source_value ILIKE '%empagliflozin%'
        OR drug_source_value ILIKE '%canagliflozin%'
        OR drug_source_value ILIKE '%dapagliflozin%'
        OR drug_source_value ILIKE '%repaglinide%'
        OR drug_source_value ILIKE '%nateglinide%'
        OR drug_source_value ILIKE '%acarbose%'
        OR drug_source_value ILIKE '%miglitol%'
),

labs AS (
    -- Abnormal labs: A1c ≥6.5 OR glucose ≥126 fasting OR ≥200 random
    SELECT person_id, measurement_date
    FROM measurement
    WHERE
        (
            -- HbA1c
            (measurement_source_value ILIKE '%a1c%' OR measurement_source_value ILIKE '%hba1c%')
            AND value_as_number >= 6.5
        )
        OR (
            -- Glucose
            measurement_source_value ILIKE '%glucose%'
            AND unit_source_value ILIKE '%mg/dl%'
            AND (
                value_as_number >= 200  -- random glucose
                OR value_as_number >= 126  -- fasting glucose (no reliable fasting flag)
            )
        )
),
labs_two_dates AS (
    -- Require ≥2 abnormal labs on different dates
    SELECT person_id
    FROM labs
    GROUP BY person_id
    HAVING COUNT(DISTINCT measurement_date) >= 2
)

SELECT DISTINCT person_id
FROM (
    SELECT person_id FROM dx
    UNION
    SELECT person_id FROM meds
    UNION
    SELECT person_id FROM labs_two_dates
);
