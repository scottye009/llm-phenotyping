-- filepath: 
WITH t2dm_concepts AS (
    -- Map ICD9/ICD10 codes for T2DM to Standard Concepts
    SELECT DISTINCT cr.concept_id_2 as standard_concept_id
    FROM public.concept c
    JOIN public.concept_relationship cr ON c.concept_id = cr.concept_id_1
    WHERE (
        (c.vocabulary_id = 'ICD10CM' AND c.concept_code ~* '^E11') OR
        (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~* '^250\.[0-9][02]')
    )
    AND cr.relationship_id = 'Maps to'
),

t1dm_concepts AS (
    -- Map ICD9/ICD10 codes for T1DM (Exclusion) to Standard Concepts
    SELECT DISTINCT cr.concept_id_2 as standard_concept_id
    FROM public.concept c
    JOIN public.concept_relationship cr ON c.concept_id = cr.concept_id_1
    WHERE (
        (c.vocabulary_id = 'ICD10CM' AND c.concept_code ~* '^E10') OR
        (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~* '^250\.[0-9][13]')
    )
    AND cr.relationship_id = 'Maps to'
),

antidiabetic_meds AS (
    -- Identify anti-diabetic drug concepts using ancestor for "Antidiabetic agent"
    SELECT descendant_concept_id 
    FROM public.concept_ancestor 
    WHERE ancestor_concept_id = 21600712 -- ATC Antidiabetics
),

hba1c_labs AS (
    -- Identify HbA1c measurement concepts
    SELECT concept_id 
    FROM public.concept 
    WHERE concept_name ~* 'hemoglobin a1c' AND domain_id = 'Measurement'
),

diagnosis_counts AS (
    -- Count distinct dates of T2DM diagnoses per person
    SELECT person_id, COUNT(DISTINCT condition_start_date) as dx_date_count
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (SELECT standard_concept_id FROM t2dm_concepts)
    GROUP BY person_id
),

med_users AS (
    -- Patients with at least one anti-diabetic medication
    SELECT DISTINCT person_id 
    FROM public.drug_exposure
    WHERE drug_concept_id IN (SELECT descendant_concept_id FROM antidiabetic_meds)
),

lab_positive AS (
    -- Patients with HbA1c >= 6.5
    SELECT DISTINCT person_id
    FROM public.measurement
    WHERE measurement_concept_id IN (SELECT concept_id FROM hba1c_labs)
    AND value_as_number >= 6.5
),

exclusions AS (
    -- Patients to exclude (T1DM/Gestational)
    SELECT DISTINCT person_id 
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (SELECT standard_concept_id FROM t1dm_concepts)
)

-- Final Phenotype Selection
SELECT DISTINCT d.person_id
FROM diagnosis_counts d
LEFT JOIN med_users m ON d.person_id = m.person_id
LEFT JOIN lab_positive l ON d.person_id = l.person_id
WHERE (
    d.dx_date_count >= 2 -- 2+ diagnoses on diff dates
    OR (d.dx_date_count >= 1 AND (m.person_id IS NOT NULL OR l.person_id IS NOT NULL)) -- 1 dx + med or lab
)
AND d.person_id NOT IN (SELECT person_id FROM exclusions);