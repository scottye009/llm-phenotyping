-- Phenotyping Algorithm for Type 2 Diabetes Mellitus (T2DM)
-- Modified for Shire Environment: Denormalized Source Value Matching

WITH 
-- 1. Identify patients with T2DM Diagnostic Codes via source values
diag_counts AS (
    SELECT 
        person_id, 
        COUNT(DISTINCT condition_source_value) as code_count
    FROM memory.condition_occurrence
    WHERE (
-- ICD-10: E11.x (T2DM)
        condition_source_value LIKE 'E11%' COLLATE NOCASE
-- ICD-9: 250.0x (T2DM)
        OR condition_source_value LIKE '250.0%' COLLATE NOCASE
-- Specific codes mentioned in original logic
        OR condition_source_value IN ('250.00', '250.01', 'E11.0', 'E11.1', 'E11.2', 'E11.3', 'E11.4', 'E11.5', 'E11.6', 'E11.7', 'E11.8', 'E11.9')
    )
    GROUP BY person_id
),

-- 2. Identify patients with T2DM Medications via source values
drug_counts AS (
    SELECT 
        person_id, 
        COUNT(DISTINCT drug_source_value) as drug_count
    FROM memory.drug_exposure
    WHERE (
        drug_source_value LIKE '%Metformin%' COLLATE NOCASE OR 
        drug_source_value LIKE '%Glipizide%' COLLATE NOCASE OR 
        drug_source_value LIKE '%Pioglitazone%' COLLATE NOCASE OR 
        drug_source_value LIKE '%Sitagliptin%' COLLATE NOCASE OR 
        drug_source_value LIKE '%Liraglutide%' COLLATE NOCASE OR 
        drug_source_value LIKE '%Empagliflozin%' COLLATE NOCASE OR 
        drug_source_value LIKE '%Januvia%' COLLATE NOCASE OR 
        drug_source_value LIKE '%Victoza%' COLLATE NOCASE OR 
        drug_source_value LIKE '%Jardiance%' COLLATE NOCASE
    )
    GROUP BY person_id
),

-- 3. Identify patients with Lab Evidence via source value text
-- HbA1c >= 6.5% or Fasting Glucose >= 126 mg/dL
lab_evidence AS (
    SELECT DISTINCT person_id
    FROM memory.measurement
    WHERE (
        (measurement_source_value LIKE '%HbA1c%' COLLATE NOCASE AND value_as_number >= 6.5)
        OR 
        (measurement_source_value LIKE '%Glucose%' COLLATE NOCASE AND measurement_source_value LIKE '%Fasting%' COLLATE NOCASE AND value_as_number >= 126)
    )
),

-- 4. Exclusions (T1DM or Gestational)
exclusions AS (
    SELECT DISTINCT person_id
    FROM memory.condition_occurrence
    WHERE (
-- ICD-10: E10.x (T1DM) or O24.4 (Gestational)
        condition_source_value LIKE 'E10%' COLLATE NOCASE
        OR condition_source_value LIKE 'O24.4%' COLLATE NOCASE
-- ICD-9: 250.1 (T1DM)
        OR condition_source_value LIKE '250.1%' COLLATE NOCASE
-- Specific codes mentioned in original logic
        OR condition_source_value IN ('250.10', 'E10.0', 'E10.1', 'E10.2', 'E10.3', 'E10.4', 'E10.5', 'E10.6', 'E10.7', 'E10.8', 'E10.9', 'O24.4')
    )
)

-- Final Algorithm Assembly
SELECT 
    p.person_id
FROM memory.person p
WHERE (
-- Criterion 1: At least 2 diagnostic codes
    (p.person_id IN (SELECT person_id FROM diag_counts WHERE code_count >= 2))
    OR 
-- Criterion 2: 1 diagnostic code AND 1 lab result
    (p.person_id IN (SELECT person_id FROM diag_counts WHERE code_count >= 1) 
     AND p.person_id IN (SELECT person_id FROM lab_evidence))
    OR 
-- Criterion 3: 1 diagnostic code AND 1 T2DM medication
    (p.person_id IN (SELECT person_id FROM diag_counts WHERE code_count >= 1) 
     AND p.person_id IN (SELECT person_id FROM drug_counts WHERE drug_count >= 1))
    OR 
-- Criterion 4: 2 or more T2DM medications
    (p.person_id IN (SELECT person_id FROM drug_counts WHERE drug_count >= 2))
)
-- Exclusion Logic: NOT T1DM or Gestational
AND p.person_id NOT IN (SELECT person_id FROM exclusions)