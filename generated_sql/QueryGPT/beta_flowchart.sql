-- Flowchart for QueryGPT_beta_shire.sql (Output B only)
-- Focus: evidence arms -> index_date -> OP inclusion -> exclusion drops -> adult gate

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

/* Arm 1: >=2 dx dates */
arm1_dx_ge2 as (
  select cast(d2.person_id as varchar) as person_id, min(d2.dx_date) as index_date
  from (
    select distinct
      co.person_id,
      try_cast(co.condition_start_date as date) as dx_date
    from condition_occurrence co
    where co.condition_source_value ilike 'E11%'
       or co.condition_source_value in (
         '250.00','250.02','250.10','250.12','250.20','250.22',
         '250.30','250.32','250.40','250.42','250.50','250.52',
         '250.60','250.62','250.70','250.72','250.80','250.82',
         '250.90','250.92'
       )
  ) d2
  group by cast(d2.person_id as varchar)
  having count(*) >= 2
),

/* Arm 2: dx + non-insulin drug within +/-365d */
arm2_dx_rx as (
  select cast(d.person_id as varchar) as person_id, min(least(d.dx_date, rx.rx_date)) as index_date
  from (
    select distinct
      co.person_id,
      try_cast(co.condition_start_date as date) as dx_date
    from condition_occurrence co
    where co.condition_source_value ilike 'E11%'
       or co.condition_source_value in (
         '250.00','250.02','250.10','250.12','250.20','250.22',
         '250.30','250.32','250.40','250.42','250.50','250.52',
         '250.60','250.62','250.70','250.72','250.80','250.82',
         '250.90','250.92'
       )
  ) d
  join (
    select
      de.person_id,
      try_cast(coalesce(de.drug_exposure_start_date, de.drug_exposure_start_datetime) as date) as rx_date
    from drug_exposure de
    where (
        de.drug_source_value ilike '%metformin%'
        or de.drug_source_value ilike '%glipizide%'
        or de.drug_source_value ilike '%glyburide%'
        or de.drug_source_value ilike '%glimepiride%'
        or de.drug_source_value ilike '%repaglinide%'
        or de.drug_source_value ilike '%nateglinide%'
        or de.drug_source_value ilike '%pioglitazone%'
        or de.drug_source_value ilike '%rosiglitazone%'
        or de.drug_source_value ilike '%sitagliptin%'
        or de.drug_source_value ilike '%saxagliptin%'
        or de.drug_source_value ilike '%linagliptin%'
        or de.drug_source_value ilike '%alogliptin%'
        or de.drug_source_value ilike '%exenatide%'
        or de.drug_source_value ilike '%liraglutide%'
        or de.drug_source_value ilike '%semaglutide%'
        or de.drug_source_value ilike '%dulaglutide%'
        or de.drug_source_value ilike '%lixisenatide%'
        or de.drug_source_value ilike '%tirzepatide%'
        or de.drug_source_value ilike '%canagliflozin%'
        or de.drug_source_value ilike '%dapagliflozin%'
        or de.drug_source_value ilike '%empagliflozin%'
        or de.drug_source_value ilike '%ertugliflozin%'
        or de.drug_source_value ilike '%acarbose%'
        or de.drug_source_value ilike '%miglitol%'
        or de.drug_source_value ilike '%glucophage%'
        or de.drug_source_value ilike '%glumetza%'
        or de.drug_source_value ilike '%riomet%'
        or de.drug_source_value ilike '%fortamet%'
        or de.drug_source_value ilike '%glucotrol%'
        or de.drug_source_value ilike '%diabeta%'
        or de.drug_source_value ilike '%micronase%'
        or de.drug_source_value ilike '%glynase%'
        or de.drug_source_value ilike '%amaryl%'
        or de.drug_source_value ilike '%actos%'
        or de.drug_source_value ilike '%avandia%'
        or de.drug_source_value ilike '%januvia%'
        or de.drug_source_value ilike '%onglyza%'
        or de.drug_source_value ilike '%tradjenta%'
        or de.drug_source_value ilike '%nesina%'
        or de.drug_source_value ilike '%byetta%'
        or de.drug_source_value ilike '%bydureon%'
        or de.drug_source_value ilike '%victoza%'
        or de.drug_source_value ilike '%ozempic%'
        or de.drug_source_value ilike '%rybelsus%'
        or de.drug_source_value ilike '%trulicity%'
        or de.drug_source_value ilike '%adlyxin%'
        or de.drug_source_value ilike '%mounjaro%'
        or de.drug_source_value ilike '%invokana%'
        or de.drug_source_value ilike '%farxiga%'
        or de.drug_source_value ilike '%jardiance%'
        or de.drug_source_value ilike '%steglatro%'
      )
      and de.drug_source_value not ilike '%insulin%'
  ) rx
    on rx.person_id = d.person_id
   and rx.rx_date between d.dx_date - interval 365 day and d.dx_date + interval 365 day
  group by cast(d.person_id as varchar)
),

