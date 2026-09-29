-- T2DM_standard_corrected_v4_POSTGRES.sql
-- Synthetic/full-OMOP PostgreSQL version.
-- This file is for pgAdmin/PostgreSQL and intentionally uses public.* tables.
--
-- eMERGE-style 5-path case logic with best-effort Path 5 approximation.
-- Main v4 fix: prevent T1/T2 diagnosis contamination by using clean standard
-- concept ancestry rooted at Type 1 diabetes mellitus vs Type 2 diabetes mellitus
-- and explicitly removing concept overlap before counting diagnosis dates.

with
root_t1dm as (
    select concept_id
    from public.concept
    where domain_id = 'Condition'
      and concept_name = 'Type 1 diabetes mellitus'
),

root_t2dm as (
    select concept_id
    from public.concept
    where domain_id = 'Condition'
      and concept_name = 'Type 2 diabetes mellitus'
),

raw_t1dm_std_concepts as (
    select concept_id from root_t1dm
    union
    select ca.descendant_concept_id as concept_id
    from public.concept_ancestor ca
    join root_t1dm r
      on ca.ancestor_concept_id = r.concept_id
),

raw_t2dm_std_concepts as (
    select concept_id from root_t2dm
    union
    select ca.descendant_concept_id as concept_id
    from public.concept_ancestor ca
    join root_t2dm r
      on ca.ancestor_concept_id = r.concept_id
),

overlap_dm_std_concepts as (
    select concept_id from raw_t1dm_std_concepts
    intersect
    select concept_id from raw_t2dm_std_concepts
),

t1dm_std_concepts as (
    select concept_id
    from raw_t1dm_std_concepts
    where concept_id not in (select concept_id from overlap_dm_std_concepts)
),

t2dm_std_concepts as (
    select concept_id
    from raw_t2dm_std_concepts
    where concept_id not in (select concept_id from overlap_dm_std_concepts)
),

t1dm_dx_dates as (
    select distinct
        co.person_id,
        co.condition_start_date as dx_date
    from public.condition_occurrence co
    join t1dm_std_concepts t1
      on co.condition_concept_id = t1.concept_id
    where co.condition_start_date is not null
),

t2dm_dx_dates as (
    select distinct
        co.person_id,
        co.condition_start_date as dx_date
    from public.condition_occurrence co
    join t2dm_std_concepts t2
      on co.condition_concept_id = t2.concept_id
    where co.condition_start_date is not null
),

t1dm_rx_dates as (
    select
        de.person_id,
        min(coalesce(de.drug_exposure_start_date, de.drug_exposure_end_date)) as first_t1dm_rx_date
    from public.drug_exposure de
    left join public.concept c
      on de.drug_concept_id = c.concept_id
    where coalesce(de.drug_exposure_start_date, de.drug_exposure_end_date) is not null
      and (
          coalesce(lower(de.drug_source_value), '') like '%insulin%'
          or coalesce(lower(de.drug_source_value), '') like '%symlin%'
          or coalesce(lower(de.drug_source_value), '') like '%pramlintide%'
          or coalesce(lower(c.concept_name), '') like '%insulin%'
          or coalesce(lower(c.concept_name), '') like '%symlin%'
          or coalesce(lower(c.concept_name), '') like '%pramlintide%'
      )
    group by de.person_id
),

