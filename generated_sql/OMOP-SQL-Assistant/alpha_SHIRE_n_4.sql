-- SHIRE-adapted from alpha_n_4.sql

with
 dx_events as (
  select
    co.person_id,
    try_cast(co.condition_start_date as date) as evt_date,
    coalesce(vo.visit_source_value,'') as visit_source_value
  from memory.condition_occurrence co
  left join memory.visit_occurrence vo on vo.visit_occurrence_id = co.visit_occurrence_id
  where coalesce(co.condition_source_value,'') ilike 'E11%'
     or regexp_matches(coalesce(co.condition_source_value,''), '^250\\.?[0-9]?[02]$')
 ),
 dx_events_counts as (
  select
    person_id,
    count(distinct evt_date) as dx_distinct_dates,
    count(*) filter (where visit_source_value ilike '%hospital%' or visit_source_value ilike '%inpatient%') as dx_ip
  from dx_events
  group by person_id
 ),
 dx_exclusion as (
  select distinct person_id
  from memory.condition_occurrence
  where coalesce(condition_source_value,'') ilike 'E10%'
     or regexp_matches(coalesce(condition_source_value,''), '^250\\.?[0-9]?[13]$')
     or coalesce(condition_source_value,'') ilike 'E08%'
     or coalesce(condition_source_value,'') ilike 'E09%'
     or coalesce(condition_source_value,'') ilike 'E13%'
     or coalesce(condition_source_value,'') ilike 'O24.4%'
     or coalesce(condition_source_value,'') ilike '648.8%'
 ),
 lab_abnormal as (
  select m.person_id, try_cast(m.measurement_date as date) as evt_date
  from memory.measurement m
  where (
    ((coalesce(m.measurement_source_value,'') ilike '%a1c%') and ((coalesce(lower(m.unit_source_value), '') in ('%','percent') and m.value_as_number >= 6.5) or (coalesce(lower(m.unit_source_value), '') = 'mmol/mol' and m.value_as_number >= 48) or (coalesce(m.unit_source_value,'') = '' and m.value_as_number between 6.5 and 20)))
    or ((coalesce(m.measurement_source_value,'') ilike '%glucose%' and coalesce(m.measurement_source_value,'') ilike '%fast%') and (((coalesce(m.unit_source_value,'') ilike '%mmol/l%' and m.value_as_number >= 7.0) or m.value_as_number >= 126)))
    or (((coalesce(m.measurement_source_value,'') ilike '%ogtt%' or coalesce(m.measurement_source_value,'') ilike '%tolerance%')) and (((coalesce(m.unit_source_value,'') ilike '%mmol/l%' and m.value_as_number >= 11.1) or m.value_as_number >= 200)))
    or ((coalesce(m.measurement_source_value,'') ilike '%glucose%') and (((coalesce(m.unit_source_value,'') ilike '%mmol/l%' and m.value_as_number >= 11.1) or m.value_as_number >= 200)))
  )
 ),
 lab_rule as (
  select person_id, count(distinct evt_date) as abnormal_lab_dates, min(evt_date) as first_abn_lab_date
  from lab_abnormal
  group by person_id
 ),
 rx_events as (
  select
    de.person_id,
    try_cast(de.drug_exposure_start_date as date) as evt_date,
    case when coalesce(de.drug_source_value,'') ilike '%insulin%' then 'INSULIN_OR_OTHER' else 'NON_INSULIN' end as drug_type
  from memory.drug_exposure de
  where coalesce(de.drug_source_value,'') ilike '%metformin%'
     or coalesce(de.drug_source_value,'') ilike '%glipizide%'
     or coalesce(de.drug_source_value,'') ilike '%glyburide%'
     or coalesce(de.drug_source_value,'') ilike '%glimepiride%'
     or coalesce(de.drug_source_value,'') ilike '%sitagliptin%'
     or coalesce(de.drug_source_value,'') ilike '%saxagliptin%'
     or coalesce(de.drug_source_value,'') ilike '%linagliptin%'
     or coalesce(de.drug_source_value,'') ilike '%alogliptin%'
     or coalesce(de.drug_source_value,'') ilike '%exenatide%'
     or coalesce(de.drug_source_value,'') ilike '%liraglutide%'
     or coalesce(de.drug_source_value,'') ilike '%semaglutide%'
     or coalesce(de.drug_source_value,'') ilike '%dulaglutide%'
     or coalesce(de.drug_source_value,'') ilike '%tirzepatide%'
     or coalesce(de.drug_source_value,'') ilike '%canagliflozin%'
     or coalesce(de.drug_source_value,'') ilike '%dapagliflozin%'
     or coalesce(de.drug_source_value,'') ilike '%empagliflozin%'
     or coalesce(de.drug_source_value,'') ilike '%ertugliflozin%'
     or coalesce(de.drug_source_value,'') ilike '%pioglitazone%'
     or coalesce(de.drug_source_value,'') ilike '%rosiglitazone%'
     or coalesce(de.drug_source_value,'') ilike '%insulin%'
 ),
 rx_rule as (
  select person_id,
         min(evt_date) as first_rx_date,
         count(*) filter (where drug_type='NON_INSULIN') as non_insulin_count,
         count(*) filter (where drug_type='INSULIN_OR_OTHER') as insulin_count,
         count(distinct evt_date) as rx_distinct_dates
  from rx_events
  group by person_id
 ),
 diagnosis_rule as (
  select d.person_id, min(e.evt_date) as first_dx_date
  from dx_events e
  join dx_events_counts d on d.person_id = e.person_id
  where (d.dx_ip >= 1 or d.dx_distinct_dates >= 2)
  group by d.person_id
 ),
 combined_logic as (
  select
    p.person_id,
    (dr.person_id is not null) as has_dx_rule,
    (lr.abnormal_lab_dates >= 2) as has_lab_rule,
    ((rx.non_insulin_count >= 1) or (rx.insulin_count >= 2 and (dr.person_id is not null))) as has_rx_rule,
    least(coalesce(dr.first_dx_date, date '9999-12-31'), coalesce(lr.first_abn_lab_date, date '9999-12-31'), coalesce(rx.first_rx_date, date '9999-12-31')) as candidate_index_date
  from memory.person p
  left join diagnosis_rule dr on dr.person_id = p.person_id
  left join lab_rule lr on lr.person_id = p.person_id
  left join rx_rule rx on rx.person_id = p.person_id
 ),
 person_birth as (
  select person_id,
         coalesce(try_cast(birth_datetime as date), make_date(year_of_birth, coalesce(month_of_birth,1), coalesce(day_of_birth,1))) as birth_date
  from memory.person
 ),
 age_at_index as (
  select c.person_id, c.candidate_index_date as index_date, date_diff('year', pb.birth_date, c.candidate_index_date) as age_years
  from combined_logic c join person_birth pb on pb.person_id = c.person_id
 ),
 t2dm_cases as (
  select a.person_id, a.index_date
  from combined_logic c
  join age_at_index a on a.person_id = c.person_id
  where ((c.has_dx_rule and (c.has_lab_rule or c.has_rx_rule)) or (c.has_rx_rule and c.has_lab_rule))
    and a.age_years >= 18
    and c.candidate_index_date is not null
    and c.person_id not in (select person_id from dx_exclusion)
 )
select person_id, index_date from t2dm_cases order by person_id;
