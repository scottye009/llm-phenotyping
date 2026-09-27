-- 1. Identify patients with T2DM diagnosis codes (ICD-9/ICD-10)
WITH t2dm_dx AS (
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE condition_source_value ILIKE 'E11%' -- ICD10 T2DM
       OR condition_source_value ILIKE '250.00%' -- ICD9 T2DM
       OR condition_source_value ILIKE '250.02%' -- ICD9 T2DM
       OR condition_source_concept_name ILIKE '%type 2 diabetes%'
       OR condition_source_concept_name ILIKE '%type II diabetes%'
),

-- 2. Identify patients with lab results (HbA1c >= 6.5%)
t2dm_labs AS (
    SELECT DISTINCT person_id
    FROM measurement
    WHERE (
        measurement_source_value ILIKE '%hba1c%'
        OR measurement_source_value ILIKE '%hemoglobin a1c%'
        OR measurement_source_value ILIKE '%glycated hemoglobin%'
    )
    AND value_as_number >= 6.5
),

-- 3. Identify patients on T2DM specific medications
t2dm_meds AS (
    SELECT DISTINCT person_id
    FROM drug_exposure
    WHERE drug_concept_name ILIKE '%metformin%'
       OR drug_concept_name ILIKE '%glipizide%'
       OR drug_concept_name ILIKE '%glyburide%'
       OR drug_concept_name ILIKE '%glimepiride%'
       OR drug_concept_name ILIKE '%sitagliptin%'
       OR drug_concept_name ILIKE '%pioglitazone%'
       OR drug_source_value ILIKE '%metformin%'
       OR drug_source_value ILIKE '%glipizide%'
       OR drug_source_value ILIKE '%glyburide%'
       OR drug_source_value ILIKE '%glimepiride%'
       OR drug_source_value ILIKE '%sitagliptin%'
       OR drug_source_value ILIKE '%pioglitazone%'
)

-- Final Algorithm: Union of all criteria
SELECT DISTINCT p.person_id
FROM person p
WHERE EXISTS (SELECT 1 FROM t2dm_dx WHERE t2dm_dx.person_id = p.person_id)
   OR EXISTS (SELECT 1 FROM t2dm_labs WHERE t2dm_labs.person_id = p.person_id)
   OR EXISTS (SELECT 1 FROM t2dm_meds WHERE t2dm_meds.person_id = p.person_id);