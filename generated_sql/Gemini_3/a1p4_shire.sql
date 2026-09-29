with t2dm_codes as (
    -- Get T2DM diagnosis rows from source codes
    select condition_source_value
    from memory.condition_occurrence
    where condition_source_value like 'E11%'
       or condition_source_value like '250.00%'
       or condition_source_value like '250.02%'
),
t1dm_codes as (
    -- Exclusion codes for Type 1
    select condition_source_value
    from memory.condition_occurrence
    where condition_source_value like 'E10%'
       or condition_source_value like '250.01%'
),
t2dm_meds as (
    -- Identify T2DM specific meds (Generic and Brand)
    select drug_source_value
    from memory.drug_exposure
    where lower(coalesce(drug_source_value, '')) similar to '%(metformin|glucophage|glipizide|glucotrol|jardiance|empagliflozin|ozempic|semaglutide|pioglitazone|actos)%'
),
hba1c_labs as (
    -- Identify HbA1c >= 6.5%
    select person_id
    from memory.measurement
    where measurement_source_value in ('3004410', '3005673')
      and value_as_number >= 6.5
)

select distinct co.person_id
from memory.condition_occurrence co
where (
    co.condition_source_value like 'E11%'
    or co.condition_source_value like '250.00%'
    or co.condition_source_value like '250.02%'
)

-- Logic: 2+ occurrences OR 1 occurrence AND (Medication OR Lab)
and (
    (select count(*)
     from memory.condition_occurrence co2
     where co2.person_id = co.person_id
       and (
           co2.condition_source_value like 'E11%'
           or co2.condition_source_value like '250.00%'
           or co2.condition_source_value like '250.02%'
       )) >= 2
    or
    exists (
        select 1
        from memory.drug_exposure de
        where de.person_id = co.person_id
          and lower(coalesce(de.drug_source_value, '')) similar to '%(metformin|glucophage|glipizide|glucotrol|jardiance|empagliflozin|ozempic|semaglutide|pioglitazone|actos)%'
    )
    or
    co.person_id in (select person_id from hba1c_labs)
)

-- Exclusion Logic: NOT Type 1 (where T1 codes outnumber T2 codes)
and not exists (
    select 1
    from memory.condition_occurrence co3
    where co3.person_id = co.person_id
      and (
          co3.condition_source_value like 'E10%'
          or co3.condition_source_value like '250.01%'
      )
    group by co3.person_id
    having count(co3.condition_occurrence_id) > (
        select count(*)
        from memory.condition_occurrence co4
        where co4.person_id = co.person_id
          and (
              co4.condition_source_value like 'E11%'
              or co4.condition_source_value like '250.00%'
              or co4.condition_source_value like '250.02%'
          )
    )
);