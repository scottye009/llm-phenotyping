
WITH
-- 1. Identify ICD-9-CM and ICD-10-CM T2DM concepts.
t2dm_icd AS (
    SELECT concept_id
    FROM public.concept
    WHERE invalid_reason IS NULL
      AND (
          (vocabulary_id = 'ICD10CM'
           AND (concept_code = 'E11'
                OR concept_code LIKE 'E11.%'))
          OR
          (vocabulary_id = 'ICD9CM'
           AND concept_code ~ '^250\.[0-9]{2}[02]$')
      )
),

-- 2. Map ICD diagnoses to standard OMOP concepts.
t2dm_standard AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM public.concept_relationship cr
    JOIN t2dm_icd i
      ON cr.concept_id_1 = i.concept_id
    JOIN public.concept c
      ON c.concept_id = cr.concept_id_2
    WHERE cr.relationship_id = 'Maps to'
      AND cr.invalid_reason IS NULL
      AND CURRENT_DATE BETWEEN cr.valid_start_date
                           AND cr.valid_end_date
      AND c.standard_concept = 'S'
      AND c.invalid_reason IS NULL
      AND c.domain_id = 'Condition'
),

-- 3. Expand standardized diagnoses through OMOP hierarchy.
t2dm_concepts AS (
    SELECT concept_id FROM t2dm_standard

    UNION

    SELECT ca.descendant_concept_id
    FROM public.concept_ancestor ca
    JOIN t2dm_standard s
      ON ca.ancestor_concept_id = s.concept_id
),

-- 4. Identify T2DM diagnosis events.
t2dm_diagnoses AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date AS event_date
    FROM public.condition_occurrence co
    WHERE co.condition_start_date IS NOT NULL
      AND (
          co.condition_concept_id IN (
              SELECT concept_id FROM t2dm_concepts
          )
          OR co.condition_source_concept_id IN (
              SELECT concept_id FROM t2dm_icd
          )
          OR co.condition_source_value ~* '^E11(\.|$)'
          OR co.condition_source_value ~
             '^250\.[0-9]{2}[02]$'
      )
),

-- 5. Select antidiabetic RxNorm ingredients.
diabetes_ingredients AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id IN ('RxNorm', 'RxNorm Extension')
      AND concept_class_id = 'Ingredient'
      AND invalid_reason IS NULL
      AND LOWER(concept_name) IN (
          'metformin',
          'glipizide',
          'glyburide',
          'glimepiride',
          'chlorpropamide',
          'tolbutamide',
          'tolazamide',
          'gliclazide',
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
          'liraglutide',
          'semaglutide',
          'dulaglutide',
          'exenatide',
          'lixisenatide',
          'tirzepatide',
          'acarbose',
          'miglitol',
          'repaglinide',
          'nateglinide'
      )
),

-- 6. Resolve ingredient descendants and named drug products.
diabetes_drugs AS (
    SELECT concept_id
    FROM diabetes_ingredients

    UNION

    SELECT ca.descendant_concept_id
    FROM public.concept_ancestor ca
    JOIN diabetes_ingredients i
      ON ca.ancestor_concept_id = i.concept_id

    UNION

    SELECT c.concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Drug'
      AND c.vocabulary_id IN ('RxNorm', 'RxNorm Extension')
      AND c.invalid_reason IS NULL
      AND c.concept_name ~* (
          '(^|[^[:alpha:]])(' ||
          'metformin|glipizide|glyburide|glimepiride|' ||
          'pioglitazone|rosiglitazone|' ||
          'sitagliptin|saxagliptin|linagliptin|alogliptin|' ||
          'empagliflozin|dapagliflozin|canagliflozin|' ||
          'ertugliflozin|bexagliflozin|' ||
          'liraglutide|semaglutide|dulaglutide|' ||
          'exenatide|lixisenatide|tirzepatide|' ||
          'acarbose|miglitol|repaglinide|nateglinide|' ||
          'janumet|januvia|jardiance|synjardy|' ||
          'farxiga|xigduo|invokana|invokamet|' ||
          'ozempic|rybelsus|wegovy|trulicity|' ||
          'victoza|saxenda|byetta|bydureon|' ||
          'mounjaro|zepbound|glucophage|glucotrol|' ||
          'amaryl|actos|avandia|onglyza|tradjenta|' ||
          'nesina|kombiglyze|jentadueto|glyxambi|' ||
          'qtern|steglatro|steglujan|seg luromet' ||
          ')([^[:alpha:]]|$)'
      )
),

