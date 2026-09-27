/* 
  T2DM Phenotyping Algorithm
  Logic: (T2DM Diagnosis OR T2DM Medication OR Lab Evidence) AND NOT Type 1 Diabetes
*/

WITH t2dm_diagnosis AS (
    -- Identify patients with ICD-9/10 codes for Type 2 Diabetes
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE (
        condition_source_value ILIKE 'E11%' -- ICD-10 Type 2
        OR condition_source_value ILIKE '250%' -- ICD-9 Diabetes (broad, usually T2 in adults)
        OR condition_source_concept_name ILIKE '%type 2 diabetes%'
        OR condition_source_concept_name ILIKE '%non-insulin dependent diabetes%'
    )
),

t1dm_exclusion AS (
    -- Identify patients with explicit Type 1 Diabetes for exclusion
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE (
        condition_source_value ILIKE 'E10%' -- ICD-10 Type 1
        OR condition_source_concept_name ILIKE '%type 1 diabetes%'
        OR condition_source_concept_name ILIKE '%insulin dependent diabetes%'
    )
),

t2dm_meds AS (
    -- Identify patients using T2DM medications
    SELECT DISTINCT person_id
    FROM drug_exposure
    WHERE (
        drug_source_value ILIKE '%metformin%'
        OR drug_source_value ILIKE '%glipizide%'
        OR drug_source_value ILIKE '%glyburide%'
        OR drug_source_value ILIKE '%glimepiride%'
        OR drug_source_value ILIKE '%sitagliptin%'
        OR drug_source_value ILIKE '%empagliflozin%'
        OR drug_source_value ILIKE '%canagliflozin%'
        OR drug_source_value ILIKE '%dapagliflozin%'
        OR drug_source_value ILIKE '%liraglutide%'
        OR drug_source_value ILIKE '%semaglutide%'
        OR drug_concept_name ILIKE '%metformin%'
        OR drug_concept_name ILIKE '%januvia%'
        OR drug_concept_name ILIKE '%jarvis%'
    )
),

t2dm_labs AS (
    -- Identify patients meeting glycemic thresholds
    SELECT person_id
    FROM measurement
    WHERE (
        -- HbA1c >= 6.5%
        (measurement_source_value ILIKE '%HbA1c%' AND value_as_number >= 6.5)
        OR 
        -- Fasting Glucose >= 126 mg/dL (approximate check for 'fasting' in source value)
        (measurement_source_value ILIKE '%glucose%' AND measurement_source_value ILIKE '%fasting%' AND value_as_number >= 126)
        OR
        -- Random Glucose >= 200 mg/dL
        (measurement_source_value ILIKE '%glucose%' AND value_as_number >= 200)
    )
    GROUP BY person_id
    HAVING COUNT(DISTINCT measurement_date) >= 1 -- Use 1 for sensitivity, 2 for higher specificity
),

final_cohort AS (
    -- Combine criteria and apply exclusion
    SELECT person_id
    FROM (
        SELECT person_id FROM t2dm_diagnosis
        UNION
        SELECT person_id FROM t2dm_meds
        UNION
        SELECT person_id FROM t2dm_labs
    )
    WHERE person_id NOT IN (SELECT person_id FROM t1dm_exclusion)
)

SELECT person_id FROM final_cohort;