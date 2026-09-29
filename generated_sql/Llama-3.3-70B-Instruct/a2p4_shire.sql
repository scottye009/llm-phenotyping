with type2_diabetes_diagnoses as (
  select distinct person_id
  from memory.condition_occurrence
  where condition_source_value ilike '250.x0%'
     or condition_source_value ilike '250.x2%'
     or condition_source_value ilike 'E11.x%'
),
type2_diabetes_labs as (
  select distinct person_id
  from memory.measurement
  where (measurement_source_value ilike '%HbA1c%' and value_as_number >= 6.5)
     or (measurement_source_value ilike '%Fasting plasma glucose%' and value_as_number >= 126)
     or (measurement_source_value ilike '%2-hour plasma glucose during OGTT%' and value_as_number >= 200)
),
type2_diabetes_meds as (
  select distinct person_id
  from memory.drug_exposure
  where (
    drug_source_value ilike '%Metformin%'
    or drug_source_value ilike '%Glipizide%'
    or drug_source_value ilike '%Insulin Glargine (Lantus)%'
    or drug_source_value ilike '%Insulin Aspart (NovoLog)%'
  )
)
select distinct person_id
from (
  select person_id
  from type2_diabetes_diagnoses
  union
  select person_id
  from type2_diabetes_labs
  union
  select person_id
  from type2_diabetes_meds
) as combined
where person_id in (
  select person_id
  from type2_diabetes_diagnoses
  intersect
  select person_id
  from type2_diabetes_labs
)
or person_id in (
  select person_id
  from type2_diabetes_diagnoses
  intersect
  select person_id
  from type2_diabetes_meds
)
or person_id in (
  select person_id
  from type2_diabetes_labs
  intersect
  select person_id
  from type2_diabetes_meds
);
