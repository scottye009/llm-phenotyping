with 

t2dm_diagnosis as (
    select distinct
        co.person_id,
        co.condition_start_date as event_date,
        co.condition_concept_id,
        null as concept_name,
        'Diagnosis' as criterion_type
    from memory.condition_occurrence co
    where 
        co.condition_source_value in (
            'E11', 'E11.0', 'E11.00', 'E11.01', 'E11.1', 'E11.10', 'E11.11',
            'E11.2', 'E11.21', 'E11.22', 'E11.29',
            'E11.3', 'E11.31', 'E11.32', 'E11.33', 'E11.34', 'E11.35', 'E11.36', 'E11.39',
            'E11.4', 'E11.40', 'E11.41', 'E11.42', 'E11.43', 'E11.44', 'E11.49',
            'E11.5', 'E11.51', 'E11.52', 'E11.59',
            'E11.6', 'E11.61', 'E11.62', 'E11.63', 'E11.64', 'E11.65', 'E11.69',
            'E11.8', 'E11.9',
            '250.00', '250.02', '250.10', '250.12', '250.20', '250.22',
            '250.30', '250.32', '250.40', '250.42', '250.50', '250.52',
            '250.60', '250.62', '250.70', '250.72', '250.80', '250.82',
            '250.90', '250.92'
        )
),

exclusion_diagnosis as (
    select distinct
        co.person_id,
        co.condition_start_date as event_date,
        'Exclusion' as criterion_type
    from memory.condition_occurrence co
    where co.condition_source_value like 'E10%'
       or co.condition_source_value in ('250.01','250.03','250.11','250.13','250.21','250.23','250.31','250.33','250.41','250.43','250.51','250.53','250.61','250.63','250.71','250.73','250.81','250.83','250.91','250.93')
       or co.condition_source_value like '648.8%'
       or co.condition_source_value like 'O24.4%'
       or co.condition_source_value like '249.%'
       or co.condition_source_value like 'E08%'
       or co.condition_source_value like 'E09%'
       or co.condition_source_value like 'E13%'
),

t2dm_labs as (
    select distinct
        m.person_id,
        m.measurement_date as event_date,
        m.value_as_number,
        m.measurement_source_value,
        'Laboratory' as criterion_type
    from memory.measurement m
    where (
            (m.measurement_source_value ilike '%a1c%' or m.measurement_source_value ilike '%hba1c%') and m.value_as_number >= 6.5
        )
        or (
            m.measurement_source_value ilike '%fasting glucose%' and m.value_as_number >= 126
        )
        or (
            m.measurement_source_value ilike '%glucose%' and m.value_as_number >= 200
        )
),

t2dm_medications as (
    select distinct
        de.person_id,
        de.drug_exposure_start_date as event_date,
        de.drug_concept_id,
        de.drug_source_value,
        'Medication' as criterion_type
    from memory.drug_exposure de
    where de.drug_source_value ilike '%metformin%'
       or de.drug_source_value ilike '%glucophage%'
       or de.drug_source_value ilike '%glumetza%'
       or de.drug_source_value ilike '%fortamet%'
       or de.drug_source_value ilike '%riomet%'
       or de.drug_source_value ilike '%glipizide%'
       or de.drug_source_value ilike '%glucotrol%'
       or de.drug_source_value ilike '%glyburide%'
       or de.drug_source_value ilike '%diabeta%'
       or de.drug_source_value ilike '%micronase%'
       or de.drug_source_value ilike '%glynase%'
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
       or de.drug_source_value ilike '%insulin%'
),

all_criteria as (
    select person_id, event_date, criterion_type from t2dm_diagnosis
    union all
    select person_id, event_date, criterion_type from t2dm_labs
    union all
    select person_id, event_date, criterion_type from t2dm_medications
),

person_criteria_summary as (
    select
        person_id,
        min(event_date) as index_date,
        count(distinct case when criterion_type = 'Diagnosis' then event_date end) as diagnosis_dates,
        count(distinct case when criterion_type = 'Laboratory' then event_date end) as lab_dates,
        count(distinct case when criterion_type = 'Medication' then event_date end) as med_dates
    from all_criteria
    group by person_id
),

final_t2dm_cohort as (
    select
        pcs.person_id,
        pcs.index_date
    from person_criteria_summary pcs
    where (
            pcs.diagnosis_dates >= 2
         or (pcs.diagnosis_dates >= 1 and pcs.lab_dates >= 1)
         or (pcs.diagnosis_dates >= 1 and pcs.med_dates >= 1)
         or (pcs.lab_dates >= 2)
         or (pcs.med_dates >= 2)
    )
      and pcs.person_id not in (select person_id from exclusion_diagnosis)
)

select *
from final_t2dm_cohort
order by person_id;
