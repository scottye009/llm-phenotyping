WITH
-- 1. Identify ICD-9-CM and ICD-10-CM T2DM concepts.
t2d_icd AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND invalid_reason IS NULL
      AND (
          (vocabulary_id = 'ICD10CM'
           AND (concept_code = 'E11'
                OR concept_code LIKE 'E11.%'))
          OR
          (vocabulary_id = 'ICD9CM'
           AND concept_code ~ '^250(\.[0-9][02])$')
      )
),

-- 2. Map ICD concepts to standard OMOP concepts.
t2d_mapped AS (
    SELECT concept_id
    FROM t2d_icd

    UNION

    SELECT cr.concept_id_2
    FROM public.concept_relationship cr
    JOIN t2d_icd i
      ON cr.concept_id_1 = i.concept_id
    WHERE cr.relationship_id = 'Maps to'
      AND cr.invalid_reason IS NULL
),

-- 3. Expand mapped T2DM concepts through OMOP ancestry.
t2d_concepts AS (
    SELECT concept_id
    FROM t2d_mapped

    UNION

    SELECT ca.descendant_concept_id
    FROM public.concept_ancestor ca
    JOIN t2d_mapped m
      ON ca.ancestor_concept_id = m.concept_id
    JOIN public.concept c
      ON c.concept_id = ca.descendant_concept_id
    WHERE c.domain_id = 'Condition'
      AND c.standard_concept = 'S'
      AND c.invalid_reason IS NULL
),

-- 4. Capture T2DM diagnoses from standard and source concepts.
t2d_diagnoses AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date::date AS event_date
    FROM public.condition_occurrence co
    WHERE co.condition_start_date IS NOT NULL
      AND (
          co.condition_concept_id IN (
              SELECT concept_id FROM t2d_concepts
          )
          OR co.condition_source_concept_id IN (
              SELECT concept_id FROM t2d_icd
          )
          OR co.condition_source_concept_id IN (
              SELECT concept_id FROM t2d_concepts
          )
          OR co.condition_source_value ~* '^E11(\.|$)'
          OR co.condition_source_value ~ '^250\.[0-9][02]$'
      )
),

-- 5. Identify relevant antidiabetic medication ingredients.
drug_ingredients AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id IN ('RxNorm', 'RxNorm Extension')
      AND concept_class_id = 'Ingredient'
      AND invalid_reason IS NULL
      AND (
          concept_name ~* '(^|[^a-z])(metformin|glipizide|glyburide|glimepiride|gliclazide|pioglitazone|rosiglitazone|repaglinide|nateglinide|acarbose|miglitol|sitagliptin|saxagliptin|linagliptin|alogliptin|vildagliptin|empagliflozin|dapagliflozin|canagliflozin|ertugliflozin|liraglutide|semaglutide|dulaglutide|exenatide|lixisenatide|tirzepatide|lixisenatide|pramlintide)([^a-z]|$)'
      )
),

-- 6. Resolve ingredient descendants, formulations, and brand drugs.
t2d_drugs AS (
    SELECT concept_id
    FROM drug_ingredients

    UNION

    SELECT ca.descendant_concept_id
    FROM public.concept_ancestor ca
    JOIN drug_ingredients di
      ON ca.ancestor_concept_id = di.concept_id

    UNION

    SELECT concept_id
    FROM public.concept
    WHERE domain_id = 'Drug'
      AND invalid_reason IS NULL
      AND (
          concept_name ~* '(^|[^a-z])(Glucophage|Glucophage XR|Glumetza|Fortamet|Riomet|Glucotrol|Glucotrol XL|Amaryl|DiaBeta|Glynase|Micronase|Actos|Avandia|Prandin|Starlix|Precose|Glyset|Januvia|Janumet|Onglyza|Kombiglyze|Tradjenta|Jentadueto|Nesina|Kazano|Oseni|Jardiance|Synjardy|Farxiga|Xigduo|Invokana|Invokamet|Steglatro|Segluromet|Trulicity|Victoza|Saxenda|Ozempic|Rybelsus|Wegovy|Byetta|Bydureon|Adlyxin|Mounjaro|Zepbound)([^a-z]|$)'
      )
),

