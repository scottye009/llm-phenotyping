select distinct p.person_id
from memory.person p
join memory.condition_occurrence co
  on p.person_id = co.person_id
where
  (
    co.condition_source_value ilike 'E11%'
    or co.condition_source_value ~ '^250\.[0-9]0$'
    or co.condition_source_value ~ '^250\.[0-9]2$'
  )
  and (
    (
      select count(distinct try_cast(co2.condition_start_date as date))
      from memory.condition_occurrence co2
      where co2.person_id = p.person_id
        and (
          co2.condition_source_value ilike 'E11%'
          or co2.condition_source_value ~ '^250\.[0-9]0$'
          or co2.condition_source_value ~ '^250\.[0-9]2$'
        )
    ) >= 2
    or exists (
      select 1
      from memory.drug_exposure de
      where de.person_id = p.person_id
        and (
          lower(coalesce(de.drug_source_value, '')) like '%metformin%' or lower(coalesce(de.drug_source_value, '')) like '%glucophage%' or
          lower(coalesce(de.drug_source_value, '')) like '%glipizide%' or lower(coalesce(de.drug_source_value, '')) like '%glucotrol%' or
          lower(coalesce(de.drug_source_value, '')) like '%glyburide%' or lower(coalesce(de.drug_source_value, '')) like '%micronase%' or
          lower(coalesce(de.drug_source_value, '')) like '%glimepiride%' or lower(coalesce(de.drug_source_value, '')) like '%amaryl%' or
          lower(coalesce(de.drug_source_value, '')) like '%pioglitazone%' or lower(coalesce(de.drug_source_value, '')) like '%actos%' or
          lower(coalesce(de.drug_source_value, '')) like '%rosiglitazone%' or lower(coalesce(de.drug_source_value, '')) like '%avandia%' or
          lower(coalesce(de.drug_source_value, '')) like '%sitagliptin%' or lower(coalesce(de.drug_source_value, '')) like '%januvia%' or
          lower(coalesce(de.drug_source_value, '')) like '%saxagliptin%' or lower(coalesce(de.drug_source_value, '')) like '%onglyza%' or
          lower(coalesce(de.drug_source_value, '')) like '%linagliptin%' or lower(coalesce(de.drug_source_value, '')) like '%tradjenta%' or
          lower(coalesce(de.drug_source_value, '')) like '%empagliflozin%' or lower(coalesce(de.drug_source_value, '')) like '%jardiance%' or
          lower(coalesce(de.drug_source_value, '')) like '%dapagliflozin%' or lower(coalesce(de.drug_source_value, '')) like '%farxiga%' or
          lower(coalesce(de.drug_source_value, '')) like '%canagliflozin%' or lower(coalesce(de.drug_source_value, '')) like '%invokana%' or
          lower(coalesce(de.drug_source_value, '')) like '%liraglutide%' or lower(coalesce(de.drug_source_value, '')) like '%victoza%' or
          lower(coalesce(de.drug_source_value, '')) like '%semaglutide%' or lower(coalesce(de.drug_source_value, '')) like '%ozempic%' or lower(coalesce(de.drug_source_value, '')) like '%rybelsus%' or
          lower(coalesce(de.drug_source_value, '')) like '%exenatide%' or lower(coalesce(de.drug_source_value, '')) like '%byetta%' or lower(coalesce(de.drug_source_value, '')) like '%bydureon%' or
          lower(coalesce(de.drug_source_value, '')) like '%dulaglutide%' or lower(coalesce(de.drug_source_value, '')) like '%trulicity%'
        )
    )
    or exists (
      select 1
      from memory.measurement m
      where m.person_id = p.person_id
        and (
          lower(coalesce(m.measurement_source_value, '')) like '%a1c%'
          or lower(coalesce(m.measurement_source_value, '')) like '%hba1c%'
          or lower(coalesce(m.measurement_source_value, '')) like '%hemoglobin a1c%'
          or lower(coalesce(m.measurement_source_value, '')) like '%glycated hemoglobin%'
        )
        and m.value_as_number >= 6.5
    )
  )
  and not exists (
    select 1
    from memory.condition_occurrence co_ex
    where co_ex.person_id = p.person_id
      and (
        co_ex.condition_source_value ilike 'E10%'
        or co_ex.condition_source_value ~ '^250\.[0-9]1$'
        or co_ex.condition_source_value ~ '^250\.[0-9]3$'
        or co_ex.condition_source_value ilike 'O24.4%'
        or co_ex.condition_source_value ilike 'O24.9%'
        or co_ex.condition_source_value like '648.0%'
      )
  );