t2dm_rx_dates as (
    select
        de.person_id,
        min(coalesce(de.drug_exposure_start_date, de.drug_exposure_end_date)) as first_t2dm_rx_date
    from public.drug_exposure de
    left join public.concept c
      on de.drug_concept_id = c.concept_id
    where coalesce(de.drug_exposure_start_date, de.drug_exposure_end_date) is not null
      and (
          coalesce(lower(de.drug_source_value), '') like '%metformin%' or
          coalesce(lower(de.drug_source_value), '') like '%glipizide%' or
          coalesce(lower(de.drug_source_value), '') like '%acetohexamide%' or
          coalesce(lower(de.drug_source_value), '') like '%dymelor%' or
          coalesce(lower(de.drug_source_value), '') like '%tolazamide%' or
          coalesce(lower(de.drug_source_value), '') like '%tolinase%' or
          coalesce(lower(de.drug_source_value), '') like '%chlorpropamide%' or
          coalesce(lower(de.drug_source_value), '') like '%diabinese%' or
          coalesce(lower(de.drug_source_value), '') like '%glucotrol%' or
          coalesce(lower(de.drug_source_value), '') like '%glucotrol xl%' or
          coalesce(lower(de.drug_source_value), '') like '%glyburide%' or
          coalesce(lower(de.drug_source_value), '') like '%micronase%' or
          coalesce(lower(de.drug_source_value), '') like '%glynase%' or
          coalesce(lower(de.drug_source_value), '') like '%diabeta%' or
          coalesce(lower(de.drug_source_value), '') like '%glimepiride%' or
          coalesce(lower(de.drug_source_value), '') like '%amaryl%' or
          coalesce(lower(de.drug_source_value), '') like '%repaglinide%' or
          coalesce(lower(de.drug_source_value), '') like '%prandin%' or
          coalesce(lower(de.drug_source_value), '') like '%nateglinide%' or
          coalesce(lower(de.drug_source_value), '') like '%starlix%' or
          coalesce(lower(de.drug_source_value), '') like '%glucophage%' or
          coalesce(lower(de.drug_source_value), '') like '%rosiglitazone%' or
          coalesce(lower(de.drug_source_value), '') like '%avandia%' or
          coalesce(lower(de.drug_source_value), '') like '%pioglitazone%' or
          coalesce(lower(de.drug_source_value), '') like '%actos%' or
          coalesce(lower(de.drug_source_value), '') like '%troglitazone%' or
          coalesce(lower(de.drug_source_value), '') like '%rezulin%' or
          coalesce(lower(de.drug_source_value), '') like '%acarbose%' or
          coalesce(lower(de.drug_source_value), '') like '%precose%' or
          coalesce(lower(de.drug_source_value), '') like '%miglitol%' or
          coalesce(lower(de.drug_source_value), '') like '%glyset%' or
          coalesce(lower(de.drug_source_value), '') like '%sitagliptin%' or
          coalesce(lower(de.drug_source_value), '') like '%januvia%' or
          coalesce(lower(de.drug_source_value), '') like '%exenatide%' or
          coalesce(lower(de.drug_source_value), '') like '%byetta%' or
          coalesce(lower(c.concept_name), '') like '%metformin%' or
          coalesce(lower(c.concept_name), '') like '%glipizide%' or
          coalesce(lower(c.concept_name), '') like '%acetohexamide%' or
          coalesce(lower(c.concept_name), '') like '%dymelor%' or
          coalesce(lower(c.concept_name), '') like '%tolazamide%' or
          coalesce(lower(c.concept_name), '') like '%tolinase%' or
          coalesce(lower(c.concept_name), '') like '%chlorpropamide%' or
          coalesce(lower(c.concept_name), '') like '%diabinese%' or
          coalesce(lower(c.concept_name), '') like '%glucotrol%' or
          coalesce(lower(c.concept_name), '') like '%glucotrol xl%' or
          coalesce(lower(c.concept_name), '') like '%glyburide%' or
          coalesce(lower(c.concept_name), '') like '%micronase%' or
          coalesce(lower(c.concept_name), '') like '%glynase%' or
          coalesce(lower(c.concept_name), '') like '%diabeta%' or
          coalesce(lower(c.concept_name), '') like '%glimepiride%' or
          coalesce(lower(c.concept_name), '') like '%amaryl%' or
          coalesce(lower(c.concept_name), '') like '%repaglinide%' or
          coalesce(lower(c.concept_name), '') like '%prandin%' or
          coalesce(lower(c.concept_name), '') like '%nateglinide%' or
          coalesce(lower(c.concept_name), '') like '%starlix%' or
          coalesce(lower(c.concept_name), '') like '%glucophage%' or
          coalesce(lower(c.concept_name), '') like '%rosiglitazone%' or
          coalesce(lower(c.concept_name), '') like '%avandia%' or
          coalesce(lower(c.concept_name), '') like '%pioglitazone%' or
          coalesce(lower(c.concept_name), '') like '%actos%' or
          coalesce(lower(c.concept_name), '') like '%troglitazone%' or
          coalesce(lower(c.concept_name), '') like '%rezulin%' or
          coalesce(lower(c.concept_name), '') like '%acarbose%' or
          coalesce(lower(c.concept_name), '') like '%precose%' or
          coalesce(lower(c.concept_name), '') like '%miglitol%' or
          coalesce(lower(c.concept_name), '') like '%glyset%' or
          coalesce(lower(c.concept_name), '') like '%sitagliptin%' or
          coalesce(lower(c.concept_name), '') like '%januvia%' or
          coalesce(lower(c.concept_name), '') like '%exenatide%' or
          coalesce(lower(c.concept_name), '') like '%byetta%'
      )
    group by de.person_id
),

