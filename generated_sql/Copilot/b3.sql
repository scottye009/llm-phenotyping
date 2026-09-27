WITH dx_t2 AS (
    -- T2DM diagnosis from ICD‑9 250.x0 / 250.x2 and ICD‑10 E11*
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE
        condition_source_value ILIKE '250.%0'
        OR condition_source_value ILIKE '250.%2'
        OR condition_source_value ILIKE 'E11%'
),

dx_t1 AS (
    -- Type 1 diabetes to exclude
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE
        condition_source_value ILIKE '250.%1'
        OR condition_source_value ILIKE '250.%3'
        OR condition_source_value ILIKE 'E10%'
),

meds AS (
    -- Oral/GLP1/SGLT2/TZD diabetes medications (generic + brand)
    SELECT DISTINCT d.person_id
    FROM drug_exposure d
    WHERE EXISTS (
        SELECT 1
        FROM (
            VALUES
                -- Biguanides
                ('metformin'), ('glucophage'), ('fortamet'), ('glumetza'), ('riomet'),
                -- Sulfonylureas
                ('glipizide'), ('glyburide'), ('glimepiride'),
                -- DPP‑4 inhibitors
                ('sitagliptin'), ('januvia'),
                ('linagliptin'), ('tradjenta'),
                ('saxagliptin'), ('onglyza'),
                ('alogliptin'), ('nesina'),
                -- GLP‑1 receptor agonists
                ('liraglutide'), ('victoza'),
                ('semaglutide'), ('ozempic'), ('rybelsus'),
                ('dulaglutide'), ('trulicity'),
                ('exenatide'), ('byetta'), ('bydureon'),
                -- SGLT2 inhibitors
                ('empagliflozin'), ('jardiance'),
                ('dapagliflozin'), ('farxiga'),
                ('canagliflozin'), ('invokana'),
                -- TZDs
                ('pioglitazone'), ('actos'),
                ('rosiglitazone'), ('avandia'),
                -- Insulin (counts as supportive evidence but not alone)
                ('insulin')
        ) AS m(drugname)
        WHERE
            d.drug_source_value ILIKE '%' || m.drugname || '%'
            OR d.drug_concept_name ILIKE '%' || m.drugname || '%'
            OR d.drug_source_concept_code ILIKE '%' || m.drugname || '%'
    )
),

insulin_only AS (
    -- People with insulin but NO other T2DM‑relevant meds
    SELECT DISTINCT d.person_id
    FROM drug_exposure d
    WHERE d.drug_source_value ILIKE '%insulin%'
    EXCEPT
    SELECT person_id FROM meds
),

labs AS (
    -- Laboratory evidence of diabetes
    SELECT DISTINCT person_id
    FROM measurement
    WHERE
        (
            -- HbA1c ≥ 6.5
            (measurement_source_value ILIKE '%a1c%' OR measurement_source_value ILIKE '%hba1c%')
            AND value_as_number >= 6.5
        )
        OR (
            -- Fasting glucose ≥ 126 mg/dL
            measurement_source_value ILIKE '%fasting%'
            AND measurement_source_value ILIKE '%glucose%'
            AND value_as_number >= 126
        )
        OR (
            -- Random glucose ≥ 200 mg/dL
            measurement_source_value ILIKE '%glucose%'
            AND value_as_number >= 200
        )
),

combined AS (
    SELECT DISTINCT person_id
    FROM (
        SELECT person_id FROM dx_t2
        UNION
        SELECT person_id FROM meds
        UNION
        SELECT person_id FROM labs
    )
),

final AS (
    SELECT c.person_id
    FROM combined c
    LEFT JOIN dx_t1 t1 ON c.person_id = t1.person_id
    LEFT JOIN insulin_only io ON c.person_id = io.person_id
    WHERE t1.person_id IS NULL     -- remove Type 1 diabetes
      AND io.person_id IS NULL     -- remove insulin‑only users
)

SELECT DISTINCT person_id
FROM final
ORDER BY person_id;
