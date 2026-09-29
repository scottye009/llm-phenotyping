with type2_diabetes as (
  select distinct person_id
  from (
    -- Diagnosis of Type 2 Diabetes
    select person_id
    from memory.condition_occurrence
    where (
      condition_source_value ilike '%Type 2 diabetes mellitus%'
      or condition_source_value ilike '%Diabetes mellitus type 2%'
      or condition_source_value ilike '250.00%'
      or condition_source_value ilike '250.02%'
      or condition_source_value ilike '250.10%'
      or condition_source_value ilike '250.12%'
      or condition_source_value ilike 'E11.%'
    )
    union all
    -- Symptoms and Signs
    select person_id
    from memory.condition_occurrence
    where (
      condition_source_value ilike '%Polyuria%'
      or condition_source_value ilike '%Polydipsia%'
      or condition_source_value ilike '%Polyphagia%'
      or condition_source_value ilike '%Weight loss%'
      or condition_source_value ilike '%Blurry vision%'
    )
    intersect
    -- Laboratory Tests
    select person_id
    from memory.measurement
    where (
      (measurement_source_value ilike '%Fasting plasma glucose%' and value_as_number >= 126)
      or person_id in (
        select person_id
        from memory.measurement
        where measurement_source_value ilike '%Hemoglobin A1c%'
          and value_as_number >= 6.5
      )
    )
    union all
    -- Medications
    select person_id
    from memory.drug_exposure
    where (
      drug_source_value ilike '%Metformin%'
      or drug_source_value ilike '%Glucophage%'
      or drug_source_value ilike '%Sulfonylureas%'
      or drug_source_value ilike '%Glipizide%'
      or drug_source_value ilike '%Glyburide%'
      or drug_source_value ilike '%Pioglitazone%'
      or drug_source_value ilike '%Actos%'
    )
  ) as subquery
  -- Exclusion Criteria
  except
  select person_id
  from memory.condition_occurrence
  where (
    condition_source_value ilike '%Type 1 diabetes mellitus%'
    or condition_source_value ilike '%Diabetes mellitus type 1%'
    or condition_source_value ilike '%Gestational diabetes%'
    or condition_source_value ilike '%Secondary diabetes%'
    or condition_source_value ilike '250.01%'
    or condition_source_value ilike '250.03%'
    or condition_source_value ilike '648.00%'
    or condition_source_value ilike '648.01%'
    or condition_source_value ilike 'E10.%'
    or condition_source_value ilike 'O24.%'
    or condition_source_value ilike 'E08.%'
  )
)
select 1 as cohort_id, 1 as cohort_definition_id, person_id
from type2_diabetes;
