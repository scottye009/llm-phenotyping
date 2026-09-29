-- Step 1: Define the T2DM Cohort
create temp table t2dm_cohort as
with t2dm_diagnoses as (
    -- Selecting T2DM ICD codes (OMOP maps these to Standard Concepts)
    -- ICD10CM: E11, ICD9CM: 250.00, 250.02
    select distinct person_id
    from memory.condition_occurrence
    where condition_source_value like 'E11%' 
       or condition_source_value like '250.00%' 
       or condition_source_value like '250.02%'
),

t1dm_exclusion as (
    -- Identify Type 1 to exclude (ICD10: E10, ICD9: 250.01)
    select distinct person_id
    from memory.condition_occurrence
    where condition_source_value like 'E10%' 
       or condition_source_value like '250.01%'
),

t2dm_meds as (
    -- Identifying by Generic and Brand names in drug_exposure
    select distinct person_id
    from memory.drug_exposure
    where lower(drug_source_value) similar to 
        '%(metformin|glucophage|glipizide|glucotrol|glyburide|diabeta|sitagliptin|januvia|empagliflozin|jardiance|liraglutide|victoza|pioglitazone|actos)%'
),

high_hba1c as (
    -- Lab result criteria (HbA1c >= 6.5%)
    -- Maps to Measurement table in your CDM diagram
    select distinct person_id
    from memory.measurement
    where measurement_source_value like '%A1c%' 
      and value_as_number >= 6.5
)

select p.person_id
from memory.person p
where (
    p.person_id in (select person_id from t2dm_diagnoses)
    or 
    p.person_id in (select person_id from t2dm_meds)
    or
    p.person_id in (select person_id from high_hba1c)
)
and p.person_id not in (select person_id from t1dm_exclusion);

-- Summary Count
select count(*) as total_t2dm_patients from t2dm_cohort;
