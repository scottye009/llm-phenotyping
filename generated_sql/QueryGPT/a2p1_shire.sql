-- SHIRE-adapted from alpha_n_1.sql
-- Same overall algorithm, operationalized on source-value fields for SHIRE/DuckDB

with
-- diagnosis signals from source codes/text
 dx_all as (
  select
    co.person_id,
    try_cast(co.condition_start_date as date) as cond_date,
    co.visit_occurrence_id,
    vo.visit_source_value,
    case
      when coalesce(co.condition_source_value,'') ilike 'E11%' or (coalesce(co.condition_source_value,'') ilike '250.%' and (coalesce(co.condition_source_value,'') ilike '%type 2%' or coalesce(co.condition_source_value,'') ilike '%type ii%')) then 'T2'
      when coalesce(co.condition_source_value,'') ilike 'E10%' or (coalesce(co.condition_source_value,'') ilike '250.%' and (coalesce(co.condition_source_value,'') ilike '%type 1%' or coalesce(co.condition_source_value,'') ilike '%type i%')) then 'T1'
      when coalesce(co.condition_source_value,'') ilike 'O24%' or coalesce(co.condition_source_value,'') ilike '648.8%' or coalesce(co.condition_source_value,'') ilike '%gestational diabetes%' then 'GEST'
      when coalesce(co.condition_source_value,'') ilike 'E08%' or coalesce(co.condition_source_value,'') ilike 'E09%' or coalesce(co.condition_source_value,'') ilike 'E13%' or coalesce(co.condition_source_value,'') ilike '249%' then 'SEC'
      else null
    end as dx_flag
  from memory.condition_occurrence co
  left join memory.visit_occurrence vo on vo.visit_occurrence_id = co.visit_occurrence_id
  where try_cast(co.condition_start_date as date) is not null
 ),
 dx_t2 as (select * from dx_all where dx_flag = 'T2'),
 dx_t1 as (select * from dx_all where dx_flag = 'T1'),
 dx_gest as (select * from dx_all where dx_flag = 'GEST'),
 dx_secondary as (select * from dx_all where dx_flag = 'SEC'),

 lab_pos as (
  select
    m.person_id,
    try_cast(m.measurement_date as date) as meas_date,
    case
      when coalesce(m.measurement_source_value,'') ilike '%a1c%' and m.value_as_number is not null and (
        ((coalesce(m.unit_source_value,'') ilike '%' or coalesce(m.unit_source_value,'') ilike 'percent' or coalesce(m.unit_source_value,'') = '%') and m.value_as_number >= 6.5)
        or (coalesce(m.unit_source_value,'') ilike 'mmol/mol' and m.value_as_number >= 48)
        or coalesce(m.unit_source_value,'') = '' and m.value_as_number between 6.5 and 20
      ) then 'A1C>=6.5'
      when (coalesce(m.measurement_source_value,'') ilike '%fast%' and coalesce(m.measurement_source_value,'') ilike '%glucose%') and m.value_as_number is not null and (
        ((coalesce(m.unit_source_value,'') ilike '%mg/dl%' or coalesce(m.unit_source_value,'') = '') and m.value_as_number >= 126)
        or (coalesce(m.unit_source_value,'') ilike '%mmol/l%' and m.value_as_number >= 7.0)
      ) then 'FPG>=126'
      when ((coalesce(m.measurement_source_value,'') ilike '%ogtt%' and coalesce(m.measurement_source_value,'') ilike '%2%') or (coalesce(m.measurement_source_value,'') ilike '%tolerance%' and coalesce(m.measurement_source_value,'') ilike '%glucose%'))
        and m.value_as_number is not null and (
        ((coalesce(m.unit_source_value,'') ilike '%mg/dl%' or coalesce(m.unit_source_value,'') = '') and m.value_as_number >= 200)
        or (coalesce(m.unit_source_value,'') ilike '%mmol/l%' and m.value_as_number >= 11.1)
      ) then 'OGTT2H>=200'
      when coalesce(m.measurement_source_value,'') ilike '%glucose%' and m.value_as_number is not null and (
        ((coalesce(m.unit_source_value,'') ilike '%mg/dl%' or coalesce(m.unit_source_value,'') = '') and m.value_as_number >= 200)
        or (coalesce(m.unit_source_value,'') ilike '%mmol/l%' and m.value_as_number >= 11.1)
      ) then 'RPG>=200'
      else null
    end as lab_flag
  from memory.measurement m
  where try_cast(m.measurement_date as date) is not null
 ),
 lab_any as (
  select person_id, min(meas_date) as first_lab_date
  from lab_pos
  where lab_flag is not null
  group by person_id
 ),

 med_all as (
  select
    de.person_id,
    try_cast(de.drug_exposure_start_date as date) as fill_date,
    case
      when coalesce(de.drug_source_value,'') ilike '%metformin%' or coalesce(de.drug_source_value,'') ilike '%glipizide%' or coalesce(de.drug_source_value,'') ilike '%glyburide%' or coalesce(de.drug_source_value,'') ilike '%glimepiride%' or coalesce(de.drug_source_value,'') ilike '%repaglinide%' or coalesce(de.drug_source_value,'') ilike '%nateglinide%' or coalesce(de.drug_source_value,'') ilike '%pioglitazone%' or coalesce(de.drug_source_value,'') ilike '%rosiglitazone%' or coalesce(de.drug_source_value,'') ilike '%sitagliptin%' or coalesce(de.drug_source_value,'') ilike '%saxagliptin%' or coalesce(de.drug_source_value,'') ilike '%linagliptin%' or coalesce(de.drug_source_value,'') ilike '%alogliptin%' or coalesce(de.drug_source_value,'') ilike '%semaglutide%' or coalesce(de.drug_source_value,'') ilike '%liraglutide%' or coalesce(de.drug_source_value,'') ilike '%dulaglutide%' or coalesce(de.drug_source_value,'') ilike '%exenatide%' or coalesce(de.drug_source_value,'') ilike '%lixisenatide%' or coalesce(de.drug_source_value,'') ilike '%empagliflozin%' or coalesce(de.drug_source_value,'') ilike '%canagliflozin%' or coalesce(de.drug_source_value,'') ilike '%dapagliflozin%' or coalesce(de.drug_source_value,'') ilike '%ertugliflozin%' then 'T2_MED'
      else null
    end as med_flag
  from memory.drug_exposure de
  where try_cast(de.drug_exposure_start_date as date) is not null
 ),
 med_t2 as (
  select person_id, fill_date
  from med_all
  where med_flag = 'T2_MED'
 ),
 med_2fills as (
  select d1.person_id, min(d1.fill_date) as first_fill
  from (select distinct person_id, fill_date from med_t2) d1
  join (select distinct person_id, fill_date from med_t2) d2
    on d1.person_id = d2.person_id
   and d2.fill_date >= d1.fill_date + interval 30 day
  group by d1.person_id
 ),

 dx_rule as (
  select person_id, min(cond_date) as index_date, 'A:DX' as rule_label
  from (
    select person_id, min(cond_date) as cond_date
    from dx_t2
    where coalesce(visit_source_value,'') ilike '%hospital%'
       or coalesce(visit_source_value,'') ilike '%inpatient%'
    group by person_id
    union all
    select d1.person_id, min(d1.cond_date) as cond_date
    from (
      select person_id, cond_date
      from dx_t2
      where not (coalesce(visit_source_value,'') ilike '%hospital%' or coalesce(visit_source_value,'') ilike '%inpatient%')
      group by person_id, cond_date
    ) d1
    join (
      select person_id, cond_date
      from dx_t2
      where not (coalesce(visit_source_value,'') ilike '%hospital%' or coalesce(visit_source_value,'') ilike '%inpatient%')
      group by person_id, cond_date
    ) d2
      on d1.person_id = d2.person_id
     and d2.cond_date >= d1.cond_date + interval 30 day
    group by d1.person_id
  ) z
  group by person_id
 ),
 dx_lab_rule as (
  select d.person_id, least(min(d.cond_date), l.first_lab_date) as index_date, 'B:DX+LAB' as rule_label
  from dx_t2 d
  join lab_any l on l.person_id = d.person_id
  group by d.person_id, l.first_lab_date
 ),
 med_rule as (
  select person_id, first_fill as index_date, 'C:MEDS' as rule_label
  from med_2fills
 ),
 included as (
  select * from dx_rule
  union all
  select * from dx_lab_rule
  union all
  select * from med_rule
 ),
 gest_window as (select person_id, cond_date from dx_gest),
 secondary_any as (select person_id from dx_secondary group by person_id),
 type1_only as (
  select t1.person_id
  from dx_t1 t1
  left join dx_t2 t2 on t2.person_id = t1.person_id
  where t2.person_id is null
  group by t1.person_id
 ),
 person_birth as (
  select
    p.person_id,
    coalesce(try_cast(p.birth_datetime as date), make_date(p.year_of_birth, coalesce(p.month_of_birth,1), coalesce(p.day_of_birth,1))) as birth_date
  from memory.person p
 ),
 age_ok as (
  select i.person_id, i.index_date, date_diff('year', b.birth_date, i.index_date) as age_yrs
  from included i
  join person_birth b on b.person_id = i.person_id
  where b.birth_date is not null
 )
select
  i.person_id,
  min(i.index_date) as index_date,
  string_agg(distinct i.rule_label, '|') as evidence_rule
from included i
join age_ok a on a.person_id = i.person_id and a.index_date = i.index_date
left join gest_window gw on gw.person_id = i.person_id and gw.cond_date between i.index_date - interval 270 day and i.index_date + interval 270 day
left join secondary_any sec on sec.person_id = i.person_id
left join type1_only t1o on t1o.person_id = i.person_id
where a.age_yrs >= 18
  and gw.person_id is null
  and sec.person_id is null
  and t1o.person_id is null
group by i.person_id
;
