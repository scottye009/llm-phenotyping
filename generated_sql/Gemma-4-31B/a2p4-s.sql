/*
Phenotyping Algorithm for Type 2 Diabetes Mellitus (T2DM)
Modified for Shire Environment: Denormalized Source Value Matching
*/

WITH
-- 1. Identify T2DM Diagnosis via Source Values (ICD9, ICD10)
t2dm_diag_evidence AS (
SELECT person_id, condition_occurrence_id
FROM memory.condition_occurrence
WHERE (
condition_source_value LIKE 'E11%' COLLATE NOCASE
OR condition_source_value IN ('E11.9', 'E11.8', 'E11.65')
OR condition_source_value IN ('250.00', '250.01')
)
),

-- 2. Identify T2DM-Specific Medications via Source Values
t2dm_med_evidence AS (
SELECT DISTINCT person_id
FROM memory.drug_exposure
WHERE (
drug_source_value LIKE '%Metformin%' COLLATE NOCASE OR drug_source_value LIKE '%Glucophage%' COLLATE NOCASE
OR drug_source_value LIKE '%Pioglitazone%' COLLATE NOCASE OR drug_source_value LIKE '%Actos%' COLLATE NOCASE
OR drug_source_value LIKE '%Sitagliptin%' COLLATE NOCASE OR drug_source_value LIKE '%Januvia%' COLLATE NOCASE
OR drug_source_value LIKE '%Empagliflozin%' COLLATE NOCASE OR drug_source_value LIKE '%Jardiance%' COLLATE NOCASE
OR drug_source_value LIKE '%Liraglutide%' COLLATE NOCASE OR drug_source_value LIKE '%Victoza%' COLLATE NOCASE
)
),

-- 3. Identify Lab Tests for Hyperglycemia (HbA1c >= 6.5% or Fasting Glucose >= 126 mg/dL)
t2dm_lab_evidence AS (
SELECT DISTINCT person_id
FROM memory.measurement
WHERE (
(measurement_source_value LIKE '%HbA1c%' COLLATE NOCASE AND value_as_number >= 6.5)
OR
(measurement_source_value LIKE '%Glucose%' COLLATE NOCASE AND measurement_source_value LIKE '%Fasting%' COLLATE NOCASE AND value_as_number >= 126)
)
),

-- 4. Define Exclusion Criteria (Type 1 Diabetes indicators and Ketoacidosis)
t1dm_exclusion AS (
SELECT DISTINCT person_id
FROM memory.condition_occurrence
WHERE (
condition_source_value LIKE 'E10%' COLLATE NOCASE
OR condition_source_value LIKE '%Ketoacidosis%' COLLATE NOCASE
)
),

-- 5. Apply the Combination Logic
t2dm_candidates AS (
-- Logic: (2+ Diagnoses)
SELECT person_id
FROM t2dm_diag_evidence
GROUP BY person_id
HAVING COUNT(DISTINCT condition_occurrence_id) >= 2

UNION

-- Logic: (1 Diagnosis AND (Lab OR Med))
SELECT person_id
FROM t2dm_diag_evidence
WHERE person_id IN (SELECT person_id FROM t2dm_lab_evidence) 
   OR person_id IN (SELECT person_id FROM t2dm_med_evidence)
)

-- Final Algorithm Output
SELECT
c.person_id
FROM t2dm_candidates c
LEFT JOIN t1dm_exclusion e ON c.person_id = e.person_id
WHERE e.person_id IS NULL