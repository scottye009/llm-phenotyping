
WITH
-- 1. Identify ICD-9-CM and ICD-10-CM type 2 diabetes codes.
t2d_icd AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND invalid_reason IS NULL
      AND (
          (vocabulary_id = 'ICD10CM'
           AND concept_code ~ '^E11(\.|[0-9]|$)')
          OR
          (vocabulary_id = 'ICD9CM'
           AND REPLACE(concept_code, '.', '')
               ~ '^250[0-9][02]$')
      )
),

-- 2. Resolve ICD source concepts to standard OMOP concepts.
t2d_concepts AS (
    SELECT concept_id
    FROM t2d_icd

    UNION

    SELECT cr.concept_id_2
    FROM public.concept_relationship cr
    JOIN t2d_icd i
      ON i.concept_id = cr.concept_id_1
    JOIN public.concept c
      ON c.concept_id = cr.concept_id_2
    WHERE cr.relationship_id = 'Maps to'
      AND cr.invalid_reason IS NULL
      AND CURRENT_DATE BETWEEN cr.valid_start_date
                           AND cr.valid_end_date
      AND c.standard_concept = 'S'
      AND c.domain_id = 'Condition'
      AND c.invalid_reason IS NULL
),

-- 3. Find qualifying type 2 diabetes diagnoses.
t2d_diagnoses AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date AS event_date
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (
              SELECT concept_id FROM t2d_concepts
          )
       OR co.condition_source_concept_id IN (
              SELECT concept_id FROM t2d_icd
          )
       OR (
           REPLACE(UPPER(TRIM(co.condition_source_value)),
                   '.', '') ~ '^E11([0-9]|$)'
           OR
           REPLACE(TRIM(co.condition_source_value),
                   '.', '') ~ '^250[0-9][02]$'
       )
),

-- 4. Identify diabetes medication ingredients.
-- Excludes insulin because insulin is not T2D-specific.
diabetes_ingredients AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'RxNorm'
      AND concept_class_id = 'Ingredient'
      AND invalid_reason IS NULL
      AND (
          concept_name ILIKE ANY (ARRAY[
              '%metformin%',
              '%glipizide%',
              '%glyburide%',
              '%glimepiride%',
              '%gliclazide%',
              '%glibenclamide%',
              '%chlorpropamide%',
              '%tolbutamide%',
              '%tolazamide%',
              '%pioglitazone%',
              '%rosiglitazone%',
              '%sitagliptin%',
              '%saxagliptin%',
              '%linagliptin%',
              '%alogliptin%',
              '%vildagliptin%',
              '%exenatide%',
              '%liraglutide%',
              '%dulaglutide%',
              '%semaglutide%',
              '%lixisenatide%',
              '%tirzepatide%',
              '%empagliflozin%',
              '%dapagliflozin%',
              '%canagliflozin%',
              '%ertugliflozin%',
              '%bexagliflozin%',
              '%repaglinide%',
              '%nateglinide%',
              '%acarbose%',
              '%miglitol%'
          ])
      )
),

-- 5. Expand ingredients to standard drug products.
diabetes_drug_concepts AS (
    SELECT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    JOIN diabetes_ingredients di
      ON di.concept_id = ca.ancestor_concept_id

    UNION

    SELECT concept_id
    FROM diabetes_ingredients

    UNION

    -- Generic and brand-name fallback for products
    -- when ingredient ancestry is incomplete.
    SELECT concept_id
    FROM public.concept
    WHERE domain_id = 'Drug'
      AND standard_concept = 'S'
      AND invalid_reason IS NULL
      AND concept_name ILIKE ANY (ARRAY[
          '%metformin%',
          '%glipizide%',
          '%glyburide%',
          '%glimepiride%',
          '%pioglitazone%',
          '%rosiglitazone%',
          '%sitagliptin%',
          '%saxagliptin%',
          '%linagliptin%',
          '%alogliptin%',
          '%exenatide%',
          '%liraglutide%',
          '%dulaglutide%',
          '%semaglutide%',
          '%tirzepatide%',
          '%empagliflozin%',
          '%dapagliflozin%',
          '%canagliflozin%',
          '%ertugliflozin%',
          '%repaglinide%',
          '%nateglinide%',
          '%acarbose%',
          '%miglitol%',
          '%Glucophage%',
          '%Glucotrol%',
          '%Glucovance%',
          '%Amaryl%',
          '%Actos%',
          '%Avandia%',
          '%Januvia%',
          '%Janumet%',
          '%Onglyza%',
          '%Tradjenta%',
          '%Nesina%',
          '%Byetta%',
          '%Victoza%',
          '%Trulicity%',
          '%Ozempic%',
          '%Rybelsus%',
          '%Mounjaro%',
          '%Jardiance%',
          '%Farxiga%',
          '%Invokana%',
          '%Steglatro%',
          '%Synjardy%',
          '%Xigduo%',
          '%Glyxambi%',
          '%Prandin%',
          '%Starlix%'
      ])
),

