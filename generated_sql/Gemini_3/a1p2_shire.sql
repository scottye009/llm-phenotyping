with t2dm_diagnosis as (
    -- Identifying T2DM ICD9/10 and SNOMED through the Concept table
    select person_id, condition_start_date
    from memory.condition_occurrence
    where coalesce(condition_source_value, '') like 'E11%'
       or condition_source_value = '250.00'
       or condition_source_value = '250.02'
),
t1dm_exclusion as (
    -- Type 1 and Gestational exclusions
    select person_id
    from memory.condition_occurrence
    where coalesce(condition_source_value, '') like 'E10%'
       or coalesce(condition_source_value, '') like '648.0%'
       or coalesce(condition_source_value, '') like 'O24%'
),
medication_users as (
    -- T2DM Medications: Metformin (Glucophage), Glipizide (Glucotrol), Empagliflozin (Jardiance), etc.
    select distinct person_id
    from memory.drug_exposure
    where regexp_matches(coalesce(lower(drug_source_value), ''), 'metformin|glucophage|glipizide|glucotrol|sitagliptin|januvia|empagliflozin|jardiance')
),
lab_confirmed as (
    -- HbA1c >= 6.5%
    select distinct person_id
    from memory.measurement
    where (measurement_source_value in ('3004410', '3007263', '40758583')
           or regexp_matches(coalesce(lower(measurement_source_value), ''), 'hba1c|a1c|4548-4'))
      and value_as_number >= 6.5
)

select distinct p.person_id
from memory.person p
join memory.condition_occurrence co on p.person_id = co.person_id
where (
    coalesce(co.condition_source_value, '') like 'E11%'
    or co.condition_source_value = '250.00'
    or co.condition_source_value = '250.02'
)
-- EXCLUSION LOGIC: NOT T1DM
and p.person_id not in (select person_id from t1dm_exclusion)
-- CRITERIA COMBINATION
and (
    -- Two separate diagnosis dates
    p.person_id in (
        select person_id
        from t2dm_diagnosis
        group by person_id having count(distinct condition_start_date) >= 2
    )
    or p.person_id in (select person_id from medication_users)
    or p.person_id in (select person_id from lab_confirmed)
);
