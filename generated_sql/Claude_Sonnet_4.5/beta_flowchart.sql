-- Flowchart for Claude_beta_shire.sql (Output B only)

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

dx as (
  select distinct cast(co.person_id as varchar) as person_id
  from condition_occurrence co
  where
    co.condition_source_value ilike 'E11%'
    or co.condition_source_value in (
      '250.00','250.02','250.10','250.12','250.20','250.22','250.30','250.32','250.40','250.42',
      '250.50','250.52','250.60','250.62','250.70','250.72','250.80','250.82','250.90','250.92'
    )
),

dx_ge2dates as (
  select cast(co.person_id as varchar) as person_id
  from condition_occurrence co
  where
    co.condition_source_value ilike 'E11%'
    or co.condition_source_value in (
      '250.00','250.02','250.10','250.12','250.20','250.22','250.30','250.32','250.40','250.42',
      '250.50','250.52','250.60','250.62','250.70','250.72','250.80','250.82','250.90','250.92'
    )
  group by cast(co.person_id as varchar)
  having count(distinct try_cast(co.condition_start_date as date)) >= 2
),

med as (
  select distinct cast(de.person_id as varchar) as person_id
  from drug_exposure de
  where
    de.drug_source_value ilike '%metformin%'
    or de.drug_source_value ilike '%glucophage%'
    or de.drug_source_value ilike '%fortamet%'
    or de.drug_source_value ilike '%glumetza%'
    or de.drug_source_value ilike '%riomet%'
    or de.drug_source_value ilike '%glipizide%'
    or de.drug_source_value ilike '%glucotrol%'
    or de.drug_source_value ilike '%glyburide%'
    or de.drug_source_value ilike '%diabeta%'
    or de.drug_source_value ilike '%micronase%'
    or de.drug_source_value ilike '%glimepiride%'
    or de.drug_source_value ilike '%amaryl%'
    or de.drug_source_value ilike '%gliclazide%'
    or de.drug_source_value ilike '%sitagliptin%'
    or de.drug_source_value ilike '%januvia%'
    or de.drug_source_value ilike '%saxagliptin%'
    or de.drug_source_value ilike '%onglyza%'
    or de.drug_source_value ilike '%linagliptin%'
    or de.drug_source_value ilike '%tradjenta%'
    or de.drug_source_value ilike '%alogliptin%'
    or de.drug_source_value ilike '%nesina%'
    or de.drug_source_value ilike '%exenatide%'
    or de.drug_source_value ilike '%byetta%'
    or de.drug_source_value ilike '%bydureon%'
    or de.drug_source_value ilike '%liraglutide%'
    or de.drug_source_value ilike '%victoza%'
    or de.drug_source_value ilike '%saxenda%'
    or de.drug_source_value ilike '%dulaglutide%'
    or de.drug_source_value ilike '%trulicity%'
    or de.drug_source_value ilike '%semaglutide%'
    or de.drug_source_value ilike '%ozempic%'
    or de.drug_source_value ilike '%wegovy%'
    or de.drug_source_value ilike '%rybelsus%'
    or de.drug_source_value ilike '%canagliflozin%'
    or de.drug_source_value ilike '%invokana%'
    or de.drug_source_value ilike '%dapagliflozin%'
    or de.drug_source_value ilike '%farxiga%'
    or de.drug_source_value ilike '%empagliflozin%'
    or de.drug_source_value ilike '%jardiance%'
    or de.drug_source_value ilike '%ertugliflozin%'
    or de.drug_source_value ilike '%steglatro%'
    or de.drug_source_value ilike '%pioglitazone%'
    or de.drug_source_value ilike '%actos%'
    or de.drug_source_value ilike '%rosiglitazone%'
    or de.drug_source_value ilike '%avandia%'
    or de.drug_source_value ilike '%repaglinide%'
    or de.drug_source_value ilike '%prandin%'
    or de.drug_source_value ilike '%nateglinide%'
    or de.drug_source_value ilike '%starlix%'
    or de.drug_source_value ilike '%acarbose%'
    or de.drug_source_value ilike '%precose%'
    or de.drug_source_value ilike '%miglitol%'
    or de.drug_source_value ilike '%glyset%'
),

lab as (
  select distinct cast(m.person_id as varchar) as person_id
  from measurement m
  where
    value_as_number is not null
    and (
      (
        (
          m.measurement_source_value ilike '%hemoglobin%a1c%'
          or m.measurement_source_value ilike '%hba1c%'
          or m.measurement_source_value ilike '%glycohemoglobin%'
          or m.measurement_source_value ilike '%glycated hemoglobin%'
          or m.measurement_source_value ilike '%a1c%'
        )
        and m.value_as_number >= 6.5
      )
      or (
        (
          m.measurement_source_value ilike '%fasting glucose%'
          or m.measurement_source_value ilike '%fasting blood glucose%'
          or m.measurement_source_value ilike '%fasting plasma glucose%'
        )
        and m.value_as_number >= 126
      )
      or (
        (
          m.measurement_source_value ilike '%glucose%'
          and m.measurement_source_value not ilike '%fasting%'
          and (
            m.measurement_source_value ilike '%2 hour%'
            or m.measurement_source_value ilike '%2-hour%'
            or m.measurement_source_value ilike '%ogtt%'
            or m.measurement_source_value ilike '%oral glucose tolerance%'
          )
        )
        and m.value_as_number >= 200
      )
    )
),

