
WITH
-- 1. Identify Type 2 diabetes ICD-9-CM and ICD-10-CM concepts.
t2_icd AS (
    SELECT concept_id, concept_code
    FROM public.concept
    WHERE vocabulary_id = 'ICD10CM'
      AND (concept_code = 'E11' OR concept_code LIKE 'E11.%')
      AND invalid_reason IS NULL

    UNION

    SELECT concept_id, concept_code
    FROM public.concept
    WHERE vocabulary_id = 'ICD9CM'
      AND concept_code ~ '^250\.[0-9][02]$'
      AND invalid_reason IS NULL
),

-- 2. Map ICD concepts to standardized OMOP concepts.
t2_standard AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM t2_icd i
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = i.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
    JOIN public.concept c
      ON c.concept_id = cr.concept_id_2
     AND c.standard_concept = 'S'
     AND c.invalid_reason IS NULL

    UNION

    SELECT concept_id
    FROM t2_icd
),

-- 3. Expand standardized diagnosis concepts through hierarchy.
t2_concepts AS (
    SELECT concept_id FROM t2_standard

    UNION

    SELECT ca.descendant_concept_id
    FROM public.concept_ancestor ca
    JOIN t2_standard s
      ON ca.ancestor_concept_id = s.concept_id
),

-- 4. Find T2DM diagnoses using standard and source concepts.
t2_diagnoses AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date::date AS diagnosis_date
    FROM public.condition_occurrence co
    WHERE co.condition_start_date IS NOT NULL
      AND (
          co.condition_concept_id IN (
              SELECT concept_id FROM t2_concepts
          )
          OR co.condition_source_concept_id IN (
              SELECT concept_id FROM t2_icd
          )
          OR UPPER(TRIM(co.condition_source_value))
                ~ '^E11(\.|$)'
          OR TRIM(co.condition_source_value)
                ~ '^250\.[0-9][02]$'
      )
),

-- 5. Identify Type 1 diabetes diagnoses for specificity.
t1_icd AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD10CM'
      AND (concept_code = 'E10' OR concept_code LIKE 'E10.%')
      AND invalid_reason IS NULL

    UNION

    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD9CM'
      AND concept_code ~ '^250\.[0-9][13]$'
      AND invalid_reason IS NULL
),

t1_standard AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM t1_icd i
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = i.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL

    UNION

    SELECT concept_id FROM t1_icd
),

t1_concepts AS (
    SELECT concept_id FROM t1_standard

    UNION

    SELECT ca.descendant_concept_id
    FROM public.concept_ancestor ca
    JOIN t1_standard s
      ON ca.ancestor_concept_id = s.concept_id
),

t1_patients AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (
              SELECT concept_id FROM t1_concepts
          )
       OR co.condition_source_concept_id IN (
              SELECT concept_id FROM t1_icd
          )
       OR UPPER(TRIM(co.condition_source_value))
              ~ '^E10(\.|$)'
       OR TRIM(co.condition_source_value)
              ~ '^250\.[0-9][13]$'
),

-- 6. Select HbA1c and fasting glucose LOINC concepts.
lab_loinc AS (
    SELECT
        concept_id,
        concept_code,
        CASE
            WHEN concept_code IN (
                '4548-4',  -- HbA1c
                '17856-6', -- HbA1c
                '59261-8'  -- HbA1c
            ) THEN 'HBA1C'
            WHEN concept_code IN (
                '1558-6',  -- Fasting glucose
                '14771-0', -- Fasting glucose
                '17865-7'  -- Fasting glucose
            ) THEN 'FASTING_GLUCOSE'
        END AS lab_type
    FROM public.concept
    WHERE vocabulary_id = 'LOINC'
      AND concept_code IN (
          '4548-4', '17856-6', '59261-8',
          '1558-6', '14771-0', '17865-7'
      )
      AND invalid_reason IS NULL
),

