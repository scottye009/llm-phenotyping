-- Type 2 diabetes mellitus phenotype
-- Criteria:
--   1) T2DM diagnosis code/text from condition source fields
--   2) Diabetes medication exposure, excluding insulin-only evidence
--   3) Diabetes-range lab evidence from measurement source fields and numeric values
-- Final algorithm:
--   Include patients with T2DM diagnosis OR strong medication + lab evidence.
--   Exclude patients with evidence suggesting type 1, gestational, secondary, or drug-induced diabetes.

WITH t2dm_diagnosis AS (
    SELECT DISTINCT
        person_id
    FROM condition_occurrence
    WHERE
        (
            -- ICD-10-CM E11.* = Type 2 diabetes mellitus
            (
                condition_source_concept_vocabulary_id ILIKE '%ICD10%'
                AND regexp_matches(UPPER(condition_source_value), '^E11')
            )
            OR
            -- ICD-9-CM 250.x0 or 250.x2 = type 2 or unspecified type, uncontrolled/controlled
            (
                condition_source_concept_vocabulary_id ILIKE '%ICD9%'
                AND regexp_matches(condition_source_value, '^250\.[0-9][02]$')
            )
            OR
            -- Diagnosis text fallback
            condition_source_concept_name ILIKE '%type 2 diabetes%'
            OR condition_source_concept_name ILIKE '%type ii diabetes%'
            OR condition_source_concept_name ILIKE '%t2dm%'
            OR condition_source_concept_name ILIKE '%non-insulin dependent diabetes%'
            OR condition_concept_name ILIKE '%type 2 diabetes%'
            OR condition_concept_name ILIKE '%type ii diabetes%'
        )
),

exclusion_diagnosis AS (
    SELECT DISTINCT
        person_id
    FROM condition_occurrence
    WHERE
        (
            -- Type 1 diabetes
            (
                condition_source_concept_vocabulary_id ILIKE '%ICD10%'
                AND regexp_matches(UPPER(condition_source_value), '^E10')
            )
            OR (
                condition_source_concept_vocabulary_id ILIKE '%ICD9%'
                AND regexp_matches(condition_source_value, '^250\.[0-9][13]$')
            )
            OR condition_source_concept_name ILIKE '%type 1 diabetes%'
            OR condition_source_concept_name ILIKE '%type i diabetes%'
            OR condition_source_concept_name ILIKE '%t1dm%'

            -- Gestational, secondary, or drug-induced diabetes
            OR (
                condition_source_concept_vocabulary_id ILIKE '%ICD10%'
                AND (
                    regexp_matches(UPPER(condition_source_value), '^O24')
                    OR regexp_matches(UPPER(condition_source_value), '^E08')
                    OR regexp_matches(UPPER(condition_source_value), '^E09')
                    OR regexp_matches(UPPER(condition_source_value), '^E13')
                )
            )
            OR condition_source_concept_name ILIKE '%gestational diabetes%'
            OR condition_source_concept_name ILIKE '%secondary diabetes%'
            OR condition_source_concept_name ILIKE '%drug-induced diabetes%'
            OR condition_source_concept_name ILIKE '%postpancreatectomy diabetes%'
        )
),

