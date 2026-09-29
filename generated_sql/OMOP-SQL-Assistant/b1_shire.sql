with t2_dx as (
    select
        co.person_id,
        try_cast(co.condition_start_date as date) as dx_date
    from memory.condition_occurrence co
    where (
        co.condition_source_value ilike 'E11%'
        or (
            co.condition_source_value ilike '250.%'
            and right(regexp_replace(co.condition_source_value, '[^0-9]', '', 'g'), 1) in ('0','2')
        )
    )
),
non_insulin_rx as (
    select
        de.person_id,
        try_cast(de.drug_exposure_start_date as date) as drug_date
    from memory.drug_exposure de
    where (
        de.drug_source_value ilike '%metformin%' or de.drug_source_value ilike '%glucophage%' or
        de.drug_source_value ilike '%fortamet%' or de.drug_source_value ilike '%glumetza%' or
        de.drug_source_value ilike '%riomet%' or
        de.drug_source_value ilike '%glipizide%' or de.drug_source_value ilike '%glucotrol%' or
        de.drug_source_value ilike '%glucotrol xl%' or de.drug_source_value ilike '%glyburide%' or
        de.drug_source_value ilike '%diabeta%' or de.drug_source_value ilike '%micronase%' or
        de.drug_source_value ilike '%glynase%' or de.drug_source_value ilike '%glimepiride%' or
        de.drug_source_value ilike '%amaryl%' or
        de.drug_source_value ilike '%pioglitazone%' or de.drug_source_value ilike '%actos%' or
        de.drug_source_value ilike '%rosiglitazone%' or de.drug_source_value ilike '%avandia%' or
        de.drug_source_value ilike '%sitagliptin%' or de.drug_source_value ilike '%januvia%' or
        de.drug_source_value ilike '%saxagliptin%' or de.drug_source_value ilike '%onglyza%' or
        de.drug_source_value ilike '%linagliptin%' or de.drug_source_value ilike '%tradjenta%' or
        de.drug_source_value ilike '%alogliptin%' or de.drug_source_value ilike '%nesina%' or
        de.drug_source_value ilike '%exenatide%' or de.drug_source_value ilike '%byetta%' or
        de.drug_source_value ilike '%bydureon%' or de.drug_source_value ilike '%liraglutide%' or
        de.drug_source_value ilike '%victoza%' or de.drug_source_value ilike '%dulaglutide%' or
        de.drug_source_value ilike '%trulicity%' or de.drug_source_value ilike '%semaglutide%' or
        de.drug_source_value ilike '%ozempic%' or de.drug_source_value ilike '%rybelsus%' or
        de.drug_source_value ilike '%lixisenatide%' or de.drug_source_value ilike '%adlyxin%' or
        de.drug_source_value ilike '%tirzepatide%' or de.drug_source_value ilike '%mounjaro%' or
        de.drug_source_value ilike '%canagliflozin%' or de.drug_source_value ilike '%invokana%' or
        de.drug_source_value ilike '%dapagliflozin%' or de.drug_source_value ilike '%farxiga%' or
        de.drug_source_value ilike '%empagliflozin%' or de.drug_source_value ilike '%jardiance%' or
        de.drug_source_value ilike '%ertugliflozin%' or de.drug_source_value ilike '%steglatro%' or
        de.drug_source_value ilike '%repaglinide%' or de.drug_source_value ilike '%prandin%' or
        de.drug_source_value ilike '%nateglinide%' or de.drug_source_value ilike '%starlix%' or
        de.drug_source_value ilike '%acarbose%' or de.drug_source_value ilike '%precose%' or
        de.drug_source_value ilike '%miglitol%' or de.drug_source_value ilike '%glyset%' or
        de.drug_source_value ilike '%pramlintide%' or de.drug_source_value ilike '%symlin%' or
        de.drug_source_value ilike '%janumet%' or de.drug_source_value ilike '%synjardy%' or
        de.drug_source_value ilike '%xigduo%' or de.drug_source_value ilike '%glyxambi%' or
        de.drug_source_value ilike '%qtern%'
    )
),
abnormal_labs as (
    select
        m.person_id,
        try_cast(m.measurement_date as date) as lab_date
    from memory.measurement m
    where m.value_as_number is not null
      and (
        ((m.measurement_source_value ilike '%hemoglobin a1c%' or m.measurement_source_value ilike '%hba1c%' or m.measurement_source_value ilike '%a1c%') and m.value_as_number >= 6.5)
        or ((m.measurement_source_value ilike '%glucose%' and m.measurement_source_value ilike '%fasting%') and m.value_as_number >= 126)
        or ((m.measurement_source_value ilike '%glucose%') and m.value_as_number >= 200)
        or ((m.measurement_source_value ilike '%oral glucose tolerance%') and m.value_as_number >= 200)
        or ((m.measurement_source_value ilike '%glucose%' and m.measurement_source_value ilike '%2 hour%') and m.value_as_number >= 200)
      )
),
visit_window as (
    select
        person_id,
        min(try_cast(visit_start_date as date)) as obs_start_date,
        max(try_cast(coalesce(visit_end_date, visit_start_date) as date)) as obs_end_date
    from memory.visit_occurrence
    group by person_id
),
final as (
    select
        ci.person_id,
        ci.index_date
    from (
        select
            u.person_id,
            min(u.index_date) as index_date
        from (
            select
                dx.person_id,
                min(dx.dx_date) as index_date
            from t2_dx dx
            group by dx.person_id
            having count(distinct dx.dx_date) >= 2

            union all

            select
                j.person_id,
                min(j.first_evidence_date) as index_date
            from (
                select
                    d.person_id,
                    least(d.dx_date, m.drug_date) as first_evidence_date
                from t2_dx d
                join non_insulin_rx m
                  on m.person_id = d.person_id
            ) j
            group by j.person_id

            union all

            select
                l.person_id,
                min(l.lab_date) as index_date
            from abnormal_labs l
            group by l.person_id
            having count(distinct l.lab_date) >= 2

            union all

            select
                j.person_id,
                min(j.first_evidence_date) as index_date
            from (
                select
                    l.person_id,
                    least(l.lab_date, m.drug_date) as first_evidence_date
                from abnormal_labs l
                join non_insulin_rx m
                  on m.person_id = l.person_id
            ) j
            group by j.person_id
        ) u
        group by u.person_id
    ) ci
    join visit_window vw
      on vw.person_id = ci.person_id
     and ci.index_date between vw.obs_start_date and vw.obs_end_date
)
select
    final.person_id,
    final.index_date
from final
where not exists (
    select 1
    from memory.condition_occurrence co
    where co.person_id = final.person_id
      and (
        co.condition_source_value ilike 'E10%'
        or (
            co.condition_source_value ilike '250.%'
            and right(regexp_replace(co.condition_source_value, '[^0-9]', '', 'g'), 1) in ('1','3')
        )
        or co.condition_source_value ilike 'O24%'
        or co.condition_source_value ilike '648.8%'
        or co.condition_source_value ilike '6488%'
        or co.condition_source_value ilike 'E08%'
        or co.condition_source_value ilike 'E09%'
        or co.condition_source_value ilike 'E13%'
        or co.condition_source_value ilike '249%'
      )
)
order by final.person_id, final.index_date;
