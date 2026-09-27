/**
  Refined Phenotyping Algorithm for Type 2 Diabetes Mellitus (T2DM)
  Modified for Shire Environment: Denormalized Source Value Matching
  Logic:
    (Diagnostic Codes OR T2DM-Specific Meds OR Robust Lab Evidence)
    AND NOT (Type 1 Diabetes Evidence)
**/

-- 1. Identify patients with Type 1 Diabetes for exclusion
WITH t1dm_exclusion AS (
    SELECT DISTINCT person_id
    FROM memory.condition_occurrence
    WHERE (
        condition_source_value LIKE 'E10%' COLLATE NOCASE -- ICD-10 Type 1
-- logic shifted to source_value as concept names are metadata
        OR condition_source_value LIKE '%type 1 diabetes%' COLLATE NOCASE
        OR condition_source_value LIKE '%insulin dependent diabetes%' COLLATE NOCASE
    )
),

-- 2. Patients identified by T2DM Diagnostic Codes
diag_t2dm AS (
    SELECT DISTINCT person_id
    FROM memory.condition_occurrence
    WHERE (
        condition_source_value LIKE 'E11%' COLLATE NOCASE -- ICD-10 Type 2
        OR condition_source_value LIKE '250%' COLLATE NOCASE -- ICD-9 Diabetes (broad)
        OR condition_source_value LIKE '%type 2 diabetes%' COLLATE NOCASE
        OR condition_source_value LIKE '%non-insulin dependent diabetes%' COLLATE NOCASE
    )
),

-- 3. Patients identified by T2DM-specific Medications
med_t2dm AS (
    SELECT DISTINCT person_id
    FROM memory.drug_exposure
    WHERE (
-- Biguanides
        drug_source_value LIKE '%Metformin%' COLLATE NOCASE
-- Sulfonylureas
        OR drug_source_value LIKE '%Glipizide%' COLLATE NOCASE
        OR drug_source_value LIKE '%Glyburide%' COLLATE NOCASE
        OR drug_source_value LIKE '%Glimepiride%' COLLATE NOCASE
-- DPP-4 Inhibitors
        OR drug_source_value LIKE '%Sitagliptin%' COLLATE NOCASE
        OR drug_source_value LIKE '%Januvia%' COLLATE NOCASE
        OR drug_source_value LIKE '%Saxagliptin%' COLLATE NOCASE
        OR drug_source_value LIKE '%Linagliptin%' COLLATE NOCASE
-- SGLT2 Inhibitors
        OR drug_source_value LIKE '%Canagliflozin%' COLLATE NOCASE
        OR drug_source_value LIKE '%Invokana%' COLLATE NOCASE
        OR drug_source_value LIKE '%Dapagliflozin%' COLLATE NOCASE
        OR drug_source_value LIKE '%Farxiga%' COLLATE NOCASE
        OR drug_source_value LIKE '%Empagliflozin%' COLLATE NOCASE
        OR drug_source_value LIKE '%Jardiance%' COLLATE NOCASE
-- GLP-1 Agonists
        OR drug_source_value LIKE '%Exenatide%' COLLATE NOCASE
        OR drug_source_value LIKE '%Byetta%' COLLATE NOCASE
        OR drug_source_value LIKE '%Liraglutide%' COLLATE NOCASE
        OR drug_source_value LIKE '%Victoza%' COLLATE NOCASE
        OR drug_source_value LIKE '%Semaglutide%' COLLATE NOCASE
        OR drug_source_value LIKE '%Ozempic%' COLLATE NOCASE
-- TZDs
        OR drug_source_value LIKE '%Pioglitazone%' COLLATE NOCASE
        OR drug_source_value LIKE '%Rosiglitazone%' COLLATE NOCASE
    )
),

-- 4. Patients identified by laboratory criteria
-- Requiring 2+ distinct dates/events to avoid transient hyperglycemia
lab_t2dm AS (
    SELECT person_id
    FROM memory.measurement
    WHERE (
-- HbA1c >= 6.5%
        (measurement_source_value LIKE '%HbA1c%' COLLATE NOCASE AND value_as_number >= 6.5)
        OR
-- Fasting Glucose >= 126 mg/dL
        (measurement_source_value LIKE '%Glucose%' COLLATE NOCASE AND measurement_source_value LIKE '%Fasting%' COLLATE NOCASE AND value_as_number >= 126)
        OR
-- Random Glucose >= 200 mg/dL
        (measurement_source_value LIKE '%Glucose%' COLLATE NOCASE AND value_as_number >= 200)
    )
    GROUP BY person_id
    HAVING COUNT(DISTINCT measurement_date) >= 2
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
)