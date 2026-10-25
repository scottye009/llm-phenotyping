
WITH
-- 1. Identify ICD-9-CM and ICD-10-CM T2DM concepts.
t2dm_icd AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND invalid_reason IS NULL
      AND (
          (vocabulary_id = 'ICD10CM'
           AND concept_code ~* '^E11(\.|$)')
          OR
          (vocabulary_id = 'ICD9CM'
           AND concept_code ~ '^250\.[0-9][02]$')
      )
),

-- 2. Map ICD diagnosis concepts to standard OMOP concepts.
t2dm_standard AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM public.concept_relationship cr
    JOIN t2dm_icd i
      ON cr.concept_id_1 = i.concept_id
    WHERE cr.relationship_id = 'Maps to'
      AND cr.invalid_reason IS NULL
      AND CURRENT_DATE BETWEEN cr.valid_start_date
                           AND cr.valid_end_date
),

-- 3. Find patients with T2DM diagnosis evidence.
t2dm_diagnoses AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date AS event_date
    FROM public.condition_occurrence co
    WHERE co.condition_start_date IS NOT NULL
      AND (
          co.condition_concept_id IN (
              SELECT concept_id FROM t2dm_standard
          )
          OR co.condition_source_concept_id IN (
              SELECT concept_id FROM t2dm_icd
          )
          OR (
              co.condition_source_value ~*
              '^E11(\.|$)'
          )
          OR (
              co.condition_source_value ~
              '^250\.[0-9][02]$'
          )
      )
),

-- 4. Count separate dates with T2DM diagnoses.
diagnosis_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS diagnosis_days
    FROM t2dm_diagnoses
    GROUP BY person_id
),

-- 5. Identify antidiabetic ingredients.
-- Includes ingredients used in generic and branded drugs.
diabetes_ingredients AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'RxNorm'
      AND concept_class_id = 'Ingredient'
      AND invalid_reason IS NULL
      AND LOWER(concept_name) IN (
          'metformin',
          'glipizide',
          'glyburide',
          'glimepiride',
          'chlorpropamide',
          'tolbutamide',
          'pioglitazone',
          'rosiglitazone',
          'sitagliptin',
          'saxagliptin',
          'linagliptin',
          'alogliptin',
          'empagliflozin',
          'dapagliflozin',
          'canagliflozin',
          'ertugliflozin',
          'liraglutide',
          'semaglutide',
          'dulaglutide',
          'exenatide',
          'lixisenatide',
          'tirzepatide',
          'repaglinide',
          'nateglinide',
          'acarbose',
          'miglitol'
      )
),

-- 6. Expand ingredients to associated standard drug concepts.
-- This captures generic drugs, brands, and combinations.
diabetes_drugs AS (
    SELECT DISTINCT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    JOIN diabetes_ingredients i
      ON ca.ancestor_concept_id = i.concept_id

    UNION

    SELECT DISTINCT ds.drug_concept_id AS concept_id
    FROM public.drug_strength ds
    JOIN diabetes_ingredients i
      ON ds.ingredient_concept_id = i.concept_id

    UNION

    SELECT concept_id
    FROM diabetes_ingredients
),

-- 7. Identify patients exposed to antidiabetic medication.
medication_patients AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    WHERE de.drug_concept_id IN (
        SELECT concept_id FROM diabetes_drugs
    )
),

-- 8. Identify relevant laboratory tests using LOINC.
lab_concepts AS (
    SELECT concept_id,
           CASE
               WHEN concept_code IN (
                   '4548-4', '17856-6', '59261-8'
               ) THEN 'HBA1C'
               WHEN concept_code = '1558-6'
                   THEN 'FASTING_GLUCOSE'
               WHEN concept_code = '2345-7'
                   THEN 'GLUCOSE'
           END AS test_type
    FROM public.concept
    WHERE vocabulary_id = 'LOINC'
      AND invalid_reason IS NULL
      AND concept_code IN (
          '4548-4', '17856-6', '59261-8',
          '1558-6', '2345-7'
      )
),

