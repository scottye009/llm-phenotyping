with t2dm_diagnosis as (
    select distinct
        co.person_id,
        co.condition_start_date,
        co.condition_concept_id,
        co.condition_source_value as concept_code,
        null as concept_name
    from memory.condition_occurrence co
    where (
        regexp_matches(co.condition_source_value, '^250\\.[0-9][02]$')
        or co.condition_source_value like 'E11%'
    )
),

exclusion_diagnosis as (
    select distinct
        co.person_id
    from memory.condition_occurrence co
    where (
        co.condition_source_value like 'E10%'
        or co.condition_source_value in ('250.01', '250.03', '250.11', '250.13', '250.21', '250.23',
                                         '250.31', '250.33', '250.41', '250.43', '250.51', '250.53',
                                         '250.61', '250.63', '250.71', '250.73', '250.81', '250.83',
                                         '250.91', '250.93')
        or co.condition_source_value in ('O24.4', 'O24.41', 'O24.42', 'O24.43', 'O24.419', 'O24.429', 'O24.439', '648.8')
        or co.condition_source_value like 'E08%'
        or co.condition_source_value like 'E09%'
        or co.condition_source_value like 'E13%'
    )
),

t2dm_medications as (
    select distinct
        de.person_id,
        de.drug_exposure_start_date,
        de.drug_concept_id,
        null as concept_name
    from memory.drug_exposure de
    where (
        de.drug_source_value ilike '%metformin%' or de.drug_source_value ilike '%glucophage%' or de.drug_source_value ilike '%fortamet%' or de.drug_source_value ilike '%glumetza%'
        or de.drug_source_value ilike '%glipizide%' or de.drug_source_value ilike '%glucotrol%'
        or de.drug_source_value ilike '%glyburide%' or de.drug_source_value ilike '%diabeta%' or de.drug_source_value ilike '%glynase%' or de.drug_source_value ilike '%micronase%'
        or de.drug_source_value ilike '%glimepiride%' or de.drug_source_value ilike '%amaryl%'
        or de.drug_source_value ilike '%sitagliptin%' or de.drug_source_value ilike '%januvia%'
        or de.drug_source_value ilike '%saxagliptin%' or de.drug_source_value ilike '%onglyza%'
        or de.drug_source_value ilike '%linagliptin%' or de.drug_source_value ilike '%tradjenta%'
        or de.drug_source_value ilike '%alogliptin%' or de.drug_source_value ilike '%nesina%'
        or de.drug_source_value ilike '%exenatide%' or de.drug_source_value ilike '%byetta%' or de.drug_source_value ilike '%bydureon%'
        or de.drug_source_value ilike '%liraglutide%' or de.drug_source_value ilike '%victoza%'
        or de.drug_source_value ilike '%dulaglutide%' or de.drug_source_value ilike '%trulicity%'
        or de.drug_source_value ilike '%semaglutide%' or de.drug_source_value ilike '%ozempic%' or de.drug_source_value ilike '%rybelsus%'
        or de.drug_source_value ilike '%canagliflozin%' or de.drug_source_value ilike '%invokana%'
        or de.drug_source_value ilike '%dapagliflozin%' or de.drug_source_value ilike '%farxiga%'
        or de.drug_source_value ilike '%empagliflozin%' or de.drug_source_value ilike '%jardiance%'
        or de.drug_source_value ilike '%ertugliflozin%' or de.drug_source_value ilike '%steglatro%'
        or de.drug_source_value ilike '%pioglitazone%' or de.drug_source_value ilike '%actos%'
        or de.drug_source_value ilike '%rosiglitazone%' or de.drug_source_value ilike '%avandia%'
        or de.drug_source_value ilike '%acarbose%' or de.drug_source_value ilike '%precose%'
        or de.drug_source_value ilike '%miglitol%' or de.drug_source_value ilike '%glyset%'
        or de.drug_source_value ilike '%repaglinide%' or de.drug_source_value ilike '%prandin%'
        or de.drug_source_value ilike '%nateglinide%' or de.drug_source_value ilike '%starlix%'
    )
),

t2dm_labs as (
    select distinct
        m.person_id,
        m.measurement_date,
        m.value_as_number,
        m.measurement_source_value as lab_name
    from memory.measurement m
    where (
        ((m.measurement_source_value ilike '%a1c%' or m.measurement_source_value ilike '%hba1c%') and m.value_as_number >= 6.5)
        or ((m.measurement_source_value ilike '%fasting glucose%') and m.value_as_number >= 126)
        or ((m.measurement_source_value ilike '%glucose%') and m.value_as_number >= 200)
    )
),

diagnosis_count as (
    select
        person_id,
        count(distinct condition_start_date) as dx_count,
        min(condition_start_date) as first_dx_date,
        max(condition_start_date) as last_dx_date
    from t2dm_diagnosis
    group by person_id
    having count(distinct condition_start_date) >= 2
       and datediff('day', min(condition_start_date), max(condition_start_date)) <= 730
),

dx_plus_labs as (
    select distinct
        d.person_id,
        d.condition_start_date as index_date
    from t2dm_diagnosis d
    inner join t2dm_labs l on d.person_id = l.person_id
        and l.measurement_date between d.condition_start_date - interval 90 day and d.condition_start_date + interval 90 day
),

dx_plus_meds as (
    select distinct
        d.person_id,
        d.condition_start_date as index_date
    from t2dm_diagnosis d
    inner join t2dm_medications m on d.person_id = m.person_id
        and m.drug_exposure_start_date >= d.condition_start_date
        and m.drug_exposure_start_date <= d.condition_start_date + interval 365 day
),

t2dm_cohort as (
    select distinct person_id, 'Multiple Diagnoses' as inclusion_criteria from diagnosis_count
    union
    select distinct person_id, 'Diagnosis + Labs' as inclusion_criteria from dx_plus_labs
    union
    select distinct person_id, 'Diagnosis + Medications' as inclusion_criteria from dx_plus_meds
)

select distinct
    tc.person_id,
    p.gender_concept_id,
    p.year_of_birth,
    p.race_concept_id,
    p.ethnicity_concept_id,
    string_agg(distinct tc.inclusion_criteria, '; ') as criteria_met,
    min(d.condition_start_date) as earliest_t2dm_date
from t2dm_cohort tc
inner join memory.person p on tc.person_id = p.person_id
left join t2dm_diagnosis d on tc.person_id = d.person_id
where tc.person_id not in (select person_id from exclusion_diagnosis)
group by tc.person_id, p.gender_concept_id, p.year_of_birth, p.race_concept_id, p.ethnicity_concept_id
order by tc.person_id;
