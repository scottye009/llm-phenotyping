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
        drug_source_value ilike '%metformin%'
        or drug_source_value ilike '%glipizide%'
        or drug_source_value ilike '%glyburide%'
        or drug_source_value ilike '%repaglinide%'
        or drug_source_value ilike '%nateglinide%'
        or drug_source_value ilike '%pioglitazone%'
        or drug_source_value ilike '%rosiglitazone%'
        or drug_source_value ilike '%sitagliptin%'
        or drug_source_value ilike '%saxagliptin%'
        or drug_source_value ilike '%exenatide%'
        or drug_source_value ilike '%liraglutide%'
        or drug_source_value ilike '%canagliflozin%'
        or drug_source_value ilike '%empagliflozin%'
        or drug_source_value ilike '%glucophage%'
        or drug_source_value ilike '%glucotrol%'
        or drug_source_value ilike '%micronase%'
    )

    union

    select person_id
    from memory.measurement
    where (
        (
            measurement_source_value ilike '%hemoglobin a1c%'
            or measurement_source_value ilike '%hba1c%'
        )
        and value_as_number > 6.5
    )
    or (
        (
            measurement_source_value ilike '%fasting plasma glucose%'
            or measurement_source_value ilike '%fasting glucose%'
        )
        and value_as_number > 126
    )
    or (
        measurement_source_value ilike '%2-hour plasma glucose%'
        and value_as_number > 200
    )

    union

    select person_id
    from memory.condition_occurrence
    where (
        condition_source_value ilike '%polyuria%'
        or condition_source_value ilike '%polydipsia%'
        or condition_source_value ilike '%polyphagia%'
        or condition_source_value ilike '%unexplained weight loss%'
    )
) combined
where person_id not in (
    select person_id
    from memory.condition_occurrence
    where (
        condition_source_value ilike '%type 1 diabetes%'
        or condition_source_value ilike '%diabetes mellitus type 1%'
        or condition_source_value ilike '%gestational diabetes%'
        or condition_source_value ilike '%secondary diabetes%'
        or condition_source_value ilike '250.01%'
        or condition_source_value ilike '250.03%'
        or condition_source_value ilike 'E10%'
        or condition_source_value ilike 'O24%'
    )
);