-- 9. Include standard measurement mappings for LOINC.
lab_standard AS (
    SELECT concept_id, test_type
    FROM lab_concepts

    UNION

    SELECT DISTINCT
        cr.concept_id_2 AS concept_id,
        lc.test_type
    FROM public.concept_relationship cr
    JOIN lab_concepts lc
      ON cr.concept_id_1 = lc.concept_id
    WHERE cr.relationship_id = 'Maps to'
      AND cr.invalid_reason IS NULL
),

-- 10. Identify units using UCUM vocabulary.
lab_units AS (
    SELECT concept_id,
           CASE
               WHEN concept_code = '%'
                   THEN 'PERCENT'
               WHEN concept_code = 'mmol/mol'
                   THEN 'MMOL_PER_MOL'
               WHEN concept_code = 'mg/dL'
                   THEN 'MG_PER_DL'
               WHEN concept_code = 'mmol/L'
                   THEN 'MMOL_PER_L'
           END AS unit_type
    FROM public.concept
    WHERE vocabulary_id = 'UCUM'
      AND concept_code IN (
          '%', 'mmol/mol', 'mg/dL', 'mmol/L'
      )
),

-- 11. Resolve laboratory tests and units.
patient_labs AS (
    SELECT
        m.person_id,
        m.measurement_date,
        ls.test_type,
        m.value_as_number,
        COALESCE(
            lu.unit_type,
            CASE
                WHEN TRIM(m.unit_source_value) IN ('%', 'percent')
                    THEN 'PERCENT'
                WHEN LOWER(TRIM(m.unit_source_value)) = 'mmol/mol'
                    THEN 'MMOL_PER_MOL'
                WHEN LOWER(TRIM(m.unit_source_value)) = 'mg/dl'
                    THEN 'MG_PER_DL'
                WHEN LOWER(TRIM(m.unit_source_value)) = 'mmol/l'
                    THEN 'MMOL_PER_L'
            END
        ) AS unit_type
    FROM public.measurement m
    JOIN lab_standard ls
      ON m.measurement_concept_id = ls.concept_id
    LEFT JOIN lab_units lu
      ON m.unit_concept_id = lu.concept_id
    WHERE m.value_as_number IS NOT NULL
      AND m.measurement_date IS NOT NULL
),

-- 12. Apply diabetes diagnostic laboratory thresholds.
abnormal_labs AS (
    SELECT DISTINCT
        person_id,
        measurement_date
    FROM patient_labs
    WHERE
        (
            test_type = 'HBA1C'
            AND (
                (unit_type = 'PERCENT'
                 AND value_as_number >= 6.5)
                OR
                (unit_type = 'MMOL_PER_MOL'
                 AND value_as_number >= 48)
            )
        )
        OR
        (
            test_type = 'FASTING_GLUCOSE'
            AND (
                (unit_type = 'MG_PER_DL'
                 AND value_as_number >= 126)
                OR
                (unit_type = 'MMOL_PER_L'
                 AND value_as_number >= 7.0)
            )
        )
        OR
        (
            test_type = 'GLUCOSE'
            AND (
                (unit_type = 'MG_PER_DL'
                 AND value_as_number >= 200)
                OR
                (unit_type = 'MMOL_PER_L'
                 AND value_as_number >= 11.1)
            )
        )
),

-- 13. Require two abnormal laboratory dates for
-- laboratory-only confirmation within the supporting evidence.
lab_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT measurement_date) AS abnormal_lab_days
    FROM abnormal_labs
    GROUP BY person_id
),

-- 14. Combine independent phenotype evidence.
-- Require T2DM diagnosis evidence to distinguish type 2
-- from other forms of diabetes.
eligible_patients AS (
    SELECT ds.person_id
    FROM diagnosis_summary ds
    LEFT JOIN medication_patients mp
      ON ds.person_id = mp.person_id
    LEFT JOIN lab_summary ls
      ON ds.person_id = ls.person_id
    WHERE
        ds.diagnosis_days >= 2
        OR
        (
            ds.diagnosis_days >= 1
            AND (
                mp.person_id IS NOT NULL
                OR COALESCE(ls.abnormal_lab_days, 0) >= 2
            )
        )
)

-- 15. Return the final type 2 diabetes patient cohort.
SELECT DISTINCT person_id
FROM eligible_patients
ORDER BY person_id;
