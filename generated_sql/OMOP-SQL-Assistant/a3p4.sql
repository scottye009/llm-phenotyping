-- Type 2 Diabetes Mellitus phenotype
-- Returns person_id

WITH t2dm_dx AS (
    -- >=2 T2DM diagnoses on distinct dates
    SELECT
        person_id
    FROM condition_occurrence
    WHERE
        (
            regexp_matches(condition_source_value, '^250\\.[0-9]*0$')
            OR regexp_matches(condition_source_value, '^250\\.[0-9]*2$')
            OR condition_source_value ILIKE 'E11%'
        )
    GROUP BY person_id
    HAVING COUNT(DISTINCT condition_start_date) >= 2
),

t1dm_dx AS (
    -- Exclude probable Type 1 diabetes
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE
        condition_source_value ILIKE 'E10%'
        OR regexp_matches(condition_source_value, '^250\\.[0-9]*1$')
        OR regexp_matches(condition_source_value, '^250\\.[0-9]*3$')
),

dm_med AS (
    -- Non-insulin diabetes medications
    SELECT DISTINCT d.person_id
    FROM drug_exposure d
    WHERE
        (
            d.drug_source_value ILIKE '%metformin%'
            OR d.drug_source_value ILIKE '%glucophage%'
            OR d.drug_source_value ILIKE '%glipizide%'
            OR d.drug_source_value ILIKE '%glucotrol%'
            OR d.drug_source_value ILIKE '%glyburide%'
            OR d.drug_source_value ILIKE '%diabeta%'
            OR d.drug_source_value ILIKE '%micronase%'
            OR d.drug_source_value ILIKE '%glynase%'
            OR d.drug_source_value ILIKE '%glimepiride%'
            OR d.drug_source_value ILIKE '%amaryl%'
            OR d.drug_source_value ILIKE '%pioglitazone%'
            OR d.drug_source_value ILIKE '%actos%'
            OR d.drug_source_value ILIKE '%rosiglitazone%'
            OR d.drug_source_value ILIKE '%avandia%'
            OR d.drug_source_value ILIKE '%sitagliptin%'
            OR d.drug_source_value ILIKE '%januvia%'
            OR d.drug_source_value ILIKE '%saxagliptin%'
            OR d.drug_source_value ILIKE '%onglyza%'
            OR d.drug_source_value ILIKE '%linagliptin%'
            OR d.drug_source_value ILIKE '%tradjenta%'
            OR d.drug_source_value ILIKE '%alogliptin%'
            OR d.drug_source_value ILIKE '%nesina%'
            OR d.drug_source_value ILIKE '%empagliflozin%'
            OR d.drug_source_value ILIKE '%jardiance%'
            OR d.drug_source_value ILIKE '%canagliflozin%'
            OR d.drug_source_value ILIKE '%invokana%'
            OR d.drug_source_value ILIKE '%dapagliflozin%'
            OR d.drug_source_value ILIKE '%farxiga%'
            OR d.drug_source_value ILIKE '%ertugliflozin%'
            OR d.drug_source_value ILIKE '%steglatro%'
            OR d.drug_source_value ILIKE '%semaglutide%'
            OR d.drug_source_value ILIKE '%ozempic%'
            OR d.drug_source_value ILIKE '%rybelsus%'
            OR d.drug_source_value ILIKE '%liraglutide%'
            OR d.drug_source_value ILIKE '%victoza%'
            OR d.drug_source_value ILIKE '%dulaglutide%'
            OR d.drug_source_value ILIKE '%trulicity%'
            OR d.drug_source_value ILIKE '%exenatide%'
            OR d.drug_source_value ILIKE '%byetta%'
            OR d.drug_source_value ILIKE '%bydureon%'
            OR d.drug_source_value ILIKE '%tirzepatide%'
            OR d.drug_source_value ILIKE '%mounjaro%'
        )
        OR
        (
            d.drug_concept_name ILIKE '%metformin%'
            OR d.drug_concept_name ILIKE '%glucophage%'
            OR d.drug_concept_name ILIKE '%glipizide%'
            OR d.drug_concept_name ILIKE '%glucotrol%'
            OR d.drug_concept_name ILIKE '%glyburide%'
            OR d.drug_concept_name ILIKE '%diabeta%'
            OR d.drug_concept_name ILIKE '%micronase%'
            OR d.drug_concept_name ILIKE '%glynase%'
            OR d.drug_concept_name ILIKE '%glimepiride%'
            OR d.drug_concept_name ILIKE '%amaryl%'
            OR d.drug_concept_name ILIKE '%pioglitazone%'
            OR d.drug_concept_name ILIKE '%actos%'
            OR d.drug_concept_name ILIKE '%rosiglitazone%'
            OR d.drug_concept_name ILIKE '%avandia%'
            OR d.drug_concept_name ILIKE '%sitagliptin%'
            OR d.drug_concept_name ILIKE '%januvia%'
            OR d.drug_concept_name ILIKE '%saxagliptin%'
            OR d.drug_concept_name ILIKE '%onglyza%'
            OR d.drug_concept_name ILIKE '%linagliptin%'
            OR d.drug_concept_name ILIKE '%tradjenta%'
            OR d.drug_concept_name ILIKE '%alogliptin%'
            OR d.drug_concept_name ILIKE '%nesina%'
            OR d.drug_concept_name ILIKE '%empagliflozin%'
            OR d.drug_concept_name ILIKE '%jardiance%'
            OR d.drug_concept_name ILIKE '%canagliflozin%'
            OR d.drug_concept_name ILIKE '%invokana%'
            OR d.drug_concept_name ILIKE '%dapagliflozin%'
            OR d.drug_concept_name ILIKE '%farxiga%'
            OR d.drug_concept_name ILIKE '%ertugliflozin%'
            OR d.drug_concept_name ILIKE '%steglatro%'
            OR d.drug_concept_name ILIKE '%semaglutide%'
            OR d.drug_concept_name ILIKE '%ozempic%'
            OR d.drug_concept_name ILIKE '%rybelsus%'
            OR d.drug_concept_name ILIKE '%liraglutide%'
            OR d.drug_concept_name ILIKE '%victoza%'
            OR d.drug_concept_name ILIKE '%dulaglutide%'
            OR d.drug_concept_name ILIKE '%trulicity%'
            OR d.drug_concept_name ILIKE '%exenatide%'
            OR d.drug_concept_name ILIKE '%byetta%'
            OR d.drug_concept_name ILIKE '%bydureon%'
            OR d.drug_concept_name ILIKE '%tirzepatide%'
            OR d.drug_concept_name ILIKE '%mounjaro%'
        )
),