-- 7. Extract medication exposure evidence.
t2d_medications AS (
    SELECT DISTINCT
        de.person_id,
        de.drug_exposure_start_date::date AS event_date
    FROM public.drug_exposure de
    WHERE de.drug_exposure_start_date IS NOT NULL
      AND (
          de.drug_concept_id IN (
              SELECT concept_id FROM t2d_drugs
          )
          OR de.drug_source_concept_id IN (
              SELECT concept_id FROM t2d_drugs
          )
      )
),

-- 8. Resolve HbA1c and fasting plasma glucose LOINC concepts.
lab_concepts AS (
    SELECT
        concept_id,
        CASE
            WHEN concept_code IN ('4548-4', '17856-6')
                THEN 'HBA1C'
            WHEN concept_code IN ('1558-6', '76629-5')
                THEN 'FASTING_GLUCOSE'
        END AS lab_type
    FROM public.concept
    WHERE vocabulary_id = 'LOINC'
      AND concept_code IN (
          '4548-4',
          '17856-6',
          '1558-6',
          '76629-5'
      )
),

-- 9. Find standard mapped laboratory measurements.
lab_mapped AS (
    SELECT
        lc.concept_id,
        lc.lab_type
    FROM lab_concepts lc

    UNION

    SELECT
        cr.concept_id_2,
        lc.lab_type
    FROM lab_concepts lc
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = lc.concept_id
    WHERE cr.relationship_id = 'Maps to'
      AND cr.invalid_reason IS NULL
),

-- 10. Identify units using UCUM vocabulary.
lab_units AS (
    SELECT
        concept_id,
        CASE
            WHEN concept_code = '%' THEN 'PERCENT'
            WHEN concept_code = 'mmol/mol' THEN 'MMOL_MOL'
            WHEN concept_code = 'mg/dL' THEN 'MG_DL'
            WHEN concept_code = 'mmol/L' THEN 'MMOL_L'
        END AS unit_type
    FROM public.concept
    WHERE vocabulary_id = 'UCUM'
      AND concept_code IN (
          '%', 'mmol/mol', 'mg/dL', 'mmol/L'
      )
),

-- 11. Normalize laboratory values to HbA1c % and glucose mg/dL.
normalized_labs AS (
    SELECT
        m.person_id,
        m.measurement_date::date AS event_date,
        lm.lab_type,
        CASE
            WHEN lm.lab_type = 'HBA1C'
             AND (
                 lu.unit_type = 'PERCENT'
                 OR (
                     COALESCE(m.unit_concept_id, 0) = 0
                     AND lower(trim(m.unit_source_value)) IN (
                         '%', 'percent'
                     )
                 )
             )
                THEN m.value_as_number

            WHEN lm.lab_type = 'HBA1C'
             AND (
                 lu.unit_type = 'MMOL_MOL'
                 OR (
                     COALESCE(m.unit_concept_id, 0) = 0
                     AND lower(trim(m.unit_source_value)) = 'mmol/mol'
                 )
             )
                THEN (m.value_as_number * 0.09148) + 2.152

            WHEN lm.lab_type = 'FASTING_GLUCOSE'
             AND (
                 lu.unit_type = 'MG_DL'
                 OR (
                     COALESCE(m.unit_concept_id, 0) = 0
                     AND lower(trim(m.unit_source_value)) = 'mg/dl'
                 )
             )
                THEN m.value_as_number

            WHEN lm.lab_type = 'FASTING_GLUCOSE'
             AND (
                 lu.unit_type = 'MMOL_L'
                 OR (
                     COALESCE(m.unit_concept_id, 0) = 0
                     AND lower(trim(m.unit_source_value)) = 'mmol/l'
                 )
             )
                THEN m.value_as_number * 18.0182

            ELSE NULL
        END AS normalized_value
    FROM public.measurement m
    JOIN lab_mapped lm
      ON m.measurement_concept_id = lm.concept_id
      OR m.measurement_source_concept_id = lm.concept_id
      OR (
          COALESCE(m.measurement_concept_id, 0) = 0
          AND m.measurement_source_value IN (
              '4548-4', '17856-6', '1558-6', '76629-5'
          )
          AND lm.concept_id IN (
              SELECT concept_id FROM lab_concepts
          )
      )
    LEFT JOIN lab_units lu
      ON m.unit_concept_id = lu.concept_id
    WHERE m.value_as_number IS NOT NULL
      AND m.measurement_date IS NOT NULL
      AND m.value_as_number > 0
),

