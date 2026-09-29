with t2dm_diagnosis as (
    -- Step 1: Identify T2DM diagnoses (ICD9: 250.00, 250.02; ICD10: E11.x)
    select person_id, condition_start_date
    from memory.condition_occurrence
    where regexp_matches(coalesce(lower(condition_source_value), ''), '^(250\\.00|250\\.02|e11)')
),
t2dm_meds as (
    -- Step 2: Identify T2DM specific medications (Generic and Brand)
    -- Includes: Metformin (Glucophage), Glipizide (Glucotrol), Empagliflozin (Jardiance), etc.
    select person_id, drug_exposure_start_date
    from memory.drug_exposure
    where regexp_matches(coalesce(lower(drug_source_value), ''), '(metformin|glucophage|glipizide|glucotrol|glyburide|micronase|pioglitazone|actos|sitagliptin|januvia|empagliflozin|jardiance|liraglutide|victoza)')
),
t2dm_labs as (
    -- Step 3: Identify Lab results (HbA1c >= 6.5%)
    -- LOINC 4548-4 is the standard for HbA1c
    select person_id, measurement_date
    from memory.measurement
    where regexp_matches(coalesce(lower(measurement_source_value), ''), '(4548-4|hba1c|a1c)')
      and value_as_number >= 6.5
),
t1dm_exclusion as (
    -- Step 4: Identify Type 1 Diabetes for exclusion (ICD9: 250.01, 250.03; ICD10: E10.x)
    select distinct person_id
    from memory.condition_occurrence
    where regexp_matches(coalesce(lower(condition_source_value), ''), '^(250\\.01|250\\.03|e10)')
)

-- Final Selection Logic
select distinct d.person_id
from t2dm_diagnosis d
left join t2dm_meds m on d.person_id = m.person_id
left join t2dm_labs l on d.person_id = l.person_id
where d.person_id not in (select person_id from t1dm_exclusion)
and (
    -- Rule: 2+ diagnoses on different days
    (select count(distinct condition_start_date) from t2dm_diagnosis d2 where d2.person_id = d.person_id) >= 2
    or
    -- Rule: 1 diagnosis AND 1 medication
    m.person_id is not null
    or
    -- Rule: 1 diagnosis AND 1 abnormal lab
    l.person_id is not null
);
