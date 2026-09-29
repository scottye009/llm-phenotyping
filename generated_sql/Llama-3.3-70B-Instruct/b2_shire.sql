select distinct person_id
from (
    select person_id
    from memory.condition_occurrence
    where (
        condition_source_value ilike '250.00%'
        or condition_source_value ilike '250.02%'
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

    union

    select person_id
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
        or drug_source_value ilike '%Glucophage%'
        or drug_source_value ilike '%Glucotrol%'
        or drug_source_value ilike '%Micronase%'
    )

    union

    select person_id
    from memory.measurement
    where (
        (
            measurement_source_value ilike '%Hemoglobin A1c%'
            and value_as_number > 6.5
        )
        or (
            measurement_source_value ilike '%Fasting Plasma Glucose%'
            and value_as_number > 126
        )
        or (
            measurement_source_value ilike '%2-hour Plasma Glucose%'
            and value_as_number > 200
        )
    )

    union

    select person_id
    from memory.condition_occurrence
    where (
        condition_source_value ilike '%Polyuria%'
        or condition_source_value ilike '%Polydipsia%'
        or condition_source_value ilike '%Polyphagia%'
        or condition_source_value ilike '%Unexplained weight loss%'
    )
) as combined
where person_id not in (
    select person_id
    from memory.condition_occurrence
    where (
        condition_source_value ilike '%Type 1 diabetes mellitus%'
        or condition_source_value ilike '%Diabetes mellitus type 1%'
        or condition_source_value ilike '%Gestational diabetes%'
        or condition_source_value ilike '%Secondary diabetes%'
    )
);
