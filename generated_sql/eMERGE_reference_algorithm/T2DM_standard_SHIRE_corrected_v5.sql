-- T2DM_standard_SHIRE_corrected_v5_DUCKDB.sql
-- SHIRE / DuckDB version.
-- Best-effort SHIRE operationalization of the published eMERGE T2DM case algorithm.
--
-- Fixes from v4:
-- 1. Excludes ICD-9 250.10 and 250.12 from T2DM diagnosis logic, as specified by eMERGE.
-- 2. Adds a separate physician-entered T2DM diagnosis count for eMERGE path 5.
-- 3. Searches medication names across drug_source_value, drug_concept_name,
--    drug_source_concept_name, and drug_source_concept_code.
-- 4. Allows generic "Glucose" measurement_source_value for random glucose logic.
-- 5. Continues to use SHIRE source fields directly instead of OMOP vocabulary joins.

with

condition_source_codes as (
    select distinct
        person_id,
        cast(condition_start_date as date) as dx_date,
        upper(regexp_replace(coalesce(condition_source_value, ''), '[^A-Za-z0-9]', '', 'g')) as src_code,
        lower(coalesce(condition_type_concept_name, '')) as condition_type_text,
        lower(coalesce(condition_status_source_value, '')) as condition_status_text,
        lower(coalesce(condition_source_concept_name, '')) as condition_source_name_text,
        lower(coalesce(condition_concept_name, '')) as condition_name_text
    from memory.condition_occurrence
    where cast(condition_start_date as date) is not null
),

t2dm_dx_dates as (
    select distinct person_id, dx_date
    from condition_source_codes
    where src_code like 'E11%'
       or (
            regexp_matches(src_code, '^250[0-9][02]$')
            and src_code not in ('25010', '25012')
       )
),

t1dm_dx_dates as (
    select distinct person_id, dx_date
    from condition_source_codes
    where src_code like 'E10%'
       or regexp_matches(src_code, '^250[0-9][13]$')
),

t2dm_physician_dx_dates as (
    select distinct person_id, dx_date
    from condition_source_codes
    where (
            src_code like 'E11%'
            or (
                regexp_matches(src_code, '^250[0-9][02]$')
                and src_code not in ('25010', '25012')
            )
          )
      and (
            condition_type_text like '%problem%'
            or condition_type_text like '%encounter%'
            or condition_status_text like '%problem%'
            or condition_status_text like '%encounter%'
            or condition_source_name_text like '%problem%'
            or condition_source_name_text like '%encounter%'
          )
      and condition_type_text not like '%billing%'
      and condition_status_text not like '%billing%'
      and condition_source_name_text not like '%billing%'
),

drug_text as (
    select
        person_id,
        coalesce(
            cast(drug_exposure_start_date as date),
            cast(drug_exposure_end_date as date)
        ) as rx_date,
        lower(
            coalesce(drug_source_value, '') || ' ' ||
            coalesce(drug_concept_name, '') || ' ' ||
            coalesce(drug_source_concept_code, '') || ' ' ||
            coalesce(drug_type_concept_name, '')
        ) as rx_text
    from memory.drug_exposure
    where coalesce(
            cast(drug_exposure_start_date as date),
            cast(drug_exposure_end_date as date)
          ) is not null
),

t1dm_rx_dates as (
    select
        person_id,
        min(rx_date) as first_t1dm_rx_date
    from drug_text
    where rx_text like '%insulin%'
       or rx_text like '%symlin%'
       or rx_text like '%pramlintide%'
    group by person_id
),

t2dm_rx_dates as (
    select
        person_id,
        min(rx_date) as first_t2dm_rx_date
    from drug_text
    where rx_text like '%metformin%'
       or rx_text like '%glucophage%'
       or rx_text like '%glipizide%'
       or rx_text like '%glucotrol%'
       or rx_text like '%glucotrol xl%'
       or rx_text like '%glyburide%'
       or rx_text like '%micronase%'
       or rx_text like '%glynase%'
       or rx_text like '%diabeta%'
       or rx_text like '%glimepiride%'
       or rx_text like '%amaryl%'
       or rx_text like '%repaglinide%'
       or rx_text like '%prandin%'
       or rx_text like '%nateglinide%'
       or rx_text like '%starlix%'
       or rx_text like '%rosiglitazone%'
       or rx_text like '%avandia%'
       or rx_text like '%pioglitazone%'
       or rx_text like '%actos%'
       or rx_text like '%troglitazone%'
       or rx_text like '%rezulin%'
       or rx_text like '%acarbose%'
       or rx_text like '%precose%'
       or rx_text like '%miglitol%'
       or rx_text like '%glyset%'
       or rx_text like '%sitagliptin%'
       or rx_text like '%januvia%'
       or rx_text like '%exenatide%'
       or rx_text like '%byetta%'
       or rx_text like '%acetohexamide%'
       or rx_text like '%dymelor%'
       or rx_text like '%tolazamide%'
       or rx_text like '%tolinase%'
       or rx_text like '%chlorpropamide%'
       or rx_text like '%diabinese%'
    group by person_id
),

