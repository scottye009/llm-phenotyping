select distinct p.person_id
from memory.person p
join memory.condition_occurrence co
  on p.person_id = co.person_id
where
  -- inclusion: must have at least one t2dm diagnosis code
  (
    co.condition_source_value ilike 'E11%'
    or regexp_matches(co.condition_source_value, '^250\.[0-9][02]$')
  )
  and (
    -- criteria A: two or more t2dm diagnoses on different days
    (
      select count(distinct try_cast(co2.condition_start_date as date))
      from memory.condition_occurrence co2
      where co2.person_id = p.person_id
        and (
          co2.condition_source_value ilike 'E11%'
          or regexp_matches(co2.condition_source_value, '^250\.[0-9][02]$')
        )
    ) >= 2

    or

    -- criteria B: t2dm specific medication exposure
    exists (
      select 1
      from memory.drug_exposure de
      where de.person_id = p.person_id
        and (
          lower(de.drug_source_value) like '%metformin%' or lower(de.drug_source_value) like '%glucophage%' or
          lower(de.drug_source_value) like '%glipizide%' or lower(de.drug_source_value) like '%glucotrol%' or
          lower(de.drug_source_value) like '%glyburide%' or lower(de.drug_source_value) like '%micronase%' or
          lower(de.drug_source_value) like '%glimepiride%' or lower(de.drug_source_value) like '%amaryl%' or
          lower(de.drug_source_value) like '%pioglitazone%' or lower(de.drug_source_value) like '%actos%' or
          lower(de.drug_source_value) like '%rosiglitazone%' or lower(de.drug_source_value) like '%avandia%' or
          lower(de.drug_source_value) like '%sitagliptin%' or lower(de.drug_source_value) like '%januvia%' or
          lower(de.drug_source_value) like '%saxagliptin%' or lower(de.drug_source_value) like '%onglyza%' or
          lower(de.drug_source_value) like '%linagliptin%' or lower(de.drug_source_value) like '%tradjenta%' or
          lower(de.drug_source_value) like '%empagliflozin%' or lower(de.drug_source_value) like '%jardiance%' or
          lower(de.drug_source_value) like '%dapagliflozin%' or lower(de.drug_source_value) like '%farxiga%' or
          lower(de.drug_source_value) like '%canagliflozin%' or lower(de.drug_source_value) like '%invokana%' or
          lower(de.drug_source_value) like '%liraglutide%' or lower(de.drug_source_value) like '%victoza%' or
          lower(de.drug_source_value) like '%semaglutide%' or lower(de.drug_source_value) like '%ozempic%' or lower(de.drug_source_value) like '%rybelsus%' or
          lower(de.drug_source_value) like '%exenatide%' or lower(de.drug_source_value) like '%byetta%' or lower(de.drug_source_value) like '%bydureon%' or
          lower(de.drug_source_value) like '%dulaglutide%' or lower(de.drug_source_value) like '%trulicity%'
        )
    )

    or

    -- criteria C: abnormal HbA1c lab result (>= 6.5%)
    exists (
      select 1
      from memory.measurement m
      where m.person_id = p.person_id
        and (
          lower(m.measurement_source_value) like '%a1c%'
          or lower(m.measurement_source_value) like '%hba1c%'
          or lower(m.measurement_source_value) like '%hemoglobin a1c%'
          or lower(m.measurement_source_value) like '%glycated hemoglobin%'
        )
        and try_cast(m.value_as_number as double) >= 6.5
    )
  )
  -- exclusions: remove type 1 and gestational diabetes
  and not exists (
    select 1
    from memory.condition_occurrence co_ex
    where co_ex.person_id = p.person_id
      and (
        -- type 1 diabetes
        co_ex.condition_source_value ilike 'E10%'
        or regexp_matches(co_ex.condition_source_value, '^250\.[0-9][13]$')
        -- gestational diabetes
        or co_ex.condition_source_value ilike 'O24.4%'
        or co_ex.condition_source_value ilike 'O24.9%'
        or co_ex.condition_source_value ilike '648.0%'
      )
  );
