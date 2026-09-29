-- ============================================================================
-- SHIRE-READY TYPE 2 DIABETES PHENOTYPING ALGORITHM
-- Adapted from beta_n.sql for SHIRE DuckDB execution
-- Keeps original algorithm structure, replacing OMOP vocabulary dependencies
-- with SHIRE-compatible source-field logic.
-- ============================================================================

with visit_observation as (
    select
        person_id,
        min(visit_start_date) as observation_period_start_date,
        max(visit_start_date) as observation_period_end_date
    from memory.visit_occurrence
    where visit_start_date is not null
    group by person_id
),

all_evidence as (
    -- T2DM Diagnosis Codes
    select distinct
        co.person_id,
        co.condition_start_date as event_date,
        'diagnosis' as criterion_type
    from memory.condition_occurrence co
    where co.condition_start_date is not null
      and (
          co.condition_source_value ilike 'E11%'
          or co.condition_source_value in (
              '250.00', '250.02',
              '250.10', '250.12',
              '250.20', '250.22',
              '250.30', '250.32',
              '250.40', '250.42',
              '250.50', '250.52',
              '250.60', '250.62',
              '250.70', '250.72',
              '250.80', '250.82',
              '250.90', '250.92'
          )
      )

    union all

    -- Abnormal Laboratory Values
    select distinct
        m.person_id,
        m.measurement_date as event_date,
        'laboratory' as criterion_type
    from memory.measurement m
    where m.measurement_date is not null
      and m.value_as_number is not null
      and (
          (
              (
                  m.measurement_source_value ilike '%a1c%'
                  or m.measurement_source_value ilike '%hba1c%'
                  or m.measurement_source_value ilike '%hemoglobin a1c%'
                  or m.measurement_source_value ilike '%glycated hemoglobin%'
              )
              and m.value_as_number >= 6.5
          )
          or
          (
              (
                  m.measurement_source_value ilike '%fasting glucose%'
                  or m.measurement_source_value ilike '%glucose fasting%'
                  or m.measurement_source_value ilike '%fasting blood glucose%'
              )
              and m.value_as_number >= 126
          )
          or
          (
              (
                  m.measurement_source_value ilike '%glucose%'
                  or m.measurement_source_value ilike '%blood glucose%'
                  or m.measurement_source_value ilike '%serum glucose%'
              )
              and m.measurement_source_value not ilike '%fasting%'
              and m.value_as_number >= 200
          )
      )

    union all

    -- Type 2 Diabetes Medications
    select distinct
        de.person_id,
        de.drug_exposure_start_date as event_date,
        'medication' as criterion_type
    from memory.drug_exposure de
    where de.drug_exposure_start_date is not null
      and (
          de.drug_source_value ilike '%metformin%' or
          de.drug_source_value ilike '%glucophage%' or
          de.drug_source_value ilike '%fortamet%' or
          de.drug_source_value ilike '%glumetza%' or
          de.drug_source_value ilike '%riomet%' or
          de.drug_source_value ilike '%glyburide%' or
          de.drug_source_value ilike '%glibenclamide%' or
          de.drug_source_value ilike '%diabeta%' or
          de.drug_source_value ilike '%glynase%' or
          de.drug_source_value ilike '%micronase%' or
          de.drug_source_value ilike '%glipizide%' or
          de.drug_source_value ilike '%glucotrol%' or
          de.drug_source_value ilike '%glimepiride%' or
          de.drug_source_value ilike '%amaryl%' or
          de.drug_source_value ilike '%pioglitazone%' or
          de.drug_source_value ilike '%actos%' or
          de.drug_source_value ilike '%rosiglitazone%' or
          de.drug_source_value ilike '%avandia%' or
          de.drug_source_value ilike '%sitagliptin%' or
          de.drug_source_value ilike '%januvia%' or
          de.drug_source_value ilike '%saxagliptin%' or
          de.drug_source_value ilike '%onglyza%' or
          de.drug_source_value ilike '%linagliptin%' or
          de.drug_source_value ilike '%tradjenta%' or
          de.drug_source_value ilike '%alogliptin%' or
          de.drug_source_value ilike '%nesina%' or
          de.drug_source_value ilike '%exenatide%' or
          de.drug_source_value ilike '%byetta%' or
          de.drug_source_value ilike '%bydureon%' or
          de.drug_source_value ilike '%liraglutide%' or
          de.drug_source_value ilike '%victoza%' or
          de.drug_source_value ilike '%saxenda%' or
          de.drug_source_value ilike '%dulaglutide%' or
          de.drug_source_value ilike '%trulicity%' or
          de.drug_source_value ilike '%semaglutide%' or
          de.drug_source_value ilike '%ozempic%' or
          de.drug_source_value ilike '%rybelsus%' or
          de.drug_source_value ilike '%wegovy%' or
          de.drug_source_value ilike '%tirzepatide%' or
          de.drug_source_value ilike '%mounjaro%' or
          de.drug_source_value ilike '%zepbound%' or
          de.drug_source_value ilike '%canagliflozin%' or
          de.drug_source_value ilike '%invokana%' or
          de.drug_source_value ilike '%dapagliflozin%' or
          de.drug_source_value ilike '%farxiga%' or
          de.drug_source_value ilike '%empagliflozin%' or
          de.drug_source_value ilike '%jardiance%' or
          de.drug_source_value ilike '%ertugliflozin%' or
          de.drug_source_value ilike '%steglatro%' or
          de.drug_source_value ilike '%bexagliflozin%' or
          de.drug_source_value ilike '%brenzavvy%' or
          de.drug_source_value ilike '%repaglinide%' or
          de.drug_source_value ilike '%prandin%' or
          de.drug_source_value ilike '%nateglinide%' or
          de.drug_source_value ilike '%starlix%' or
          de.drug_source_value ilike '%acarbose%' or
          de.drug_source_value ilike '%precose%' or
          de.drug_source_value ilike '%miglitol%' or
          de.drug_source_value ilike '%glyset%' or
          de.drug_source_value ilike '%insulin glargine%' or
          de.drug_source_value ilike '%lantus%' or
          de.drug_source_value ilike '%basaglar%' or
          de.drug_source_value ilike '%toujeo%' or
          de.drug_source_value ilike '%insulin detemir%' or
          de.drug_source_value ilike '%levemir%' or
          de.drug_source_value ilike '%insulin degludec%' or
          de.drug_source_value ilike '%tresiba%' or
          de.drug_source_value ilike '%insulin nph%'
      )
),

