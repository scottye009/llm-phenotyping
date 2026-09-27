-- SHIRE-adapted from alpha_5.sql
-- Preserve visit-setting logic using visit_source_value on SHIRE.

with
dx_events as (
  select
    co.person_id,
    try_cast(co.condition_start_date as date) as dx_date,
    co.visit_occurrence_id
  from memory.condition_occurrence co
  where try_cast(co.condition_start_date as date) is not null
    and (
  coalesce(condition_source_value,'') ilike 'E11%' or
  coalesce(condition_source_value,'') ilike '250%0' or
  coalesce(condition_source_value,'') ilike '250%2' or
  regexp_matches(replace(coalesce(condition_source_value,''),'.',''), '^250[0-9][02]$')
)
),
t1_dx as (
  select distinct person_id
  from memory.condition_occurrence
  where (
  coalesce(condition_source_value,'') ilike 'E10%' or
  coalesce(condition_source_value,'') ilike '250%1' or
  coalesce(condition_source_value,'') ilike '250%3' or
  regexp_matches(replace(coalesce(condition_source_value,''),'.',''), '^250[0-9][13]$')
)
),
gest_dx as (
  select distinct person_id
  from memory.condition_occurrence
  where (
  coalesce(condition_source_value,'') ilike 'O24%' or
  coalesce(condition_source_value,'') ilike '648.8%' or
  coalesce(condition_source_value,'') ilike '6488%'
)
),
visit_labeled as (
  select
    visit_occurrence_id,
    person_id,
    coalesce(visit_source_value,'') as visit_source_value,
    case
      when coalesce(visit_source_value,'') ilike '%hospital%' or coalesce(visit_source_value,'') ilike '%inpatient%' then 1 else 0
    end as is_inpt_or_ed,
    case
      when coalesce(visit_source_value,'') ilike '%outpatient%' or coalesce(visit_source_value,'') ilike '%ambulatory%' or coalesce(visit_source_value,'') ilike '%ed%' or coalesce(visit_source_value,'') ilike '%emergency%' then 1 else 0
    end as is_outpatient
  from memory.visit_occurrence
),
dx_labeled as (
  select d.person_id, d.dx_date,
         coalesce(v.is_inpt_or_ed,0) as is_inpt_or_ed,
         coalesce(v.is_outpatient,1) as is_outpatient
  from dx_events d
  left join visit_labeled v
    on d.visit_occurrence_id=v.visit_occurrence_id
),
dx_evidence as (
  select person_id,
         count(distinct case when is_outpatient=1 then dx_date end) as n_outpt_dx_dates,
         max(is_inpt_or_ed) as has_inpt_or_ed_dx,
         min(dx_date) as first_dx_date
  from dx_labeled
  group by person_id
),
med_evidence as (
  select person_id, min(try_cast(drug_exposure_start_date as date)) as first_med_date
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
  group by person_id
),
lab_evidence as (
  select person_id,
         count(distinct try_cast(measurement_date as date)) as n_abnl_lab_dates,
         min(try_cast(measurement_date as date)) as first_lab_date
  from memory.measurement
  where try_cast(measurement_date as date) is not null
    and value_as_number is not null
    and (case
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
end) is not null
  group by person_id
),
combined as (
  select
    p.person_id,
    least(
      coalesce(d.first_dx_date, date '9999-12-31'),
      coalesce(m.first_med_date, date '9999-12-31'),
      coalesce(l.first_lab_date, date '9999-12-31')
    ) as index_date,
    coalesce(d.n_outpt_dx_dates,0) as n_outpt_dx_dates,
    coalesce(d.has_inpt_or_ed_dx,0) as has_inpt_or_ed_dx,
    case when m.person_id is not null then 1 else 0 end as has_med,
    coalesce(l.n_abnl_lab_dates,0) as n_abnl_lab_dates
  from memory.person p
  left join dx_evidence d on p.person_id=d.person_id
  left join med_evidence m on p.person_id=m.person_id
  left join lab_evidence l on p.person_id=l.person_id
)
select person_id, index_date
from combined c
where (
    (n_outpt_dx_dates >= 2 or has_inpt_or_ed_dx = 1) or
    ((n_outpt_dx_dates >= 1 or has_inpt_or_ed_dx = 1) and has_med = 1) or
    n_abnl_lab_dates >= 2
  )
  and not exists (select 1 from t1_dx t1 where t1.person_id=c.person_id)
  and not exists (select 1 from gest_dx g where g.person_id=c.person_id)
order by person_id;
