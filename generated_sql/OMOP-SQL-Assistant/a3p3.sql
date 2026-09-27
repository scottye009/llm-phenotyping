-- Type 2 Diabetes Mellitus (T2DM) phenotype
-- Logic:
--   Include patients meeting ANY of:
--     1) >= 2 T2DM diagnoses on different dates
--     2) >= 1 T2DM diagnosis + >= 1 antidiabetic medication exposure
--     3) >= 2 diabetes laboratory results in diabetic range
--     4) >= 1 antidiabetic medication exposure + >= 1 diabetes laboratory result in diabetic range
--
-- Exclude patients with evidence suggesting Type 1 diabetes.

WITH t2dm_dx AS (
    -- T2DM diagnosis codes and diagnosis text
    SELECT
        person_id,
        condition_start_date
    FROM condition_occurrence
    WHERE
        (
            -- ICD-10-CM E11*
            condition_source_value ILIKE 'E11%'
            OR
            -- ICD-9-CM 250.x0 / 250.x2 patterns (T2DM)
            regexp_matches(condition_source_value, '^250\\..*[02]$')
            OR
            (
                condition_source_concept_name IS NOT NULL
                AND (
                    condition_source_concept_name ILIKE '%type 2 diabetes%'
                    OR condition_source_concept_name ILIKE '%type ii diabetes%'
                    OR condition_source_concept_name ILIKE '%t2dm%'
                    OR condition_source_concept_name ILIKE '%non-insulin dependent diabetes%'
                )
            )
        )
),

t1dm_dx AS (
    -- Type 1 diabetes exclusion evidence
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE
        condition_source_value ILIKE 'E10%'
        OR regexp_matches(condition_source_value, '^250\\..*[13]$')
        OR (
            condition_source_concept_name IS NOT NULL
            AND (
                condition_source_concept_name ILIKE '%type 1 diabetes%'
                OR condition_source_concept_name ILIKE '%type i diabetes%'
                OR condition_source_concept_name ILIKE '%t1dm%'
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

dm_labs AS (
    -- Diabetes laboratory criteria:
    -- HbA1c >= 6.5%
    -- Fasting glucose >= 126 mg/dL
    -- Random glucose >= 200 mg/dL
    SELECT
        person_id,
        measurement_date
    FROM measurement
    WHERE
        value_as_number IS NOT NULL
        AND
        (
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
                (
                    measurement_source_value ILIKE '%fasting glucose%'
                    OR measurement_source_value ILIKE '%fast glucose%'
                    OR measurement_source_value ILIKE '%fpg%'
                )
                AND value_as_number >= 126
            )

            OR

            (
                (
                    measurement_source_value ILIKE '%glucose%'
                    OR measurement_source_value ILIKE '%blood glucose%'
                    OR measurement_source_value ILIKE '%serum glucose%'
                )
                AND value_as_number >= 200
            )
        )
),

lab_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT measurement_date) AS diabetic_lab_dates
    FROM dm_labs
    GROUP BY person_id
),

dm_meds AS (
    -- Antidiabetic medications (generic + common brand names)
    SELECT DISTINCT
        person_id
    FROM drug_exposure
    WHERE
        drug_source_value IS NOT NULL
        AND
        (
            drug_source_value ILIKE '%metformin%'
            OR drug_source_value ILIKE '%glucophage%'
            OR drug_source_value ILIKE '%glumetza%'
            OR drug_source_value ILIKE '%fortamet%'

            OR drug_source_value ILIKE '%glipizide%'
            OR drug_source_value ILIKE '%glucotrol%'

            OR drug_source_value ILIKE '%glyburide%'
            OR drug_source_value ILIKE '%diabeta%'
            OR drug_source_value ILIKE '%glynase%'

            OR drug_source_value ILIKE '%glimepiride%'
            OR drug_source_value ILIKE '%amaryl%'

            OR drug_source_value ILIKE '%pioglitazone%'
            OR drug_source_value ILIKE '%actos%'

            OR drug_source_value ILIKE '%rosiglitazone%'
            OR drug_source_value ILIKE '%avandia%'

            OR drug_source_value ILIKE '%sitagliptin%'
            OR drug_source_value ILIKE '%januvia%'

            OR drug_source_value ILIKE '%saxagliptin%'
            OR drug_source_value ILIKE '%onglyza%'

            OR drug_source_value ILIKE '%linagliptin%'
            OR drug_source_value ILIKE '%tradjenta%'

            OR drug_source_value ILIKE '%alogliptin%'
            OR drug_source_value ILIKE '%nesina%'

            OR drug_source_value ILIKE '%canagliflozin%'
            OR drug_source_value ILIKE '%invokana%'

            OR drug_source_value ILIKE '%dapagliflozin%'
            OR drug_source_value ILIKE '%farxiga%'

            OR drug_source_value ILIKE '%empagliflozin%'
            OR drug_source_value ILIKE '%jardiance%'

            OR drug_source_value ILIKE '%ertugliflozin%'
            OR drug_source_value ILIKE '%steglatro%'

            OR drug_source_value ILIKE '%liraglutide%'
            OR drug_source_value ILIKE '%victoza%'

            OR drug_source_value ILIKE '%semaglutide%'
            OR drug_source_value ILIKE '%ozempic%'
            OR drug_source_value ILIKE '%rybelsus%'

            OR drug_source_value ILIKE '%dulaglutide%'
            OR drug_source_value ILIKE '%trulicity%'

            OR drug_source_value ILIKE '%exenatide%'
            OR drug_source_value ILIKE '%byetta%'
            OR drug_source_value ILIKE '%bydureon%'

            OR drug_source_value ILIKE '%tirzepatide%'
            OR drug_source_value ILIKE '%mounjaro%'

            OR drug_source_value ILIKE '%acarbose%'
            OR drug_source_value ILIKE '%precose%'

            OR drug_source_value ILIKE '%miglitol%'
            OR drug_source_value ILIKE '%glyset%'

            OR drug_source_value ILIKE '%repaglinide%'
            OR drug_source_value ILIKE '%prandin%'

            OR drug_source_value ILIKE '%nateglinide%'
            OR drug_source_value ILIKE '%starlix%'
        )
),

final_candidates AS (
    SELECT person_id
    FROM dx_summary
    WHERE dx_dates >= 2

    UNION

    SELECT d.person_id
    FROM dx_summary d
    INNER JOIN dm_meds m
        ON d.person_id = m.person_id

    UNION

    SELECT person_id
    FROM lab_summary
    WHERE diabetic_lab_dates >= 2

    UNION

    SELECT l.person_id
    FROM lab_summary l
    INNER JOIN dm_meds m
        ON l.person_id = m.person_id
)

SELECT DISTINCT
    fc.person_id
FROM final_candidates fc
LEFT JOIN t1dm_dx t1
    ON fc.person_id = t1.person_id
WHERE t1.person_id IS NULL
ORDER BY fc.person_id;