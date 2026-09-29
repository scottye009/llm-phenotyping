-- Step 1: Define the T2DM Cohort
CREATE TABLE public.t2dm_phenotype AS
WITH diagnosis_codes AS (
    -- Selecting T2DM concepts (ICD9: 250.00, 250.02; ICD10: E11)
    -- Mapping to Standard OMOP Concepts via Concept_Relationship
    SELECT person_id, condition_start_date
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (
        SELECT concept_id FROM public.concept 
        WHERE concept_code LIKE 'E11%' AND vocabulary_id = 'ICD10CM'
        UNION
        SELECT concept_id FROM public.concept 
        WHERE (concept_code LIKE '250.00%' OR concept_code LIKE '250.02%') AND vocabulary_id = 'ICD9CM'
    )
),
lab_results AS (
    -- HbA1c >= 6.5% or Glucose >= 126 mg/dL
    SELECT person_id, measurement_date
    FROM public.measurement
    WHERE (measurement_concept_id IN (3004410, 3005673) AND value_as_number >= 6.5) -- HbA1c
       OR (measurement_concept_id IN (3003280, 3000671) AND value_as_number >= 126) -- Glucose
),
medications AS (
    -- T2DM Meds: Metformin (Glucophage), Glipizide (Glucotrol), Empagliflozin (Jardiance), etc.
    SELECT person_id, drug_exposure_start_date
    FROM public.drug_exposure
    WHERE drug_concept_id IN (
        SELECT concept_id FROM public.concept 
        WHERE lower(concept_name) LIKE '%metformin%' 
           OR lower(concept_name) LIKE '%glucophage%'
           OR lower(concept_name) LIKE '%glipizide%'
           OR lower(concept_name) LIKE '%glucotrol%'
           OR lower(concept_name) LIKE '%jardiance%'
           OR lower(concept_name) LIKE '%empagliflozin%'
    )
),
type1_exclusion AS (
    -- Identify patients with Type 1 codes to exclude
    SELECT DISTINCT person_id
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (
        SELECT concept_id FROM public.concept 
        WHERE concept_code LIKE 'E10%' AND vocabulary_id = 'ICD10CM'
    )
)

-- Final Selection Logic
SELECT DISTINCT d.person_id
FROM diagnosis_codes d
LEFT JOIN lab_results l ON d.person_id = l.person_id
LEFT JOIN medications m ON d.person_id = m.person_id
WHERE (d.person_id IS NOT NULL OR l.person_id IS NOT NULL) -- Must have Dx or Lab
  AND d.person_id NOT IN (SELECT person_id FROM type1_exclusion) -- AND NOT Type 1
  AND m.person_id IS NOT NULL; -- Supporting medication use

