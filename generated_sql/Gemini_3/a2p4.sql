-- Step 1: Define the T2DM Cohort
CREATE TEMP TABLE t2dm_cohort AS
WITH t2dm_diagnoses AS (
    -- Selecting T2DM ICD codes (OMOP maps these to Standard Concepts)
    -- ICD10CM: E11, ICD9CM: 250.00, 250.02
    SELECT DISTINCT person_id
    FROM public.condition_occurrence
    WHERE condition_source_value LIKE 'E11%' 
       OR condition_source_value LIKE '250.00%' 
       OR condition_source_value LIKE '250.02%'
),
t1dm_exclusion AS (
    -- Identify Type 1 to exclude (ICD10: E10, ICD9: 250.01)
    SELECT DISTINCT person_id
    FROM public.condition_occurrence
    WHERE condition_source_value LIKE 'E10%' 
       OR condition_source_value LIKE '250.01%'
),
t2dm_meds AS (
    -- Identifying by Generic and Brand names in drug_exposure
    SELECT DISTINCT person_id
    FROM public.drug_exposure
    WHERE LOWER(drug_source_value) SIMILAR TO 
        '%(metformin|glucophage|glipizide|glucotrol|glyburide|diabeta|sitagliptin|januvia|empagliflozin|jardiance|liraglutide|victoza|pioglitazone|actos)%'
),
high_hba1c AS (
    -- Lab result criteria (HbA1c >= 6.5%)
    -- Maps to Measurement table in your CDM diagram
    SELECT DISTINCT person_id
    FROM public.measurement
    WHERE measurement_source_value LIKE '%A1c%' 
      AND value_as_number >= 6.5
)

SELECT p.person_id
FROM public.person p
WHERE (
    p.person_id IN (SELECT person_id FROM t2dm_diagnoses)
    OR 
    p.person_id IN (SELECT person_id FROM t2dm_meds)
    OR
    p.person_id IN (SELECT person_id FROM high_hba1c)
)
AND p.person_id NOT IN (SELECT person_id FROM t1dm_exclusion);

-- Summary Count
SELECT count(*) AS total_t2dm_patients FROM t2dm_cohort;

