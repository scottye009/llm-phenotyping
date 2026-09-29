with

t2dm_dx as (
    select distinct
        co.person_id,
        co.condition_start_date
    from memory.condition_occurrence co
    where (
            co.condition_source_value like 'E11%'
         or (
                co.condition_source_value like '250.%'
            and right(co.condition_source_value, 1) in ('0', '2')
         )
    )
),

t1dm_dx as (
    select distinct
        co.person_id
    from memory.condition_occurrence co
    where (
            co.condition_source_value like 'E10%'
         or (
                co.condition_source_value like '250.%'
            and right(co.condition_source_value, 1) in ('1', '3')
         )
    )
),

gest_dm_dx as (
    select distinct
        co.person_id
    from memory.condition_occurrence co
    where co.condition_source_value like 'O24.4%'
),

secondary_dm_dx as (
    select distinct
        co.person_id
    from memory.condition_occurrence co
    where co.condition_source_value like 'E08%'
       or co.condition_source_value like 'E09%'
       or co.condition_source_value like 'E13%'
),

t2dm_meds as (
    select distinct
        de.person_id,
        de.drug_exposure_start_date
    from memory.drug_exposure de
    where (
            de.drug_source_value ilike '%metformin%'
         or de.drug_source_value ilike '%glucophage%'
         or de.drug_source_value ilike '%glipizide%'
         or de.drug_source_value ilike '%glucotrol%'
         or de.drug_source_value ilike '%glyburide%'
         or de.drug_source_value ilike '%diabeta%'
         or de.drug_source_value ilike '%micronase%'
         or de.drug_source_value ilike '%glimepiride%'
         or de.drug_source_value ilike '%amaryl%'
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
         or de.drug_source_value ilike '%dulaglutide%'
         or de.drug_source_value ilike '%trulicity%'
         or de.drug_source_value ilike '%semaglutide%'
         or de.drug_source_value ilike '%ozempic%'
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
    )
),

insulin_meds as (
    select distinct
        de.person_id,
        de.drug_exposure_start_date
    from memory.drug_exposure de
    where de.drug_source_value ilike '%insulin%'
       or de.drug_source_value ilike '%lantus%'
       or de.drug_source_value ilike '%levemir%'
       or de.drug_source_value ilike '%tresiba%'
       or de.drug_source_value ilike '%humalog%'
       or de.drug_source_value ilike '%novolog%'
),

t2dm_labs as (
    select distinct
        m.person_id,
        m.measurement_date,
        m.value_as_number
    from memory.measurement m
    where (
            m.measurement_source_value ilike '%hemoglobin a1c%'
        and m.value_as_number >= 6.5
    )
       or (
            m.measurement_source_value ilike '%fasting glucose%'
        and m.value_as_number >= 126
    )
       or (
            m.measurement_source_value ilike '%glucose%'
        and m.value_as_number >= 200
    )
),

t2dm_dx_agg as (
    select
        person_id,
        count(distinct condition_start_date) as dx_dates
    from t2dm_dx
    group by person_id
),

t2dm_med_flag as (
    select distinct person_id
    from t2dm_meds
),

insulin_med_flag as (
    select distinct person_id
    from insulin_meds
),

t2dm_lab_flag as (
    select distinct person_id
    from t2dm_labs
),

eligible_persons as (
    select
        p.person_id,
        p.year_of_birth,
        min(v.visit_start_date) as first_obs_date
    from memory.person p
    join memory.visit_occurrence v
        on p.person_id = v.person_id
    group by p.person_id, p.year_of_birth
),

t2dm_cohort as (
    select distinct
        e.person_id
    from eligible_persons e
    left join t2dm_dx_agg dx on e.person_id = dx.person_id
    left join t2dm_med_flag med on e.person_id = med.person_id
    left join insulin_med_flag ins on e.person_id = ins.person_id
    left join t2dm_lab_flag lab on e.person_id = lab.person_id
    left join t1dm_dx t1 on e.person_id = t1.person_id
    left join gest_dm_dx gdm on e.person_id = gdm.person_id
    left join secondary_dm_dx sdm on e.person_id = sdm.person_id
    where (year(first_obs_date) - e.year_of_birth) >= 18
      and (
            (dx.dx_dates >= 2)
         or (dx.dx_dates >= 1 and med.person_id is not null)
         or (dx.dx_dates >= 1 and lab.person_id is not null)
         or (lab.person_id is not null and med.person_id is not null)
         or (dx.dx_dates >= 1 and ins.person_id is not null)
      )
      and t1.person_id is null
      and gdm.person_id is null
      and sdm.person_id is null
)

select *
from t2dm_cohort;
