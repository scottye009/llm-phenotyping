
WITH
-- 1. Identify standard SNOMED T2DM concepts.
t2d_seed AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'SNOMED'
      AND concept_code = '44054006'
      AND standard_concept = 'S'
      AND invalid_reason IS NULL
),

t2d_standard_concepts AS (
    SELECT concept_id FROM t2d_seed

    UNION

    SELECT ca.descendant_concept_id
    FROM public.concept_ancestor ca
    JOIN t2d_seed s
      ON ca.ancestor_concept_id = s.concept_id
),

-- 2. Resolve ICD source concepts through valid Maps to relationships.
t2d_icd_mappings AS (
    SELECT DISTINCT
        src.concept_id AS source_concept_id,
        src.concept_code AS source_code,
        cr.concept_id_2 AS standard_concept_id
    FROM public.concept src
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = src.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
    JOIN public.concept std
      ON std.concept_id = cr.concept_id_2
     AND std.standard_concept = 'S'
     AND std.domain_id = 'Condition'
     AND std.invalid_reason IS NULL
    WHERE src.invalid_reason IS NULL
      AND (
          (src.vocabulary_id = 'ICD10CM'
           AND src.concept_code ~ '^E11(\.|$)')
          OR
          (src.vocabulary_id = 'ICD9CM'
           AND src.concept_code ~ '^250\.[0-9][02]$')
      )
),

t2d_condition_concepts AS (
    SELECT concept_id
    FROM t2d_standard_concepts

    UNION

    SELECT standard_concept_id
    FROM t2d_icd_mappings
),

-- 3. Identify patients with T2DM diagnoses.
diagnosis_patients AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (
        SELECT concept_id FROM t2d_condition_concepts
    )
    OR co.condition_source_concept_id IN (
        SELECT source_concept_id FROM t2d_icd_mappings
    )
    OR EXISTS (
        SELECT 1
        FROM t2d_icd_mappings im
        WHERE UPPER(TRIM(co.condition_source_value))
              = UPPER(im.source_code)
    )
),

-- 4. Identify standardized antidiabetic ingredients.
drug_ingredients AS (
    SELECT concept_id
    FROM public.concept
    WHERE domain_id = 'Drug'
      AND vocabulary_id = 'RxNorm'
      AND concept_class_id = 'Ingredient'
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
          '%empagliflozin%',
          '%dapagliflozin%',
          '%canagliflozin%',
          '%ertugliflozin%',
          '%liraglutide%',
          '%dulaglutide%',
          '%semaglutide%',
          '%exenatide%',
          '%tirzepatide%',
          '%repaglinide%',
          '%nateglinide%',
          '%acarbose%'
      ])
),

drug_concepts AS (
    SELECT concept_id FROM drug_ingredients

    UNION

    SELECT ca.descendant_concept_id
    FROM public.concept_ancestor ca
    JOIN drug_ingredients di
      ON ca.ancestor_concept_id = di.concept_id
),

medication_patients AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    WHERE de.drug_concept_id IN (
        SELECT concept_id FROM drug_concepts
    )
),

-- 5. Identify HbA1c and fasting glucose tests.
lab_records AS (
    SELECT
        m.person_id,
        m.measurement_date,
        m.value_as_number,
        LOWER(TRIM(COALESCE(m.unit_source_value, '')))
            AS source_unit,
        LOWER(TRIM(COALESCE(uc.concept_code, '')))
            AS standard_unit_code,
        LOWER(TRIM(COALESCE(uc.concept_name, '')))
            AS standard_unit_name,
        CASE
            WHEN (
                c.concept_name ILIKE '%hemoglobin a1c%'
                OR c.concept_name ILIKE '%glycated hemoglobin%'
                OR (
                    c.vocabulary_id = 'LOINC'
                    AND c.concept_code IN ('4548-4', '17856-6')
                )
                OR m.measurement_source_value IN
                    ('4548-4', '17856-6')
            )
            THEN 'HBA1C'

            WHEN (
                (
                    c.concept_name ILIKE '%glucose%'
                    AND c.concept_name ILIKE '%fast%'
                )
                OR (
                    c.vocabulary_id = 'LOINC'
                    AND c.concept_code = '1558-6'
                )
                OR m.measurement_source_value = '1558-6'
            )
            THEN 'FASTING_GLUCOSE'

            ELSE NULL
        END AS test_type
    FROM public.measurement m
    LEFT JOIN public.concept c
      ON m.measurement_concept_id = c.concept_id
    LEFT JOIN public.concept uc
      ON m.unit_concept_id = uc.concept_id
    WHERE m.value_as_number IS NOT NULL
      AND m.measurement_date IS NOT NULL
),

-- 6. Apply diagnostic thresholds with explicit unit checks.
abnormal_labs AS (
    SELECT DISTINCT
        person_id,
        measurement_date,
        test_type
    FROM lab_records
    WHERE
        (
            test_type = 'HBA1C'
            AND (
                (
                    value_as_number >= 6.5
                    AND (
                        source_unit IN ('%', 'percent', 'percentage')
                        OR standard_unit_code = '%'
                        OR standard_unit_name = 'percent'
                    )
                )
                OR (
                    value_as_number >= 48
                    AND (
                        source_unit = 'mmol/mol'
                        OR standard_unit_code = 'mmol/mol'
                        OR standard_unit_name
                           ILIKE '%millimole per mole%'
                    )
                )
            )
        )
        OR
        (
            test_type = 'FASTING_GLUCOSE'
            AND (
                (
                    value_as_number >= 126
                    AND (
                        source_unit IN ('mg/dl', 'mg/100ml')
                        OR standard_unit_code IN
                           ('mg/dl', 'mg/100ml')
                        OR standard_unit_name
                           ILIKE '%milligram per deciliter%'
                    )
                )
                OR (
                    value_as_number >= 7.0
                    AND (
                        source_unit = 'mmol/l'
                        OR standard_unit_code = 'mmol/l'
                        OR standard_unit_name
                           ILIKE '%millimole per liter%'
                    )
                )
            )
        )
),

-- 7. Require two abnormal results on different dates.
confirmed_lab_patients AS (
    SELECT person_id
    FROM abnormal_labs
    GROUP BY person_id
    HAVING COUNT(DISTINCT measurement_date) >= 2
),

-- 8. Combine complementary evidence.
combined_cohort AS (
    -- Recorded T2DM diagnosis.
    SELECT person_id
    FROM diagnosis_patients

    UNION

    -- Repeated abnormal laboratory evidence.
    SELECT person_id
    FROM confirmed_lab_patients

    UNION

    -- Abnormal laboratory evidence plus drug exposure.
    SELECT al.person_id
    FROM abnormal_labs al
    JOIN medication_patients mp
      ON al.person_id = mp.person_id
)

-- 9. Return unique patients.
SELECT DISTINCT p.person_id
FROM public.person p
JOIN combined_cohort cc
  ON p.person_id = cc.person_id
ORDER BY p.person_id;
