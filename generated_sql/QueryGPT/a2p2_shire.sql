-- SHIRE-adapted from alpha_n_2.sql

with
 t2dm_dx as (
  select person_id, try_cast(condition_start_date as date) as dx_date
  from memory.condition_occurrence
  where coalesce(condition_source_value,'') ilike 'E11%'
     or regexp_matches(coalesce(condition_source_value,''), '^250\\.?[0-9]?[02]$')
 ),
 exclude_dx as (
  select person_id
  from memory.condition_occurrence
  where coalesce(condition_source_value,'') ilike 'E10%'
     or regexp_matches(coalesce(condition_source_value,''), '^250\\.?[0-9]?[13]$')
     or coalesce(condition_source_value,'') ilike 'E08%'
     or coalesce(condition_source_value,'') ilike 'E09%'
     or coalesce(condition_source_value,'') ilike 'E13%'
     or coalesce(condition_source_value,'') ilike 'O24.4%'
 ),
 abnl_a1c as (
  select person_id, try_cast(measurement_date as date) as lab_date
  from memory.measurement
  where coalesce(measurement_source_value,'') ilike '%a1c%'
    and value_as_number is not null
    and ((coalesce(unit_source_value,'') ilike 'mmol/mol' and value_as_number >= 48) or value_as_number >= 6.5)
 ),
 abnl_fpg as (
  select person_id, try_cast(measurement_date as date) as lab_date
  from memory.measurement
  where coalesce(measurement_source_value,'') ilike '%glucose%'
    and coalesce(measurement_source_value,'') ilike '%fast%'
    and value_as_number is not null
    and ((coalesce(unit_source_value,'') ilike '%mmol/l%' and value_as_number >= 7.0) or value_as_number >= 126)
 ),
 abnl_ogtt as (
  select person_id, try_cast(measurement_date as date) as lab_date
  from memory.measurement
  where (coalesce(measurement_source_value,'') ilike '%ogtt%' or coalesce(measurement_source_value,'') ilike '%tolerance%')
    and value_as_number is not null
    and ((coalesce(unit_source_value,'') ilike '%mmol/l%' and value_as_number >= 11.1) or value_as_number >= 200)
 ),
 abnl_labs as (
  select person_id, lab_date from abnl_a1c
  union all
  select person_id, lab_date from abnl_fpg
  union all
  select person_id, lab_date from abnl_ogtt
 ),
 any_antihyperglycemic as (
  select person_id, try_cast(drug_exposure_start_date as date) as rx_date
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
     or coalesce(drug_source_value,'') ilike '%empagliflozin%'
     or coalesce(drug_source_value,'') ilike '%canagliflozin%'
     or coalesce(drug_source_value,'') ilike '%dapagliflozin%'
     or coalesce(drug_source_value,'') ilike '%ertugliflozin%'
     or coalesce(drug_source_value,'') ilike '%semaglutide%'
     or coalesce(drug_source_value,'') ilike '%liraglutide%'
     or coalesce(drug_source_value,'') ilike '%dulaglutide%'
     or coalesce(drug_source_value,'') ilike '%exenatide%'
     or coalesce(drug_source_value,'') ilike '%tirzepatide%'
     or coalesce(drug_source_value,'') ilike '%insulin%'
 ),
 all_hits as (
  select person_id, min(dx_date) as index_date, 'RULE1_TWO_DX' as rule_hit
  from (select distinct person_id, dx_date from t2dm_dx) s
  group by person_id
  having count(*) filter (where dx_date is not null) >= 2
  union all
  select t.person_id, least(min(t.dx_date), min(r.rx_date)) as index_date, 'RULE2_DX_PLUS_RX' as rule_hit
  from t2dm_dx t join any_antihyperglycemic r on r.person_id = t.person_id
  group by t.person_id
  union all
  select person_id, min(lab_date) as index_date, 'RULE3_TWO_ABNL_LABS' as rule_hit
  from (select distinct person_id, lab_date from abnl_labs) s
  group by person_id
  having count(*) >= 2
  union all
  select l.person_id, least(min(l.lab_date), min(r.rx_date)) as index_date, 'RULE4_LAB_PLUS_RX' as rule_hit
  from abnl_labs l join any_antihyperglycemic r on r.person_id = l.person_id
  group by l.person_id
 ),
 first_hit as (
  select person_id, min(index_date) as index_date
  from all_hits
  group by person_id
 ),
 person_birth as (
  select person_id,
         coalesce(try_cast(birth_datetime as date), make_date(year_of_birth, coalesce(month_of_birth,1), coalesce(day_of_birth,1))) as birth_date
  from memory.person
 ),
 age_ok as (
  select fh.person_id, fh.index_date
  from first_hit fh
  join person_birth p on p.person_id = fh.person_id
  where p.birth_date is not null and date_diff('year', p.birth_date, fh.index_date) >= 18
 ),
 exclude_people as (select distinct person_id from exclude_dx),
 final_cases as (
  select ah.person_id, ah.index_date,
         string_agg(h.rule_hit, ' | ' order by h.rule_hit) as rules_met
  from age_ok ah
  join all_hits h on h.person_id = ah.person_id
   and h.index_date = (select min(index_date) from all_hits h2 where h2.person_id = ah.person_id)
  where ah.person_id not in (select person_id from exclude_people)
  group by ah.person_id, ah.index_date
 )
select * from final_cases;
