with type2_diabetes_diagnosis as (
  select distinct person_id
  from memory.condition_occurrence
  where (
    condition_source_value ilike '%Diabetes mellitus type 2 (disorder)%'
    or condition_source_value ilike '%Type 2 diabetes mellitus%'
  )
),
type2_diabetes_symptoms as (
  select distinct person_id, condition_source_value
  from memory.condition_occurrence
  where (
    condition_source_value ilike '%Polyuria%'
    or condition_source_value ilike '%Polydipsia%'
    or condition_source_value ilike '%Polyphagia%'
    or condition_source_value ilike '%Unexplained weight loss%'
  )
),
type2_diabetes_laboratory as (
  select distinct person_id
  from memory.measurement
  where (
    (measurement_source_value ilike '%Fasting plasma glucose%' and value_as_number > 126)
    or (measurement_source_value ilike '%Hemoglobin A1c%' and value_as_number > 126)
  )
),
type2_diabetes_medications as (
  select distinct person_id
  from memory.drug_exposure
  where (
    drug_source_value ilike '%Metformin%'
    or drug_source_value ilike '%Glimepiride%'
    or drug_source_value ilike '%Pioglitazone%'
    or drug_source_value ilike '%Actos%'
    or drug_source_value ilike '%Avandia%'
  )
)
select 1 as cohort_definition_id, person_id as subject_id
from (
  select person_id
  from type2_diabetes_diagnosis
  union
  select person_id
  from (
    select person_id
    from type2_diabetes_symptoms
    group by person_id
    having count(distinct condition_source_value) >= 2
  ) as symptoms
  intersect
  select person_id
  from type2_diabetes_laboratory
  union
  select person_id
  from type2_diabetes_medications
) as type2_diabetes_cohort;
