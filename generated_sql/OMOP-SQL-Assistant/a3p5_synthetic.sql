
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
           AND concept_code ~ '^250\.?[0-9][02]$')
      )
),

-- 2. Map ICD source concepts to standard OMOP concepts.
t2dm_standard AS (
    SELECT concept_id
    FROM public.concept
    WHERE concept_id IN (SELECT concept_id FROM t2dm_icd)

    UNION

    SELECT cr.concept_id_2
    FROM public.concept_relationship cr
    JOIN t2dm_icd icd
      ON icd.concept_id = cr.concept_id_1
    JOIN public.concept target
      ON target.concept_id = cr.concept_id_2
    WHERE cr.relationship_id = 'Maps to'
      AND cr.invalid_reason IS NULL
      AND CURRENT_DATE BETWEEN cr.valid_start_date
                           AND cr.valid_end_date
      AND target.standard_concept = 'S'
      AND target.invalid_reason IS NULL
      AND target.domain_id = 'Condition'
),

-- 3. Expand standardized T2DM concepts to descendants.
t2dm_concepts AS (
    SELECT concept_id
    FROM t2dm_standard

    UNION

    SELECT ca.descendant_concept_id
    FROM public.concept_ancestor ca
    JOIN t2dm_standard s
      ON ca.ancestor_concept_id = s.concept_id
),

-- 4. Find qualifying T2DM diagnosis records.
diagnosis_events AS (
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
          OR (
              co.condition_source_value ~*
              '^E11(\.|$)'
          )
          OR (
              co.condition_source_value ~
              '^250\.?[0-9][02]$'
          )
      )
),

-- 5. Count distinct dates with a T2DM diagnosis.
diagnosis_evidence AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS diagnosis_days
    FROM diagnosis_events
    GROUP BY person_id
),

-- 6. Identify relevant generic and brand diabetes drugs.
diabetes_drug_terms AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id IN ('RxNorm', 'RxNorm Extension')
      AND invalid_reason IS NULL
      AND (
          (
              concept_class_id = 'Ingredient'
              AND LOWER(concept_name) IN (
                  'metformin',
                  'glipizide',
                  'glyburide',
                  'glimepiride',
                  'gliclazide',
                  'tolbutamide',
                  'chlorpropamide',
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
                  'miglitol',
                  'colesevelam',
                  'bromocriptine'
              )
          )
          OR (
              concept_name ~*
              ('(^|[^[:alnum:]])(Glucophage|Glucotrol|'
              || 'Glucotrol XL|Glucovance|Amaryl|'
              || 'Diabeta|Glynase|Actos|Avandia|'
              || 'Januvia|Janumet|Onglyza|Tradjenta|'
              || 'Nesina|Jardiance|Synjardy|'
              || 'Farxiga|Xigduo|Invokana|Invokamet|'
              || 'Steglatro|Trulicity|Victoza|'
              || 'Ozempic|Rybelsus|Byetta|Bydureon|'
              || 'Mounjaro|Adlyxin|Prandin|'
              || 'Starlix|Precose|Glyset|'
              || 'Qtern|Glyxambi|Trijardy|'
              || 'Segluromet)([^[:alnum:]]|$)')
          )
      )
),

-- 7. Include descendant drug products and mapped ingredients.
diabetes_drug_concepts AS (
    SELECT concept_id
    FROM diabetes_drug_terms

    UNION

    SELECT ca.descendant_concept_id
    FROM public.concept_ancestor ca
    JOIN diabetes_drug_terms d
      ON ca.ancestor_concept_id = d.concept_id

    UNION

    SELECT cr.concept_id_1
    FROM public.concept_relationship cr
    JOIN diabetes_drug_terms d
      ON cr.concept_id_2 = d.concept_id
    WHERE cr.relationship_id = 'RxNorm has ing'
      AND cr.invalid_reason IS NULL
      AND CURRENT_DATE BETWEEN cr.valid_start_date
                           AND cr.valid_end_date
),

-- 8. Identify patients with qualifying medication exposure.
medication_evidence AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    WHERE de.drug_concept_id IN (
        SELECT concept_id FROM diabetes_drug_concepts
    )
       OR de.drug_source_concept_id IN (
        SELECT concept_id FROM diabetes_drug_concepts
    )
),

