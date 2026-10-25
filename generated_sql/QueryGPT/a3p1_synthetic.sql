WITH
-- 1. Identify ICD-9-CM and ICD-10-CM T2DM concepts.
t2d_icd AS (
    SELECT concept_id
    FROM public.concept
    WHERE invalid_reason IS NULL
      AND (
          (vocabulary_id = 'ICD10CM'
           AND concept_code ~ '^E11(\.|$)')
          OR
          (vocabulary_id = 'ICD9CM'
           AND concept_code ~ '^250\.[0-9][02]$')
      )
),

-- 2. Resolve ICD concepts to standard OMOP concepts.
t2d_concepts AS (
    SELECT concept_id FROM t2d_icd

    UNION

    SELECT cr.concept_id_2
    FROM public.concept_relationship cr
    JOIN t2d_icd i
      ON cr.concept_id_1 = i.concept_id
    WHERE cr.relationship_id = 'Maps to'
      AND cr.invalid_reason IS NULL
      AND CURRENT_DATE BETWEEN cr.valid_start_date
                           AND cr.valid_end_date
),

-- 3. Identify type 1 diabetes concepts for exclusion.
t1d_icd AS (
    SELECT concept_id
    FROM public.concept
    WHERE invalid_reason IS NULL
      AND (
          (vocabulary_id = 'ICD10CM'
           AND concept_code ~ '^E10(\.|$)')
          OR
          (vocabulary_id = 'ICD9CM'
           AND concept_code ~ '^250\.[0-9][13]$')
      )
),

t1d_concepts AS (
    SELECT concept_id FROM t1d_icd

    UNION

    SELECT cr.concept_id_2
    FROM public.concept_relationship cr
    JOIN t1d_icd i
      ON cr.concept_id_1 = i.concept_id
    WHERE cr.relationship_id = 'Maps to'
      AND cr.invalid_reason IS NULL
      AND CURRENT_DATE BETWEEN cr.valid_start_date
                           AND cr.valid_end_date
),

-- 4. Find T2DM diagnosis events.
t2d_diagnoses AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date AS event_date
    FROM public.condition_occurrence co
    WHERE co.condition_start_date IS NOT NULL
      AND (
          co.condition_concept_id IN (
              SELECT concept_id FROM t2d_concepts
          )
          OR co.condition_source_concept_id IN (
              SELECT concept_id FROM t2d_concepts
          )
          OR co.condition_source_value ~*
             '^(E11(\.|$)|250\.[0-9][02]$)'
      )
),

-- 5. Find patients with type 1 diabetes diagnoses.
t1d_patients AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (
              SELECT concept_id FROM t1d_concepts
          )
       OR co.condition_source_concept_id IN (
              SELECT concept_id FROM t1d_concepts
          )
       OR co.condition_source_value ~*
          '^(E10(\.|$)|250\.[0-9][13]$)'
),

-- 6. Identify antidiabetic ingredients in RxNorm.
drug_ingredients AS (
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
          'semaglutide',
          'liraglutide',
          'dulaglutide',
          'exenatide',
          'tirzepatide',
          'acarbose',
          'miglitol',
          'repaglinide',
          'nateglinide'
      )
),

-- 7. Expand ingredients to descendant drug products.
antidiabetic_drug_concepts AS (
    SELECT descendant_concept_id AS concept_id
    FROM public.concept_ancestor
    WHERE ancestor_concept_id IN (
        SELECT concept_id FROM drug_ingredients
    )

    UNION

    SELECT concept_id
    FROM drug_ingredients

    UNION

    -- Generic and brand-name fallback when ancestry is incomplete.
    SELECT concept_id
    FROM public.concept
    WHERE domain_id = 'Drug'
      AND invalid_reason IS NULL
      AND concept_name ~* (
          '\m(' ||
          'metformin|glipizide|glyburide|glimepiride|' ||
          'pioglitazone|rosiglitazone|' ||
          'sitagliptin|saxagliptin|linagliptin|alogliptin|' ||
          'empagliflozin|dapagliflozin|canagliflozin|' ||
          'ertugliflozin|semaglutide|liraglutide|' ||
          'dulaglutide|exenatide|tirzepatide|' ||
          'acarbose|miglitol|repaglinide|nateglinide|' ||
          'glucophage|glucotrol|diabeta|amaryl|' ||
          'actos|avandia|januvia|onglyza|tradjenta|' ||
          'nesina|jardiance|farxiga|invokana|' ||
          'steglatro|ozempic|rybelsus|wegovy|' ||
          'victoza|saxenda|trulicity|byetta|bydureon|' ||
          'mounjaro|zepbound|precose|glyset|' ||
          'prandin|starlix' ||
          ')\M'
      )
),