-- 7. Resolve laboratory concepts to standard concepts.
lab_concepts AS (
    SELECT
        concept_id,
        concept_code,
        lab_type
    FROM lab_loinc

    UNION

    SELECT
        cr.concept_id_2,
        l.concept_code,
        l.lab_type
    FROM lab_loinc l
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = l.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
),

-- 8. Select numeric laboratory measurements.
lab_values AS (
    SELECT DISTINCT
        m.person_id,
        m.measurement_date::date AS lab_date,
        m.value_as_number AS lab_value,
        l.lab_type,
        LOWER(TRIM(COALESCE(
            NULLIF(m.unit_source_value, ''),
            u.concept_name,
            ''
        ))) AS unit_name,
        LOWER(TRIM(COALESCE(u.concept_code, '')))
            AS unit_code
    FROM public.measurement m
    JOIN lab_concepts l
      ON m.measurement_concept_id = l.concept_id
      OR m.measurement_source_concept_id = l.concept_id
      OR m.measurement_source_value = l.concept_code
    LEFT JOIN public.concept u
      ON m.unit_concept_id = u.concept_id
    WHERE m.value_as_number IS NOT NULL
      AND m.measurement_date IS NOT NULL
),

-- 9. Apply diagnostic thresholds with explicit units.
abnormal_labs AS (
    SELECT DISTINCT person_id, lab_date
    FROM lab_values
    WHERE
        (
            lab_type = 'HBA1C'
            AND (
                (
                    lab_value >= 6.5
                    AND (
                        unit_name IN ('%', 'percent', 'percentage')
                        OR unit_code = '%'
                    )
                )
                OR
                (
                    lab_value >= 48
                    AND (
                        unit_name IN ('mmol/mol', 'mmol per mol')
                        OR unit_code = 'mmol/mol'
                    )
                )
            )
        )
        OR
        (
            lab_type = 'FASTING_GLUCOSE'
            AND (
                (
                    lab_value >= 126
                    AND (
                        unit_name IN (
                            'mg/dl', 'mg/dl.',
                            'milligram per deciliter'
                        )
                        OR unit_code = 'mg/dL'
                    )
                )
                OR
                (
                    lab_value >= 7.0
                    AND (
                        unit_name IN (
                            'mmol/l', 'mmol/l.',
                            'millimole per liter'
                        )
                        OR unit_code = 'mmol/L'
                    )
                )
            )
        )
),

-- 10. Identify non-insulin antidiabetic ingredients.
diabetes_ingredients AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id IN ('RxNorm', 'RxNorm Extension')
      AND concept_class_id = 'Ingredient'
      AND invalid_reason IS NULL
      AND concept_name ~* (
          '^(metformin|glipizide|glyburide|glimepiride|'
          || 'pioglitazone|rosiglitazone|repaglinide|'
          || 'nateglinide|acarbose|miglitol|'
          || 'sitagliptin|saxagliptin|linagliptin|'
          || 'alogliptin|vildagliptin|'
          || 'empagliflozin|dapagliflozin|canagliflozin|'
          || 'ertugliflozin|'
          || 'liraglutide|semaglutide|dulaglutide|'
          || 'exenatide|lixisenatide|tirzepatide|'
          || 'pramlintide)$'
      )
),

-- 11. Expand ingredients to clinical and branded products.
diabetes_drug_concepts AS (
    SELECT concept_id
    FROM diabetes_ingredients

    UNION

    SELECT ca.descendant_concept_id
    FROM public.concept_ancestor ca
    JOIN diabetes_ingredients i
      ON ca.ancestor_concept_id = i.concept_id
),

