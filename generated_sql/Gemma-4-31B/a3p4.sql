-- Phenotyping algorithm for Type 2 Diabetes Mellitus
WITH t2dm_dx AS (
    -- Identify patients via ICD-10 (E11) and ICD-9 (250.x) T2DM codes
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE 
        condition_source_value ILIKE 'E11%' -- ICD-10 Type 2 DM
        OR condition_source_value ILIKE '250%' -- ICD-9 DM (includes T2DM)
        OR condition_source_concept_name ILIKE '%type 2 diabetes%'
        OR condition_source_concept_name ILIKE '%non-insulin dependent diabetes%'
),

t2dm_rx AS (
    -- Identify patients via T2DM specific medications (Generic and Brand)
    SELECT DISTINCT person_id
    FROM drug_exposure
    WHERE 
        drug_source_value ILIKE '%metformin%' 
        OR drug_source_value ILIKE '%glipizide%' 
        OR drug_source_value ILIKE '%glyburide%' 
        OR drug_source_value ILIKE '%glimepiride%' 
        OR drug_source_value ILIKE '%sitagliptin%' 
        OR drug_source_value ILIKE '%saxagliptin%' 
        OR drug_source_value ILIKE '%linagliptin%' 
        OR drug_source_value ILIKE '%empagliflozin%' 
        OR drug_source_value ILIKE '%canagliflozin%' 
        OR drug_source_value ILIKE '%dapagliflozin%' 
        OR drug_source_value ILIKE '%liraglutide%' 
        OR drug_source_value ILIKE '%exenatide%' 
        OR drug_source_value ILIKE '%dulaglutide%' 
        OR drug_concept_name ILIKE '%metformin%' 
        OR drug_concept_name ILIKE '%januvia%' 
        OR drug_concept_name ILIKE '%jaroza%' 
        OR drug_concept_name ILIKE '%farxiga%' 
        OR drug_concept_name ILIKE '%invokana%' 
        OR drug_concept_name ILIKE '%trulicity%'
),

t2dm_labs AS (
    -- Identify patients via lab thresholds (HbA1c >= 6.5% or Fasting Glucose >= 126 mg/dL)
    SELECT DISTINCT person_id
    FROM measurement
    WHERE 
        (
            (measurement_source_value ILIKE '%HbA1c%' OR measurement_concept_name ILIKE '%HbA1c%') 
            AND value_as_number >= 6.5
        )
        OR 
        (
            (measurement_source_value ILIKE '%glucose%' OR measurement_concept_name ILIKE '%glucose%') 
            AND (measurement_source_value ILIKE '%fasting%' OR measurement_concept_name ILIKE '%fasting%')
            AND value_as_number >= 126
        )
)

-- Final combination: Patients meeting DX, RX, or LAB criteria
SELECT person_id FROM t2dm_dx
UNION
SELECT person_id FROM t2dm_rx
UNION
SELECT person_id FROM t2dm_labs;