/* Arm 3: >=2 positive labs on distinct dates */
arm3_lab_ge2 as (
  select cast(l.person_id as varchar) as person_id, min(l.lab_date) as index_date
  from (
    select
      m.person_id,
      try_cast(m.measurement_date as date) as lab_date
    from measurement m
    where m.value_as_number is not null
      and (
        ((m.measurement_source_value ilike '%hemoglobin a1c%' or m.measurement_source_value ilike '%hba1c%' or m.measurement_source_value ilike '%a1c%')
          and m.value_as_number >= 6.5)
        or (m.measurement_source_value ilike '%glucose%' and m.measurement_source_value ilike '%fast%' and m.value_as_number >= 126)
        or (m.measurement_source_value ilike '%glucose%' and (m.measurement_source_value ilike '%tolerance%' or m.measurement_source_value ilike '%2 hour%' or m.measurement_source_value ilike '%2-hour%' or m.measurement_source_value ilike '%ogtt%')
            and m.value_as_number >= 200)
        or (m.measurement_source_value ilike '%glucose%' and m.measurement_source_value not ilike '%fast%' and m.measurement_source_value not ilike '%tolerance%'
            and m.measurement_source_value not ilike '%2 hour%' and m.measurement_source_value not ilike '%2-hour%'
            and m.value_as_number >= 200)
      )
  ) l
  group by cast(l.person_id as varchar)
  having count(distinct l.lab_date) >= 2
),

/* Arm 4: lab + non-insulin drug within +/-365d */
arm4_lab_rx as (
  select cast(l.person_id as varchar) as person_id, min(least(l.lab_date, rx.rx_date)) as index_date
  from (
    select
      m.person_id,
      try_cast(m.measurement_date as date) as lab_date
    from measurement m
    where m.value_as_number is not null
      and (
        ((m.measurement_source_value ilike '%hemoglobin a1c%' or m.measurement_source_value ilike '%hba1c%' or m.measurement_source_value ilike '%a1c%')
          and m.value_as_number >= 6.5)
        or (m.measurement_source_value ilike '%glucose%' and m.measurement_source_value ilike '%fast%' and m.value_as_number >= 126)
        or (m.measurement_source_value ilike '%glucose%' and (m.measurement_source_value ilike '%tolerance%' or m.measurement_source_value ilike '%2 hour%' or m.measurement_source_value ilike '%2-hour%' or m.measurement_source_value ilike '%ogtt%')
            and m.value_as_number >= 200)
        or (m.measurement_source_value ilike '%glucose%' and m.measurement_source_value not ilike '%fast%' and m.measurement_source_value not ilike '%tolerance%'
            and m.measurement_source_value not ilike '%2 hour%' and m.measurement_source_value not ilike '%2-hour%'
            and m.value_as_number >= 200)
      )
  ) l
  join (
    select
      de.person_id,
      try_cast(coalesce(de.drug_exposure_start_date, de.drug_exposure_start_datetime) as date) as rx_date
    from drug_exposure de
    where (
        de.drug_source_value ilike '%metformin%'
        or de.drug_source_value ilike '%glipizide%'
        or de.drug_source_value ilike '%glyburide%'
        or de.drug_source_value ilike '%glimepiride%'
        or de.drug_source_value ilike '%repaglinide%'
        or de.drug_source_value ilike '%nateglinide%'
        or de.drug_source_value ilike '%pioglitazone%'
        or de.drug_source_value ilike '%rosiglitazone%'
        or de.drug_source_value ilike '%sitagliptin%'
        or de.drug_source_value ilike '%saxagliptin%'
        or de.drug_source_value ilike '%linagliptin%'
        or de.drug_source_value ilike '%alogliptin%'
        or de.drug_source_value ilike '%exenatide%'
        or de.drug_source_value ilike '%liraglutide%'
        or de.drug_source_value ilike '%semaglutide%'
        or de.drug_source_value ilike '%dulaglutide%'
        or de.drug_source_value ilike '%lixisenatide%'
        or de.drug_source_value ilike '%tirzepatide%'
        or de.drug_source_value ilike '%canagliflozin%'
        or de.drug_source_value ilike '%dapagliflozin%'
        or de.drug_source_value ilike '%empagliflozin%'
        or de.drug_source_value ilike '%ertugliflozin%'
        or de.drug_source_value ilike '%acarbose%'
        or de.drug_source_value ilike '%miglitol%'
        or de.drug_source_value ilike '%glucophage%'
        or de.drug_source_value ilike '%glumetza%'
        or de.drug_source_value ilike '%riomet%'
        or de.drug_source_value ilike '%fortamet%'
        or de.drug_source_value ilike '%glucotrol%'
        or de.drug_source_value ilike '%diabeta%'
        or de.drug_source_value ilike '%micronase%'
        or de.drug_source_value ilike '%glynase%'
        or de.drug_source_value ilike '%amaryl%'
        or de.drug_source_value ilike '%actos%'
        or de.drug_source_value ilike '%avandia%'
        or de.drug_source_value ilike '%januvia%'
        or de.drug_source_value ilike '%onglyza%'
        or de.drug_source_value ilike '%tradjenta%'
        or de.drug_source_value ilike '%nesina%'
        or de.drug_source_value ilike '%byetta%'
        or de.drug_source_value ilike '%bydureon%'
        or de.drug_source_value ilike '%victoza%'
        or de.drug_source_value ilike '%ozempic%'
        or de.drug_source_value ilike '%rybelsus%'
        or de.drug_source_value ilike '%trulicity%'
        or de.drug_source_value ilike '%adlyxin%'
        or de.drug_source_value ilike '%mounjaro%'
        or de.drug_source_value ilike '%invokana%'
        or de.drug_source_value ilike '%farxiga%'
        or de.drug_source_value ilike '%jardiance%'
        or de.drug_source_value ilike '%steglatro%'
      )
      and de.drug_source_value not ilike '%insulin%'
  ) rx
    on rx.person_id = l.person_id
   and rx.rx_date between l.lab_date - interval 365 day and l.lab_date + interval 365 day
  group by cast(l.person_id as varchar)
),