dm_lab AS (
    -- Diagnostic laboratory evidence
    SELECT DISTINCT person_id
    FROM measurement
    WHERE
        value_as_number IS NOT NULL
        AND (
            (
                (
                    measurement_source_value ILIKE '%a1c%'
                    OR measurement_source_value ILIKE '%hba1c%'
                    OR measurement_source_value ILIKE '%hemoglobin a1c%'
                    OR measurement_source_value ILIKE '%glycohemoglobin%'
                )
                AND value_as_number >= 6.5
            )
            OR
            (
                (
                    measurement_source_value ILIKE '%fasting glucose%'
                    OR measurement_source_value ILIKE '%fast glucose%'
                    OR measurement_source_value ILIKE '%fpg%'
                )
                AND value_as_number >= 126
            )
            OR
            (
                (
                    measurement_source_value ILIKE '%glucose%'
                )
                AND value_as_number >= 200
            )
        )
)

SELECT DISTINCT dx.person_id
FROM t2dm_dx dx
LEFT JOIN t1dm_dx t1
    ON dx.person_id = t1.person_id
WHERE
    t1.person_id IS NULL
    AND (
        EXISTS (
            SELECT 1
            FROM dm_med m
            WHERE m.person_id = dx.person_id
        )
        OR
        EXISTS (
            SELECT 1
            FROM dm_lab l
            WHERE l.person_id = dx.person_id
        )
    );