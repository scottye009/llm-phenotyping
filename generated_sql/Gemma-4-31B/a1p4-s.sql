-- Type 2 Diabetes Mellitus Phenotyping Algorithm
-- Modified for Shire Environment: Denormalized Source Value Matching

WITH

-- 1. Identify Evidence via Source Values

-- Patients with T2DM diagnosis codes (ICD10: E11, ICD9: 250.00)
dx_evidence AS (
SELECT DISTINCT person_id
FROM memory.condition_occurrence
WHERE (
condition_source_value LIKE 'E11%' COLLATE NOCASE
OR condition_source_value LIKE '250.00%' COLLATE NOCASE
)
),

-- Patients taking T2DM medications (Generic and Brand names)
rx_evidence AS (
SELECT DISTINCT person_id
FROM memory.drug_exposure
WHERE (
drug_source_value LIKE '%Metformin%' COLLATE NOCASE OR
drug_source_value LIKE '%Glucophage%' COLLATE NOCASE OR
drug_source_value LIKE '%Glimepiride%' COLLATE NOCASE OR
drug_source_value LIKE '%Amaryl%' COLLATE NOCASE OR
drug_source_value LIKE '%Sitagliptin%' COLLATE NOCASE OR
drug_source_value LIKE '%Januvia%' COLLATE NOCASE OR
drug_source_value LIKE '%Empagliflozin%' COLLATE NOCASE OR
drug_source_value LIKE '%Jardiance%' COLLATE NOCASE OR
drug_source_value LIKE '%Liraglutide%' COLLATE NOCASE OR
drug_source_value LIKE '%Victoza%' COLLATE NOCASE
)
),

-- Lab Evidence: HbA1c >= 6.5% or Fasting Glucose >= 126 mg/dL
lab_evidence AS (
SELECT DISTINCT person_id
FROM memory.measurement
WHERE (
(measurement_source_value LIKE '%HbA1c%' COLLATE NOCASE AND value_as_number >= 6.5)
OR
(measurement_source_value LIKE '%Glucose%' COLLATE NOCASE AND measurement_source_value LIKE '%Fasting%' COLLATE NOCASE AND value_as_number >= 126)
)
),

-- Patients with T1DM (E10) or Gestational DM (O24.4)
excluded_patients AS (
SELECT DISTINCT person_id
FROM memory.condition_occurrence
WHERE (
condition_source_value LIKE 'E10%' COLLATE NOCASE
OR condition_source_value LIKE 'O24.4%' COLLATE NOCASE
)
)

-- 2. Final Phenotype Assembly

SELECT p.person_id
FROM memory.person p
WHERE (
p.person_id IN (SELECT person_id FROM dx_evidence)     -- Diagnosis
OR p.person_id IN (SELECT person_id FROM lab_evidence)  -- Labs
OR p.person_id IN (SELECT person_id FROM rx_evidence)   -- Medications
)
AND p.person_id NOT IN (SELECT person_id FROM excluded_patients)