with t2dm_dx as (
    -- Identifying T2DM Diagnosis Concepts (ICD9: 250.00, ICD10: E11.x)
    select distinct person_id, condition_start_date
    from memory.condition_occurrence
    where condition_source_value like '250.0%'
       or condition_source_value like 'E11%'
),

t1dm_dx as (
    -- Identifying Type 1 Exclusions (ICD9: 250.01, ICD10: E10.x)
    select distinct person_id
    from memory.condition_occurrence
    where condition_source_value like '250.01%'
       or condition_source_value like 'E10%'
),

t2dm_meds as (
    -- Medication list (Generic & Brand Examples)
    select distinct person_id, drug_exposure_id
    from memory.drug_exposure
    where lower(drug_source_value) similar to '%(metformin|glucophage|glipizide|glucotrol|glyburide|micronase|pioglitazone|actos|sitagliptin|januvia|empagliflozin|jardiance|insulin)%'
),

t2dm_labs as (
    -- Lab: HbA1c >= 6.5
    select person_id, measurement_date 
    from memory.measurement
    where measurement_source_value ilike '%a1c%'
      and value_as_number >= 6.5
),

dx_counts as (
    -- Count distinct days with a T2DM diagnosis per person
    select person_id, count(distinct condition_start_date) as dx_day_count
    from t2dm_dx
    group by person_id
)

-- Final Cohort Construction
select distinct p.person_id
from memory.person p
join dx_counts dx on p.person_id = dx.person_id
left join t2dm_meds de on p.person_id = de.person_id
left join t2dm_labs lb on p.person_id = lb.person_id

where (
    -- CRITERIA A: Two or more diagnosis dates
    dx.dx_day_count >= 2 
    or 
    -- CRITERIA B: One diagnosis AND (Medication OR Lab)
    (dx.dx_day_count >= 1 and (de.drug_exposure_id is not null or lb.person_id is not null))
)
-- EXCLUSION: No Type 1 Diabetes diagnoses
and p.person_id not in (
    select person_id from t1dm_dx
);