-- 8. Identify antidiabetic medication exposure.
antidiabetic_medications AS (
    SELECT DISTINCT
        de.person_id,
        de.drug_exposure_start_date AS event_date
    FROM public.drug_exposure de
    WHERE de.drug_exposure_start_date IS NOT NULL
      AND (
          de.drug_concept_id IN (
              SELECT concept_id
              FROM antidiabetic_drug_concepts
          )
          OR de.drug_source_concept_id IN (
              SELECT concept_id
              FROM antidiabetic_drug_concepts
          )
      )
),

-- 9. Identify HbA1c and fasting glucose LOINC concepts.
lab_loinc AS (
    SELECT
        concept_id,
        CASE
            WHEN concept_code IN ('4548-4', '17856-6')
                THEN 'HBA1C'
            WHEN concept_code IN (
                '1558-6', '14771-0', '17865-7'
            )
                THEN 'FASTING_GLUCOSE'
        END AS lab_type
    FROM public.concept
    WHERE vocabulary_id = 'LOINC'
      AND concept_code IN (
          '4548-4', '17856-6',
          '1558-6', '14771-0', '17865-7'
      )
      AND invalid_reason IS NULL
),

-- 10. Include mapped standard measurement concepts.
lab_concepts AS (
    SELECT concept_id, lab_type
    FROM lab_loinc

    UNION

    SELECT cr.concept_id_2, l.lab_type
    FROM public.concept_relationship cr
    JOIN lab_loinc l
      ON cr.concept_id_1 = l.concept_id
    WHERE cr.relationship_id = 'Maps to'
      AND cr.invalid_reason IS NULL
      AND CURRENT_DATE BETWEEN cr.valid_start_date
                           AND cr.valid_end_date
),

-- 11. Collect numeric lab values and corresponding units.
lab_values AS (
    SELECT DISTINCT
        m.measurement_id,
        m.person_id,
        m.measurement_date AS event_date,
        lc.lab_type,
        m.value_as_number,
        LOWER(
            TRIM(
                COALESCE(
                    NULLIF(m.unit_source_value, ''),
                    u.concept_code,
                    ''
                )
            )
        ) AS unit_code
    FROM public.measurement m
    JOIN lab_concepts lc
      ON m.measurement_concept_id = lc.concept_id
      OR m.measurement_source_concept_id = lc.concept_id
    LEFT JOIN public.concept u
      ON m.unit_concept_id = u.concept_id
    WHERE m.value_as_number IS NOT NULL
      AND m.measurement_date IS NOT NULL
),

-- 12. Apply diagnostic laboratory thresholds.
abnormal_labs AS (
    SELECT DISTINCT
        person_id,
        event_date
    FROM lab_values
    WHERE
        (
            lab_type = 'HBA1C'
            AND unit_code IN ('%', 'percent')
            AND value_as_number >= 6.5
        )
        OR
        (
            lab_type = 'FASTING_GLUCOSE'
            AND (
                (
                    unit_code IN ('mg/dl', 'mg/100ml')
                    AND value_as_number >= 126
                )
                OR
                (
                    unit_code IN ('mmol/l')
                    AND value_as_number >= 7.0
                )
            )
        )
),

-- 13. Criterion A: Two diagnoses on distinct dates.
repeated_diagnosis AS (
    SELECT person_id
    FROM t2d_diagnoses
    GROUP BY person_id
    HAVING COUNT(DISTINCT event_date) >= 2
),

-- 14. Criterion B: Diagnosis plus antidiabetic medication.
diagnosis_plus_medication AS (
    SELECT DISTINCT d.person_id
    FROM t2d_diagnoses d
    JOIN antidiabetic_medications rx
      ON d.person_id = rx.person_id
     AND rx.event_date BETWEEN
         d.event_date - INTERVAL '365 days'
         AND d.event_date + INTERVAL '365 days'
),

-- 15. Criterion C: Diagnosis plus abnormal laboratory result.
diagnosis_plus_lab AS (
    SELECT DISTINCT d.person_id
    FROM t2d_diagnoses d
    JOIN abnormal_labs l
      ON d.person_id = l.person_id
     AND l.event_date BETWEEN
         d.event_date - INTERVAL '365 days'
         AND d.event_date + INTERVAL '365 days'
),

-- 16. Criterion D: Two abnormal labs on different dates.
repeated_abnormal_labs AS (
    SELECT person_id
    FROM abnormal_labs
    GROUP BY person_id
    HAVING COUNT(DISTINCT event_date) >= 2
),

-- 17. Combine qualifying criteria.
t2d_candidates AS (
    SELECT person_id FROM repeated_diagnosis

    UNION

    SELECT person_id FROM diagnosis_plus_medication

    UNION

    SELECT person_id FROM diagnosis_plus_lab

    UNION

    SELECT person_id FROM repeated_abnormal_labs
)

-- 18. Return distinct patients after T1DM exclusion.
SELECT DISTINCT p.person_id
FROM public.person p
JOIN t2d_candidates t
  ON p.person_id = t.person_id
WHERE NOT EXISTS (
    SELECT 1
    FROM t1d_patients x
    WHERE x.person_id = p.person_id
)
ORDER BY p.person_id;