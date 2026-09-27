-- SHIRE-adapted from alpha_n_1.sql
-- Same core logic: A or B or C or D, then exclude Type1 / Gestational / Secondary/Other.


with
dx_events as (
  select
    person_id,
    try_cast(condition_start_date as date) as event_date,
    visit_occurrence_id,
    case
      when (
  coalesce(condition_source_value,'') ilike 'E11%' or
  coalesce(condition_source_value,'') ilike '250%0' or
  coalesce(condition_source_value,'') ilike '250%2' or
  regexp_matches(replace(coalesce(condition_source_value,''),'.',''), '^250[0-9][02]$')
) then 'T2'
      when (
  coalesce(condition_source_value,'') ilike 'E10%' or
  coalesce(condition_source_value,'') ilike '250%1' or
  coalesce(condition_source_value,'') ilike '250%3' or
  regexp_matches(replace(coalesce(condition_source_value,''),'.',''), '^250[0-9][13]$')
) then 'T1'
      when (
  coalesce(condition_source_value,'') ilike 'O24%' or
  coalesce(condition_source_value,'') ilike '648.8%' or
  coalesce(condition_source_value,'') ilike '6488%'
) then 'GEST'
      when (
  coalesce(condition_source_value,'') ilike 'E08%' or
  coalesce(condition_source_value,'') ilike 'E09%' or
  coalesce(condition_source_value,'') ilike 'E13%' or
  coalesce(condition_source_value,'') ilike '249%'
) then 'SEC'
      else null
    end as dx_type
  from memory.condition_occurrence
  where try_cast(condition_start_date as date) is not null
),
t2_dx as (
  select person_id, event_date, visit_occurrence_id from dx_events where dx_type='T2'
),
t1_dx as (
  select distinct person_id from dx_events where dx_type='T1'
),
gest_dx as (
  select distinct person_id from dx_events where dx_type='GEST'
),
sec_dx as (
  select distinct person_id from dx_events where dx_type='SEC'
),
med_events as (
  select person_id, try_cast(drug_exposure_start_date as date) as event_date
  from memory.drug_exposure
  where try_cast(drug_exposure_start_date as date) is not null
    and (
  coalesce(drug_source_value,'') ilike '%metformin%' or
  coalesce(drug_source_value,'') ilike '%glucophage%' or
  coalesce(drug_source_value,'') ilike '%fortamet%' or
  coalesce(drug_source_value,'') ilike '%glumetza%' or
  coalesce(drug_source_value,'') ilike '%riomet%' or
  coalesce(drug_source_value,'') ilike '%glipizide%' or
  coalesce(drug_source_value,'') ilike '%glucotrol%' or
  coalesce(drug_source_value,'') ilike '%glyburide%' or
  coalesce(drug_source_value,'') ilike '%diabeta%' or
  coalesce(drug_source_value,'') ilike '%glynase%' or
  coalesce(drug_source_value,'') ilike '%glimepiride%' or
  coalesce(drug_source_value,'') ilike '%amaryl%' or
  coalesce(drug_source_value,'') ilike '%pioglitazone%' or
  coalesce(drug_source_value,'') ilike '%actos%' or
  coalesce(drug_source_value,'') ilike '%rosiglitazone%' or
  coalesce(drug_source_value,'') ilike '%avandia%' or
  coalesce(drug_source_value,'') ilike '%sitagliptin%' or
  coalesce(drug_source_value,'') ilike '%januvia%' or
  coalesce(drug_source_value,'') ilike '%saxagliptin%' or
  coalesce(drug_source_value,'') ilike '%onglyza%' or
  coalesce(drug_source_value,'') ilike '%linagliptin%' or
  coalesce(drug_source_value,'') ilike '%tradjenta%' or
  coalesce(drug_source_value,'') ilike '%alogliptin%' or
  coalesce(drug_source_value,'') ilike '%nesina%' or
  coalesce(drug_source_value,'') ilike '%liraglutide%' or
  coalesce(drug_source_value,'') ilike '%victoza%' or
  coalesce(drug_source_value,'') ilike '%semaglutide%' or
  coalesce(drug_source_value,'') ilike '%ozempic%' or
  coalesce(drug_source_value,'') ilike '%rybelsus%' or
  coalesce(drug_source_value,'') ilike '%dulaglutide%' or
  coalesce(drug_source_value,'') ilike '%trulicity%' or
  coalesce(drug_source_value,'') ilike '%exenatide%' or
  coalesce(drug_source_value,'') ilike '%byetta%' or
  coalesce(drug_source_value,'') ilike '%bydureon%' or
  coalesce(drug_source_value,'') ilike '%lixisenatide%' or
  coalesce(drug_source_value,'') ilike '%adlyxin%' or
  coalesce(drug_source_value,'') ilike '%tirzepatide%' or
  coalesce(drug_source_value,'') ilike '%mounjaro%' or
  coalesce(drug_source_value,'') ilike '%empagliflozin%' or
  coalesce(drug_source_value,'') ilike '%jardiance%' or
  coalesce(drug_source_value,'') ilike '%canagliflozin%' or
  coalesce(drug_source_value,'') ilike '%invokana%' or
  coalesce(drug_source_value,'') ilike '%dapagliflozin%' or
  coalesce(drug_source_value,'') ilike '%farxiga%' or
  coalesce(drug_source_value,'') ilike '%ertugliflozin%' or
  coalesce(drug_source_value,'') ilike '%steglatro%' or
  coalesce(drug_source_value,'') ilike '%repaglinide%' or
  coalesce(drug_source_value,'') ilike '%prandin%' or
  coalesce(drug_source_value,'') ilike '%nateglinide%' or
  coalesce(drug_source_value,'') ilike '%starlix%' or
  coalesce(drug_source_value,'') ilike '%acarbose%' or
  coalesce(drug_source_value,'') ilike '%precose%' or
  coalesce(drug_source_value,'') ilike '%miglitol%' or
  coalesce(drug_source_value,'') ilike '%glyset%' or
  coalesce(drug_source_value,'') ilike '%pramlintide%' or
  coalesce(drug_source_value,'') ilike '%symlin%' or
  coalesce(drug_source_value,'') ilike '%janumet%' or
  coalesce(drug_source_value,'') ilike '%synjardy%' or
  coalesce(drug_source_value,'') ilike '%xigduo%' or
  coalesce(drug_source_value,'') ilike '%glyxambi%' or
  coalesce(drug_source_value,'') ilike '%qtern%'
)
),
lab_events as (
  select person_id, try_cast(measurement_date as date) as event_date, case
  when coalesce(measurement_source_value,'') ilike '%a1c%' and value_as_number is not null
    and (((coalesce(unit_source_value,'') ilike '%mmol/mol%') and value_as_number >= 48) or value_as_number >= 6.5)
    then 'A1C'
  when coalesce(measurement_source_value,'') ilike '%glucose%' and coalesce(measurement_source_value,'') ilike '%fast%'
    and value_as_number is not null
    and (((coalesce(unit_source_value,'') ilike '%mmol/l%') and value_as_number >= 7.0) or value_as_number >= 126)
    then 'FPG'
  when (coalesce(measurement_source_value,'') ilike '%ogtt%' or coalesce(measurement_source_value,'') ilike '%tolerance%')
    and value_as_number is not null
    and (((coalesce(unit_source_value,'') ilike '%mmol/l%') and value_as_number >= 11.1) or value_as_number >= 200)
    then 'OGTT'
  when coalesce(measurement_source_value,'') ilike '%glucose%'
    and value_as_number is not null
    and (((coalesce(unit_source_value,'') ilike '%mmol/l%') and value_as_number >= 11.1) or value_as_number >= 200)
    then 'RPG'
  else null
end as lab_type
  from memory.measurement
  where try_cast(measurement_date as date) is not null
    and value_as_number is not null
),
abnl_labs as (
  select person_id, event_date, lab_type
  from lab_events
  where lab_type is not null
)
,
t2_rollup as (
  select person_id, count(distinct event_date) as dx_dates, min(event_date) as first_dx_date
  from t2_dx group by person_id
),
med_rollup as (
  select person_id, count(distinct event_date) as med_dates, min(event_date) as first_med_date
  from med_events group by person_id
),
lab_rollup as (
  select person_id, count(distinct event_date) as lab_dates, min(event_date) as first_lab_date
  from abnl_labs group by person_id
)
select
  p.person_id,
  least(
    coalesce(t.first_dx_date, date '9999-12-31'),
    coalesce(m.first_med_date, date '9999-12-31'),
    coalesce(l.first_lab_date, date '9999-12-31')
  ) as index_date
from memory.person p
left join t2_rollup t on p.person_id=t.person_id
left join med_rollup m on p.person_id=m.person_id
left join lab_rollup l on p.person_id=l.person_id
where (
    coalesce(t.dx_dates,0) >= 2 or
    (coalesce(t.dx_dates,0) >= 1 and coalesce(m.med_dates,0) >= 1) or
    (coalesce(t.dx_dates,0) >= 1 and coalesce(l.lab_dates,0) >= 1) or
    coalesce(l.lab_dates,0) >= 2
  )
  and not exists (select 1 from t1_dx x where x.person_id=p.person_id)
  and not exists (select 1 from gest_dx g where g.person_id=p.person_id)
  and not exists (select 1 from sec_dx s where s.person_id=p.person_id)
order by p.person_id;