-- 12. Apply diagnostic laboratory thresholds.
abnormal_labs AS (
    SELECT DISTINCT
        person_id,
        event_date
    FROM normalized_labs
    WHERE (
        lab_type = 'HBA1C'
        AND normalized_value >= 6.5
        AND normalized_value <= 20
    )
    OR (
        lab_type = 'FASTING_GLUCOSE'
        AND normalized_value >= 126
        AND normalized_value <= 1000
    )
),

-- 13. Identify type 1 and gestational diabetes exclusion concepts.
other_diabetes_icd AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND invalid_reason IS NULL
      AND (
          (vocabulary_id = 'ICD10CM'
           AND (
               concept_code = 'E10'
               OR concept_code LIKE 'E10.%'
               OR concept_code = 'O24.4'
               OR concept_code LIKE 'O24.4%'
           ))
          OR
          (vocabulary_id = 'ICD9CM'
           AND (
               concept_code ~ '^250\.[0-9][13]$'
               OR concept_code ~ '^648\.8[0-4]$'
           ))
      )
),

other_diabetes_mapped AS (
    SELECT concept_id
    FROM other_diabetes_icd

    UNION

    SELECT cr.concept_id_2
    FROM public.concept_relationship cr
    JOIN other_diabetes_icd i
      ON cr.concept_id_1 = i.concept_id
    WHERE cr.relationship_id = 'Maps to'
      AND cr.invalid_reason IS NULL
),

other_diabetes_concepts AS (
    SELECT concept_id
    FROM other_diabetes_mapped

    UNION

    SELECT ca.descendant_concept_id
    FROM public.concept_ancestor ca
    JOIN other_diabetes_mapped m
      ON ca.ancestor_concept_id = m.concept_id
    JOIN public.concept c
      ON c.concept_id = ca.descendant_concept_id
    WHERE c.domain_id = 'Condition'
      AND c.standard_concept = 'S'
      AND c.invalid_reason IS NULL
),

other_diabetes_patients AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (
        SELECT concept_id FROM other_diabetes_concepts
    )
    OR co.condition_source_concept_id IN (
        SELECT concept_id FROM other_diabetes_concepts
    )
    OR co.condition_source_concept_id IN (
        SELECT concept_id FROM other_diabetes_icd
    )
    OR co.condition_source_value ~* '^E10(\.|$)'
    OR co.condition_source_value ~* '^O24\.4'
    OR co.condition_source_value ~ '^250\.[0-9][13]$'
    OR co.condition_source_value ~ '^648\.8[0-4]$'
),

-- 14. Count diagnosis dates and qualifying laboratory dates.
diagnosis_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS diagnosis_dates
    FROM t2d_diagnoses
    GROUP BY person_id
),

lab_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS abnormal_lab_dates
    FROM abnormal_labs
    GROUP BY person_id
),

-- 15. Apply phenotype inclusion rules.
phenotype AS (
    -- Rule A: At least two T2DM diagnosis dates.
    SELECT person_id
    FROM diagnosis_summary
    WHERE diagnosis_dates >= 2

    UNION

    -- Rule B: T2DM diagnosis plus antidiabetic medication.
    SELECT DISTINCT d.person_id
    FROM t2d_diagnoses d
    JOIN t2d_medications rx
      ON d.person_id = rx.person_id

    UNION

    -- Rule C: T2DM diagnosis plus diabetic-range laboratory result.
    SELECT DISTINCT d.person_id
    FROM t2d_diagnoses d
    JOIN abnormal_labs l
      ON d.person_id = l.person_id

    UNION

    -- Rule D: Repeated diabetic-range results without
    -- recorded type 1 or gestational diabetes.
    SELECT l.person_id
    FROM lab_summary l
    WHERE l.abnormal_lab_dates >= 2
      AND NOT EXISTS (
          SELECT 1
          FROM other_diabetes_patients o
          WHERE o.person_id = l.person_id
      )
)

-- 16. Return unique patient identifiers.
SELECT DISTINCT p.person_id
FROM public.person p
JOIN phenotype ph
  ON p.person_id = ph.person_id
ORDER BY p.person_id;