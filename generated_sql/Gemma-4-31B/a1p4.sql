WITH t2dm_concepts AS (
    -- T2DM Diagnosis Concepts (ICD10: E11, ICD9: 250.x, etc.)
    SELECT concept_id FROM public.concept 
    WHERE concept_id = 201820 
       OR concept_code IN ('E11', '250.00') AND vocabulary_id IN ('ICD10CM', 'ICD9CM')
),
exclusion_concepts AS (
    -- T1DM (E10) and Gestational DM (O24.4)
    SELECT concept_id FROM public.concept 
    WHERE concept_id IN (201826, 443448) 
       OR concept_code IN ('E10', 'O24.4') AND vocabulary_id IN ('ICD10CM', 'ICD9CM')
),
t2dm_medications AS (
    -- Metformin, Glimepiride, Sitagliptin, Empagliflozin, Liraglutide, etc.
    -- Includes both generic and brand names via concept mapping
    SELECT concept_id FROM public.concept 
    WHERE concept_name LIKE '%Metformin%' 
       OR concept_name LIKE '%Glucophage%'
       OR concept_name LIKE '%Glimepiride%' 
       OR concept_name LIKE '%Amaryl%'
       OR concept_name LIKE '%Sitagliptin%' 
       OR concept_name LIKE '%Januvia%'
       OR concept_name LIKE '%Empagliflozin%' 
       OR concept_name LIKE '%Jardiance%'
       OR concept_name LIKE '%Liraglutide%' 
       OR concept_name LIKE '%Victoza%'
),
lab_evidence AS (
    -- HbA1c >= 6.5% or Fasting Glucose >= 126 mg/dL
    SELECT person_id 
    FROM public.measurement m
    JOIN public.concept c ON m.measurement_concept_id = c.concept_id
    WHERE (c.concept_name LIKE '%HbA1c%' AND m.value_as_number >= 6.5)
       OR (c.concept_name LIKE '%Glucose%' AND c.concept_name LIKE '%Fasting%' AND m.value_as_number >= 126)
),
dx_evidence AS (
    -- Patients with T2DM diagnosis codes
    SELECT DISTINCT person_id 
    FROM public.condition_occurrence 
    WHERE condition_concept_id IN (SELECT concept_id FROM t2dm_concepts)
),
rx_evidence AS (
    -- Patients taking T2DM medications
    SELECT DISTINCT person_id 
    FROM public.drug_exposure 
    WHERE drug_concept_id IN (SELECT concept_id FROM t2dm_medications)
),
excluded_patients AS (
    -- Patients with T1DM or Gestational DM
    SELECT DISTINCT person_id 
    FROM public.condition_occurrence 
    WHERE condition_concept_id IN (SELECT concept_id FROM exclusion_concepts)
)

-- Final Phenotype Assembly
SELECT p.person_id
FROM public.person p
WHERE (
    p.person_id IN (SELECT person_id FROM dx_evidence) -- Diagnosis
    OR p.person_id IN (SELECT person_id FROM lab_evidence) -- Labs
    OR p.person_id IN (SELECT person_id FROM rx_evidence) -- Medications
)
AND NOT p.person_id IN (SELECT person_id FROM excluded_patients) -- Exclusions