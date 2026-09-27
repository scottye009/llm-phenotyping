/* 
   Phenotype: Type 2 Diabetes Mellitus (T2DM)
   Standard: OMOP CDM / ICD-9 / ICD-10
*/

WITH 
-- 1. Diagnosis Pathway: Specific T2DM Codes
Diagnosis_Pathway AS (
    SELECT person_id 
    FROM condition_occurrence 
    WHERE (condition_concept_id = 443258 -- OMOP Type 2 DM
           OR condition_source_value IN ('E11.0', 'E11.1', 'E11.2', 'E11.3', 'E11.4', 'E11.5', 'E11.6', 'E11.7', 'E11.8', 'E11.9', -- ICD-10
                                        '250.00', '250.01')) -- ICD-9
),

-- 2. Lab Pathway: HbA1c >= 6.5% OR Glucose >= 126 (Fasting) OR Glucose >= 200 (Random)
Lab_Pathway AS (
    SELECT person_id 
    FROM measurement 
    WHERE (
        (measurement_concept_id = 453932 AND value_as_number >= 6.5) -- HbA1c
        OR 
        (measurement_concept_id = 3004331 AND value_as_number >= 126) -- Glucose (Simplified for this example)
    )
),

-- 3. Medication Pathway: Prescription of T2DM drugs
Medication_Pathway AS (
    SELECT person_id 
    FROM drug_exposure 
    WHERE drug_concept_id IN (
        -- Metformin / Glucophage
        -- Sulfonylureas: Glimepiride / Amaryl, Glyburide / DiaBeta, Glipizide / Glucotrol
        -- DPP-4: Sitagliptin / Januvia, Saxagliptin / Onglyza
        -- SGLT2: Empagliflozin / Jardiance, Canagliflozin / Invokana
        -- GLP-1: Liraglutide / Victoza, Semaglutide / Ozempic
        -- TzD: Pioglitazone / Actos
        -- [Note: Actual Concept IDs for these medications would be mapped from RxNorm/OMOP]
        (SELECT concept_id FROM concept WHERE concept_name IN ('Metformin', 'Glucophage', 'Glimepiride', 'Amaryl', 'Glyburide', 'DiaBeta', 'Glipizide', 'Glucotrol', 'Sitagliptin', 'Januvia', 'Saxagliptin', 'Onglyza', 'Empagliflozin', 'Jardiance', 'Canagliflozin', 'Invokana', 'Liraglutide', 'Victoza', 'Semaglutide', 'Ozempic', 'Rybelsus', 'Pioglitazone', 'Actos'))
    )
),

-- 4. Exclusion Pathway: T1DM or Gestational DM
Exclusion_Pathway AS (
    SELECT person_id 
    FROM condition_occurrence 
    WHERE (condition_concept_id IN (443257, 443259) -- OMOP T1DM or Gestational
           OR condition_source_value IN ('E10.0', 'E10.1', 'E10.9', 'O24.4', '250.02', '250.03', '796.5')) -- ICD-10/9
)

-- FINAL ALGORITHM COMBINATION
SELECT DISTINCT p.person_id
FROM person p
WHERE (
    p.person_id IN (SELECT person_id FROM Diagnosis_Pathway)
    OR 
    (p.person_id IN (SELECT person_id FROM Lab_Pathway))
    OR 
    (p.person_id IN (SELECT person_id FROM Medication_Pathway))
)
AND NOT (p.person_id IN (SELECT person_id FROM Exclusion_Pathway));