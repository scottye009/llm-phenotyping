-- Phenotyping Algorithm for Type 2 Diabetes Mellitus (T2DM)
-- Schema: public

WITH 
-- 1. Define Concept Sets
concept_sets AS (
    SELECT 't2dm_codes' as set_name, concept_id FROM 
    (SELECT concept_id FROM concept WHERE 
        concept_code IN ('250.00', '250.01', 'E11.0', 'E11.1', 'E11.2', 'E11.3', 'E11.4', 'E11.5', 'E11.6', 'E11.7', 'E11.8', 'E11.9') 
        -- ICD9CM 250.0x, ICD10CM E11.x
        OR concept_id IN (443257, 200038) -- OMOP T2DM concepts
    )
    UNION ALL
    SELECT 't1dm_exclusion' as set_name, concept_id FROM 
    (SELECT concept_id FROM concept WHERE 
        concept_code IN ('250.10', 'E10.0', 'E10.1', 'E10.2', 'E10.3', 'E10.4', 'E10.5', 'E10.6', 'E10.7', 'E10.8', 'E10.9', 'O24.4') 
        -- ICD9 250.1, ICD10 E10.x (T1DM) and O24.4 (Gestational)
    )
    UNION ALL
    SELECT 't2dm_drugs' as set_name, concept_id FROM 
    (SELECT concept_id FROM concept WHERE 
        concept_name LIKE '%Metformin%' OR 
        concept_name LIKE '%Glipizide%' OR 
        concept_name LIKE '%Pioglitazone%' OR 
        concept_name LIKE '%Sitagliptin%' OR 
        concept_name LIKE '%Liraglutide%' OR 
        concept_name LIKE '%Empagliflozin%' OR 
        concept_name LIKE '%Januvia%' OR 
        concept_name LIKE '%Victoza%' OR 
        concept_name LIKE '%Jardiance%'
    )
),

-- 2. Identify patients with T2DM Diagnostic Codes
diag_counts AS (
    SELECT 
        condition_occurrence.person_id, 
        COUNT(DISTINCT condition_occurrence.condition_concept_id) as code_count
    FROM public.condition_occurrence
    JOIN concept_sets ON condition_occurrence.condition_concept_id = concept_sets.concept_id 
        AND concept_sets.set_name = 't2dm_codes'
    GROUP BY condition_occurrence.person_id
),

-- 3. Identify patients with T2DM Medications
drug_counts AS (
    SELECT 
        drug_exposure.person_id, 
        COUNT(DISTINCT drug_exposure.drug_concept_id) as drug_count
    FROM public.drug_exposure
    JOIN concept_sets ON drug_exposure.drug_concept_id = concept_sets.concept_id 
        AND concept_sets.set_name = 't2dm_drugs'
    GROUP BY drug_exposure.person_id
),

-- 4. Identify patients with Lab Evidence (HbA1c >= 6.5% or Fasting Glucose >= 126 mg/dL)
lab_evidence AS (
    SELECT DISTINCT person_id
    FROM public.measurement
    WHERE (
        (measurement_concept_id IN (3004423) AND value_as_number >= 6.5) -- HbA1c
        OR 
        (measurement_concept_id IN (3004450) AND value_as_number >= 126) -- Fasting Glucose
    )
),

-- 5. Exclusions (T1DM or Gestational)
exclusions AS (
    SELECT DISTINCT person_id
    FROM public.condition_occurrence
    JOIN concept_sets ON condition_occurrence.condition_concept_id = concept_sets.concept_id 
        AND concept_sets.set_name = 't1dm_exclusion'
)

-- Final Algorithm Assembly
SELECT 
    p.person_id
FROM public.person p
-- Combine criteria using OR/AND logic
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
AND p.person_id NOT IN (SELECT person_id FROM exclusions);