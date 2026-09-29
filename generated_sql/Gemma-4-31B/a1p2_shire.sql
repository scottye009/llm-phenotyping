-- Type 2 Diabetes Mellitus (T2DM) Phenotyping Algorithm
-- Modified for Shire Environment: Denormalized Source Value Matching

WITH T2DM_Diag_Persons AS (
-- Replaces T2DM_Concepts: Identify patients with T2DM source values
-- ICD-10 E11, ICD-9 250.00, 250.01
    SELECT person_id, condition_occurrence_id
    FROM memory.condition_occurrence
    WHERE (
        condition_source_value LIKE 'E11%' COLLATE NOCASE 
        OR condition_source_value LIKE '250.0%' COLLATE NOCASE
    )
),

T2DM_Med_Persons AS (
-- Replaces T2DM_Meds: Identify medication exposures via source values
    SELECT person_id, drug_exposure_id
    FROM memory.drug_exposure
    WHERE (
        drug_source_value LIKE '%Metformin%' COLLATE NOCASE OR drug_source_value LIKE '%Glucophage%' COLLATE NOCASE OR
        drug_source_value LIKE '%Glipizide%' COLLATE NOCASE OR drug_source_value LIKE '%Glucotrol%' COLLATE NOCASE OR
        drug_source_value LIKE '%Glyburide%' COLLATE NOCASE OR drug_source_value LIKE '%DiaBeta%' COLLATE NOCASE OR
        drug_source_value LIKE '%Glimepiride%' COLLATE NOCASE OR drug_source_value LIKE '%Amaryl%' COLLATE NOCASE OR
        drug_source_value LIKE '%Sitagliptin%' COLLATE NOCASE OR drug_source_value LIKE '%Januvia%' COLLATE NOCASE OR
        drug_source_value LIKE '%Empagliflozin%' COLLATE NOCASE OR drug_source_value LIKE '%Jardiance%' COLLATE NOCASE OR
        drug_source_value LIKE '%Canagliflozin%' COLLATE NOCASE OR drug_source_value LIKE '%Invokana%' COLLATE NOCASE OR
        drug_source_value LIKE '%Liraglutide%' COLLATE NOCASE OR drug_source_value LIKE '%Victoza%' COLLATE NOCASE OR
        drug_source_value LIKE '%Semaglutide%' COLLATE NOCASE OR drug_source_value LIKE '%Ozempic%' COLLATE NOCASE
    )
),

Lab_Evidence AS (
-- Replaces concept_id filters with source value text matching
-- HbA1c >= 6.5% or Fasting Glucose (FPG) >= 126 mg/dL
    SELECT DISTINCT person_id
    FROM memory.measurement
    WHERE (
        (measurement_source_value LIKE '%HbA1c%' COLLATE NOCASE AND value_as_number >= 6.5)
        OR 
        (measurement_source_value LIKE '%Glucose%' COLLATE NOCASE AND measurement_source_value LIKE '%Fasting%' COLLATE NOCASE AND value_as_number >= 126)
    )
),

Diagnosis_Evidence AS (
-- Path A: 2+ T2DM codes OR (1 T2DM code AND Medication)
    SELECT d.person_id
    FROM T2DM_Diag_Persons d
    LEFT JOIN T2DM_Med_Persons m ON d.person_id = m.person_id
    GROUP BY d.person_id
    HAVING COUNT(DISTINCT d.condition_occurrence_id) >= 2 
    OR (COUNT(DISTINCT d.condition_occurrence_id) >= 1 AND COUNT(m.drug_exposure_id) >= 1)
),

Medication_Evidence AS (
-- Path C: Sustained use of T2DM medications (2+ exposures)
    SELECT person_id
    FROM T2DM_Med_Persons
    GROUP BY person_id
    HAVING COUNT(DISTINCT drug_exposure_id) >= 2
),

Exclusions AS (
-- Identify persons with T1DM (E10, 250.1) or Gestational Diabetes (O24.4, 669.1)
    SELECT DISTINCT person_id
    FROM memory.condition_occurrence
    WHERE (
        condition_source_value LIKE 'E10%' COLLATE NOCASE 
        OR condition_source_value LIKE 'O24.4%' COLLATE NOCASE 
        OR condition_source_value LIKE '250.1%' COLLATE NOCASE 
        OR condition_source_value LIKE '669.1%' COLLATE NOCASE
    )
)

-- Final Algorithm Construction
SELECT DISTINCT p.person_id
FROM memory.person p
WHERE (
    p.person_id IN (SELECT person_id FROM Diagnosis_Evidence) 
    OR p.person_id IN (SELECT person_id FROM Lab_Evidence) 
    OR p.person_id IN (SELECT person_id FROM Medication_Evidence)
)
AND p.person_id NOT IN (SELECT person_id FROM Exclusions)