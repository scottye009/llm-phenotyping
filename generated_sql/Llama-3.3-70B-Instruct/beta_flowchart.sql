-- Flowchart for Llama_beta_shire.sql (Output B only)

with
labels as (
  select cast(person_id as varchar) as person_id, 1 as cohort_label, 'Cohort 1 (T2D)' as cohort_name
  from read_csv_auto('Cohort_1/person.csv')
  union all
  select cast(person_id as varchar) as person_id, 2 as cohort_label, 'Cohort 2 (Other DM)' as cohort_name
  from read_csv_auto('Cohort_2/person.csv')
  union all
  select cast(person_id as varchar) as person_id, 3 as cohort_label, 'Cohort 3 (Control)' as cohort_name
  from read_csv_auto('Cohort_3/person.csv')
),

dx_t2 as (
  select distinct cast(co.person_id as varchar) as person_id
  from condition_occurrence co
  where
    (co.condition_source_value like '250.%'
     and co.condition_source_value not in (
       '250.01','250.03','250.11','250.13','250.21','250.23',
       '250.31','250.33','250.41','250.43','250.51','250.53',
       '250.61','250.63','250.71','250.73','250.81','250.83',
       '250.91','250.93'
     ))
    or co.condition_source_value ilike 'E11%'
),

lab_pos as (
  select distinct cast(m.person_id as varchar) as person_id
  from measurement m
  where
    (
      (
        (m.measurement_source_value ilike '%hemoglobin a1c%' or m.measurement_source_value ilike '%hba1c%' or m.measurement_source_value ilike '%a1c%')
        and m.value_as_number > 6.5
      )
      or ((m.measurement_source_value ilike '%fasting%glucose%') and m.value_as_number > 126)
      or ((m.measurement_source_value ilike '%2-hour%plasma%glucose%' or m.measurement_source_value ilike '%2 hour%plasma%glucose%' or m.measurement_source_value ilike '%ogtt%' or m.measurement_source_value ilike '%oral glucose tolerance%')
          and m.value_as_number > 200)
    )
),

med_pos as (
  select distinct cast(de.person_id as varchar) as person_id
  from drug_exposure de
  where
    de.drug_source_value ilike '%metformin%'
    or de.drug_source_value ilike '%glipizide%'
    or de.drug_source_value ilike '%glimepiride%'
    or de.drug_source_value ilike '%pioglitazone%'
    or de.drug_source_value ilike '%sitagliptin%'
    or de.drug_source_value ilike '%januvia%'
    or de.drug_source_value ilike '%metformin hydrochloride%'
    or de.drug_source_value ilike '%glipizide%extended release%'
),

included_any as (
  select person_id from dx_t2
  union
  select person_id from lab_pos
  union
  select person_id from med_pos
),

t1_excl as (
  select distinct cast(co.person_id as varchar) as person_id
  from condition_occurrence co
  where
    co.condition_source_value in (
      '250.01','250.03','250.11','250.13','250.21','250.23',
      '250.31','250.33','250.41','250.43','250.51','250.53',
      '250.61','250.63','250.71','250.73','250.81','250.83',
      '250.91','250.93'
    )
    or co.condition_source_value ilike 'E10%'
),

insulin_only_excl as (
  select cast(de.person_id as varchar) as person_id
  from drug_exposure de
  where de.drug_source_value ilike '%insulin%'
  group by cast(de.person_id as varchar)
  having
    max(case when de.drug_source_value not ilike '%insulin%' then 1 else 0 end) = 0
),

final as (
  select i.person_id
  from included_any i
  left join t1_excl t1 on t1.person_id = i.person_id
  left join insulin_only_excl io on io.person_id = i.person_id
  where t1.person_id is null and io.person_id is null
),

new_lab_only_vs_dx as (
  select 'New: lab-only (not in dx)' as step, l.person_id
  from lab_pos l
  left join dx_t2 d on d.person_id = l.person_id
  where d.person_id is null
),
new_med_only_vs_dx_lab as (
  select 'New: med-only (not in dx or lab)' as step, m.person_id
  from med_pos m
  left join dx_t2 d on d.person_id = m.person_id
  left join lab_pos l on l.person_id = m.person_id
  where d.person_id is null and l.person_id is null
),
dropped_t1 as (
  select 'Dropped: T1 exclusion' as step, i.person_id
  from included_any i inner join t1_excl t1 on t1.person_id = i.person_id
),
dropped_insulin_only as (
  select 'Dropped: insulin-only exclusion' as step, i.person_id
  from included_any i inner join insulin_only_excl io on io.person_id = i.person_id
),

step_sets as (
  select 'Step 1: dx_t2' as step, person_id from dx_t2
  union all select 'Step 2: lab_pos' as step, person_id from lab_pos
  union all select 'Step 3: med_pos' as step, person_id from med_pos
  union all select 'Step 4: included_any (union)' as step, person_id from included_any
  union all select 'Step 5: T1 excl set' as step, person_id from t1_excl
  union all select 'Step 6: insulin-only excl set' as step, person_id from insulin_only_excl
  union all select 'Step 7: final' as step, person_id from final
),

report_rows as (
  select step, person_id from step_sets
  union all select step, person_id from new_lab_only_vs_dx
  union all select step, person_id from new_med_only_vs_dx_lab
  union all select step, person_id from dropped_t1
  union all select step, person_id from dropped_insulin_only
)

select
  r.step,
  count(*) as n_total,
  sum(case when l.cohort_label = 1 then 1 else 0 end) as n_cohort1,
  sum(case when l.cohort_label = 2 then 1 else 0 end) as n_cohort2,
  sum(case when l.cohort_label = 3 then 1 else 0 end) as n_cohort3,
  sum(case when l.cohort_label is null then 1 else 0 end) as n_unlabeled,
  round(sum(case when l.cohort_label = 1 then 1 else 0 end)::double / nullif(count(*), 0), 4) as pct_cohort1,
  round(sum(case when l.cohort_label in (2,3) then 1 else 0 end)::double / nullif(count(*), 0), 4) as pct_cohort2_3
from report_rows r
left join labels l on l.person_id = r.person_id
group by r.step
order by
  case r.step
    when 'Step 1: dx_t2' then 1
    when 'Step 2: lab_pos' then 2
    when 'New: lab-only (not in dx)' then 3
    when 'Step 3: med_pos' then 4
    when 'New: med-only (not in dx or lab)' then 5
    when 'Step 4: included_any (union)' then 6
    when 'Step 5: T1 excl set' then 7
    when 'Dropped: T1 exclusion' then 8
    when 'Step 6: insulin-only excl set' then 9
    when 'Dropped: insulin-only exclusion' then 10
    when 'Step 7: final' then 11
    else 99
  end