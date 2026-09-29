
WITH t2dm_codes AS (
    -- Get concept_ids for T2DM (ICD9/10 mapping usually happens in the concept table)
    SELECT concept_id FROM public.concept 
    WHERE (concept_code LIKE 'E11%' AND vocabulary_id = 'ICD10CM')
       OR (concept_code LIKE '250.00%' AND vocabulary_id = 'ICD9CM')
       OR (concept_code LIKE '250.02%' AND vocabulary_id = 'ICD9CM')
),
t1dm_codes AS (
    -- Exclusion codes for Type 1
    SELECT concept_id FROM public.concept 
    WHERE (concept_code LIKE 'E10%' AND vocabulary_id = 'ICD10CM')
       OR (concept_code LIKE '250.01%' AND vocabulary_id = 'ICD9CM')
),
t2dm_meds AS (
    -- Identify T2DM specific meds (Generic and Brand)
    SELECT concept_id FROM public.concept
    WHERE lower(concept_name) SIMILAR TO '%(metformin|glucophage|glipizide|glucotrol|jardiance|empagliflozin|ozempic|semaglutide|pioglitazone|actos)%'
    AND domain_id = 'Drug'
),
hba1c_labs AS (
    -- Identify HbA1c >= 6.5%
    SELECT person_id 
    FROM public.measurement
    WHERE measurement_concept_id IN (3004410, 3005673) -- Standard LOINC for HbA1c
    AND value_as_number >= 6.5
)

SELECT DISTINCT co.person_id
FROM public.condition_occurrence co
WHERE co.condition_concept_id IN (SELECT concept_id FROM t2dm_codes)

-- Logic: 2+ occurrences OR 1 occurrence AND (Medication OR Lab)
AND (
    (SELECT COUNT(*) FROM public.condition_occurrence co2 
     WHERE co2.person_id = co.person_id 
     AND co2.condition_concept_id IN (SELECT concept_id FROM t2dm_codes)) >= 2
    OR
    EXISTS (SELECT 1 FROM public.drug_exposure de 
            WHERE de.person_id = co.person_id 
            AND de.drug_concept_id IN (SELECT concept_id FROM t2dm_meds))
    OR
    co.person_id IN (SELECT person_id FROM hba1c_labs)
)

-- Exclusion Logic: NOT Type 1 (where T1 codes outnumber T2 codes)
AND NOT EXISTS (
    SELECT 1 FROM public.condition_occurrence co3
    WHERE co3.person_id = co.person_id
    AND co3.condition_concept_id IN (SELECT concept_id FROM t1dm_codes)
    GROUP BY co3.person_id
    HAVING COUNT(co3.condition_occurrence_id) > (
        SELECT COUNT(*) FROM public.condition_occurrence co4 
        WHERE co4.person_id = co.person_id 
        AND co4.condition_concept_id IN (SELECT concept_id FROM t2dm_codes)
    )
);
