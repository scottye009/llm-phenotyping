WITH 
-- 1. Define Concept Sets
concept_sets AS (
    -- T2DM Diagnosis: Map ICD codes to Standard Concepts, then include ancestors
    SELECT cr.concept_id_2 as concept_id, 't2dm_dx' as set_name 
    FROM concept_relationship cr
    JOIN concept c ON cr.concept_id_1 = c.concept_id
    WHERE cr.relationship_id = 'Maps to' 
      AND c.concept_code IN ('250.00', '250.01', 'E11') 
      AND c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
    UNION ALL
    SELECT descendant_concept_id as concept_id, 't2dm_dx' FROM concept_ancestor WHERE ancestor_concept_id = 443254
    
    UNION ALL
    
    -- T1DM/Gestational Exclusion: Map ICD codes to Standard Concepts
    SELECT cr.concept_id_2 as concept_id, 'exclusion' 
    FROM concept_relationship cr
    JOIN concept c ON cr.concept_id_1 = c.concept_id
    WHERE cr.relationship_id = 'Maps to' 
      AND c.concept_code IN ('250.1', 'E10', 'O24.4') 
      AND c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
    UNION ALL
    SELECT descendant_concept_id as concept_id, 'exclusion' FROM concept_ancestor WHERE ancestor_concept_id = 443448
    
    UNION ALL
    
    -- T2DM Medications: Generic and Brand names
    SELECT concept_id, 't2dm_rx' FROM concept 
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

-- 2. Calculate Evidence per Patient
patient_evidence AS (
    SELECT 
        p.person_id,
        -- Count of T2DM Dx codes
        (SELECT COUNT(DISTINCT co.condition_concept_id) 
         FROM condition_occurrence co 
         JOIN concept_sets cs ON co.condition_concept_id = cs.concept_id 
         WHERE co.person_id = p.person_id AND cs.set_name = 't2dm_dx') as dx_count,
         
        -- Count of T2DM Drugs
        (SELECT COUNT(DISTINCT de.drug_concept_id) 
         FROM drug_exposure de 
         JOIN concept_sets cs ON de.drug_concept_id = cs.concept_id 
         WHERE de.person_id = p.person_id AND cs.set_name = 't2dm_rx') as rx_count,
         
        -- Indicator for Abnormal Labs
        (SELECT MAX(1) 
         FROM measurement m 
         JOIN concept c ON m.measurement_concept_id = c.concept_id
         WHERE m.person_id = p.person_id 
         AND (
             (c.concept_name LIKE '%Hemoglobin A1c%' AND m.value_as_number >= 6.5) OR 
             (c.concept_name LIKE '%Glucose%' AND c.concept_name LIKE '%Fasting%' AND m.value_as_number >= 126)
         )) as has_abnormal_lab,
         
        -- Indicator for Exclusions
        (SELECT MAX(1) 
         FROM condition_occurrence co 
         JOIN concept_sets cs ON co.condition_concept_id = cs.concept_id 
         WHERE co.person_id = p.person_id AND cs.set_name = 'exclusion') as is_excluded
    FROM person p
)

-- 3. Final Cohort Selection
SELECT 
    person_id
FROM 
    patient_evidence
WHERE 
    is_excluded IS NULL -- Strictly exclude T1DM and Gestational
    AND (
        -- Pathway A: 2+ distinct T2DM diagnosis codes
        (dx_count >= 2) 
        OR 
        -- Pathway B: 1+ Dx AND (Drug OR Lab)
        (dx_count >= 1 AND (rx_count >= 1 OR has_abnormal_lab = 1))
        OR 
        -- Pathway C: 2+ distinct Drugs AND Lab evidence
        (rx_count >= 2 AND has_abnormal_lab = 1)
    );