aggregated as (
    select
        p.person_id,
        p.gender_concept_id,
        cast(null as varchar) as gender,
        p.year_of_birth,
        p.race_concept_id,
        cast(null as varchar) as race,
        p.ethnicity_concept_id,
        cast(null as varchar) as ethnicity,
        min(ae.event_date) as t2dm_index_date,
        max(ae.event_date) as last_evidence_date,
        count(distinct ae.event_date) as total_evidence_count,
        count(distinct case when ae.criterion_type = 'diagnosis' then ae.event_date end) as diagnosis_count,
        count(distinct case when ae.criterion_type = 'laboratory' then ae.event_date end) as lab_count,
        count(distinct case when ae.criterion_type = 'medication' then ae.event_date end) as medication_count,
        count(distinct ae.criterion_type) as distinct_criterion_types,
        date_diff(
            'year',
            make_date(p.year_of_birth, coalesce(p.month_of_birth, 1), coalesce(p.day_of_birth, 1)),
            min(ae.event_date)
        ) as age_at_index,
        case
            when count(distinct ae.criterion_type) >= 2 and count(distinct ae.event_date) >= 2 then 'High'
            when count(distinct case when ae.criterion_type = 'diagnosis' then ae.event_date end) >= 2 then 'High'
            when (
                count(distinct case when ae.criterion_type = 'diagnosis' then ae.event_date end) >= 1
                and count(distinct case when ae.criterion_type in ('laboratory', 'medication') then ae.event_date end) >= 1
            ) then 'Medium'
            else 'Low'
        end as confidence_level,
        vo.observation_period_start_date,
        vo.observation_period_end_date
    from memory.person p
    inner join all_evidence ae
        on p.person_id = ae.person_id
    inner join visit_observation vo
        on p.person_id = vo.person_id
       and ae.event_date >= vo.observation_period_start_date
       and ae.event_date <= vo.observation_period_end_date
    group by
        p.person_id,
        p.gender_concept_id,
        p.year_of_birth,
        p.month_of_birth,
        p.day_of_birth,
        p.race_concept_id,
        p.ethnicity_concept_id,
        vo.observation_period_start_date,
        vo.observation_period_end_date
    having
        (
            count(distinct case when ae.criterion_type = 'diagnosis' then ae.event_date end) >= 2
            or
            (
                count(distinct case when ae.criterion_type = 'diagnosis' then ae.event_date end) >= 1
                and count(distinct case when ae.criterion_type in ('laboratory', 'medication') then ae.event_date end) >= 1
            )
            or
            (
                count(distinct case when ae.criterion_type = 'laboratory' then ae.event_date end) >= 2
                and count(distinct case when ae.criterion_type = 'medication' then ae.event_date end) >= 2
            )
        )
)

select
    person_id,
    gender_concept_id,
    gender,
    year_of_birth,
    race_concept_id,
    race,
    ethnicity_concept_id,
    ethnicity,
    t2dm_index_date,
    last_evidence_date,
    total_evidence_count,
    diagnosis_count,
    lab_count,
    medication_count,
    distinct_criterion_types,
    age_at_index,
    confidence_level
from aggregated
where age_at_index >= 18
  and date_diff('day', observation_period_start_date, observation_period_end_date) >= 365
  and person_id not in (
      select distinct co.person_id
      from memory.condition_occurrence co
      where
          co.condition_source_value ilike 'E10%'
          or co.condition_source_value in (
              '250.01', '250.03', '250.11', '250.13', '250.21', '250.23',
              '250.31', '250.33', '250.41', '250.43', '250.51', '250.53',
              '250.61', '250.63', '250.71', '250.73', '250.81', '250.83',
              '250.91', '250.93'
          )
  )
  and person_id not in (
      select distinct co.person_id
      from memory.condition_occurrence co
      where
          (
              co.condition_source_value ilike 'O24.4%'
              or co.condition_source_value in ('648.80', '648.81', '648.82', '648.83', '648.84')
          )
          and not exists (
              select 1
              from memory.condition_occurrence co2
              where co2.person_id = co.person_id
                and co2.condition_start_date > co.condition_start_date + interval 12 month
                and (
                    co2.condition_source_value ilike 'E11%'
                    or co2.condition_source_value in (
                        '250.00', '250.02', '250.10', '250.12', '250.20', '250.22',
                        '250.30', '250.32', '250.40', '250.42', '250.50', '250.52',
                        '250.60', '250.62', '250.70', '250.72', '250.80', '250.82',
                        '250.90', '250.92'
                    )
                )
          )
  )
  and person_id not in (
      select distinct co.person_id
      from memory.condition_occurrence co
      where
          co.condition_source_value ilike 'E08%'
          or co.condition_source_value ilike 'E09%'
          or co.condition_source_value ilike 'E13%'
  )
order by t2dm_index_date, person_id;
