
-- Step 1: Identify the T2DM Cohort
WITH t2dm_concepts AS (
    SELECT concept_id FROM public.concept 
    WHERE (concept_code LIKE 'E11%' AND vocabulary_id = 'ICD10CM')
       OR (concept_code ~ '^250\.[0-9][0,2]$' AND vocabulary_id = 'ICD9CM')
),

t1dm_concepts AS (
    SELECT concept_id FROM public.concept 
    WHERE (concept_code LIKE 'E10%' AND vocabulary_id = 'ICD10CM')
       OR (concept_code ~ '^250\.[0-9][1,3]$' AND vocabulary_id = 'ICD9CM')
),

t2dm_meds AS (
    -- Includes Generic (Metformin, Glipizide) and common Brands (Glucophage, Januvia)
    SELECT concept_id FROM public.concept
    WHERE LOWER(concept_name) ~ 'metformin|glucophage|glipizide|glucotrol|sitagliptin|januvia|empagliflozin|jardiance'
    AND domain_id = 'Drug'
),

lab_results AS (
    -- HbA1c >= 6.5%
    SELECT person_id, measurement_date
    FROM public.measurement
    WHERE measurement_concept_id IN (3004410, 3005673) -- standard OMOP HbA1c concepts
    AND value_as_number >= 6.5
)

SELECT DISTINCT p.person_id
FROM public.person p
JOIN public.condition_occurrence co ON p.person_id = co.person_id
WHERE co.condition_concept_id IN (SELECT concept_id FROM t2dm_concepts)

-- AND criteria: Ensuring it's not a one-off screening/miscode
AND (
    -- 2nd Diagnosis on a different day
    EXISTS (
        SELECT 1 FROM public.condition_occurrence co2 
        WHERE co2.person_id = p.person_id 
        AND co2.condition_concept_id IN (SELECT concept_id FROM t2dm_concepts)
        AND co2.condition_start_date != co.condition_start_date
    )
    OR 
    -- Presence of medication (Metformin, etc.)
    EXISTS (
        SELECT 1 FROM public.drug_exposure de 
        WHERE de.person_id = p.person_id 
        AND de.drug_concept_id IN (SELECT concept_id FROM t2dm_meds)
    )
    OR
    -- High Lab value
    EXISTS (
        SELECT 1 FROM lab_results lr WHERE lr.person_id = p.person_id
    )
)

-- NOT criteria: Exclude if Type 1 codes are the dominant diagnosis
AND NOT EXISTS (
    SELECT 1 FROM public.condition_occurrence co3
    WHERE co3.person_id = p.person_id
    AND co3.condition_concept_id IN (SELECT concept_id FROM t1dm_concepts)
    -- Simple heuristic: Exclude if T1 codes > T2 codes
    HAVING COUNT(*) > (SELECT COUNT(*) FROM public.condition_occurrence WHERE person_id = p.person_id AND condition_concept_id IN (SELECT concept_id FROM t2dm_concepts))
);
