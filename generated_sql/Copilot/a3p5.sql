WITH dx AS (
    -- T2DM diagnosis codes (ICD-9-CM 250.x0, 250.x2; ICD-10-CM E11.*)
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE
        condition_source_value ILIKE '250.%0'
        OR condition_source_value ILIKE '250.%2'
        OR condition_source_value ILIKE 'E11.%'
),

meds AS (
    -- T2DM medications: generic + brand names
    -- Includes metformin, sulfonylureas, DPP4i, GLP1-RA, SGLT2i, TZDs, insulin (exclude insulin-only unless dx present)
    SELECT DISTINCT person_id
    FROM drug_exposure
    WHERE
        drug_source_value ILIKE '%metformin%'
        OR drug_source_value ILIKE '%glucophage%'
        OR drug_source_value ILIKE '%glumetza%'
        OR drug_source_value ILIKE '%riomet%'
        OR drug_source_value ILIKE '%fortamet%'

        OR drug_source_value ILIKE '%glyburide%'
        OR drug_source_value ILIKE '%glipizide%'
        OR drug_source_value ILIKE '%glimepiride%'

        OR drug_source_value ILIKE '%sitagliptin%'
        OR drug_source_value ILIKE '%januvia%'
        OR drug_source_value ILIKE '%linagliptin%'
        OR drug_source_value ILIKE '%trajenta%'
        OR drug_source_value ILIKE '%alogliptin%'
        OR drug_source_value ILIKE '%nesina%'
        OR drug_source_value ILIKE '%saxagliptin%'
        OR drug_source_value ILIKE '%onglyza%'

        OR drug_source_value ILIKE '%liraglutide%'
        OR drug_source_value ILIKE '%victoza%'
        OR drug_source_value ILIKE '%semaglutide%'
        OR drug_source_value ILIKE '%ozempic%'
        OR drug_source_value ILIKE '%dulaglutide%'
        OR drug_source_value ILIKE '%trulicity%'

        OR drug_source_value ILIKE '%empagliflozin%'
        OR drug_source_value ILIKE '%jardiance%'
        OR drug_source_value ILIKE '%dapagliflozin%'
        OR drug_source_value ILIKE '%farxiga%'
        OR drug_source_value ILIKE '%canagliflozin%'
        OR drug_source_value ILIKE '%invokana%'

        OR drug_source_value ILIKE '%pioglitazone%'
        OR drug_source_value ILIKE '%actos%'
        OR drug_source_value ILIKE '%rosiglitazone%'
        OR drug_source_value ILIKE '%avandia%'

        OR drug_source_value ILIKE '%insulin%'  -- insulin allowed but not alone
),

labs AS (
    -- Laboratory evidence of diabetes:
    -- HbA1c ≥ 6.5%, fasting glucose ≥ 126 mg/dL, random glucose ≥ 200 mg/dL
    SELECT DISTINCT person_id
    FROM measurement
    WHERE
        (
            -- HbA1c
            (measurement_source_value ILIKE '%a1c%' OR measurement_source_value ILIKE '%hba1c%')
            AND value_as_number >= 6.5
        )
        OR (
            -- fasting glucose
            measurement_source_value ILIKE '%fasting%' 
            AND measurement_source_value ILIKE '%glucose%'
            AND value_as_number >= 126
        )
        OR (
            -- random glucose
            measurement_source_value ILIKE '%glucose%'
            AND value_as_number >= 200
        )
),

insulin_only AS (
    -- Identify people with insulin but NO oral/other T2DM meds
    SELECT DISTINCT d.person_id
    FROM drug_exposure d
    WHERE d.drug_source_value ILIKE '%insulin%'
    EXCEPT
    SELECT person_id FROM meds
),

final_cohort AS (
    SELECT DISTINCT person_id
    FROM (
        -- Diagnosis alone qualifies
        SELECT person_id FROM dx
        UNION
        -- Labs alone qualify
        SELECT person_id FROM labs
        UNION
        -- Medications qualify EXCEPT insulin-only users
        SELECT person_id FROM meds
        EXCEPT
        SELECT person_id FROM insulin_only
    )
)

SELECT person_id
FROM final_cohort
ORDER BY person_id;
