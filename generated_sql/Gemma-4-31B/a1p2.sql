-- Type 2 Diabetes Mellitus (T2DM) Phenotyping Algorithm
-- Schema: public

WITH T2DM_Concepts AS (
    -- Diagnosis Concepts (ICD-10 E11, ICD-9 250.00, OMOP Concept 443254)
    SELECT concept_id FROM concept
    WHERE concept_code IN ('E11', '250.00', '250.01') 
    OR concept_id = 443254
    OR concept_id IN (SELECT descendant_concept_id FROM concept_ancestor WHERE ancestor_concept_id = 443254)
),

Exclusion_Concepts AS (
    -- Type 1 Diabetes (E10) and Gestational Diabetes (O24.4)
    SELECT concept_id FROM concept
    WHERE concept_code IN ('E10', 'O24.4', '250.1', '669.1')
),

T2DM_Meds AS (
    -- Metformin, Sulfonylureas, DPP-4, SGLT2, GLP-1
    -- Including both generic and brand concepts
    SELECT concept_id FROM concept
    WHERE concept_name LIKE '%Metformin%' 
       OR concept_name LIKE '%Glucophage%'
       OR concept_name LIKE '%Glipizide%' OR concept_name LIKE '%Glucotrol%'
       OR concept_name LIKE '%Glyburide%' OR concept_name LIKE '%DiaBeta%'
       OR concept_name LIKE '%Glimepiride%' OR concept_name LIKE '%Amaryl%'
       OR concept_name LIKE '%Sitagliptin%' OR concept_name LIKE '%Januvia%'
       OR concept_name LIKE '%Empagliflozin%' OR concept_name LIKE '%Jardiance%'
       OR concept_name LIKE '%Canagliflozin%' OR concept_name LIKE '%Invokana%'
       OR concept_name LIKE '%Liraglutide%' OR concept_name LIKE '%Victoza%'
       OR concept_name LIKE '%Semaglutide%' OR concept_name LIKE '%Ozempic%'
),

Lab_Evidence AS (
    -- HbA1c >= 6.5% (concept_id for HbA1c: 3004-15 / OMOP equivalent)
    -- FPG >= 126 mg/dL
    SELECT person_id
    FROM measurement
    WHERE (
        (measurement_concept_id = 300415 AND value_as_number >= 6.5) -- HbA1c
        OR 
        (measurement_concept_id = 2339-6 AND value_as_number >= 126) -- Fasting Glucose
    )
),

Diagnosis_Evidence AS (
    -- Path A: 2+ T2DM codes OR (1 T2DM code AND Medication)
    SELECT co.person_id
    FROM condition_occurrence co
    INNER JOIN T2DM_Concepts tc ON co.condition_concept_id = tc.concept_id
    LEFT JOIN drug_exposure de ON co.person_id = de.person_id 
        AND de.drug_concept_id IN (SELECT concept_id FROM T2DM_Meds)
    GROUP BY co.person_id
    HAVING COUNT(DISTINCT co.condition_occurrence_id) >= 2 
       OR (COUNT(DISTINCT co.condition_occurrence_id) >= 1 AND COUNT(de.drug_exposure_id) >= 1)
),

Medication_Evidence AS (
    -- Path C: Sustained use of T2DM medications
    SELECT person_id
    FROM drug_exposure
    WHERE drug_concept_id IN (SELECT concept_id FROM T2DM_Meds)
    GROUP BY person_id
    HAVING COUNT(DISTINCT drug_exposure_id) >= 2
),

Exclusions AS (
    -- Identify persons with T1DM or Gestational Diabetes
    SELECT person_id
    FROM condition_occurrence
    WHERE condition_concept_id IN (SELECT concept_id FROM Exclusion_Concepts)
)

-- Final Algorithm Construction
SELECT DISTINCT p.person_id
FROM person p
WHERE (
    p.person_id IN (SELECT person_id FROM Diagnosis_Evidence) 
    OR p.person_id IN (SELECT person_id FROM Lab_Evidence) 
    OR p.person_id IN (SELECT person_id FROM Medication_Evidence)
)
AND p.person_id NOT IN (SELECT person_id FROM Exclusions);