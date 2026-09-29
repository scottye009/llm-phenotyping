select distinct person_id
from (
    select person_id
    from memory.condition_occurrence
    where (
        condition_source_value in ('250.00', '250.02', 'E11.0', 'E11.1', 'E11.2', 'E11.3', 'E11.4', 'E11.5', 'E11.6', 'E11.7', 'E11.8', 'E11.9')
        or condition_source_value ilike 'E11%'
    )

    union

    select person_id
    from memory.drug_exposure
    where lower(coalesce(drug_source_value, '')) in (
        'metformin', 'glipizide', 'glyburide', 'repaglinide', 'nateglinide',
        'pioglitazone', 'rosiglitazone', 'sitagliptin', 'saxagliptin',
        'exenatide', 'liraglutide', 'canagliflozin', 'empagliflozin',
        'glucophage', 'glucotrol', 'micronase'
    )

    union

    select person_id
    from memory.measurement
    where (
        (
            lower(coalesce(measurement_source_value, '')) in ('hemoglobin a1c')
            and value_as_number > 6.5
        )
        or (
            lower(coalesce(measurement_source_value, '')) in ('fasting plasma glucose')
            and value_as_number > 126
        )
        or (
            lower(coalesce(measurement_source_value, '')) in ('2-hour plasma glucose')
            and value_as_number > 200
        )
    )

    union

    select person_id
    from memory.condition_occurrence
    where lower(coalesce(condition_source_value, '')) in (
        'polyuria', 'polydipsia', 'polyphagia', 'unexplained weight loss'
    )
) as combined
where person_id not in (
    select person_id
    from memory.condition_occurrence
    where lower(coalesce(condition_source_value, '')) in (
        'type 1 diabetes mellitus', 'diabetes mellitus type 1', 'gestational diabetes', 'secondary diabetes'
    )
);
