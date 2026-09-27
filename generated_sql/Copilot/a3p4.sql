-- Type 2 Diabetes Mellitus Phenotype
-- Returns person_id

WITH t2dx AS (
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE 
        -- ICD-9-CM T2DM: 250.x0 or 250.x2
        condition_source_value ILIKE '250.%0'
        OR condition_source_value ILIKE '250.%2'
        -- ICD-10-CM T2DM: E11%
        OR condition_source_value ILIKE 'E11%'
),

t1dx AS (
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE 
        -- ICD-9-CM Type 1: 250.x1 or 250.x3
        condition_source_value ILIKE '250.%1'
        OR condition_source_value ILIKE '250.%3'
        -- ICD-10-CM Type 1: E10%
        OR condition_source_value ILIKE 'E10%'
),

meds AS (
    SELECT DISTINCT person_id
    FROM drug_exposure d
    WHERE EXISTS (
        SELECT 1
        FROM (
            VALUES
                -- Biguanides
                ('metformin'), ('glucophage'),
                -- Sulfonylureas
                ('glipizide'), ('glyburide'), ('glimepiride'),
                -- DPP-4 inhibitors
                ('sitagliptin'), ('januvia'),
                ('linagliptin'), ('tradjenta'),
                ('saxagliptin'), ('onglyza'),
                -- GLP-1 agonists
                ('liraglutide'), ('victoza'),
                ('semaglutide'), ('ozempic'), ('rybelsus'),
                ('dulaglutide'), ('trulicity'),
                -- SGLT2 inhibitors
                ('empagliflozin'), ('jardiance'),
                ('dapagliflozin'), ('farxiga'),
                ('canagliflozin'), ('invokana'),
                -- TZDs
                ('pioglitazone'), ('actos'),
                ('rosiglitazone'), ('avandia'),
                -- Insulin (still counts as supportive evidence)
                ('insulin')
        ) AS m(drugname)
        WHERE 
            d.drug_source_value ILIKE '%' || m.drugname || '%'
            OR d.drug_concept_name ILIKE '%' || m.drugname || '%'
            OR d.drug_source_concept_code ILIKE '%' || m.drugname || '%'
    )
),

labs AS (
    SELECT DISTINCT person_id
    FROM measurement m
    WHERE (
        -- HbA1c ≥ 6.5%
        (m.measurement_source_value ILIKE '%a1c%' 
         AND m.value_as_number >= 6.5)

        OR

        -- Fasting glucose ≥ 126 mg/dL
        (m.measurement_source_value ILIKE '%fasting%' 
         AND m.measurement_source_value ILIKE '%glucose%'
         AND m.value_as_number >= 126)

        OR

        -- Random glucose ≥ 200 mg/dL
        (m.measurement_source_value ILIKE '%glucose%' 
         AND m.value_as_number >= 200)
    )
),

combined AS (
    SELECT DISTINCT person_id
    FROM (
        SELECT person_id FROM t2dx
        UNION
        SELECT person_id FROM meds
        UNION
        SELECT person_id FROM labs
    )
),

final AS (
    SELECT c.person_id
    FROM combined c
    LEFT JOIN t1dx t1 ON c.person_id = t1.person_id
    WHERE t1.person_id IS NULL  -- Exclude pure Type 1 diabetes
)

SELECT DISTINCT person_id
FROM final
ORDER BY person_id;