-- 9. Identify HbA1c and fasting glucose LOINC concepts.
lab_concepts AS (
    SELECT
        concept_id,
        CASE
            WHEN concept_code IN (
                '4548-4',
                '17856-6',
                '59261-8'
            ) THEN 'HBA1C'
            WHEN concept_code = '1558-6'
            THEN 'FASTING_GLUCOSE'
        END AS lab_type
    FROM public.concept
    WHERE vocabulary_id = 'LOINC'
      AND invalid_reason IS NULL
      AND concept_code IN (
          '4548-4',
          '17856-6',
          '59261-8',
          '1558-6'
      )
),

-- 10. Resolve standardized measurement concept mappings.
lab_standard AS (
    SELECT concept_id, lab_type
    FROM lab_concepts

    UNION

    SELECT cr.concept_id_2, lc.lab_type
    FROM public.concept_relationship cr
    JOIN lab_concepts lc
      ON lc.concept_id = cr.concept_id_1
    JOIN public.concept target
      ON target.concept_id = cr.concept_id_2
    WHERE cr.relationship_id = 'Maps to'
      AND cr.invalid_reason IS NULL
      AND CURRENT_DATE BETWEEN cr.valid_start_date
                           AND cr.valid_end_date
      AND target.domain_id = 'Measurement'
      AND target.standard_concept = 'S'
      AND target.invalid_reason IS NULL
),

-- 11. Collect numeric results and documented units.
lab_values AS (
    SELECT
        m.person_id,
        m.measurement_date AS event_date,
        m.value_as_number,
        LOWER(TRIM(COALESCE(u.concept_code, '')))
            AS ucum_code,
        LOWER(TRIM(COALESCE(m.unit_source_value, '')))
            AS source_unit,
        COALESCE(
            ls.lab_type,
            lc.lab_type,
            CASE
                WHEN m.measurement_source_value IN (
                    '4548-4', '17856-6', '59261-8'
                ) THEN 'HBA1C'
                WHEN m.measurement_source_value = '1558-6'
                THEN 'FASTING_GLUCOSE'
            END
        ) AS lab_type
    FROM public.measurement m
    LEFT JOIN lab_standard ls
      ON m.measurement_concept_id = ls.concept_id
    LEFT JOIN lab_concepts lc
      ON m.measurement_source_concept_id = lc.concept_id
    LEFT JOIN public.concept u
      ON m.unit_concept_id = u.concept_id
     AND u.vocabulary_id = 'UCUM'
    WHERE m.value_as_number IS NOT NULL
      AND m.measurement_date IS NOT NULL
      AND (
          ls.concept_id IS NOT NULL
          OR lc.concept_id IS NOT NULL
          OR m.measurement_source_value IN (
              '4548-4', '17856-6',
              '59261-8', '1558-6'
          )
      )
),

-- 12. Apply diagnostic thresholds with explicit units.
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
                    (ucum_code = '%'
                     OR source_unit IN ('%', 'percent'))
                    AND value_as_number >= 6.5
                )
                OR
                (
                    (ucum_code = 'mmol/mol'
                     OR source_unit = 'mmol/mol')
                    AND value_as_number >= 48
                )
            )
        )
        OR
        (
            lab_type = 'FASTING_GLUCOSE'
            AND (
                (
                    (ucum_code = 'mg/dl'
                     OR source_unit = 'mg/dl')
                    AND value_as_number >= 126
                )
                OR
                (
                    (ucum_code = 'mmol/l'
                     OR source_unit = 'mmol/l')
                    AND value_as_number >= 7.0
                )
            )
        )
),

-- 13. Count separate dates with diagnostic lab results.
lab_evidence AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS abnormal_lab_days
    FROM abnormal_labs
    GROUP BY person_id
)

-- 14. Combine independent evidence to define T2DM.
SELECT DISTINCT p.person_id
FROM public.person p
LEFT JOIN diagnosis_evidence dx
  ON p.person_id = dx.person_id
LEFT JOIN medication_evidence med
  ON p.person_id = med.person_id
LEFT JOIN lab_evidence lab
  ON p.person_id = lab.person_id
WHERE
    -- Two diagnosis dates.
    COALESCE(dx.diagnosis_days, 0) >= 2

    -- One T2DM diagnosis plus medication evidence.
    OR (
        COALESCE(dx.diagnosis_days, 0) >= 1
        AND med.person_id IS NOT NULL
    )

    -- One T2DM diagnosis plus abnormal laboratory evidence.
    OR (
        COALESCE(dx.diagnosis_days, 0) >= 1
        AND COALESCE(lab.abnormal_lab_days, 0) >= 1
    )

    -- Repeated abnormal laboratory evidence.
    OR COALESCE(lab.abnormal_lab_days, 0) >= 2

ORDER BY p.person_id;
