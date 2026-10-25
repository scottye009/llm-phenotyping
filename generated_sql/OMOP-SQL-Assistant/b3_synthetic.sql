
WITH
-- 1. Identify ICD-9-CM and ICD-10-CM T2DM source concepts.
t2dm_icd AS (
    SELECT concept_id
    FROM public.concept
    WHERE invalid_reason IS NULL
      AND (
          (
              vocabulary_id = 'ICD10CM'
              AND concept_code ~* '^E11(\.|[0-9]|$)'
          )
          OR
          (
              vocabulary_id = 'ICD9CM'
              AND concept_code ~ '^250\.?[0-9][02]$'
          )
      )
),

-- 2. Map ICD source concepts to standard Condition concepts.
t2dm_standard AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM t2dm_icd i
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = i.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
     AND CURRENT_DATE BETWEEN cr.valid_start_date
                          AND cr.valid_end_date
    JOIN public.concept c
      ON c.concept_id = cr.concept_id_2
     AND c.standard_concept = 'S'
     AND c.domain_id = 'Condition'
     AND c.invalid_reason IS NULL
),

-- 3. Expand standard T2DM concepts through OMOP ancestry.
t2dm_conditions AS (
    SELECT concept_id
    FROM t2dm_standard

    UNION

    SELECT ca.descendant_concept_id
    FROM public.concept_ancestor ca
    JOIN t2dm_standard s
      ON s.concept_id = ca.ancestor_concept_id
    JOIN public.concept c
      ON c.concept_id = ca.descendant_concept_id
     AND c.domain_id = 'Condition'
     AND c.standard_concept = 'S'
     AND c.invalid_reason IS NULL
),

-- 4. Identify T2DM diagnosis events.
diagnosis_events AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date AS event_date
    FROM public.condition_occurrence co
    WHERE co.condition_start_date IS NOT NULL
      AND (
          co.condition_concept_id IN (
              SELECT concept_id FROM t2dm_conditions
          )
          OR co.condition_source_concept_id IN (
              SELECT concept_id FROM t2dm_icd
          )
      )
),

-- 5. Count distinct dates with qualifying T2DM diagnoses.
diagnosis_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS diagnosis_days
    FROM diagnosis_events
    GROUP BY person_id
),

-- 6. Specify antidiabetic ingredients.
-- Insulin is excluded because it is not T2DM-specific.
drug_names AS (
    SELECT UNNEST(ARRAY[
        'metformin',
        'glipizide',
        'glyburide',
        'glimepiride',
        'gliclazide',
        'glibenclamide',
        'chlorpropamide',
        'tolbutamide',
        'tolazamide',
        'repaglinide',
        'nateglinide',
        'pioglitazone',
        'rosiglitazone',
        'sitagliptin',
        'saxagliptin',
        'linagliptin',
        'alogliptin',
        'vildagliptin',
        'empagliflozin',
        'dapagliflozin',
        'canagliflozin',
        'ertugliflozin',
        'bexagliflozin',
        'exenatide',
        'liraglutide',
        'dulaglutide',
        'semaglutide',
        'lixisenatide',
        'tirzepatide',
        'acarbose',
        'miglitol'
    ]::text[]) AS ingredient_name
),

-- 7. Find valid RxNorm ingredient concepts.
drug_ingredients AS (
    SELECT DISTINCT c.concept_id
    FROM public.concept c
    JOIN drug_names n
      ON LOWER(c.concept_name) = n.ingredient_name
    WHERE c.vocabulary_id IN (
        'RxNorm', 'RxNorm Extension'
    )
      AND c.concept_class_id = 'Ingredient'
      AND c.invalid_reason IS NULL
),

-- 8. Resolve ingredient descendants to standard drugs.
drug_concepts AS (
    SELECT c.concept_id
    FROM public.concept c
    JOIN drug_ingredients i
      ON i.concept_id = c.concept_id
    WHERE c.domain_id = 'Drug'
      AND c.standard_concept = 'S'

    UNION

    SELECT ca.descendant_concept_id
    FROM public.concept_ancestor ca
    JOIN drug_ingredients i
      ON i.concept_id = ca.ancestor_concept_id
    JOIN public.concept c
      ON c.concept_id = ca.descendant_concept_id
    WHERE c.domain_id = 'Drug'
      AND c.standard_concept = 'S'
      AND c.invalid_reason IS NULL

),

-- 9. Identify source drug concepts mapped to included drugs.
mapped_source_drugs AS (
    SELECT DISTINCT cr.concept_id_1 AS concept_id
    FROM public.concept_relationship cr
    JOIN drug_concepts d
      ON d.concept_id = cr.concept_id_2
    WHERE cr.relationship_id = 'Maps to'
      AND cr.invalid_reason IS NULL
      AND CURRENT_DATE BETWEEN cr.valid_start_date
                           AND cr.valid_end_date
),

-- 10. Identify patients with qualifying medication exposure.
medication_evidence AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    WHERE de.drug_concept_id IN (
        SELECT concept_id FROM drug_concepts
    )
       OR (
           (de.drug_concept_id IS NULL
            OR de.drug_concept_id = 0)
           AND de.drug_source_concept_id IN (
               SELECT concept_id FROM mapped_source_drugs
           )
       )
),

