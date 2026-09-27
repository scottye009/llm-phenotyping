with t2_dx as (
    select
        co.person_id,
        try_cast(co.condition_start_date as date) as dx_date
    from memory.condition_occurrence co
    where (
        co.condition_source_value ilike 'E11%'
        or regexp_matches(co.condition_source_value, '^250\\.[0-9][02]$')
    )
),
non_insulin_rx as (
    select
        de.person_id,
        try_cast(de.drug_exposure_start_date as date) as drug_date
    from memory.drug_exposure de
    where (
        de.drug_source_value ilike '%metformin%' or de.drug_source_value ilike '%glucophage%' or
        de.drug_source_value ilike '%glucophage xr%' or de.drug_source_value ilike '%fortamet%' or
        de.drug_source_value ilike '%glumetza%' or de.drug_source_value ilike '%riomet%' or
        de.drug_source_value ilike '%glipizide%' or de.drug_source_value ilike '%glyburide%' or
        de.drug_source_value ilike '%glimepiride%' or de.drug_source_value ilike '%tolbutamide%' or
        de.drug_source_value ilike '%chlorpropamide%' or de.drug_source_value ilike '%glucotrol%' or
        de.drug_source_value ilike '%diabeta%' or de.drug_source_value ilike '%micronase%' or
        de.drug_source_value ilike '%glynase%' or de.drug_source_value ilike '%amaryl%' or
        de.drug_source_value ilike '%pioglitazone%' or de.drug_source_value ilike '%rosiglitazone%' or
        de.drug_source_value ilike '%actos%' or de.drug_source_value ilike '%avandia%' or
        de.drug_source_value ilike '%sitagliptin%' or de.drug_source_value ilike '%saxagliptin%' or
        de.drug_source_value ilike '%linagliptin%' or de.drug_source_value ilike '%alogliptin%' or
        de.drug_source_value ilike '%januvia%' or de.drug_source_value ilike '%onglyza%' or
        de.drug_source_value ilike '%tradjenta%' or de.drug_source_value ilike '%nesina%' or
        de.drug_source_value ilike '%liraglutide%' or de.drug_source_value ilike '%semaglutide%' or
        de.drug_source_value ilike '%dulaglutide%' or de.drug_source_value ilike '%exenatide%' or
        de.drug_source_value ilike '%lixisenatide%' or de.drug_source_value ilike '%victoza%' or
        de.drug_source_value ilike '%ozempic%' or de.drug_source_value ilike '%rybelsus%' or
        de.drug_source_value ilike '%trulicity%' or de.drug_source_value ilike '%byetta%' or
        de.drug_source_value ilike '%bydureon%' or de.drug_source_value ilike '%adlyxin%' or
        de.drug_source_value ilike '%canagliflozin%' or de.drug_source_value ilike '%dapagliflozin%' or
        de.drug_source_value ilike '%empagliflozin%' or de.drug_source_value ilike '%ertugliflozin%' or
        de.drug_source_value ilike '%invokana%' or de.drug_source_value ilike '%farxiga%' or
        de.drug_source_value ilike '%jardiance%' or de.drug_source_value ilike '%steglatro%' or
        de.drug_source_value ilike '%acarbose%' or de.drug_source_value ilike '%miglitol%' or
        de.drug_source_value ilike '%pramlintide%' or de.drug_source_value ilike '%repaglinide%' or
        de.drug_source_value ilike '%nateglinide%' or de.drug_source_value ilike '%precose%' or
        de.drug_source_value ilike '%glyset%' or de.drug_source_value ilike '%prandin%' or
        de.drug_source_value ilike '%starlix%'
    )
),
diabetes_labs as (
    select
        m.person_id,
        try_cast(m.measurement_date as date) as lab_date
    from memory.measurement m
    where m.value_as_number is not null
      and (
        (
            (
                m.measurement_source_value ilike '%4548-4%'
                or m.measurement_source_value ilike '%17856-6%'
                or m.measurement_source_value ilike '%41995-2%'
                or m.measurement_source_value ilike '%a1c%'
                or m.measurement_source_value ilike '%hba1c%'
                or m.measurement_source_value ilike '%hemoglobin a1c%'
            )
            and m.value_as_number >= 6.5
        )
        or
        (
            (
                m.measurement_source_value ilike '%1558-6%'
                or m.measurement_source_value ilike '%2345-7%'
                or m.measurement_source_value ilike '%2339-0%'
                or m.measurement_source_value ilike '%glucose%'
            )
            and m.value_as_number >= 126
        )
      )
),
c as (
    select
        dx.person_id,
        min(dx.dx_date) as index_date
    from t2_dx dx
    group by dx.person_id
    having count(distinct dx.dx_date) >= 2

    union

    select
        d.person_id,
        least(min(d.dx_date), min(rx.drug_date)) as index_date
    from t2_dx d
    join non_insulin_rx rx
      on rx.person_id = d.person_id
    group by d.person_id

    union

    select
        d.person_id,
        least(min(d.dx_date), min(l.lab_date)) as index_date
    from t2_dx d
    join diabetes_labs l
      on l.person_id = d.person_id
    group by d.person_id

    union

    select
        l.person_id,
        min(l.lab_date) as index_date
    from diabetes_labs l
    group by l.person_id
    having count(distinct l.lab_date) >= 2
)
select
    c.person_id,
    min(c.index_date) as index_date
from c
where not exists (
    select 1
    from memory.condition_occurrence g
    where g.person_id = c.person_id
      and (
        g.condition_source_value ilike '6488%'
        or g.condition_source_value ilike 'O244%'
        or g.condition_source_value ilike 'O249%'
      )
)
and not exists (
    select 1
    from memory.condition_occurrence s
    where s.person_id = c.person_id
      and (
        s.condition_source_value ilike 'E08%'
        or s.condition_source_value ilike 'E09%'
        or s.condition_source_value ilike 'E13%'
        or s.condition_source_value ilike '249%'
      )
)
and not exists (
    select 1
    from memory.condition_occurrence t1
    where t1.person_id = c.person_id
      and (
        t1.condition_source_value ilike 'E10%'
        or regexp_matches(t1.condition_source_value, '^250\\.[0-9][13]$')
      )
      and not exists (
          select 1
          from t2_dx t2
          where t2.person_id = t1.person_id
      )
      and not exists (
          select 1
          from non_insulin_rx de
          where de.person_id = t1.person_id
      )
      and not exists (
          select 1
          from diabetes_labs m2
          where m2.person_id = t1.person_id
      )
)
group by c.person_id
order by c.person_id;