criterion1 as (select person_id from dx_ge2dates),
criterion2 as (select distinct dx.person_id from dx inner join med on med.person_id = dx.person_id),
criterion3 as (select distinct dx.person_id from dx inner join lab on lab.person_id = dx.person_id),
criterion4 as (select distinct med.person_id from med inner join lab on lab.person_id = med.person_id),

pre_excl_final as (
  select distinct person_id from (
    select person_id from criterion1
    union all select person_id from criterion2
    union all select person_id from criterion3
    union all select person_id from criterion4
  )
),

t1_excl as (
  select distinct cast(co.person_id as varchar) as person_id
  from condition_occurrence co
  where co.condition_source_value ilike 'E10%'
     or co.condition_source_value in (
       '250.01','250.03','250.11','250.13','250.21','250.23','250.31','250.33','250.41','250.43',
       '250.51','250.53','250.61','250.63','250.71','250.73','250.81','250.83','250.91','250.93'
     )
),

gest_excl as (
  select distinct cast(co.person_id as varchar) as person_id
  from condition_occurrence co
  where co.condition_source_value ilike 'O24%'
     or co.condition_source_value ilike '648.8%'
),

sec_excl as (
  select distinct cast(co.person_id as varchar) as person_id
  from condition_occurrence co
  where co.condition_source_value ilike 'E08%'
     or co.condition_source_value ilike 'E09%'
     or co.condition_source_value ilike 'E13%'
),

final as (
  select p.person_id
  from pre_excl_final p
  left join t1_excl t1 on t1.person_id = p.person_id
  left join gest_excl g on g.person_id = p.person_id
  left join sec_excl s on s.person_id = p.person_id
  where t1.person_id is null and g.person_id is null and s.person_id is null
),

dropped_t1 as (
  select 'Dropped: T1 exclusion' as step, p.person_id
  from pre_excl_final p inner join t1_excl t1 on t1.person_id = p.person_id
),
dropped_gest as (
  select 'Dropped: Gestational exclusion' as step, p.person_id
  from pre_excl_final p inner join gest_excl g on g.person_id = p.person_id
),
dropped_sec as (
  select 'Dropped: Secondary exclusion' as step, p.person_id
  from pre_excl_final p inner join sec_excl s on s.person_id = p.person_id
),

new_crit2_only as (
  select 'New via C2 only (dx+med)' as step, c2.person_id
  from criterion2 c2
  left join criterion1 c1 on c1.person_id = c2.person_id
  left join criterion3 c3 on c3.person_id = c2.person_id
  where c1.person_id is null and c3.person_id is null
),
new_crit3_only as (
  select 'New via C3 only (dx+lab)' as step, c3.person_id
  from criterion3 c3
  left join criterion1 c1 on c1.person_id = c3.person_id
  left join criterion2 c2 on c2.person_id = c3.person_id
  where c1.person_id is null and c2.person_id is null
),
new_crit4_only as (
  select 'New via C4 only (med+lab)' as step, c4.person_id
  from criterion4 c4
  left join criterion1 c1 on c1.person_id = c4.person_id
  left join criterion2 c2 on c2.person_id = c4.person_id
  left join criterion3 c3 on c3.person_id = c4.person_id
  where c1.person_id is null and c2.person_id is null and c3.person_id is null
),

step_sets as (
  select 'Step 0: dx(any)' as step, person_id from dx
  union all select 'Step 1: med(any)' as step, person_id from med
  union all select 'Step 2: lab(any)' as step, person_id from lab
  union all select 'Step 3: Criterion1 (>=2 dx dates)' as step, person_id from criterion1
  union all select 'Step 4: Criterion2 (dx+med)' as step, person_id from criterion2
  union all select 'Step 5: Criterion3 (dx+lab)' as step, person_id from criterion3
  union all select 'Step 6: Criterion4 (med+lab)' as step, person_id from criterion4
  union all select 'Step 7: Pre-exclusion union' as step, person_id from pre_excl_final
  union all select 'Step 8: T1 excl set' as step, person_id from t1_excl
  union all select 'Step 9: Gest excl set' as step, person_id from gest_excl
  union all select 'Step 10: Sec excl set' as step, person_id from sec_excl
  union all select 'Step 11: Final' as step, person_id from final
),

report_rows as (
  select step, person_id from step_sets
  union all select step, person_id from dropped_t1
  union all select step, person_id from dropped_gest
  union all select step, person_id from dropped_sec
  union all select step, person_id from new_crit2_only
  union all select step, person_id from new_crit3_only
  union all select step, person_id from new_crit4_only
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
    when 'Step 0: dx(any)' then 0
    when 'Step 1: med(any)' then 1
    when 'Step 2: lab(any)' then 2
    when 'Step 3: Criterion1 (>=2 dx dates)' then 3
    when 'Step 4: Criterion2 (dx+med)' then 4
    when 'New via C2 only (dx+med)' then 5
    when 'Step 5: Criterion3 (dx+lab)' then 6
    when 'New via C3 only (dx+lab)' then 7
    when 'Step 6: Criterion4 (med+lab)' then 8
    when 'New via C4 only (med+lab)' then 9
    when 'Step 7: Pre-exclusion union' then 10
    when 'Step 8: T1 excl set' then 11
    when 'Dropped: T1 exclusion' then 12
    when 'Step 9: Gest excl set' then 13
    when 'Dropped: Gestational exclusion' then 14
    when 'Step 10: Sec excl set' then 15
    when 'Dropped: Secondary exclusion' then 16
    when 'Step 11: Final' then 17
    else 99
  end