-- 6. Find qualifying antidiabetic medication exposure.
t2d_medications AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    WHERE de.drug_concept_id IN (
        SELECT concept_id FROM diabetes_drug_concepts
    )
       OR de.drug_source_concept_id IN (
        SELECT concept_id FROM diabetes_drug_concepts
    )
),

-- 7. Identify HbA1c and fasting glucose LOINC concepts.
lab_loinc AS (
    SELECT
        concept_id,
        CASE
            WHEN concept_code IN (
                '4548-4', '17856-6', '59261-8'
            ) THEN 'HBA1C'
            WHEN concept_code IN (
                '1558-6', '14771-0'
            ) THEN 'FASTING_GLUCOSE'
        END AS lab_type
    FROM public.concept
    WHERE vocabulary_id = 'LOINC'
      AND concept_code IN (
          '4548-4', '17856-6', '59261-8',
          '1558-6', '14771-0'
      )
      AND invalid_reason IS NULL
),

-- 8. Include corresponding mapped standard measurements.
lab_concepts AS (
    SELECT concept_id, lab_type
    FROM lab_loinc

    UNION

    SELECT cr.concept_id_2, ll.lab_type
    FROM public.concept_relationship cr
    JOIN lab_loinc ll
      ON ll.concept_id = cr.concept_id_1
    JOIN public.concept c
      ON c.concept_id = cr.concept_id_2
    WHERE cr.relationship_id = 'Maps to'
      AND cr.invalid_reason IS NULL
      AND CURRENT_DATE BETWEEN cr.valid_start_date
                           AND cr.valid_end_date
      AND c.domain_id = 'Measurement'
      AND c.invalid_reason IS NULL
),

-- 9. Evaluate numerical results with unit-aware thresholds.
abnormal_labs AS (
    SELECT DISTINCT
        m.person_id,
        m.measurement_date AS event_date
    FROM public.measurement m
    LEFT JOIN public.concept u
      ON u.concept_id = m.unit_concept_id
    WHERE m.value_as_number IS NOT NULL
      AND EXISTS (
          SELECT 1
          FROM lab_concepts lc
          WHERE lc.concept_id = m.measurement_concept_id
            AND (
                (
                    lc.lab_type = 'HBA1C'
                    AND (
                        (
                            m.value_as_number >= 6.5
                            AND (
                                u.concept_code = '%'
                                OR LOWER(TRIM(m.unit_source_value))
                                   IN ('%', 'percent')
                            )
                        )
                        OR
                        (
                            m.value_as_number >= 48
                            AND (
                                u.concept_code = 'mmol/mol'
                                OR LOWER(TRIM(m.unit_source_value))
                                   = 'mmol/mol'
                            )
                        )
                    )
                )
                OR
                (
                    lc.lab_type = 'FASTING_GLUCOSE'
                    AND (
                        (
                            m.value_as_number >= 126
                            AND (
                                u.concept_code = 'mg/dL'
                                OR LOWER(TRIM(m.unit_source_value))
                                   IN ('mg/dl', 'mgdl')
                            )
                        )
                        OR
                        (
                            m.value_as_number >= 7.0
                            AND (
                                u.concept_code = 'mmol/L'
                                OR LOWER(TRIM(m.unit_source_value))
                                   IN ('mmol/l', 'mmol per l')
                            )
                        )
                    )
                )
            )
      )
),

-- 10. Aggregate independent diagnosis and lab evidence.
diagnosis_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS diagnosis_days
    FROM t2d_diagnoses
    GROUP BY person_id
),

lab_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS abnormal_lab_days
    FROM abnormal_labs
    GROUP BY person_id
),

-- 11. Apply the combined T2D phenotype rules.
phenotype AS (
    -- Two diagnoses on distinct dates.
    SELECT person_id
    FROM diagnosis_summary
    WHERE diagnosis_days >= 2

    UNION

    -- One diagnosis supported by medication exposure.
    SELECT ds.person_id
    FROM diagnosis_summary ds
    JOIN t2d_medications dm
      ON dm.person_id = ds.person_id
    WHERE ds.diagnosis_days >= 1

    UNION

    -- One diagnosis supported by an abnormal diabetes lab.
    SELECT ds.person_id
    FROM diagnosis_summary ds
    JOIN lab_summary ls
      ON ls.person_id = ds.person_id
    WHERE ds.diagnosis_days >= 1
      AND ls.abnormal_lab_days >= 1

    UNION

    -- Repeated abnormal labs plus medication exposure.
    SELECT ls.person_id
    FROM lab_summary ls
    JOIN t2d_medications dm
      ON dm.person_id = ls.person_id
    WHERE ls.abnormal_lab_days >= 2
)

-- 12. Return unique persons meeting the phenotype.
SELECT DISTINCT p.person_id
FROM phenotype ph
JOIN public.person p
  ON p.person_id = ph.person_id
ORDER BY p.person_id;
