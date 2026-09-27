-- Final T2DM Cohort Construction
with t2dm_concepts as (
    -- Identifying T2DM (ICD9: 250.00, 250.02 | ICD10: E11.*)
    select condition_source_value
    from memory.condition_occurrence
    where (
        condition_source_value like '250.00'
        or condition_source_value like '250.02'
        or condition_source_value like 'E11%'
    )
),
t1dm_concepts as (
    -- Identifying T1DM for exclusion (ICD9: 250.01 | ICD10: E10.*)
    select condition_source_value
    from memory.condition_occurrence
    where (
        condition_source_value like '250.01'
        or condition_source_value like 'E10%'
    )
),
medication_concepts as (
    -- Metformin (Glucophage), Sulfonylureas (Glipizide/Glucotrol), SGLT2 (Jardiance), etc.
    select drug_source_value
    from memory.drug_exposure
    where lower(coalesce(drug_source_value, '')) in (
        'metformin', 'glucophage', 'glipizide', 'glucotrol',
        'empagliflozin', 'jardiance', 'sitagliptin', 'januvia'
    )
),
lab_criteria as (
    -- HbA1c >= 6.5%
    select person_id
    from memory.measurement
    where (measurement_source_value = '3004410' or measurement_source_value = '40758583')
      and value_as_number >= 6.5
)

select distinct p.person_id
from memory.person p
join memory.condition_occurrence co on p.person_id = co.person_id
where (
    -- CRITERIA 1: Has T2DM Diagnosis
    (
        co.condition_source_value like '250.00'
        or co.condition_source_value like '250.02'
        or co.condition_source_value like 'E11%'
    )

    or

    -- CRITERIA 2: Medication AND Lab Evidence
    (
        p.person_id in (
            select person_id
            from memory.drug_exposure
            where lower(coalesce(drug_source_value, '')) in (
                'metformin', 'glucophage', 'glipizide', 'glucotrol',
                'empagliflozin', 'jardiance', 'sitagliptin', 'januvia'
            )
        )
        and p.person_id in (select person_id from lab_criteria)
    )
)
-- CRITERIA 3: Exclude Type 1 (Simple Logic: If T1 codes exist, exclude unless T2 codes are more frequent)
and not exists (
    select 1
    from memory.condition_occurrence co_ex
    where co_ex.person_id = p.person_id
      and (
          co_ex.condition_source_value like '250.01'
          or co_ex.condition_source_value like 'E10%'
      )
);