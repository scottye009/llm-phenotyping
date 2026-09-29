-- SHIRE-adapted from alpha_n_3.sql

with
 dx_events as (
  select
    person_id,
    try_cast(condition_start_date as date) as event_date,
    case
      when coalesce(condition_source_value,'') ilike 'E11%' or regexp_matches(coalesce(condition_source_value,''), '^250\\.?[0-9]?[02]$') then 'T2'
      when coalesce(condition_source_value,'') ilike 'E10%' or regexp_matches(coalesce(condition_source_value,''), '^250\\.?[0-9]?[13]$') then 'T1'
      when coalesce(condition_source_value,'') ilike 'E08%' or coalesce(condition_source_value,'') ilike 'E09%' or coalesce(condition_source_value,'') ilike '249%' then 'SEC'
      when coalesce(condition_source_value,'') ilike 'O24.4%' or coalesce(condition_source_value,'') ilike '648.8%' then 'GEST'
      when coalesce(condition_source_value,'') ilike 'R73%' or coalesce(condition_source_value,'') ilike '790.2%' then 'PREDM'
      else null
    end as dx_type
  from memory.condition_occurrence
  where try_cast(condition_start_date as date) is not null
 ),
 dx_rollup as (
  select
    person_id,
    count(*) filter (where dx_type='T1') as t1_count,
    count(*) filter (where dx_type='T2') as t2_count,
    count(distinct event_date) filter (where dx_type='T2') as t2_distinct_dates,
    min(event_date) filter (where dx_type='T2') as first_t2_date,
    max(case when dx_type='SEC' then true else false end) as has_secondary,
    max(case when dx_type='GEST' then true else false end) as has_gestational,
    max(case when dx_type='PREDM' then true else false end) as has_predm
  from dx_events
  group by person_id
 ),
 med_events as (
  select
    person_id,
    try_cast(drug_exposure_start_date as date) as event_date,
    case
      when coalesce(drug_source_value,'') ilike '%metformin%' or coalesce(drug_source_value,'') ilike '%glipizide%' or coalesce(drug_source_value,'') ilike '%glyburide%' or coalesce(drug_source_value,'') ilike '%glimepiride%' or coalesce(drug_source_value,'') ilike '%pioglitazone%' or coalesce(drug_source_value,'') ilike '%rosiglitazone%' or coalesce(drug_source_value,'') ilike '%sitagliptin%' or coalesce(drug_source_value,'') ilike '%saxagliptin%' or coalesce(drug_source_value,'') ilike '%linagliptin%' or coalesce(drug_source_value,'') ilike '%alogliptin%' or coalesce(drug_source_value,'') ilike '%semaglutide%' or coalesce(drug_source_value,'') ilike '%liraglutide%' or coalesce(drug_source_value,'') ilike '%dulaglutide%' or coalesce(drug_source_value,'') ilike '%exenatide%' or coalesce(drug_source_value,'') ilike '%canagliflozin%' or coalesce(drug_source_value,'') ilike '%dapagliflozin%' or coalesce(drug_source_value,'') ilike '%empagliflozin%' or coalesce(drug_source_value,'') ilike '%ertugliflozin%' then 'NON_INSULIN'
      when coalesce(drug_source_value,'') ilike '%insulin%' then 'INSULIN'
      else null
    end as med_type
  from memory.drug_exposure
  where try_cast(drug_exposure_start_date as date) is not null
 ),
 med_rollup as (
  select
    person_id,
    count(*) filter (where med_type='NON_INSULIN') as non_insulin_count,
    count(*) filter (where med_type='INSULIN') as insulin_count,
    count(distinct event_date) filter (where med_type='NON_INSULIN') as non_insulin_distinct_dates,
    min(event_date) filter (where med_type='NON_INSULIN') as first_non_insulin_date,
    min(event_date) filter (where med_type='INSULIN') as first_insulin_date
  from med_events
  group by person_id
 ),
 lab_events as (
  select
    person_id,
    try_cast(measurement_date as date) as event_date,
    case
      when coalesce(measurement_source_value,'') ilike '%a1c%' and value_as_number >= 6.5 then 'ABN'
      when coalesce(measurement_source_value,'') ilike '%glucose%' and coalesce(measurement_source_value,'') ilike '%fast%' and (((coalesce(unit_source_value,'') ilike '%mmol/l%' and value_as_number >= 7.0) or value_as_number >= 126)) then 'ABN'
      when (coalesce(measurement_source_value,'') ilike '%ogtt%' or coalesce(measurement_source_value,'') ilike '%tolerance%') and (((coalesce(unit_source_value,'') ilike '%mmol/l%' and value_as_number >= 11.1) or value_as_number >= 200)) then 'ABN'
      when coalesce(measurement_source_value,'') ilike '%glucose%' and (((coalesce(unit_source_value,'') ilike '%mmol/l%' and value_as_number >= 11.1) or value_as_number >= 200)) then 'ABN'
      else null
    end as lab_type
  from memory.measurement
  where value_as_number is not null and try_cast(measurement_date as date) is not null
 ),
 lab_rollup as (
  select
    person_id,
    count(distinct event_date) filter (where lab_type='ABN') as abn_distinct_dates,
    min(event_date) filter (where lab_type='ABN') as first_abn_date
  from lab_events
  group by person_id
 ),
 person_birth as (
  select person_id,
         coalesce(try_cast(birth_datetime as date), make_date(year_of_birth, coalesce(month_of_birth,1), coalesce(day_of_birth,1))) as birth_date
  from memory.person
 ),
 first_signal as (
  select
    p.person_id,
    least(
      coalesce(dr.first_t2_date, date '9999-12-31'),
      coalesce(mr.first_non_insulin_date, date '9999-12-31'),
      coalesce(mr.first_insulin_date, date '9999-12-31'),
      coalesce(lr.first_abn_date, date '9999-12-31')
    ) as index_date
  from memory.person p
  left join dx_rollup dr on dr.person_id = p.person_id
  left join med_rollup mr on mr.person_id = p.person_id
  left join lab_rollup lr on lr.person_id = p.person_id
 ),
 age_at_index as (
  select f.person_id, f.index_date, date_diff('year', pb.birth_date, f.index_date) as age_index
  from first_signal f join person_birth pb on pb.person_id = f.person_id
 ),
 incl_dx as (
  select person_id, (t2_distinct_dates >= 2) as incl_dx_only, (t2_distinct_dates >= 1) as has_t2_dx
  from dx_rollup
 ),
 incl_dx_med as (
  select mr.person_id, (coalesce(d.has_t2_dx,false) and mr.non_insulin_distinct_dates >= 1) as incl_dx_plus_med
  from med_rollup mr left join incl_dx d on d.person_id = mr.person_id
 ),
 incl_labs as (
  select person_id, (abn_distinct_dates >= 2) as incl_labs_only
  from lab_rollup
 ),
 incl_med_only as (
  select person_id, (non_insulin_distinct_dates >= 2) as incl_med_only
  from med_rollup
 ),
 exclusions as (
  select
    p.person_id,
    coalesce(dr.has_secondary,false) as has_secondary,
    coalesce(dr.has_gestational,false) as has_gestational,
    coalesce(dr.has_predm,false) as has_predm_only,
    coalesce(dr.t1_count,0) as t1_count,
    coalesce(dr.t2_count,0) as t2_count,
    coalesce(mr.non_insulin_count,0) as non_insulin_count,
    coalesce(mr.insulin_count,0) as insulin_count,
    a.age_index
  from (select distinct person_id from memory.person) p
  left join dx_rollup dr on dr.person_id = p.person_id
  left join med_rollup mr on mr.person_id = p.person_id
  left join age_at_index a on a.person_id = p.person_id
 ),
 likely_t1 as (
  select person_id,
         (age_index is not null and age_index < 30 and non_insulin_count = 0 and t1_count >= t2_count) as is_likely_t1
  from exclusions
 ),
 final_flags as (
  select
    p.person_id,
    a.index_date,
    coalesce(dx.incl_dx_only,false) or coalesce(dxm.incl_dx_plus_med,false) or coalesce(l.incl_labs_only,false) or coalesce(mo.incl_med_only,false) as meets_inclusion,
    coalesce(e.has_secondary,false) as ex_secondary,
    coalesce(e.has_gestational,false) as ex_gestational,
    coalesce(t1.is_likely_t1,false) as ex_likely_t1,
    (coalesce(e.has_predm_only,false) and not (coalesce(dx.incl_dx_only,false) or coalesce(dxm.incl_dx_plus_med,false) or coalesce(l.incl_labs_only,false) or coalesce(mo.incl_med_only,false))) as ex_predm_only
  from (select distinct person_id from memory.person) p
  left join age_at_index a on a.person_id = p.person_id
  left join incl_dx dx on dx.person_id = p.person_id
  left join incl_dx_med dxm on dxm.person_id = p.person_id
  left join incl_labs l on l.person_id = p.person_id
  left join incl_med_only mo on mo.person_id = p.person_id
  left join exclusions e on e.person_id = p.person_id
  left join likely_t1 t1 on t1.person_id = p.person_id
 )
select
  person_id,
  index_date,
  case when meets_inclusion and not ex_secondary and not ex_gestational and not ex_likely_t1 and not ex_predm_only then 1 else 0 end as t2dm_flag,
  meets_inclusion,
  ex_secondary,
  ex_gestational,
  ex_likely_t1,
  ex_predm_only
from final_flags
where meets_inclusion or ex_secondary or ex_gestational or ex_likely_t1 or ex_predm_only
order by t2dm_flag desc, index_date nulls last;