measurement_text as (
    select
        person_id,
        cast(measurement_date as date) as measurement_date,
        lower(coalesce(measurement_source_value, '')) as meas_text,
        trim(lower(coalesce(measurement_source_value, ''))) as meas_text_trim,
        lower(coalesce(unit_source_value, '')) as unit_source_text,
        lower(coalesce(unit_concept_name, '')) as unit_concept_text,
        value_as_number
    from memory.measurement
    where value_as_number is not null
),

abnormal_lab_people as (
    select distinct person_id
    from measurement_text
    where
        (
            (
                meas_text like '%a1c%'
                or meas_text like '%hba1c%'
                or meas_text like '%hemoglobin%a1c%'
            )
            and value_as_number >= 6.5
        )
        or
        (
            meas_text like '%fasting%glucose%'
            and meas_text not like '%urine%'
            and value_as_number >= 125
        )
        or
        (
            (
                meas_text like '%random%glucose%'
                or meas_text_trim = 'glucose'
                or (
                    meas_text like '%glucose%'
                    and (
                        meas_text like '%blood%'
                        or meas_text like '%serum%'
                        or meas_text like '%plasma%'
                        or meas_text like 'glucose %'
                    )
                    and meas_text not like '%fasting%'
                    and meas_text not like '%urine%'
                    and meas_text not like '%cerebrospinal%'
                    and meas_text not like '%csf%'
                )
            )
            and value_as_number > 200
        )
),

all_people as (
    select distinct person_id
    from memory.person
),

t1dm_dx_counts as (
    select
        person_id,
        count(*) as t1dm_dx_dt_cnt
    from t1dm_dx_dates
    group by person_id
),

t2dm_dx_counts as (
    select
        person_id,
        count(*) as t2dm_dx_dt_cnt
    from t2dm_dx_dates
    group by person_id
),

t2dm_physician_dx_counts as (
    select
        person_id,
        count(*) as t2dm_physcn_dx_dt_cnt
    from t2dm_physician_dx_dates
    group by person_id
),

features as (
    select
        p.person_id,
        coalesce(t1c.t1dm_dx_dt_cnt, 0) as t1dm_dx_dt_cnt,
        coalesce(t2c.t2dm_dx_dt_cnt, 0) as t2dm_dx_dt_cnt,
        coalesce(t2pc.t2dm_physcn_dx_dt_cnt, 0) as t2dm_physcn_dx_dt_cnt,
        t1.first_t1dm_rx_date as t1dm_rx_dt,
        t2.first_t2dm_rx_date as t2dm_rx_dt,
        case when abl.person_id is not null then 1 else 0 end as has_abnormal_lab
    from all_people p
    left join t1dm_dx_counts t1c
      on p.person_id = t1c.person_id
    left join t2dm_dx_counts t2c
      on p.person_id = t2c.person_id
    left join t2dm_physician_dx_counts t2pc
      on p.person_id = t2pc.person_id
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
        -- Path 1:
        -- no T1DM dx, T2DM dx present, both med types present,
        -- and T2DM medication precedes T1DM medication
        (
            f.t1dm_dx_dt_cnt = 0
            and f.t2dm_dx_dt_cnt > 0
            and f.t2dm_rx_dt is not null
            and f.t1dm_rx_dt is not null
            and f.t2dm_rx_dt < f.t1dm_rx_dt
        )

        or

        -- Path 2:
        -- no T1DM dx, T2DM dx present, no T1DM med, T2DM med present
        (
            f.t1dm_dx_dt_cnt = 0
            and f.t2dm_dx_dt_cnt > 0
            and f.t1dm_rx_dt is null
            and f.t2dm_rx_dt is not null
        )

        or

        -- Path 3:
        -- no T1DM dx, T2DM dx present, no diabetes meds,
        -- and abnormal lab present
        (
            f.t1dm_dx_dt_cnt = 0
            and f.t2dm_dx_dt_cnt > 0
            and f.t1dm_rx_dt is null
            and f.t2dm_rx_dt is null
            and f.has_abnormal_lab = 1
        )

        or

        -- Path 4:
        -- no T1DM dx, no T2DM dx, T2DM med present,
        -- and abnormal lab present
        (
            f.t1dm_dx_dt_cnt = 0
            and f.t2dm_dx_dt_cnt = 0
            and f.t2dm_rx_dt is not null
            and f.has_abnormal_lab = 1
        )

        or

        -- Path 5:
        -- no T1DM dx, T2DM dx present, T1DM med present,
        -- no T2DM med, and at least 2 physician-entered T2DM dx dates
        (
            f.t1dm_dx_dt_cnt = 0
            and f.t2dm_dx_dt_cnt > 0
            and f.t1dm_rx_dt is not null
            and f.t2dm_rx_dt is null
            and f.t2dm_physcn_dx_dt_cnt >= 2
        )
)

select distinct person_id
from classified
order by person_id;