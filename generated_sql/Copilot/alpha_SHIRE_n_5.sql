with

t2dm_dx_concepts as (
    select 'placeholder' as concept_id
),

t1dm_dx_concepts as (
    select 'placeholder' as concept_id
),

gestational_dm_dx_concepts as (
    select 'placeholder' as concept_id
),

other_dm_dx_concepts as (
    select 'placeholder' as concept_id
),

hba1c_meas_concepts as (
    select 'placeholder' as concept_id
),

fpg_meas_concepts as (
    select 'placeholder' as concept_id
),

ogtt_meas_concepts as (
    select 'placeholder' as concept_id
),

random_glucose_meas_concepts as (
    select 'placeholder' as concept_id
),

non_insulin_antihyperglycemic_drug_concepts as (
    select 'placeholder' as concept_id
),

insulin_drug_concepts as (
    select 'placeholder' as concept_id
),

t2dm_dx as (
    select person_id, condition_start_date
    from memory.condition_occurrence
    where condition_source_value like 'E11%'
       or (condition_source_value like '250.%' and right(condition_source_value, 1) in ('0','2'))
),

t1dm_dx as (
    select person_id, condition_start_date
    from memory.condition_occurrence
    where condition_source_value like 'E10%'
       or (condition_source_value like '250.%' and right(condition_source_value, 1) in ('1','3'))
),

gestational_dm_dx as (
    select person_id, condition_start_date
    from memory.condition_occurrence
    where condition_source_value like 'O24.4%'
),

other_dm_dx as (
    select person_id, condition_start_date
    from memory.condition_occurrence
    where condition_source_value like 'E08%'
       or condition_source_value like 'E09%'
       or condition_source_value like 'E13%'
),

abnormal_glucose_labs as (
    select person_id, measurement_date
    from memory.measurement
    where (
        (measurement_source_value ilike '%a1c%' or measurement_source_value ilike '%hba1c%')
        and value_as_number >= 6.5
    ) or (
        measurement_source_value ilike '%fasting glucose%'
        and value_as_number >= 126
    ) or (
        measurement_source_value ilike '%ogtt%'
        and value_as_number >= 200
    ) or (
        measurement_source_value ilike '%random glucose%' or measurement_source_value ilike '%glucose%'
        and value_as_number >= 200
    )
),

abnormal_glucose_labs_agg as (
    select person_id,
           count(distinct measurement_date) as abnormal_lab_dates
    from abnormal_glucose_labs
    group by person_id
),

non_insulin_exposure as (
    select person_id, drug_exposure_start_date
    from memory.drug_exposure
    where drug_source_value ilike '%metformin%'
       or drug_source_value ilike '%glipizide%'
       or drug_source_value ilike '%glyburide%'
       or drug_source_value ilike '%glimepiride%'
       or drug_source_value ilike '%pioglitazone%'
       or drug_source_value ilike '%rosiglitazone%'
       or drug_source_value ilike '%sitagliptin%'
       or drug_source_value ilike '%saxagliptin%'
       or drug_source_value ilike '%linagliptin%'
       or drug_source_value ilike '%alogliptin%'
       or drug_source_value ilike '%exenatide%'
       or drug_source_value ilike '%liraglutide%'
       or drug_source_value ilike '%dulaglutide%'
       or drug_source_value ilike '%semaglutide%'
       or drug_source_value ilike '%canagliflozin%'
       or drug_source_value ilike '%dapagliflozin%'
       or drug_source_value ilike '%empagliflozin%'
       or drug_source_value ilike '%ertugliflozin%'
),

non_insulin_exposure_agg as (
    select person_id,
           count(distinct drug_exposure_start_date) as non_insulin_exposure_dates
    from non_insulin_exposure
    group by person_id
),

insulin_exposure as (
    select person_id, drug_exposure_start_date
    from memory.drug_exposure
    where drug_source_value ilike '%insulin%'
),

insulin_exposure_agg as (
    select person_id,
           count(distinct drug_exposure_start_date) as insulin_exposure_dates
    from insulin_exposure
    group by person_id
),

t2dm_dx_agg as (
    select person_id,
           count(distinct condition_start_date) as t2dm_dx_dates
    from t2dm_dx
    group by person_id
),

t1dm_dx_agg as (
    select person_id,
           count(distinct condition_start_date) as t1dm_dx_dates
    from t1dm_dx
    group by person_id
),

gestational_dm_dx_agg as (
    select person_id,
           count(distinct condition_start_date) as gestational_dm_dx_dates
    from gestational_dm_dx
    group by person_id
),

other_dm_dx_agg as (
    select person_id,
           count(distinct condition_start_date) as other_dm_dx_dates
    from other_dm_dx
    group by person_id
),

positive_evidence as (
    select p.person_id,
           case when t2.t2dm_dx_dates >= 2 then 1 else 0 end as cond_a_dx2,
           case when t2.t2dm_dx_dates >= 1 and (ni.non_insulin_exposure_dates >= 1 or i.insulin_exposure_dates >= 1)
                then 1 else 0 end as cond_b_dx_plus_med,
           case when labs.abnormal_lab_dates >= 2 then 1 else 0 end as cond_c_labs2,
           case when ni.non_insulin_exposure_dates >= 2 and (t2.t2dm_dx_dates >= 1 or labs.abnormal_lab_dates >= 1)
                then 1 else 0 end as cond_d_meds2_plus_dx_or_lab
    from memory.person p
    left join t2dm_dx_agg t2 on p.person_id = t2.person_id
    left join abnormal_glucose_labs_agg labs on p.person_id = labs.person_id
    left join non_insulin_exposure_agg ni on p.person_id = ni.person_id
    left join insulin_exposure_agg i on p.person_id = i.person_id
),

exclusions as (
    select p.person_id,
           coalesce(t1.t1dm_dx_dates, 0) as t1dm_dx_dates,
           coalesce(g.gestational_dm_dx_dates, 0) as gestational_dm_dx_dates,
           coalesce(o.other_dm_dx_dates, 0) as other_dm_dx_dates,
           coalesce(t2.t2dm_dx_dates, 0) as t2dm_dx_dates
    from memory.person p
    left join t1dm_dx_agg t1 on p.person_id = t1.person_id
    left join gestational_dm_dx_agg g on p.person_id = g.person_id
    left join other_dm_dx_agg o on p.person_id = o.person_id
    left join t2dm_dx_agg t2 on p.person_id = t2.person_id
),

t2dm_cohort as (
    select pe.person_id
    from positive_evidence pe
    join exclusions ex on pe.person_id = ex.person_id
    where (
        pe.cond_a_dx2 = 1 or
        pe.cond_b_dx_plus_med = 1 or
        pe.cond_c_labs2 = 1 or
        pe.cond_d_meds2_plus_dx_or_lab = 1
    )
    and not (
        ex.t1dm_dx_dates >= 2 and ex.t2dm_dx_dates = 0
    )
    and ex.gestational_dm_dx_dates = 0
    and ex.other_dm_dx_dates = 0
)

select *
from t2dm_cohort;
