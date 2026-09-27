WITH t2dm_diagnoses AS (
    -- Identifying T2DM via ICD codes mapped to OMOP Standard Concepts
    -- ICD-10: E11.x | ICD-9: 250.00, 250.02
    SELECT DISTINCT person_id
    FROM public.condition_occurrence
    WHERE condition_source_value LIKE 'E11%' -- ICD10CM
       OR condition_source_value LIKE '250.00%' -- ICD9CM
       OR condition_source_value LIKE '250.02%'
),

t2dm_meds AS (
    -- Identifying specific T2DM medications (Generic and common Brands)
    -- Includes Metformin (Glucophage), Glyburide (Diabeta), Sitagliptin (Januvia), etc.
    SELECT DISTINCT person_id
    FROM public.drug_exposure
    WHERE LOWER(drug_source_value) SIMILAR TO 
        '%(metformin|glucophage|glyburide|diabeta|glipizide|glucotrol|sitagliptin|januvia|empagliflozin|jardiance|liraglutide|victoza)%'
),

t2dm_labs AS (
    -- HbA1c >= 6.5% (Standardized Measurement)
    SELECT DISTINCT person_id
    FROM public.measurement
    WHERE measurement_concept_id IN (3004410, 3005673) -- HbA1c LOINC concepts
      AND value_as_number >= 6.5
),

t1dm_exclusion AS (
    -- Identifying Type 1 to be used in exclusion logic
    -- ICD-10: E10.x | ICD-9: 250.01, 250.03
    SELECT DISTINCT person_id
    FROM public.condition_occurrence
    WHERE condition_source_value LIKE 'E10%'
       OR condition_source_value LIKE '250.01%'
       OR condition_source_value LIKE '250.03%'
)

-- Final Algorithm Construction
SELECT p.person_id
FROM public.person p
WHERE (
    p.person_id IN (SELECT person_id FROM t2dm_diagnoses)
    OR 
    p.person_id IN (SELECT person_id FROM t2dm_meds)
    OR 
    p.person_id IN (SELECT person_id FROM t2dm_labs)
)
AND p.person_id NOT IN (
    -- Exclude Type 1 patients unless they also have a clear T2DM diagnosis
    SELECT person_id FROM t1dm_exclusion 
    WHERE person_id NOT IN (SELECT person_id FROM t2dm_diagnoses)
);
