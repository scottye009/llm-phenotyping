with
-- Define the criteria for diagnosis of type 2 diabetes
 diagnosis as (
    select person_id, condition_start_date, condition_end_date
    from memory.condition_occurrence
    where (
        condition_source_value ilike '250.00%'
        or condition_source_value ilike '250.01%'
        or condition_source_value ilike '250.02%'
        or condition_source_value ilike '250.03%'
        or condition_source_value ilike 'E11.0%'
        or condition_source_value ilike 'E11.1%'
        or condition_source_value ilike 'E11.2%'
        or condition_source_value ilike 'E11.3%'
        or condition_source_value ilike 'E11.4%'
        or condition_source_value ilike 'E11.5%'
        or condition_source_value ilike 'E11.6%'
        or condition_source_value ilike 'E11.7%'
        or condition_source_value ilike 'E11.8%'
        or condition_source_value ilike 'E11.9%'
    )
),

-- Define the criteria for medication use
medication as (
    select person_id, drug_exposure_start_date, drug_exposure_end_date
    from memory.drug_exposure
    where (
        drug_source_value ilike '%Metformin%'
        or drug_source_value ilike '%Glipizide%'
        or drug_source_value ilike '%Glyburide%'
        or drug_source_value ilike '%Repaglinide%'
        or drug_source_value ilike '%Nateglinide%'
        or drug_source_value ilike '%Pioglitazone%'
        or drug_source_value ilike '%Rosiglitazone%'
        or drug_source_value ilike '%Sitagliptin%'
        or drug_source_value ilike '%Saxagliptin%'
        or drug_source_value ilike '%Exenatide%'
        or drug_source_value ilike '%Liraglutide%'
        or drug_source_value ilike '%Canagliflozin%'
        or drug_source_value ilike '%Empagliflozin%'
    )
),

-- Define the criteria for abnormal laboratory test results
lab_results as (
    select person_id, measurement_date
    from memory.measurement
    where (
        (measurement_source_value ilike '%Hemoglobin A1c%' and value_as_number > 6.5)
        or (measurement_source_value ilike '%Fasting Plasma Glucose%' and value_as_number > 126)
        or (measurement_source_value ilike '%2-hour Plasma Glucose%' and value_as_number > 200)
    )
),

-- Define the criteria for symptoms
symptoms as (
    select person_id, condition_start_date
    from memory.condition_occurrence
    where (
        condition_source_value ilike '%Polyuria%'
        or condition_source_value ilike '%Polydipsia%'
        or condition_source_value ilike '%Polyphagia%'
        or condition_source_value ilike '%Unexplained weight loss%'
    )
),

-- Identify individuals with type 2 diabetes based on diagnosis and at least one of the other criteria
cohort_from_diagnosis as (
    select distinct d.person_id
    from diagnosis d
    where exists (
        select 1
        from medication m
        where m.person_id = d.person_id
          and m.drug_exposure_start_date between d.condition_start_date and d.condition_end_date
    )
    or exists (
        select 1
        from lab_results l
        where l.person_id = d.person_id
          and l.measurement_date between d.condition_start_date and d.condition_end_date
    )
    or exists (
        select 1
        from symptoms s
        where s.person_id = d.person_id
          and s.condition_start_date between d.condition_start_date and d.condition_end_date
    )
),

-- Identify individuals with no diagnosis but with medication use and abnormal lab results or symptoms
cohort_from_medication as (
    select distinct m.person_id
    from medication m
    where not exists (
        select 1
        from diagnosis d
        where d.person_id = m.person_id
    )
    and exists (
        select 1
        from lab_results l
        where l.person_id = m.person_id
          and l.measurement_date between m.drug_exposure_start_date and m.drug_exposure_end_date
    )
    and exists (
        select 1
        from symptoms s
        where s.person_id = m.person_id
          and s.condition_start_date between m.drug_exposure_start_date and m.drug_exposure_end_date
    )
)

select person_id
from cohort_from_diagnosis
union
select person_id
from cohort_from_medication;
