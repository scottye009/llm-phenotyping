/* 
Refined Phenotyping Algorithm for Type 2 Diabetes Mellitus (T2DM)
Logic: 
  (Diagnostic Codes OR T2DM-Specific Meds OR Robust Lab Evidence) 
  AND NOT (Type 1 Diabetes Evidence)
*/

-- 1. Identify patients with Type 1 Diabetes for exclusion
WITH t1dm_exclusion AS (
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE (
        condition_source_value ILIKE 'E10%' -- ICD-10 Type 1
        OR condition_source_concept_name ILIKE '%type 1 diabetes%'
        OR condition_source_concept_name ILIKE '%insulin dependent diabetes%'
    )
),

-- 2. Patients identified by T2DM Diagnostic Codes
diag_t2dm AS (
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE (
        condition_source_value ILIKE 'E11%' -- ICD-10 Type 2
        OR condition_source_value ILIKE '250%' -- ICD-9 Diabetes (broad)
        OR condition_source_concept_name ILIKE '%type 2 diabetes%'
        OR condition_source_concept_name ILIKE '%non-insulin dependent diabetes%'
    )
),

-- 3. Patients identified by T2DM-specific Medications
-- We exclude Insulin here because it is non-specific for T2DM
med_t2dm AS (
    SELECT DISTINCT person_id
    FROM drug_exposure
    WHERE (
        -- Biguanides
        drug_source_value ILIKE '%Metformin%' 
        -- Sulfonylureas
        OR drug_source_value ILIKE '%Glipizide%' 
        OR drug_source_value ILIKE '%Glyburide%' 
        OR drug_source_value ILIKE '%Glimepiride%'
        -- DPP-4 Inhibitors
        OR drug_source_value ILIKE '%Sitagliptin%' 
        OR drug_source_value ILIKE '%Januvia%' 
        OR drug_source_value ILIKE '%Saxagliptin%' 
        OR drug_source_value ILIKE '%Linagliptin%'
        -- SGLT2 Inhibitors
        OR drug_source_value ILIKE '%Canagliflozin%' 
        OR drug_source_value ILIKE '%Invokana%' 
        OR drug_source_value ILIKE '%Dapagliflozin%' 
        OR drug_source_value ILIKE '%Farxiga%' 
        OR drug_source_value ILIKE '%Empagliflozin%' 
        OR drug_source_value ILIKE '%Jardiance%'
        -- GLP-1 Agonists
        OR drug_source_value ILIKE '%Exenatide%' 
        OR drug_source_value ILIKE '%Byetta%' 
        OR drug_source_value ILIKE '%Liraglutide%' 
        OR drug_source_value ILIKE '%Victoza%' 
        OR drug_source_value ILIKE '%Semaglutide%' 
        OR drug_source_value ILIKE '%Ozempic%'
        -- TZDs
        OR drug_source_value ILIKE '%Pioglitazone%' 
        OR drug_source_value ILIKE '%Rosiglitazone%'
    )
),

-- 4. Patients identified by laboratory criteria
-- Requiring 2+ distinct dates/events to avoid transient hyperglycemia
lab_t2dm AS (
    SELECT person_id
    FROM measurement
    WHERE (
        -- HbA1c >= 6.5%
        (measurement_source_value ILIKE '%HbA1c%' AND value_as_number >= 6.5)
        OR
        -- Fasting Glucose >= 126 mg/dL
        (measurement_source_value ILIKE '%Glucose%' AND measurement_source_value ILIKE '%Fasting%' AND value_as_number >= 126)
        OR
        -- Random Glucose >= 200 mg/dL
        (measurement_source_value ILIKE '%Glucose%' AND value_as_number >= 200)
    )
    GROUP BY person_id
    HAVING COUNT(DISTINCT CAST(measurement_date AS DATE)) >= 2
)

-- Final Cohort Construction
SELECT 
    all_t2dm.person_id
FROM (
    SELECT person_id FROM diag_t2dm
    UNION
    SELECT person_id FROM med_t2dm
    UNION
    SELECT person_id FROM lab_t2dm
) AS all_t2dm
WHERE NOT EXISTS (
    SELECT 1 
    FROM t1dm_exclusion 
    WHERE t1dm_exclusion.person_id = all_t2dm.person_id
);