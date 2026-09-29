-- Refined Phenotyping Algorithm for Type 2 Diabetes Mellitus (T2DM)
-- Target: OMOP Common Data Model
-- Strategy: Multi-modal evidence (Diagnosis, Medication, Labs) with T1DM/Gestational exclusion.

WITH 
---------------------------------------------------------------------------
-- 1. CONCEPT DEFINITIONS
---------------------------------------------------------------------------
t2dm_concept_set AS (
    -- Capture T2DM via ICD10, ICD9, and OMOP Standard concepts
    SELECT concept_id FROM concept
    WHERE (concept_code IN ('E11', '250.00', '250.01') AND vocabulary_id IN ('ICD10CM', 'ICD9CM'))
    OR (concept_name = 'Type 2 diabetes mellitus' AND domain_id = 'Condition')
    UNION
    -- Include all descendants of the standard T2DM concept
    SELECT descendant_concept_id FROM concept_ancestor 
    WHERE ancestor_concept_id IN (SELECT concept_id FROM concept WHERE concept_name = 'Type 2 diabetes mellitus' AND domain_id = 'Condition')
),

exclusion_concept_set AS (
    -- Type 1 Diabetes and Gestational Diabetes
    SELECT concept_id FROM concept
    WHERE (concept_code IN ('E10', 'O24.4', '250.03', '669.1') AND vocabulary_id IN ('ICD10CM', 'ICD9CM'))
    OR (concept_name LIKE 'Type 1 diabetes%' AND domain_id = 'Condition')
    OR (concept_name LIKE 'Gestational diabetes%' AND domain_id = 'Condition')
),

t2dm_med_set AS (
    -- Comprehensive list of Generic and Brand names
    SELECT concept_id FROM concept
    WHERE (
        concept_name LIKE '%Metformin%' OR concept_name LIKE '%Glucophage%' OR
        concept_name LIKE '%Glipizide%' OR concept_name LIKE '%Glucotrol%' OR
        concept_name LIKE '%Glyburide%' OR concept_name LIKE '%DiaBeta%' OR
        concept_name LIKE '%Glimepiride%' OR concept_name LIKE '%Amaryl%' OR
        concept_name LIKE '%Sitagliptin%' OR concept_name LIKE '%Januvia%' OR
        concept_name LIKE '%Empagliflozin%' OR concept_name LIKE '%Jardiance%' OR
        concept_name LIKE '%Canagliflozin%' OR concept_name LIKE '%Invokana%' OR
        concept_name LIKE '%Liraglutide%' OR concept_name LIKE '%Victoza%' OR
        concept_name LIKE '%Semaglutide%' OR concept_name LIKE '%Ozempic%' OR
        concept_name LIKE '%Pioglitazone%' OR concept_name LIKE '%Actos%'
    ) AND domain_id = 'Drug'
),

lab_concept_set AS (
    -- Define Lab concepts for HbA1c and Fasting Glucose
    SELECT concept_id, concept_name FROM concept
    WHERE (concept_name LIKE '%Hemoglobin A1c%' OR concept_name LIKE '%HbA1c%')
       OR (concept_name LIKE '%Glucose%' AND concept_name LIKE '%Fasting%')
),

---------------------------------------------------------------------------
-- 2. PATIENT EVIDENCE AGGREGATION
---------------------------------------------------------------------------
patient_evidence AS (
    SELECT 
        p.person_id,
        -- Count distinct diagnosis occurrences
        (SELECT COUNT(DISTINCT co.condition_occurrence_id) 
         FROM condition_occurrence co 
         WHERE co.person_id = p.person_id 
         AND co.condition_concept_id IN (SELECT concept_id FROM t2dm_concept_set)) as diag_count,
        
        -- Check for T2DM Medication use
        (SELECT MAX(1) 
         FROM drug_exposure de 
         WHERE de.person_id = p.person_id 
         AND de.drug_concept_id IN (SELECT concept_id FROM t2dm_med_set)) as has_med,
        
        -- Check for abnormal lab results
        (SELECT MAX(1) 
         FROM measurement m
         JOIN lab_concept_set lcs ON m.measurement_concept_id = lcs.concept_id
         WHERE m.person_id = p.person_id 
         AND (
             (lcs.concept_name LIKE '%A1c%' AND m.value_as_number >= 6.5)
             OR 
             (lcs.concept_name LIKE '%Glucose%' AND m.value_as_number >= 126)
         )) as has_lab,
        
        -- Exclusion indicator
        (SELECT MAX(1) 
         FROM condition_occurrence co 
         WHERE co.person_id = p.person_id 
         AND co.condition_concept_id IN (SELECT concept_id FROM exclusion_concept_set)) as is_excluded
    FROM person p
)

---------------------------------------------------------------------------
-- 3. FINAL COHORT SELECTION
---------------------------------------------------------------------------
SELECT 
    person_id
FROM 
    patient_evidence
WHERE 
    is_excluded IS NULL -- Must not have T1DM or Gestational Diabetes
    AND (
        -- Path 1: High diagnostic confidence (2+ codes)
        diag_count >= 2 
        OR 
        -- Path 2: Diagnosis supported by medication
        (diag_count >= 1 AND has_med = 1) 
        OR 
        -- Path 3: Diagnosis supported by lab results
        (diag_count >= 1 AND has_lab = 1) 
        OR 
        -- Path 4: Medication and Labs combined (Strong evidence even if diagnosis is missing)
        (has_med = 1 AND has_lab = 1)
    )