with

t2dm_dx as (
    select
        co.person_id,
        co.condition_start_date as event_date
    from memory.condition_occurrence co
    where (
            co.condition_source_value like 'E11%'
         or (
                co.condition_source_value like '250.%'
            and substr(co.condition_source_value, 6, 1) in ('0', '2')
         )
    )
),

t1dm_dx as (
    select
        co.person_id,
        co.condition_start_date as event_date
    from memory.condition_occurrence co
    where (
            co.condition_source_value like 'E10%'
         or (
                co.condition_source_value like '250.%'
            and substr(co.condition_source_value, 6, 1) in ('1', '3')
         )
    )
),

gest_secondary_dm_dx as (
    select
        co.person_id,
        co.condition_start_date as event_date
    from memory.condition_occurrence co
    where co.condition_source_value like 'O24.4%'
       or co.condition_source_value like 'O24.9%'
       or co.condition_source_value like 'E08%'
       or co.condition_source_value like 'E09%'
       or co.condition_source_value like 'E13%'
),

t2dm_meds as (
    select
        de.person_id,
        de.drug_exposure_start_date as event_date
    from memory.drug_exposure de
    where de.drug_source_value ilike '%metformin%'
       or de.drug_source_value ilike '%glucophage%'
       or de.drug_source_value ilike '%glipizide%'
       or de.drug_source_value ilike '%glucotrol%'
       or de.drug_source_value ilike '%glyburide%'
       or de.drug_source_value ilike '%diabeta%'
       or de.drug_source_value ilike '%glimepiride%'
       or de.drug_source_value ilike '%amaryl%'
       or de.drug_source_value ilike '%pioglitazone%'
       or de.drug_source_value ilike '%actos%'
       or de.drug_source_value ilike '%rosiglitazone%'
       or de.drug_source_value ilike '%avandia%'
       or de.drug_source_value ilike '%sitagliptin%'
       or de.drug_source_value ilike '%januvia%'
       or de.drug_source_value ilike '%saxagliptin%'
       or de.drug_source_value ilike '%onglyza%'
       or de.drug_source_value ilike '%linagliptin%'
       or de.drug_source_value ilike '%tradjenta%'
       or de.drug_source_value ilike '%exenatide%'
       or de.drug_source_value ilike '%byetta%'
       or de.drug_source_value ilike '%liraglutide%'
       or de.drug_source_value ilike '%victoza%'
       or de.drug_source_value ilike '%semaglutide%'
       or de.drug_source_value ilike '%ozempic%'
       or de.drug_source_value ilike '%dulaglutide%'
       or de.drug_source_value ilike '%trulicity%'
       or de.drug_source_value ilike '%canagliflozin%'
       or de.drug_source_value ilike '%invokana%'
       or de.drug_source_value ilike '%dapagliflozin%'
       or de.drug_source_value ilike '%farxiga%'
       or de.drug_source_value ilike '%empagliflozin%'
       or de.drug_source_value ilike '%jardiance%'
),

insulin_meds as (
    select
        de.person_id,
        de.drug_exposure_start_date as event_date
    from memory.drug_exposure de
    where de.drug_source_value ilike '%insulin%'
       or de.drug_source_value ilike '%lantus%'
       or de.drug_source_value ilike '%levemir%'
       or de.drug_source_value ilike '%tresiba%'
       or de.drug_source_value ilike '%humalog%'
       or de.drug_source_value ilike '%novolog%'
),

t2dm_labs as (
    select
        m.person_id,
        m.measurement_date as event_date,
        m.value_as_number,
        m.unit_concept_id
    from memory.measurement m
    where m.measurement_source_value ilike '%glucose%'
       or m.measurement_source_value ilike '%a1c%'
       or m.measurement_source_value ilike '%hba1c%'
),

qual_labs as (
    select distinct person_id, event_date
    from t2dm_labs
    where value_as_number is not null
      and (
            value_as_number >= 6.5
         or value_as_number >= 126
      )
),

person_t2dm_dx as (
    select person_id, count(distinct event_date) as t2dm_dx_dates, min(event_date) as first_t2dm_dx_date
    from t2dm_dx
    group by person_id
),

person_t1dm_dx as (
    select person_id, count(distinct event_date) as t1dm_dx_dates, min(event_date) as first_t1dm_dx_date
    from t1dm_dx
    group by person_id
),

person_gest_secondary_dm as (
    select person_id, min(event_date) as first_gest_secondary_date
    from gest_secondary_dm_dx
    group by person_id
),

person_t2dm_meds as (
    select person_id, count(*) as t2dm_med_count, min(event_date) as first_t2dm_med_date
    from t2dm_meds
    group by person_id
),

person_insulin_meds as (
    select person_id, count(*) as insulin_med_count, min(event_date) as first_insulin_date
    from insulin_meds
    group by person_id
),

person_qual_labs as (
    select person_id, count(*) as qual_lab_count, min(event_date) as first_qual_lab_date
    from qual_labs
    group by person_id
),

candidate_cases as (
    select
        p.person_id,
        least(
            coalesce(dx.first_t2dm_dx_date, date '2999-12-31'),
            coalesce(m.first_t2dm_med_date, date '2999-12-31'),
            coalesce(l.first_qual_lab_date, date '2999-12-31'),
            coalesce(i.first_insulin_date, date '2999-12-31')
        ) as index_date,
        coalesce(dx.t2dm_dx_dates, 0) as t2dm_dx_dates,
        coalesce(m.t2dm_med_count, 0) as t2dm_med_count,
        coalesce(i.insulin_med_count, 0) as insulin_med_count,
        coalesce(l.qual_lab_count, 0) as qual_lab_count,
        coalesce(t1.t1dm_dx_dates, 0) as t1dm_dx_dates,
        case when gs.person_id is not null then 1 else 0 end as gest_secondary_flag
    from memory.person p
    left join person_t2dm_dx dx on p.person_id = dx.person_id
    left join person_t2dm_meds m on p.person_id = m.person_id
    left join person_insulin_meds i on p.person_id = i.person_id
    left join person_qual_labs l on p.person_id = l.person_id
    left join person_t1dm_dx t1 on p.person_id = t1.person_id
    left join person_gest_secondary_dm gs on p.person_id = gs.person_id
),

t2dm_cohort as (
    select *
    from candidate_cases
    where (
            t2dm_dx_dates >= 2
         or (t2dm_dx_dates >= 1 and t2dm_med_count >= 1)
         or (t2dm_dx_dates >= 1 and qual_lab_count >= 1)
         or (qual_lab_count >= 2)
         or (t2dm_med_count >= 1 and qual_lab_count >= 1)
         or (t2dm_dx_dates >= 1 and insulin_med_count >= 1)
    )
      and t1dm_dx_dates = 0
      and gest_secondary_flag = 0
)

select *
from t2dm_cohort;