-- 12. Capture generic and brand drug names.
diabetes_medications AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    LEFT JOIN public.concept dc
      ON de.drug_concept_id = dc.concept_id
    LEFT JOIN public.concept sc
      ON de.drug_source_concept_id = sc.concept_id
    WHERE
        de.drug_concept_id IN (
            SELECT concept_id FROM diabetes_drug_concepts
        )
        OR EXISTS (
            SELECT 1
            FROM public.concept_relationship cr
            WHERE cr.concept_id_1 = de.drug_source_concept_id
              AND cr.relationship_id = 'Maps to'
              AND cr.invalid_reason IS NULL
              AND cr.concept_id_2 IN (
                  SELECT concept_id
                  FROM diabetes_drug_concepts
              )
        )
        OR COALESCE(dc.concept_name, '') ~* (
            '\m(metformin|glipizide|glyburide|glimepiride|'
            || 'pioglitazone|rosiglitazone|repaglinide|'
            || 'nateglinide|acarbose|miglitol|'
            || 'sitagliptin|saxagliptin|linagliptin|'
            || 'alogliptin|vildagliptin|'
            || 'empagliflozin|dapagliflozin|canagliflozin|'
            || 'ertugliflozin|liraglutide|semaglutide|'
            || 'dulaglutide|exenatide|lixisenatide|'
            || 'tirzepatide|pramlintide|'
            || 'Glucophage|Glucotrol|DiaBeta|Amaryl|'
            || 'Actos|Avandia|Januvia|Onglyza|Tradjenta|'
            || 'Nesina|Jardiance|Farxiga|Invokana|'
            || 'Steglatro|Victoza|Ozempic|Rybelsus|'
            || 'Trulicity|Byetta|Bydureon|'
            || 'Adlyxin|Mounjaro|Starlix|Prandin|'
            || 'Precose|Glyset|Janumet|Synjardy|'
            || 'Xigduo|Segluromet|Glyxambi|Qtern|'
            || 'Soliqua|Xultophy)\M'
        )
        OR COALESCE(sc.concept_name, '') ~* (
            '\m(metformin|glipizide|glyburide|glimepiride|'
            || 'pioglitazone|sitagliptin|linagliptin|'
            || 'empagliflozin|dapagliflozin|canagliflozin|'
            || 'semaglutide|liraglutide|dulaglutide|'
            || 'tirzepatide|Glucophage|Januvia|'
            || 'Jardiance|Farxiga|Invokana|Ozempic|'
            || 'Rybelsus|Victoza|Trulicity|Mounjaro|'
            || 'Janumet|Synjardy|Xigduo)\M'
        )
),

-- 13. Count independent diagnostic dates and lab dates.
diagnosis_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT diagnosis_date) AS diagnosis_count
    FROM t2_diagnoses
    GROUP BY person_id
),

lab_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT lab_date) AS abnormal_lab_count
    FROM abnormal_labs
    GROUP BY person_id
),

-- 14. Construct phenotype based on corroborating evidence.
t2dm_phenotype AS (
    SELECT p.person_id
    FROM public.person p
    LEFT JOIN diagnosis_summary d
      ON p.person_id = d.person_id
    LEFT JOIN lab_summary l
      ON p.person_id = l.person_id
    LEFT JOIN diabetes_medications med
      ON p.person_id = med.person_id
    LEFT JOIN t1_patients t1
      ON p.person_id = t1.person_id
    WHERE
        -- Two independent T2DM diagnosis dates.
        COALESCE(d.diagnosis_count, 0) >= 2

        -- One T2DM diagnosis plus laboratory or drug evidence.
        OR (
            COALESCE(d.diagnosis_count, 0) >= 1
            AND (
                COALESCE(l.abnormal_lab_count, 0) >= 1
                OR med.person_id IS NOT NULL
            )
        )

        -- Lab-and-medication phenotype without T1DM coding.
        OR (
            COALESCE(l.abnormal_lab_count, 0) >= 2
            AND med.person_id IS NOT NULL
            AND t1.person_id IS NULL
        )
)

-- Final output: one row per qualifying patient.
SELECT DISTINCT person_id
FROM t2dm_phenotype
ORDER BY person_id;