z_raw as (
  select person_id, index_date, 'Arm1_dx_ge2' as arm from arm1_dx_ge2
  union all select person_id, index_date, 'Arm2_dx+rx' as arm from arm2_dx_rx
  union all select person_id, index_date, 'Arm3_lab_ge2' as arm from arm3_lab_ge2
  union all select person_id, index_date, 'Arm4_lab+rx' as arm from arm4_lab_rx
),

z as (
  select person_id, min(index_date) as index_date
  from z_raw
  group by person_id
),

op as (
  select
    cast(person_id as varchar) as person_id,
    min(try_cast(visit_start_date as date)) as op_start,
    max(try_cast(coalesce(visit_end_date, visit_start_date) as date)) as op_end
  from visit_occurrence
  group by cast(person_id as varchar)
),

in_op as (
  select z.person_id
  from z
  join op on op.person_id = z.person_id
        and z.index_date between op.op_start and op.op_end
),

t1 as (
  select distinct cast(co.person_id as varchar) as person_id, try_cast(co.condition_start_date as date) as t1_date
  from condition_occurrence co
  where co.condition_source_value ilike 'E10%'
     or co.condition_source_value in (
       '250.01','250.03','250.11','250.13','250.21','250.23',
       '250.31','250.33','250.41','250.43','250.51','250.53',
       '250.61','250.63','250.71','250.73','250.81','250.83',
       '250.91','250.93'
     )
),

gdm as (
  select distinct cast(co.person_id as varchar) as person_id, try_cast(co.condition_start_date as date) as gdm_date
  from condition_occurrence co
  where co.condition_source_value ilike 'O24.4%'
     or co.condition_source_value ilike '648.8%'
),

sec as (
  select distinct cast(co.person_id as varchar) as person_id, try_cast(co.condition_start_date as date) as sec_date
  from condition_occurrence co
  where co.condition_source_value ilike 'E08%'
     or co.condition_source_value ilike 'E09%'
     or co.condition_source_value ilike 'E13%'
     or co.condition_source_value ilike '249%'
),

adult_pass as (
  select z.person_id
  from z
  join person p on p.person_id = try_cast(z.person_id as bigint)
  where (
    extract(year from z.index_date) - p.year_of_birth
    - case
        when strftime(z.index_date, '%m%d')
             < lpad(cast(coalesce(p.month_of_birth, 1) as varchar), 2, '0')
               || lpad(cast(coalesce(p.day_of_birth, 1) as varchar), 2, '0')
        then 1 else 0
      end
  ) >= 18
),

