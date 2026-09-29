-- Step 1: Define the T2DM Cohort
with diagnosis_codes as (
    -- Selecting T2DM concepts (ICD9: 250.00, 250.02; ICD10: E11)
    select person_id, condition_start_date
    from memory.condition_occurrence
    where condition_source_value like 'E11%'
       or condition_source_value like '250.00%'
       or condition_source_value like '250.02%'
),

lab_results as (
    -- HbA1c >= 6.5% or Glucose >= 126 mg/dL
    select person_id, measurement_date
    from memory.measurement
    where (measurement_source_value ilike '%a1c%' and value_as_number >= 6.5)
       or (measurement_source_value ilike '%glucose%' and value_as_number >= 126)
),

medications as (
    -- T2DM Meds: Metformin (Glucophage), Glipizide (Glucotrol), Empagliflozin (Jardiance), etc.
    select person_id, drug_exposure_start_date
    from memory.drug_exposure
    where lower(drug_source_value) like '%metformin%'
       or lower(drug_source_value) like '%glucophage%'
       or lower(drug_source_value) like '%glipizide%'
       or lower(drug_source_value) like '%glucotrol%'
       or lower(drug_source_value) like '%jardiance%'
       or lower(drug_source_value) like '%empagliflozin%'
),

type1_exclusion as (
    -- Identify patients with Type 1 codes to exclude
    select distinct person_id
    from memory.condition_occurrence
    where condition_source_value like 'E10%'
)

-- Final Selection Logic
select distinct d.person_id
from diagnosis_codes d
left join lab_results l on d.person_id = l.person_id
left join medications m on d.person_id = m.person_id
where (d.person_id is not null or l.person_id is not null)
  and d.person_id not in (select person_id from type1_exclusion)
  and m.person_id is not null;
