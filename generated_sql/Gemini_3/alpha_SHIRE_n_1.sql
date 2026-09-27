-- Final T2DM Phenotype Algorithm adapted for SHIRE
with t2dm_dx AS (
    -- Identifying T2DM via source diagnosis codes
    select distinct person_id
    from memory.condition_occurrence
    where condition_source_value like 'E11%'
       or condition_source_value in ('250.00', '250.02', '250.10', '250.12')
       or condition_source_value like '250.00%'
       or condition_source_value like '250.02%'
       or condition_source_value like '250.10%'
       or condition_source_value like '250.12%'
),

t1dm_dx AS (
    -- Exclusionary Type 1 concepts operationalized on source codes
    select distinct person_id
    from memory.condition_occurrence
    where condition_source_value like 'E10%'
       or condition_source_value in ('250.01', '250.03')
       or condition_source_value like '250.01%'
       or condition_source_value like '250.03%'
),

t2dm_meds AS (
    -- Generic and Brand names (Metformin/Glucophage, Glipizide/Glucotrol, etc.)
    select distinct person_id
    from memory.drug_exposure
    where lower(drug_source_value) similar to '%(metformin|glucophage|glipizide|glucotrol|sitagliptin|januvia|empagliflozin|jardiance|liraglutide|victoza)%'
),

lab_evidence AS (
    -- Lab results: HbA1c >= 6.5
    select person_id
    from memory.measurement
    where measurement_source_value ilike '%a1c%'
      and value_as_number >= 6.5
)

select distinct p.person_id
from memory.person p
join memory.condition_occurrence co on p.person_id = co.person_id
left join memory.drug_exposure de on p.person_id = de.person_id
where (
    -- INCLUSION CRITERIA
    p.person_id in (select person_id from t2dm_dx)
    or p.person_id in (select person_id from t2dm_meds)
    or p.person_id in (select person_id from lab_evidence)
)
and not exists (
    -- EXCLUSION CRITERIA: Rule out T1DM dominance
    select 1
    from memory.condition_occurrence co_ex
    where co_ex.person_id = p.person_id
      and co_ex.person_id in (select person_id from t1dm_dx)
)
and exists (
    select 1
    from memory.visit_occurrence vo
    where vo.person_id = p.person_id
);
