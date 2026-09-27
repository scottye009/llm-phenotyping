-- Phenotype for Type 2 Diabetes Mellitus (T2DM)

WITH t2dm_dx AS (
    -- Criterion 1: Diagnosis codes (ICD-10 E11 or ICD-9 250.x0/250.x2)
    -- We exclude Type 1 codes (250.x1, 250.x3)
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE condition_source_value ILIKE 'E11%'
       OR condition_source_value ILIKE '250.%0'
       OR condition_source_value ILIKE '250.%2'
       OR condition_source_concept_name ILIKE '%type 2 diabetes%'
       OR condition_source_concept_name ILIKE '%T2DM%'
),

t2dm_meds AS (
    -- Criterion 2: T2DM specific medications (Generic and Brand)
    SELECT DISTINCT person_id
    FROM drug_exposure
    WHERE drug_source_value ILIKE '%metformin%' OR drug_source_value ILIKE '%glucophage%'
       OR drug_source_value ILIKE '%glipizide%' OR drug_source_value ILIKE '%glucotrol%'
       OR drug_source_value ILIKE '%glyburide%' OR drug_source_value ILIKE '%diabeta%'
       OR drug_source_value ILIKE '%glimepiride%' OR drug_source_value ILIKE '%amaryl%'
       OR drug_source_value ILIKE '%sitagliptin%' OR drug_source_value ILIKE '%januvia%'
       OR drug_source_value ILIKE '%pioglitazone%' OR drug_source_value ILIKE '%actos%'
       OR drug_source_value ILIKE '%empagliflozin%' OR drug_source_value ILIKE '%jardiance%'
       OR drug_source_value ILIKE '%dapagliflozin%' OR drug_source_value ILIKE '%farxiga%'
       OR drug_source_value ILIKE '%liraglutide%' OR drug_source_value ILIKE '%victoza%'
),

t2dm_labs AS (
    -- Criterion 3: Lab results (HbA1c >= 6.5 or Glucose >= 126)
    SELECT DISTINCT person_id
    FROM measurement
    WHERE (
        -- HbA1c
        (measurement_source_value ILIKE '%A1c%' OR measurement_source_value ILIKE '%glycated hemoglobin%')
        AND value_as_number >= 6.5
    ) OR (
        -- Fasting Glucose (Approximate check for high glucose values)
        (measurement_source_value ILIKE '%glucose%' AND measurement_source_value ILIKE '%fasting%')
        AND value_as_number >= 126
    )
)

-- Final result: Union of all criteria
SELECT DISTINCT person_id
FROM (
    SELECT person_id FROM t2dm_dx
    UNION
    SELECT person_id FROM t2dm_meds
    UNION
    SELECT person_id FROM t2dm_labs
) as combined_t2dm;