-- 11. Identify HbA1c and fasting glucose LOINC concepts.
lab_loinc AS (
    SELECT
        concept_id,
        concept_code,
        CASE
            WHEN concept_code IN (
                '4548-4',
                '17856-6',
                '59261-8'
            ) THEN 'HBA1C'
            WHEN concept_code IN (
                '1558-6',
                '14771-0'
            ) THEN 'FASTING_GLUCOSE'
        END AS lab_type
    FROM public.concept
    WHERE vocabulary_id = 'LOINC'
      AND invalid_reason IS NULL
      AND concept_code IN (
          '4548-4',
          '17856-6',
          '59261-8',
          '1558-6',
          '14771-0'
      )
),

-- 12. Resolve LOINC concepts to standard measurements.
lab_standard AS (
    SELECT
        concept_id,
        lab_type
    FROM lab_loinc

    UNION

    SELECT
        cr.concept_id_2,
        ll.lab_type
    FROM lab_loinc ll
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = ll.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
     AND CURRENT_DATE BETWEEN cr.valid_start_date
                          AND cr.valid_end_date
    JOIN public.concept c
      ON c.concept_id = cr.concept_id_2
     AND c.domain_id = 'Measurement'
     AND c.standard_concept = 'S'
     AND c.invalid_reason IS NULL
),

-- 13. Match measurements using standard or source identifiers.
lab_matches AS (
    -- Match standard measurement concepts.
    SELECT
        m.measurement_id,
        ls.lab_type
    FROM public.measurement m
    JOIN lab_standard ls
      ON m.measurement_concept_id = ls.concept_id
    WHERE m.value_as_number IS NOT NULL

    UNION

    -- Match recorded LOINC source concept IDs.
    SELECT
        m.measurement_id,
        ll.lab_type
    FROM public.measurement m
    JOIN lab_loinc ll
      ON m.measurement_source_concept_id = ll.concept_id
    WHERE m.value_as_number IS NOT NULL

),

-- 14. Retrieve results and normalize reported units.
lab_values AS (
    SELECT
        m.person_id,
        m.measurement_date AS event_date,
        lm.lab_type,
        m.value_as_number,
        LOWER(TRIM(COALESCE(
            NULLIF(u.concept_code, ''),
            m.unit_source_value,
            ''
        ))) AS standard_unit,
        LOWER(TRIM(COALESCE(
            m.unit_source_value, ''
        ))) AS source_unit
    FROM lab_matches lm
    JOIN public.measurement m
      ON m.measurement_id = lm.measurement_id
    LEFT JOIN public.concept u
      ON u.concept_id = m.unit_concept_id
     AND u.vocabulary_id = 'UCUM'
     AND u.invalid_reason IS NULL
    WHERE m.measurement_date IS NOT NULL
      AND m.value_as_number IS NOT NULL
),

-- 15. Apply diabetes-range laboratory thresholds.
abnormal_labs AS (
    SELECT DISTINCT
        person_id,
        event_date
    FROM lab_values
    WHERE
        (
            lab_type = 'HBA1C'
            AND (
                (
                    value_as_number >= 6.5
                    AND (
                        standard_unit IN ('%', 'percent')
                        OR source_unit IN ('%', 'percent')
                    )
                )
                OR
                (
                    value_as_number >= 48
                    AND (
                        standard_unit = 'mmol/mol'
                        OR source_unit = 'mmol/mol'
                    )
                )
                OR
                (
                    value_as_number >= 0.065
                    AND value_as_number <= 1
                    AND (
                        standard_unit IN ('1', 'fraction')
                        OR source_unit IN ('1', 'fraction')
                    )
                )
            )
        )
        OR
        (
            lab_type = 'FASTING_GLUCOSE'
            AND (
                (
                    value_as_number >= 126
                    AND (
                        standard_unit IN ('mg/dl', 'mgdl')
                        OR source_unit IN ('mg/dl', 'mgdl')
                    )
                )
                OR
                (
                    value_as_number >= 7.0
                    AND (
                        standard_unit IN ('mmol/l', 'mmol per l')
                        OR source_unit IN ('mmol/l', 'mmol per l')
                    )
                )
            )
        )
),

-- 16. Count distinct dates with abnormal laboratory evidence.
lab_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS abnormal_lab_days
    FROM abnormal_labs
    GROUP BY person_id
),

-- 17. Apply the T2DM-specific inclusion criteria.
eligible_patients AS (
    -- Criterion A: At least two T2DM diagnosis dates.
    SELECT person_id
    FROM diagnosis_summary
    WHERE diagnosis_days >= 2

    UNION

    -- Criterion B: T2DM diagnosis plus diabetes medication.
    SELECT d.person_id
    FROM diagnosis_summary d
    JOIN medication_evidence med
      ON med.person_id = d.person_id
    WHERE d.diagnosis_days >= 1

    UNION

    -- Criterion C: T2DM diagnosis plus abnormal laboratory result.
    SELECT d.person_id
    FROM diagnosis_summary d
    JOIN lab_summary lab
      ON lab.person_id = d.person_id
    WHERE d.diagnosis_days >= 1
      AND lab.abnormal_lab_days >= 1
)

-- 18. Return unique patients in the final T2DM cohort.
SELECT ep.person_id
FROM eligible_patients ep
JOIN public.person p
  ON p.person_id = ep.person_id
ORDER BY ep.person_id;
