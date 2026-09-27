with type2_diabetes_diagnosis as (
  select person_id
  from memory.condition_occurrence
  where (
    condition_source_value ilike '%Type 2 diabetes mellitus%'
    or condition_source_value ilike '%Diabetes mellitus type 2%'
    or condition_source_value ilike '250.0%'
    or condition_source_value ilike '250.1%'
    or condition_source_value ilike '250.2%'
    or condition_source_value ilike '250.3%'
    or condition_source_value ilike 'E11.0%'
    or condition_source_value ilike 'E11.1%'
    or condition_source_value ilike 'E11.2%'
    or condition_source_value ilike 'E11.3%'
  )
),
type2_diabetes_symptoms as (
  select person_id
  from memory.condition_occurrence
  where (
    condition_source_value ilike '%Polyuria%'
    or condition_source_value ilike '%Polydipsia%'
    or condition_source_value ilike '%Polyphagia%'
  )
  group by person_id
  having count(distinct condition_source_value) >= 2
),
type2_diabetes_labs as (
  select person_id
  from memory.measurement
  where (
    (measurement_source_value ilike '%Hemoglobin A1c%' and value_as_number >= 6.5)
    or (measurement_source_value ilike '%Fasting plasma glucose%' and value_as_number >= 126)
  )
),
type2_diabetes_meds as (
  select person_id
  from memory.drug_exposure
  where (
    drug_source_value ilike '%Metformin%'
    or drug_source_value ilike '%Glipizide%'
    or drug_source_value ilike '%Glyburide%'
    or drug_source_value ilike '%Insulin%'
  )
),
type1_diabetes_diagnosis as (
  select person_id
  from memory.condition_occurrence
  where (
    condition_source_value ilike '%Type 1 diabetes mellitus%'
    or condition_source_value ilike '%Diabetes mellitus type 1%'
    or condition_source_value ilike '250.0%'
    or condition_source_value ilike '250.1%'
    or condition_source_value ilike '250.2%'
    or condition_source_value ilike '250.3%'
    or condition_source_value ilike 'E10.0%'
    or condition_source_value ilike 'E10.1%'
    or condition_source_value ilike 'E10.2%'
    or condition_source_value ilike 'E10.3%'
  )
)
select person_id
from (
 select person_id
  from type2_diabetes_diagnosis
  union
  select person_id
  from (
    select person_id
    from type2_diabetes_symptoms
    intersect
    select person_id
    from type2_diabetes_labs
    intersect
    select person_id
    from type2_diabetes_meds
  ) as intersection_table
) as union_table
where person_id not in (
  select person_id
  from type1_diabetes_diagnosis
);