-- 7. Identify patients with antidiabetic drug exposure.
t2dm_medications AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    WHERE de.drug_concept_id IN (
        SELECT concept_id FROM diabetes_drugs
    )
),

-- 8. Identify HbA1c and fasting glucose LOINC concepts.
lab_concepts AS (
    SELECT
        c.concept_id,
        CASE
            WHEN c.concept_code IN (
                '4548-4', '17856-6', '59261-8'
            ) THEN 'HBA1C'
            WHEN c.concept_code = '1558-6'
            THEN 'FASTING_GLUCOSE'
        END AS lab_type
    FROM public.concept c
    WHERE c.vocabulary_id = 'LOINC'
      AND c.invalid_reason IS NULL
      AND c.concept_code IN (
          '4548-4', '17856-6', '59261-8', '1558-6'
      )
),

-- 9. Resolve standard lab concepts using Maps to.
lab_standard AS (
    SELECT concept_id, lab_type
    FROM lab_concepts

    UNION

    SELECT cr.concept_id_2, lc.lab_type
    FROM lab_concepts lc
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = lc.concept_id
    WHERE cr.relationship_id = 'Maps to'
      AND cr.invalid_reason IS NULL
      AND CURRENT_DATE BETWEEN cr.valid_start_date
                           AND cr.valid_end_date
),

-- 10. Retrieve laboratory values and units.
lab_values AS (
    SELECT
        m.person_id,
        m.measurement_date,
        ls.lab_type,
        m.value_as_number,
        LOWER(TRIM(COALESCE(
            NULLIF(u.concept_code, ''),
            NULLIF(m.unit_source_value, ''),
            ''
        ))) AS unit_code,
        LOWER(TRIM(COALESCE(
            m.unit_source_value, ''
        ))) AS source_unit
    FROM public.measurement m
    JOIN lab_standard ls
      ON m.measurement_concept_id = ls.concept_id
    LEFT JOIN public.concept u
      ON m.unit_concept_id = u.concept_id
    WHERE m.value_as_number IS NOT NULL
      AND m.measurement_date IS NOT NULL
),

-- 11. Apply diagnostic laboratory thresholds.
abnormal_labs AS (
    SELECT DISTINCT
        person_id,
        measurement_date AS event_date
    FROM lab_values
    WHERE
        (
            lab_type = 'HBA1C'
            AND (
                (
                    value_as_number >= 6.5
                    AND (
                        unit_code IN ('%', 'percent')
                        OR source_unit IN ('%', 'percent')
                    )
                )
                OR
                (
                    value_as_number >= 48
                    AND (
                        unit_code IN ('mmol/mol', 'mmol/mmol')
                        OR source_unit IN ('mmol/mol', 'mmol/mmol')
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
                        unit_code = 'mg/dl'
                        OR source_unit = 'mg/dl'
                    )
                )
                OR
                (
                    value_as_number >= 7.0
                    AND (
                        unit_code = 'mmol/l'
                        OR source_unit = 'mmol/l'
                    )
                )
            )
        )
),

-- 12. Count diagnoses on different calendar dates.
diagnosis_counts AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS diagnosis_days
    FROM t2dm_diagnoses
    GROUP BY person_id
),

-- 13. Count abnormal laboratory dates.
lab_counts AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS abnormal_lab_days
    FROM abnormal_labs
    GROUP BY person_id
),

-- 14. Combine patient-level phenotype evidence.
patient_evidence AS (
    SELECT
        p.person_id,
        COALESCE(d.diagnosis_days, 0) AS diagnosis_days,
        COALESCE(l.abnormal_lab_days, 0) AS abnormal_lab_days,
        CASE
            WHEN rx.person_id IS NOT NULL THEN 1
            ELSE 0
        END AS has_diabetes_medication
    FROM public.person p
    LEFT JOIN diagnosis_counts d
      ON p.person_id = d.person_id
    LEFT JOIN lab_counts l
      ON p.person_id = l.person_id
    LEFT JOIN t2dm_medications rx
      ON p.person_id = rx.person_id
)

-- 15. Return distinct patients meeting the T2DM phenotype.
SELECT DISTINCT person_id
FROM patient_evidence
WHERE
       diagnosis_days >= 2
    OR (
        diagnosis_days >= 1
        AND has_diabetes_medication = 1
    )
    OR (
        diagnosis_days >= 1
        AND abnormal_lab_days >= 1
    )
    OR abnormal_lab_days >= 2
ORDER BY person_id;