abnormal_lab_people as (
    select distinct m.person_id
    from public.measurement m
    left join public.concept c
      on m.measurement_concept_id = c.concept_id
    where m.value_as_number is not null
      and (
          (
              (
                  coalesce(lower(m.measurement_source_value), '') like '%a1c%'
                  or coalesce(lower(m.measurement_source_value), '') like '%hba1c%'
                  or coalesce(lower(m.measurement_source_value), '') like '%hemoglobin%a1c%'
                  or coalesce(lower(c.concept_name), '') like '%hemoglobin a1c%'
              )
              and m.value_as_number >= 6.5
          )
          or
          (
              (
                  coalesce(lower(m.measurement_source_value), '') like '%fasting%glucose%'
                  or coalesce(lower(c.concept_name), '') like '%fasting glucose%'
              )
              and coalesce(lower(m.measurement_source_value), '') not like '%urine%'
              and m.value_as_number >= 125
          )
          or
          (
              (
                  coalesce(lower(m.measurement_source_value), '') like '%random%glucose%'
                  or coalesce(lower(c.concept_name), '') like '%random glucose%'
              )
              and m.value_as_number > 200
          )
      )
),

all_people as (
    select person_id from public.person
),

t1dm_dx_counts as (
    select person_id, count(*) as t1dm_dx_dt_cnt
    from t1dm_dx_dates
    group by person_id
),

t2dm_dx_counts as (
    select person_id, count(*) as t2dm_dx_dt_cnt
    from t2dm_dx_dates
    group by person_id
),

features as (
    select
        p.person_id,
        coalesce(t1c.t1dm_dx_dt_cnt, 0) as t1dm_dx_dt_cnt,
        coalesce(t2c.t2dm_dx_dt_cnt, 0) as t2dm_dx_dt_cnt,
        t1.first_t1dm_rx_date as t1dm_rx_dt,
        t2.first_t2dm_rx_date as t2dm_rx_dt,
        case when abl.person_id is not null then 1 else 0 end as has_abnormal_lab
    from all_people p
    left join t1dm_dx_counts t1c
      on p.person_id = t1c.person_id
    left join t2dm_dx_counts t2c
      on p.person_id = t2c.person_id
    left join t1dm_rx_dates t1
      on p.person_id = t1.person_id
    left join t2dm_rx_dates t2
      on p.person_id = t2.person_id
    left join abnormal_lab_people abl
      on p.person_id = abl.person_id
),

classified as (
    select person_id
    from features f
    where
        (
            f.t1dm_dx_dt_cnt = 0
            and f.t2dm_dx_dt_cnt > 0
            and f.t2dm_rx_dt is not null
            and f.t1dm_rx_dt is not null
            and f.t2dm_rx_dt < f.t1dm_rx_dt
        )
        or
        (
            f.t1dm_dx_dt_cnt = 0
            and f.t2dm_dx_dt_cnt > 0
            and f.t1dm_rx_dt is null
            and f.t2dm_rx_dt is not null
        )
        or
        (
            f.t1dm_dx_dt_cnt = 0
            and f.t2dm_dx_dt_cnt > 0
            and f.t1dm_rx_dt is null
            and f.t2dm_rx_dt is null
            and f.has_abnormal_lab = 1
        )
        or
        (
            f.t1dm_dx_dt_cnt = 0
            and f.t2dm_dx_dt_cnt = 0
            and f.t2dm_rx_dt is not null
            and f.has_abnormal_lab = 1
        )
        or
        (
            f.t1dm_dx_dt_cnt = 0
            and f.t2dm_dx_dt_cnt >= 2
            and f.t1dm_rx_dt is not null
            and f.t2dm_rx_dt is null
        )
)

select distinct person_id
from classified
order by person_id;
