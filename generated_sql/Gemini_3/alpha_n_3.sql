WITH t2dm_concepts AS (
    -- Identifying T2DM Diagnosis Concepts (ICD9: 250.00, ICD10: E11.x)
    SELECT concept_id FROM public.concept 
    WHERE (concept_code LIKE '250.0%' OR concept_code LIKE 'E11%')
    AND vocabulary_id IN ('ICD9CM', 'ICD10CM')
),
t1dm_concepts AS (
    -- Identifying Type 1 Exclusions (ICD9: 250.01, ICD10: E10.x)
    SELECT concept_id FROM public.concept 
    WHERE (concept_code LIKE '250.01%' OR concept_code LIKE 'E10%')
    AND vocabulary_id IN ('ICD9CM', 'ICD10CM')
),
t2dm_meds AS (
    -- Medication list (Generic & Brand Examples)
    SELECT concept_id FROM public.concept 
    WHERE LOWER(concept_name) SIMILAR TO '%(metformin|glucophage|glipizide|glucotrol|glyburide|micronase|pioglitazone|actos|sitagliptin|januvia|empagliflozin|jardiance|insulin)%'
    AND domain_id = 'Drug'
),
t2dm_labs AS (
    -- Lab: HbA1c >= 6.5
    SELECT person_id, measurement_date 
    FROM public.measurement
    WHERE measurement_concept_id IN (3004410, 3005673) -- LOINC codes for HbA1c
    AND value_as_number >= 6.5
),
dx_counts AS (
    -- Count distinct days with a T2DM diagnosis per person
    SELECT person_id, COUNT(DISTINCT condition_start_date) as dx_day_count
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (SELECT concept_id FROM t2dm_concepts)
    GROUP BY person_id
)

-- Final Cohort Construction
SELECT DISTINCT p.person_id
FROM public.person p
JOIN dx_counts dx ON p.person_id = dx.person_id
LEFT JOIN public.drug_exposure de ON p.person_id = de.person_id 
    AND de.drug_concept_id IN (SELECT concept_id FROM t2dm_meds)
LEFT JOIN t2dm_labs lb ON p.person_id = lb.person_id

WHERE (
    -- CRITERIA A: Two or more diagnosis dates
    dx.dx_day_count >= 2 
    OR 
    -- CRITERIA B: One diagnosis AND (Medication OR Lab)
    (dx.dx_day_count >= 1 AND (de.drug_exposure_id IS NOT NULL OR lb.person_id IS NOT NULL))
)
-- EXCLUSION: No Type 1 Diabetes diagnoses
AND p.person_id NOT IN (
    SELECT person_id FROM public.condition_occurrence 
    WHERE condition_concept_id IN (SELECT concept_id FROM t1dm_concepts)
);
