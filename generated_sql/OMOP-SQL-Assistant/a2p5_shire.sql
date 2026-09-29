-- SHIRE-adapted from alpha_n_5.sql

with
 age18 as (
  select
    person_id,
    coalesce(try_cast(birth_datetime as date), make_date(year_of_birth, coalesce(month_of_birth,1), coalesce(day_of_birth,1))) as dob
  from memory.person
 ),
 t2dx_events as (
  select person_id, try_cast(condition_start_date as date) as event_date, visit_occurrence_id
  from memory.condition_occurrence
  where coalesce(condition_source_value,'') ilike 'E11%'
     or regexp_matches(coalesce(condition_source_value,''), '^250\\.?[0-9]?[02]$')
 ),
 t1dx_events as (
  select person_id, try_cast(condition_start_date as date) as event_date
  from memory.condition_occurrence
  where coalesce(condition_source_value,'') ilike 'E10%'
     or regexp_matches(coalesce(condition_source_value,''), '^250\\.?[0-9]?[13]$')
 ),
 gest_events as (
  select person_id, try_cast(condition_start_date as date) as event_date
  from memory.condition_occurrence
  where coalesce(condition_source_value,'') ilike 'O24.4%'
     or coalesce(condition_source_value,'') ilike '648.8%'
 ),
 sec_events as (
  select person_id, try_cast(condition_start_date as date) as event_date
  from memory.condition_occurrence
  where coalesce(condition_source_value,'') ilike '249%'
     or coalesce(condition_source_value,'') ilike 'E08%'
     or coalesce(condition_source_value,'') ilike 'E09%'
     or coalesce(condition_source_value,'') ilike 'E13%'
 ),
 lab_positive as (
  select person_id, try_cast(measurement_date as date) as event_date
  from memory.measurement
  where value_as_number is not null and (
    (coalesce(measurement_source_value,'') ilike '%a1c%' and (((coalesce(unit_source_value,'') ilike 'mmol/mol' and value_as_number >= 48) or value_as_number >= 6.5)))
    or (coalesce(measurement_source_value,'') ilike '%glucose%' and coalesce(measurement_source_value,'') ilike '%fast%' and (((coalesce(unit_source_value,'') ilike '%mmol/l%' and value_as_number >= 7.0) or value_as_number >= 126)))
    or ((coalesce(measurement_source_value,'') ilike '%ogtt%' or coalesce(measurement_source_value,'') ilike '%tolerance%') and (((coalesce(unit_source_value,'') ilike '%mmol/l%' and value_as_number >= 11.1) or value_as_number >= 200)))
    or (coalesce(measurement_source_value,'') ilike '%glucose%' and (((coalesce(unit_source_value,'') ilike '%mmol/l%' and value_as_number >= 11.1) or value_as_number >= 200)))
  )
 ),
 drug_niad as (
  select person_id, try_cast(drug_exposure_start_date as date) as event_date
  from memory.drug_exposure
  where coalesce(drug_source_value,'') ilike '%metformin%'
     or coalesce(drug_source_value,'') ilike '%glipizide%'
     or coalesce(drug_source_value,'') ilike '%glyburide%'
     or coalesce(drug_source_value,'') ilike '%glimepiride%'
     or coalesce(drug_source_value,'') ilike '%pioglitazone%'
     or coalesce(drug_source_value,'') ilike '%rosiglitazone%'
     or coalesce(drug_source_value,'') ilike '%sitagliptin%'
     or coalesce(drug_source_value,'') ilike '%saxagliptin%'
     or coalesce(drug_source_value,'') ilike '%linagliptin%'
     or coalesce(drug_source_value,'') ilike '%alogliptin%'
     or coalesce(drug_source_value,'') ilike '%canagliflozin%'
     or coalesce(drug_source_value,'') ilike '%dapagliflozin%'
     or coalesce(drug_source_value,'') ilike '%empagliflozin%'
     or coalesce(drug_source_value,'') ilike '%ertugliflozin%'
     or coalesce(drug_source_value,'') ilike '%exenatide%'
     or coalesce(drug_source_value,'') ilike '%liraglutide%'
     or coalesce(drug_source_value,'') ilike '%semaglutide%'
     or coalesce(drug_source_value,'') ilike '%dulaglutide%'
     or coalesce(drug_source_value,'') ilike '%repaglinide%'
     or coalesce(drug_source_value,'') ilike '%nateglinide%'
     or coalesce(drug_source_value,'') ilike '%acarbose%'
     or coalesce(drug_source_value,'') ilike '%miglitol%'
 ),
 drug_insulin as (
  select person_id, try_cast(drug_exposure_start_date as date) as event_date
  from memory.drug_exposure
  where coalesce(drug_source_value,'') ilike '%insulin%'
 ),
 visits as (
  select visit_occurrence_id, person_id, try_cast(visit_start_date as date) as visit_start_date, visit_source_value
  from memory.visit_occurrence
 ),
 t2dx_with_setting as (
  select e.person_id, e.event_date,
         case when coalesce(v.visit_source_value,'') ilike '%hospital%' or coalesce(v.visit_source_value,'') ilike '%inpatient%' then 'INPATIENT'
              when coalesce(v.visit_source_value,'') ilike '%er%' or coalesce(v.visit_source_value,'') ilike '%emergency%' or coalesce(v.visit_source_value,'') ilike '%ed%' or coalesce(v.visit_source_value,'') ilike '%outpatient%' or coalesce(v.visit_source_value,'') ilike '%ambulatory%' then 'AMB_ED'
              else 'OTHER' end as setting
  from t2dx_events e
  left join visits v on v.visit_occurrence_id = e.visit_occurrence_id
 ),
 rule_dx as (
  select person_id, min(event_date) as index_date
  from (
    select person_id, event_date
    from t2dx_with_setting
    where setting in ('INPATIENT','AMB_ED')
    union all
    select person_id, min(event_date) as event_date
    from (
      select person_id, event_date
      from t2dx_with_setting
      where setting in ('AMB_ED')
      group by person_id, event_date
    ) d
    group by person_id
    having count(*) >= 2
  ) x
  group by person_id
 ),
 rule_lab_plus_meds as (
  select l.person_id, min(least(l.event_date, d.event_date)) as index_date
  from lab_positive l
  join drug_niad d on d.person_id = l.person_id and d.event_date between l.event_date - interval 365 day and l.event_date + interval 365 day
  group by l.person_id
  union
  select l.person_id, min(least(l.event_date, ins.event_date)) as index_date
  from lab_positive l
  join drug_insulin ins on ins.person_id = l.person_id and ins.event_date between l.event_date - interval 365 day and l.event_date + interval 365 day
  where exists (select 1 from t2dx_events td where td.person_id = l.person_id)
  group by l.person_id
 ),
 inclusion as (
  select person_id, min(index_date) as index_date
  from (
    select * from rule_dx
    union
    select * from rule_lab_plus_meds
  ) u
  group by person_id
 ),
 exclusion_any as (
  select distinct person_id
  from (
    select t1.person_id from t1dx_events t1 where not exists (select 1 from t2dx_events t2 where t2.person_id=t1.person_id)
    union
    select g.person_id from gest_events g where not exists (select 1 from t2dx_events t2 where t2.person_id=g.person_id)
    union
    select s.person_id from sec_events s where not exists (select 1 from t2dx_events t2 where t2.person_id=s.person_id)
    union
    select i.person_id from drug_insulin i where not exists (select 1 from t2dx_events t2 where t2.person_id=i.person_id) and not exists (select 1 from drug_niad n where n.person_id=i.person_id)
  ) z
 ),
 age_filtered as (
  select inc.person_id, inc.index_date
  from inclusion inc
  join age18 a on a.person_id = inc.person_id
  where a.dob is not null and date_diff('year', a.dob, inc.index_date) >= 18
 )
select af.person_id, af.index_date
from age_filtered af
left join exclusion_any ex on ex.person_id = af.person_id
where ex.person_id is null
;
