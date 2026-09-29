with t2dm_dx_dates as (
    select
        co.person_id,
        try_cast(co.condition_start_date as date) as cond_date,
        vo.visit_concept_id
    from memory.condition_occurrence co
    left join memory.visit_occurrence vo
        on vo.visit_occurrence_id = co.visit_occurrence_id
    where co.condition_source_value ilike 'E11%'
       or regexp_matches(co.condition_source_value, '^250\.[0-9]0$')
       or regexp_matches(co.condition_source_value, '^250\.[0-9]2$')
),
rule_a_inpatient as (
    select
        person_id,
        min(cond_date) as index_date
    from t2dm_dx_dates
    where visit_concept_id = 9201
    group by person_id
),
rule_a_outpatient_pairs as (
    select
        d1.person_id,
        d1.cond_date
    from (
        select person_id, cond_date
        from t2dm_dx_dates
        where visit_concept_id in (9202, 9203)
        group by person_id, cond_date
    ) d1
    join (
        select person_id, cond_date
        from t2dm_dx_dates
        where visit_concept_id in (9202, 9203)
        group by person_id, cond_date
    ) d2
        on d1.person_id = d2.person_id
       and d2.cond_date >= d1.cond_date + interval 30 day
),
rule_a as (
    select person_id, min(index_date) as index_date
    from (
        select person_id, index_date from rule_a_inpatient
        union all
        select person_id, min(cond_date) as index_date
        from rule_a_outpatient_pairs
        group by person_id
    ) x
    group by person_id
),
abnormal_labs as (
    select
        m.person_id,
        try_cast(m.measurement_date as date) as meas_date
    from memory.measurement m
    where m.value_as_number is not null
      and (
        (
            (
                m.measurement_source_value ilike '%4548-4%'
                or m.measurement_source_value ilike '%17856-6%'
                or m.measurement_source_value ilike '%41995-2%'
                or m.measurement_source_value ilike '%4549-2%'
                or m.measurement_source_value ilike '%a1c%'
                or m.measurement_source_value ilike '%hba1c%'
                or m.measurement_source_value ilike '%hemoglobin a1c%'
            )
            and (
                ((coalesce(m.unit_source_value, '') ilike '%percent%' or coalesce(m.unit_source_value, '') = '%') and m.value_as_number >= 6.5)
                or (coalesce(m.unit_source_value, '') ilike '%mmol/mol%' and m.value_as_number >= 48)
                or coalesce(m.unit_source_value, '') = '' and m.value_as_number >= 6.5
            )
        )
        or
        (
            (
                m.measurement_source_value ilike '%1558-6%'
                or m.measurement_source_value ilike '%14771-0%'
                or m.measurement_source_value ilike '%35217-9%'
                or m.measurement_source_value ilike '%fasting glucose%'
                or m.measurement_source_value ilike '%fpg%'
            )
            and (
                (coalesce(m.unit_source_value, '') ilike '%mg/dl%' and m.value_as_number >= 126)
                or (coalesce(m.unit_source_value, '') ilike '%mmol/l%' and m.value_as_number >= 7.0)
                or coalesce(m.unit_source_value, '') = '' and m.value_as_number >= 126
            )
        )
        or
        (
            (
                m.measurement_source_value ilike '%20436-2%'
                or m.measurement_source_value ilike '%1518-0%'
                or m.measurement_source_value ilike '%14763-7%'
                or m.measurement_source_value ilike '%ogtt%'
                or m.measurement_source_value ilike '%glucose tolerance%'
            )
            and (
                (coalesce(m.unit_source_value, '') ilike '%mg/dl%' and m.value_as_number >= 200)
                or (coalesce(m.unit_source_value, '') ilike '%mmol/l%' and m.value_as_number >= 11.1)
                or coalesce(m.unit_source_value, '') = '' and m.value_as_number >= 200
            )
        )
        or
        (
            (
                m.measurement_source_value ilike '%2345-7%'
                or m.measurement_source_value ilike '%2339-0%'
                or m.measurement_source_value ilike '%random glucose%'
            )
            and (
                (coalesce(m.unit_source_value, '') ilike '%mg/dl%' and m.value_as_number >= 200)
                or (coalesce(m.unit_source_value, '') ilike '%mmol/l%' and m.value_as_number >= 11.1)
                or coalesce(m.unit_source_value, '') = '' and m.value_as_number >= 200
            )
        )
      )
),
rule_b as (
    select
        d.person_id,
        least(min(d.cond_date), min(l.meas_date)) as index_date
    from t2dm_dx_dates d
    join abnormal_labs l
        on l.person_id = d.person_id
    group by d.person_id
),
non_insulin_rx as (
    select
        de.person_id,
        try_cast(de.drug_exposure_start_date as date) as rx_date
    from memory.drug_exposure de
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
        or de.drug_source_value ilike '%empagliflozin%'
        or de.drug_source_value ilike '%canagliflozin%'
        or de.drug_source_value ilike '%dapagliflozin%'
        or de.drug_source_value ilike '%ertugliflozin%'
        or de.drug_source_value ilike '%semaglutide%'
        or de.drug_source_value ilike '%liraglutide%'
        or de.drug_source_value ilike '%dulaglutide%'
        or de.drug_source_value ilike '%exenatide%'
        or de.drug_source_value ilike '%lixisenatide%'
        or de.drug_source_value ilike '%acarbose%'
        or de.drug_source_value ilike '%miglitol%'
        or de.drug_source_value ilike '%colesevelam%'
        or de.drug_source_value ilike '%bromocriptine%'
        or de.drug_source_value ilike '%tirzepatide%'
        or de.drug_source_value ilike '%glucophage%'
        or de.drug_source_value ilike '%glumetza%'
        or de.drug_source_value ilike '%fortamet%'
        or de.drug_source_value ilike '%riomet%'
        or de.drug_source_value ilike '%glucotrol%'
        or de.drug_source_value ilike '%diabeta%'
        or de.drug_source_value ilike '%micronase%'
        or de.drug_source_value ilike '%glynase%'
        or de.drug_source_value ilike '%amaryl%'
        or de.drug_source_value ilike '%prandin%'
        or de.drug_source_value ilike '%starlix%'
        or de.drug_source_value ilike '%actos%'
        or de.drug_source_value ilike '%avandia%'
        or de.drug_source_value ilike '%januvia%'
        or de.drug_source_value ilike '%onglyza%'
        or de.drug_source_value ilike '%tradjenta%'
        or de.drug_source_value ilike '%nesina%'
        or de.drug_source_value ilike '%jardiance%'
        or de.drug_source_value ilike '%invokana%'
        or de.drug_source_value ilike '%farxiga%'
        or de.drug_source_value ilike '%steglatro%'
        or de.drug_source_value ilike '%ozempic%'
        or de.drug_source_value ilike '%rybelsus%'
        or de.drug_source_value ilike '%victoza%'
        or de.drug_source_value ilike '%trulicity%'
        or de.drug_source_value ilike '%byetta%'
        or de.drug_source_value ilike '%bydureon%'
        or de.drug_source_value ilike '%adlyxin%'
        or de.drug_source_value ilike '%precose%'
        or de.drug_source_value ilike '%glyset%'
        or de.drug_source_value ilike '%welchol%'
        or de.drug_source_value ilike '%cycloset%'
        or de.drug_source_value ilike '%mounjaro%'
    )
),
rule_c as (
    select
        rx.person_id,
        min(n.rx_date) as index_date
    from (
        select
            person_id,
            min(rx_date) as first_fill,
            max(rx_date) as last_fill,
            count(*) as n_fills
        from non_insulin_rx
        group by person_id
        having count(*) >= 2
           and datediff('day', min(rx_date), max(rx_date)) >= 30
    ) rx
    join non_insulin_rx n
        on n.person_id = rx.person_id
    group by rx.person_id
),
rule_d as (
    select
        l.person_id,
        min(least(l.meas_date, d.rx_date)) as index_date
    from abnormal_labs l
    join non_insulin_rx d
        on d.person_id = l.person_id
       and d.rx_date between l.meas_date - interval 365 day and l.meas_date + interval 365 day
    group by l.person_id
),
inc as (
    select person_id, index_date from rule_a
    union all
    select person_id, index_date from rule_b
    union all
    select person_id, index_date from rule_c
    union all
    select person_id, index_date from rule_d
),
inc_min as (
    select
        person_id,
        min(index_date) as index_date
    from inc
    group by person_id
),
secondary_diabetes as (
    select distinct co.person_id
    from memory.condition_occurrence co
    where co.condition_source_value ilike 'E08%'
       or co.condition_source_value ilike 'E09%'
       or co.condition_source_value ilike 'E13%'
       or co.condition_source_value ilike '249%'
),
t1_patients as (
    select distinct person_id
    from memory.condition_occurrence
    where condition_source_value ilike 'E10%'
       or regexp_matches(condition_source_value, '^250\.[0-9]1$')
       or regexp_matches(condition_source_value, '^250\.[0-9]3$')
),
t2_patients as (
    select distinct person_id
    from memory.condition_occurrence
    where condition_source_value ilike 'E11%'
       or regexp_matches(condition_source_value, '^250\.[0-9]0$')
       or regexp_matches(condition_source_value, '^250\.[0-9]2$')
),
t1only as (
    select t1.person_id
    from t1_patients t1
    left join t2_patients t2
        on t2.person_id = t1.person_id
    where t2.person_id is null
),
gest as (
    select
        person_id,
        try_cast(condition_start_date as date) as g_date
    from memory.condition_occurrence
    where condition_source_value ilike 'O24.4%'
       or condition_source_value ilike '648.8%'
)
select
    inc_min.person_id,
    inc_min.index_date
from inc_min
join memory.person p
    on p.person_id = inc_min.person_id
left join secondary_diabetes sec
    on sec.person_id = inc_min.person_id
left join t1only
    on t1only.person_id = inc_min.person_id
where sec.person_id is null
  and t1only.person_id is null
  and not exists (
        select 1
        from gest g
        where g.person_id = inc_min.person_id
          and g.g_date between inc_min.index_date - interval 270 day and inc_min.index_date + interval 270 day
  )
  and datediff('year', try_cast(p.birth_datetime as date), inc_min.index_date) >= 18
;
