-- Type 2 Diabetes Mellitus Phenotyping Algorithm
-- Returns person_id for patients meeting diagnosis, medication, or laboratory criteria

WITH t2dm_diagnosis AS (
    -- Identify patients with T2DM based on ICD-9 and ICD-10 source codes
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE (
        -- ICD-10: E11 is Type 2 Diabetes Mellitus
        condition_source_value ILIKE 'E11%' 
        -- ICD-9: 250.x is Diabetes Mellitus (Broad, but common in legacy data)
        OR condition_source_value ILIKE '250%'
    )
    -- Exclude explicit Type 1 Diabetes to increase specificity (E10 for ICD-10)
    AND person_id NOT IN (
        SELECT person_id 
        FROM condition_occurrence 
        WHERE condition_source_value ILIKE 'E10%'
    )
),

t2dm_medications AS (
    -- Identify patients using T2DM-specific medications
    SELECT DISTINCT person_id
    FROM drug_exposure
    WHERE (
        -- Metformin / Biguanides
        drug_source_value ILIKE '%Metformin%' 
        -- Sulfonylureas
        OR drug_source_value ILIKE '%Glipizide%' 
        OR drug_source_value ILIKE '%Glyburide%' 
        OR drug_source_value ILIKE '%Glimepiride%'
        -- DPP-4 Inhibitors
        OR drug_source_value ILIKE '%Sitagliptin%' 
        OR drug_source_value ILIKE '%Saxagliptin%' 
        OR drug_source_value ILIKE '%Linagliptin%'
        -- SGLT2 Inhibitors
        OR drug_source_value ILIKE '%Empagliflozin%' 
        OR drug_source_value ILIKE '%Canagliflozin%' 
        OR drug_source_value ILIKE '%Dapagliflozin%'
        -- GLP-1 Agonists
        OR drug_source_value ILIKE '%Exenatide%' 
        OR drug_source_value ILIKE '%Liraglutide%' 
        OR drug_source_value ILIKE '%Dulaglutide%' 
        OR drug_source_value ILIKE '%Semaglutide%'
        -- Insulin (supports diabetes generally)
        OR drug_source_value ILIKE '%Insulin%'
    )
),

t2dm_labs AS (
    -- Identify patients with laboratory evidence of diabetes (requiring 2+ occurrences for robustness)
    SELECT person_id
    FROM measurement
    WHERE (
        -- HbA1c >= 6.5%
        (measurement_source_value ILIKE '%HbA1c%' AND value_as_number >= 6.5)
        -- Fasting Glucose >= 126 mg/dL
        OR (measurement_source_value ILIKE '%Glucose%' AND measurement_source_value ILIKE '%Fasting%' AND value_as_number >= 126)
        -- Random Glucose >= 200 mg/dL
        OR (measurement_source_value ILIKE '%Glucose%' AND value_as_number >= 200)
    )
    GROUP BY person_id
    HAVING COUNT(*) >= 2
)

-- Final Union: Patient matches if they fall into any of the three criteria buckets
SELECT person_id FROM t2dm_diagnosis
UNION
SELECT person_id FROM t2dm_medications
UNION
SELECT person_id FROM t2dm_labs;