diabetes_medication AS (
    SELECT DISTINCT
        person_id
    FROM drug_exposure
    WHERE
        (
            -- Biguanide
            drug_source_value ILIKE '%metformin%'
            OR drug_concept_name ILIKE '%metformin%'
            OR drug_source_concept_code ILIKE '%metformin%'

            -- Sulfonylureas
            OR drug_source_value ILIKE '%glipizide%'
            OR drug_source_value ILIKE '%glyburide%'
            OR drug_source_value ILIKE '%glimepiride%'
            OR drug_source_value ILIKE '%chlorpropamide%'
            OR drug_source_value ILIKE '%tolbutamide%'
            OR drug_source_value ILIKE '%tolazamide%'
            OR drug_concept_name ILIKE '%glipizide%'
            OR drug_concept_name ILIKE '%glyburide%'
            OR drug_concept_name ILIKE '%glimepiride%'

            -- TZDs
            OR drug_source_value ILIKE '%pioglitazone%'
            OR drug_source_value ILIKE '%rosiglitazone%'
            OR drug_source_value ILIKE '%actos%'
            OR drug_source_value ILIKE '%avandia%'
            OR drug_concept_name ILIKE '%pioglitazone%'
            OR drug_concept_name ILIKE '%rosiglitazone%'

            -- DPP-4 inhibitors
            OR drug_source_value ILIKE '%sitagliptin%'
            OR drug_source_value ILIKE '%saxagliptin%'
            OR drug_source_value ILIKE '%linagliptin%'
            OR drug_source_value ILIKE '%alogliptin%'
            OR drug_source_value ILIKE '%januvia%'
            OR drug_source_value ILIKE '%onglyza%'
            OR drug_source_value ILIKE '%tradjenta%'
            OR drug_source_value ILIKE '%nesina%'
            OR drug_concept_name ILIKE '%sitagliptin%'
            OR drug_concept_name ILIKE '%linagliptin%'

            -- GLP-1 receptor agonists / dual incretin agents
            OR drug_source_value ILIKE '%semaglutide%'
            OR drug_source_value ILIKE '%liraglutide%'
            OR drug_source_value ILIKE '%dulaglutide%'
            OR drug_source_value ILIKE '%exenatide%'
            OR drug_source_value ILIKE '%tirzepatide%'
            OR drug_source_value ILIKE '%ozempic%'
            OR drug_source_value ILIKE '%rybelsus%'
            OR drug_source_value ILIKE '%victoza%'
            OR drug_source_value ILIKE '%trulicity%'
            OR drug_source_value ILIKE '%byetta%'
            OR drug_source_value ILIKE '%bydureon%'
            OR drug_source_value ILIKE '%mounjaro%'
            OR drug_concept_name ILIKE '%semaglutide%'
            OR drug_concept_name ILIKE '%liraglutide%'
            OR drug_concept_name ILIKE '%dulaglutide%'
            OR drug_concept_name ILIKE '%tirzepatide%'

            -- SGLT2 inhibitors
            OR drug_source_value ILIKE '%empagliflozin%'
            OR drug_source_value ILIKE '%canagliflozin%'
            OR drug_source_value ILIKE '%dapagliflozin%'
            OR drug_source_value ILIKE '%ertugliflozin%'
            OR drug_source_value ILIKE '%jardiance%'
            OR drug_source_value ILIKE '%invokana%'
            OR drug_source_value ILIKE '%farxiga%'
            OR drug_source_value ILIKE '%steglatro%'
            OR drug_concept_name ILIKE '%empagliflozin%'
            OR drug_concept_name ILIKE '%canagliflozin%'
            OR drug_concept_name ILIKE '%dapagliflozin%'

            -- Other non-insulin diabetes drugs
            OR drug_source_value ILIKE '%acarbose%'
            OR drug_source_value ILIKE '%miglitol%'
            OR drug_source_value ILIKE '%repaglinide%'
            OR drug_source_value ILIKE '%nateglinide%'
            OR drug_source_value ILIKE '%pramlintide%'
            OR drug_concept_name ILIKE '%acarbose%'
            OR drug_concept_name ILIKE '%repaglinide%'
            OR drug_concept_name ILIKE '%nateglinide%'
        )
        -- Avoid insulin-only medication evidence for T2DM classification
        AND drug_source_value NOT ILIKE '%insulin%'
        AND drug_concept_name NOT ILIKE '%insulin%'
),

diabetes_lab AS (
    SELECT DISTINCT
        person_id
    FROM measurement
    WHERE
        value_as_number IS NOT NULL
        AND (
            -- HbA1c >= 6.5%
            (
                (
                    measurement_source_value ILIKE '%a1c%'
                    OR measurement_source_value ILIKE '%hba1c%'
                    OR measurement_source_value ILIKE '%hemoglobin a1c%'
                    OR measurement_concept_name ILIKE '%a1c%'
                    OR measurement_concept_name ILIKE '%hemoglobin a1c%'
                )
                AND value_as_number >= 6.5
                AND (
                    unit_source_value ILIKE '%percent%'
                    OR unit_source_value ILIKE '%%%'
                    OR unit_concept_name ILIKE '%percent%'
                    OR unit_source_value IS NULL
                )
            )

            -- Fasting glucose >= 126 mg/dL
            OR (
                (
                    measurement_source_value ILIKE '%fasting glucose%'
                    OR measurement_source_value ILIKE '%fasting blood glucose%'
                    OR measurement_source_value ILIKE '%glucose fasting%'
                    OR measurement_concept_name ILIKE '%fasting glucose%'
                )
                AND value_as_number >= 126
                AND (
                    unit_source_value ILIKE '%mg/dl%'
                    OR unit_concept_name ILIKE '%mg/dl%'
                    OR unit_source_value IS NULL
                )
            )

            -- Random/plasma glucose >= 200 mg/dL
            OR (
                (
                    measurement_source_value ILIKE '%glucose%'
                    OR measurement_source_value ILIKE '%blood sugar%'
                    OR measurement_concept_name ILIKE '%glucose%'
                )
                AND value_as_number >= 200
                AND (
                    unit_source_value ILIKE '%mg/dl%'
                    OR unit_concept_name ILIKE '%mg/dl%'
                    OR unit_source_value IS NULL
                )
            )
        )
),

candidate_t2dm AS (
    SELECT person_id FROM t2dm_diagnosis

    UNION

    SELECT
        m.person_id
    FROM diabetes_medication m
    INNER JOIN diabetes_lab l
        ON m.person_id = l.person_id
)

SELECT DISTINCT
    c.person_id
FROM candidate_t2dm c
LEFT JOIN exclusion_diagnosis e
    ON c.person_id = e.person_id
WHERE
    e.person_id IS NULL;