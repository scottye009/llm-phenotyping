-- Step 1: Identify the T2DM Cohort
with t2dm_diagnosis as (
    select person_id, condition_start_date
    from memory.condition_occurrence
    where regexp_matches(coalesce(lower(condition_source_value), ''), '^(e11|250\\.[0-9][0,2])$')
),

t1dm_diagnosis as (
    select person_id
    from memory.condition_occurrence
    where regexp_matches(coalesce(lower(condition_source_value), ''), '^(e10|250\\.[0-9][1,3])$')
),

t2dm_meds as (
    -- Includes Generic (Metformin, Glipizide) and common Brands (Glucophage, Januvia)
    select person_id
    from memory.drug_exposure
    where regexp_matches(coalesce(lower(drug_source_value), ''), 'metformin|glucophage|glipizide|glucotrol|sitagliptin|januvia|empagliflozin|jardiance')
),

lab_results as (
    -- HbA1c >= 6.5%
    select person_id, measurement_date
    from memory.measurement
    where measurement_source_value in ('3004410', '3005673')
       or regexp_matches(coalesce(lower(measurement_source_value), ''), 'hba1c|a1c|4548-4')
      and value_as_number >= 6.5
)

select distinct p.person_id
from memory.person p
join memory.condition_occurrence co on p.person_id = co.person_id
where regexp_matches(coalesce(lower(co.condition_source_value), ''), '^(e11|250\\.[0-9][0,2])$')

-- AND criteria: Ensuring it's not a one-off screening/miscode
and (
    -- 2nd Diagnosis on a different day
    exists (
        select 1 from memory.condition_occurrence co2
        where co2.person_id = p.person_id
          and regexp_matches(coalesce(lower(co2.condition_source_value), ''), '^(e11|250\\.[0-9][0,2])$')
          and co2.condition_start_date != co.condition_start_date
    )
    or
    -- Presence of medication (Metformin, etc.)
    exists (
        select 1 from memory.drug_exposure de
        where de.person_id = p.person_id
          and regexp_matches(coalesce(lower(de.drug_source_value), ''), 'metformin|glucophage|glipizide|glucotrol|sitagliptin|januvia|empagliflozin|jardiance')
    )
    or
    -- High Lab value
    exists (
        select 1 from lab_results lr where lr.person_id = p.person_id
    )
)

-- NOT criteria: Exclude if Type 1 codes are the dominant diagnosis
and not exists (
    select 1
    from memory.condition_occurrence co3
    where co3.person_id = p.person_id
      and regexp_matches(coalesce(lower(co3.condition_source_value), ''), '^(e10|250\\.[0-9][1,3])$')
    group by co3.person_id
    -- Simple heuristic: Exclude if T1 codes > T2 codes
    having count(*) > (
        select count(*)
        from memory.condition_occurrence
        where person_id = p.person_id
          and regexp_matches(coalesce(lower(condition_source_value), ''), '^(e11|250\\.[0-9][0,2])$')
    )
);
