-- Type 2 Diabetes Mellitus Phenotyping Algorithm
-- Schema: public

WITH 
---------------------------------------------------------------------------
-- 1. Define Concept Sets
---------------------------------------------------------------------------
t2dm_concepts AS (
    -- ICD10: E11.* (Type 2 diabetes mellitus)
    -- ICD9: 250.00, 250.01, 250.02 (Type 2 diabetes mellitus)
    SELECT concept_id FROM public.concept 
    WHERE concept_code IN ('E11', '250.00', '250.01', '250.02')
    OR concept_id IN (443257, 200033) -- Examples of OMOP Standard Concepts for T2DM
),
t1dm_exclusion AS (
    -- ICD10: E10.* (Type 1), O24.4* (Gestational)
    -- ICD9: 250.03 (Type 1/Idiopathic)
    SELECT concept_id FROM public.concept 
    WHERE concept_code IN ('E10', 'O24.4', '250.03')
),
diabetes_meds AS (
    -- Includes Metformin (Glucophage), Sulfonylureas, DPP-4, SGLT2, GLP-1
    -- Generic and Brand names mapped to concept_id
    SELECT concept_id FROM public.concept 
    WHERE concept_name LIKE '%Metformin%' 
       OR concept_name LIKE '%Glucophage%'
       OR concept_name LIKE '%Sitagliptin%'
       OR concept_name LIKE '%Januvia%'
       OR concept_name LIKE '%Empagliflozin%'
       OR concept_name LIKE '%Jardiance%'
       OR concept_name LIKE '%Pioglitazone%'
),
hyperglycemia_labs AS (
    -- HbA1c >= 6.5% or Fasting Plasma Glucose >= 126 mg/dL
    -- Using OMOP Concept IDs for HbA1c and Glucose
    SELECT concept_id FROM public.concept 
    WHERE concept_name LIKE '%Hemoglobin A1c%' 
       OR concept_name LIKE '%Glucose, Fasting%'
),

---------------------------------------------------------------------------
-- 2. Identify Patient Evidence
---------------------------------------------------------------------------
patient_evidence AS (
    SELECT 
        p.person_id,
        -- Count distinct diagnosis occurrences
        (SELECT COUNT(*) FROM public.condition_occurrence co 
         JOIN t2dm_concepts tc ON co.condition_concept_id = tc.concept_id
         WHERE co.person_id = p.person_id) as diag_count,
         
        -- Check for drug exposure
        (SELECT MAX(1) FROM public.drug_exposure de 
         JOIN diabetes_meds dm ON de.drug_concept_id = dm.concept_id
         WHERE de.person_id = p.person_id) as has_med,
         
        -- Check for abnormal lab results
        (SELECT MAX(1) FROM public.measurement m 
         JOIN hyperglycemia_labs hl ON m.measurement_concept_id = hl.concept_id
         WHERE m.person_id = p.person_id 
         AND (m.value_as_number >= 6.5 OR m.value_as_number >= 126)) as has_lab,
         
        -- Exclusion flag (Type 1 or Gestational)
        (SELECT MAX(1) FROM public.condition_occurrence co 
         JOIN t1dm_exclusion te ON co.condition_concept_id = te.concept_id
         WHERE co.person_id = p.person_id) as is_excluded
    FROM public.person p
)

---------------------------------------------------------------------------
-- 3. Apply Final Logic
---------------------------------------------------------------------------
SELECT 
    person_id
FROM 
    patient_evidence
WHERE 
    -- EXCLUSION CRITERIA (NOT)
    is_excluded IS NULL 
    
    AND (
        -- INCLUSION CRITERIA
        -- Case 1: 2+ Diagnoses
        (diag_count >= 2) 
        OR 
        -- Case 2: 1 Diagnosis AND (Med OR Lab)
        (diag_count >= 1 AND (has_med = 1 OR has_lab = 1)) 
        OR 
        -- Case 3: Med AND Lab
        (has_med = 1 AND has_lab = 1)
    );