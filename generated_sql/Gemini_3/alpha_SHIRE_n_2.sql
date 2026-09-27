with t2dm_diagnoses as (
    -- Identifying T2DM via ICD codes mapped to OMOP Standard Concepts
    -- ICD-10: E11.x | ICD-9: 250.00, 250.02
    select distinct person_id
    from memory.condition_occurrence
    where condition_source_value like 'E11%'
       or condition_source_value like '250.00%'
       or condition_source_value like '250.02%'
),

t2dm_meds as (
    -- Identifying specific T2DM medications (Generic and common Brands)
    -- Includes Metformin (Glucophage), Glyburide (Diabeta), Sitagliptin (Januvia), etc.
    select distinct person_id
    from memory.drug_exposure
    where lower(drug_source_value) similar to 
        '%(metformin|glucophage|glyburide|diabeta|glipizide|glucotrol|sitagliptin|januvia|empagliflozin|jardiance|liraglutide|victoza)%'
),

t2dm_labs as (
    -- HbA1c >= 6.5% (Standardized Measurement)
    select distinct person_id
    from memory.measurement
    where measurement_source_value ilike '%a1c%'
      and value_as_number >= 6.5
),

t1dm_exclusion as (
    -- Identifying Type 1 to be used in exclusion logic
    -- ICD-10: E10.x | ICD-9: 250.01, 250.03
    select distinct person_id
    from memory.condition_occurrence
    where condition_source_value like 'E10%'
       or condition_source_value like '250.01%'
       or condition_source_value like '250.03%'
)

-- Final Algorithm Construction
select p.person_id
from memory.person p
where (
    p.person_id in (select person_id from t2dm_diagnoses)
    or 
    p.person_id in (select person_id from t2dm_meds)
    or 
    p.person_id in (select person_id from t2dm_labs)
)
and p.person_id not in (
    -- Exclude Type 1 patients unless they also have a clear T2DM diagnosis
    select person_id from t1dm_exclusion 
    where person_id not in (select person_id from t2dm_diagnoses)
);
