
-- Final T2DM Cohort Construction
WITH t2dm_concepts AS (
    -- Identifying T2DM (ICD9: 250.00, 250.02 | ICD10: E11.*)
    SELECT concept_id FROM public.concept 
    WHERE (concept_code LIKE '250.00' OR concept_code LIKE '250.02' OR concept_code LIKE 'E11%')
    AND vocabulary_id IN ('ICD9CM', 'ICD10CM')
),
t1dm_concepts AS (
    -- Identifying T1DM for exclusion (ICD9: 250.01 | ICD10: E10.*)
    SELECT concept_id FROM public.concept 
    WHERE (concept_code LIKE '250.01' OR concept_code LIKE 'E10%')
    AND vocabulary_id IN ('ICD9CM', 'ICD10CM')
),
medication_concepts AS (
    -- Metformin (Glucophage), Sulfonylureas (Glipizide/Glucotrol), SGLT2 (Jardiance), etc.
    SELECT concept_id FROM public.concept 
    WHERE LOWER(concept_name) IN ('metformin', 'glucophage', 'glipizide', 'glucotrol', 'empagliflozin', 'jardiance', 'sitagliptin', 'januvia')
    AND domain_id = 'Drug'
),
lab_criteria AS (
    -- HbA1c >= 6.5%
    SELECT person_id 
    FROM public.measurement
    WHERE (concept_id = 3004410 OR concept_id = 40758583) -- LOINC for HbA1c
    AND value_as_number >= 6.5
)

SELECT DISTINCT p.person_id
FROM public.person p
JOIN public.condition_occurrence co ON p.person_id = co.person_id
WHERE (
    -- CRITERIA 1: Has T2DM Diagnosis
    co.condition_concept_id IN (SELECT concept_id FROM t2dm_concepts)
    
    OR 
    
    -- CRITERIA 2: Medication AND Lab Evidence
    (p.person_id IN (SELECT person_id FROM public.drug_exposure WHERE drug_concept_id IN (SELECT concept_id FROM medication_concepts))
     AND p.person_id IN (SELECT person_id FROM lab_criteria))
)
-- CRITERIA 3: Exclude Type 1 (Simple Logic: If T1 codes exist, exclude unless T2 codes are more frequent)
AND NOT EXISTS (
    SELECT 1 FROM public.condition_occurrence co_ex 
    WHERE co_ex.person_id = p.person_id 
    AND co_ex.condition_concept_id IN (SELECT concept_id FROM t1dm_concepts)
);