final as (
  select z.person_id
  from z
  join in_op io on io.person_id = z.person_id
  join adult_pass a on a.person_id = z.person_id
  left join t1 on t1.person_id = z.person_id and t1.t1_date <= z.index_date
  left join gdm on gdm.person_id = z.person_id and gdm.gdm_date <= z.index_date
  left join sec on sec.person_id = z.person_id and sec.sec_date <= z.index_date
  where t1.person_id is null and gdm.person_id is null and sec.person_id is null
),

dropped_not_in_op as (
  select 'Dropped: index_date not in visit-based OP' as step, z.person_id
  from z
  left join in_op io on io.person_id = z.person_id
  where io.person_id is null
),
dropped_not_adult as (
  select 'Dropped: age < 18 at index' as step, z.person_id
  from z
  left join adult_pass a on a.person_id = z.person_id
  where a.person_id is null
),
dropped_t1 as (
  select 'Dropped: T1 excl (on/before index)' as step, z.person_id
  from z
  inner join t1 on t1.person_id = z.person_id and t1.t1_date <= z.index_date
),
dropped_gdm as (
  select 'Dropped: Gestational excl (on/before index)' as step, z.person_id
  from z
  inner join gdm on gdm.person_id = z.person_id and gdm.gdm_date <= z.index_date
),
dropped_sec as (
  select 'Dropped: Secondary excl (on/before index)' as step, z.person_id
  from z
  inner join sec on sec.person_id = z.person_id and sec.sec_date <= z.index_date
),

new_arm2_only as (
  select 'New: Arm2 only (dx+rx)' as step, a2.person_id
  from arm2_dx_rx a2
  left join arm1_dx_ge2 a1 on a1.person_id = a2.person_id
  left join arm3_lab_ge2 a3 on a3.person_id = a2.person_id
  where a1.person_id is null and a3.person_id is null
),
new_arm3_only as (
  select 'New: Arm3 only (lab>=2)' as step, a3.person_id
  from arm3_lab_ge2 a3
  left join arm1_dx_ge2 a1 on a1.person_id = a3.person_id
  left join arm2_dx_rx a2 on a2.person_id = a3.person_id
  where a1.person_id is null and a2.person_id is null
),
new_arm4_only as (
  select 'New: Arm4 only (lab+rx)' as step, a4.person_id
  from arm4_lab_rx a4
  left join arm1_dx_ge2 a1 on a1.person_id = a4.person_id
  left join arm2_dx_rx a2 on a2.person_id = a4.person_id
  left join arm3_lab_ge2 a3 on a3.person_id = a4.person_id
  where a1.person_id is null and a2.person_id is null and a3.person_id is null
),

step_sets as (
  select 'Step 0: Arm1 dx>=2' as step, person_id from arm1_dx_ge2
  union all select 'Step 1: Arm2 dx+rx' as step, person_id from arm2_dx_rx
  union all select 'Step 2: Arm3 lab>=2' as step, person_id from arm3_lab_ge2
  union all select 'Step 3: Arm4 lab+rx' as step, person_id from arm4_lab_rx
  union all select 'Step 4: z (any arm, earliest index)' as step, person_id from z
  union all select 'Step 5: in OP (index within visit span)' as step, person_id from in_op
  union all select 'Step 6: adult pass' as step, person_id from adult_pass
  union all select 'Step 7: final' as step, person_id from final
),

report_rows as (
  select step, person_id from step_sets
  union all select step, person_id from new_arm2_only
  union all select step, person_id from new_arm3_only
  union all select step, person_id from new_arm4_only
  union all select step, person_id from dropped_not_in_op
  union all select step, person_id from dropped_not_adult
  union all select step, person_id from dropped_t1
  union all select step, person_id from dropped_gdm
  union all select step, person_id from dropped_sec
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
    when 'Step 0: Arm1 dx>=2' then 0
    when 'Step 1: Arm2 dx+rx' then 1
    when 'New: Arm2 only (dx+rx)' then 2
    when 'Step 2: Arm3 lab>=2' then 3
    when 'New: Arm3 only (lab>=2)' then 4
    when 'Step 3: Arm4 lab+rx' then 5
    when 'New: Arm4 only (lab+rx)' then 6
    when 'Step 4: z (any arm, earliest index)' then 7
    when 'Step 5: in OP (index within visit span)' then 8
    when 'Dropped: index_date not in visit-based OP' then 9
    when 'Step 6: adult pass' then 10
    when 'Dropped: age < 18 at index' then 11
    when 'Dropped: T1 excl (on/before index)' then 12
    when 'Dropped: Gestational excl (on/before index)' then 13
    when 'Dropped: Secondary excl (on/before index)' then 14
    when 'Step 7: final' then 15
    else 99
  end