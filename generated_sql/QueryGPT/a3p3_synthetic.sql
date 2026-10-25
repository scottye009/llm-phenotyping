
WITH
-- 1. Identify ICD-9-CM and ICD-10-CM codes for T2DM.
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
           AND REPLACE(concept_code, '.', '')
               ~ '^250[0-9][02]$')
      )
),

-- 2. Resolve ICD diagnoses to standard OMOP concepts.
t2dm_mapped AS (
    SELECT cr.concept_id_2 AS concept_id
    FROM public.concept_relationship cr
    JOIN t2dm_icd i
      ON i.concept_id = cr.concept_id_1
    JOIN public.concept c
      ON c.concept_id = cr.concept_id_2
    WHERE cr.relationship_id = 'Maps to'
      AND cr.invalid_reason IS NULL
      AND c.invalid_reason IS NULL
      AND c.standard_concept = 'S'
      AND c.domain_id = 'Condition'
),

-- 3. Expand mapped diagnoses through the OMOP hierarchy.
t2dm_concepts AS (
    SELECT concept_id FROM t2dm_mapped

    UNION

    SELECT ca.descendant_concept_id
    FROM public.concept_ancestor ca
    JOIN t2dm_mapped m
      ON ca.ancestor_concept_id = m.concept_id
),

-- 4. Collect qualifying T2DM diagnoses.
t2dm_diagnoses AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date::date AS event_date
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
              UPPER(REPLACE(
                  COALESCE(co.condition_source_value, ''),
                  '.', ''
              )) ~ '^E11([0-9A-Z]*)$'
          )
          OR (
              REPLACE(
                  COALESCE(co.condition_source_value, ''),
                  '.', ''
              ) ~ '^250[0-9][02]$'
          )
      )
),

-- 5. Identify diabetes medication ingredients.
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
          'tolazamide',
          'acetohexamide',
          'pioglitazone',
          'rosiglitazone',
          'repaglinide',
          'nateglinide',
          'acarbose',
          'miglitol',
          'sitagliptin',
          'saxagliptin',
          'linagliptin',
          'alogliptin',
          'vildagliptin',
          'canagliflozin',
          'dapagliflozin',
          'empagliflozin',
          'ertugliflozin',
          'bexagliflozin',
          'exenatide',
          'liraglutide',
          'dulaglutide',
          'semaglutide',
          'lixisenatide',
          'tirzepatide',
          'pramlintide'
      )
),

-- 6. Map ingredients to clinical drug concepts.
diabetes_drug_concepts AS (
    SELECT concept_id
    FROM diabetes_ingredients

    UNION

    SELECT ca.descendant_concept_id
    FROM public.concept_ancestor ca
    JOIN diabetes_ingredients i
      ON ca.ancestor_concept_id = i.concept_id
),

-- 7. Include generic and brand-name drug records.
diabetes_medications AS (
    SELECT DISTINCT
        de.person_id
    FROM public.drug_exposure de
    LEFT JOIN public.concept dc
      ON dc.concept_id = de.drug_concept_id
    WHERE de.drug_concept_id IN (
        SELECT concept_id FROM diabetes_drug_concepts
    )
    OR (
        dc.domain_id = 'Drug'
        AND dc.concept_name ~* (
            '(^|[^a-z])(' ||
            'metformin|glipizide|glyburide|glimepiride|' ||
            'pioglitazone|rosiglitazone|repaglinide|' ||
            'nateglinide|acarbose|miglitol|' ||
            'sitagliptin|saxagliptin|linagliptin|' ||
            'alogliptin|vildagliptin|' ||
            'canagliflozin|dapagliflozin|' ||
            'empagliflozin|ertugliflozin|' ||
            'bexagliflozin|exenatide|liraglutide|' ||
            'dulaglutide|semaglutide|lixisenatide|' ||
            'tirzepatide|pramlintide|' ||
            'Glucophage|Glucotrol|Micronase|' ||
            'Diabeta|Amaryl|Actos|Avandia|' ||
            'Januvia|Onglyza|Tradjenta|Nesina|' ||
            'Invokana|Farxiga|Jardiance|Steglatro|' ||
            'Byetta|Bydureon|Victoza|Trulicity|' ||
            'Ozempic|Rybelsus|Mounjaro|' ||
            'Janumet|Synjardy|Xigduo|Glyxambi|' ||
            'Segluromet|Steglujan' ||
            ')([^a-z]|$)'
        )
    )
),

-- 8. Identify standardized and source laboratory concepts.
diabetes_labs AS (
    SELECT
        m.person_id,
        m.measurement_date::date AS event_date,
        m.value_as_number,
        COALESCE(
            NULLIF(LOWER(TRIM(uc.concept_name)), ''),
            LOWER(TRIM(m.unit_source_value))
        ) AS unit_name,
        CASE
            WHEN lc.concept_code IN ('4548-4', '17856-6')
              OR sc.concept_code IN ('4548-4', '17856-6')
              OR m.measurement_source_value
                 IN ('4548-4', '17856-6')
            THEN 'HBA1C'

            WHEN lc.concept_code = '1558-6'
              OR sc.concept_code = '1558-6'
              OR m.measurement_source_value = '1558-6'
            THEN 'FASTING_GLUCOSE'

            ELSE NULL
        END AS lab_type
    FROM public.measurement m
    LEFT JOIN public.concept lc
      ON lc.concept_id = m.measurement_concept_id
    LEFT JOIN public.concept sc
      ON sc.concept_id = m.measurement_source_concept_id
    LEFT JOIN public.concept uc
      ON uc.concept_id = m.unit_concept_id
     AND m.unit_concept_id <> 0
    WHERE m.value_as_number IS NOT NULL
      AND m.measurement_date IS NOT NULL
),

-- 9. Apply diagnostic thresholds with unit conversion.
abnormal_labs AS (
    SELECT DISTINCT
        person_id,
        event_date
    FROM diabetes_labs
    WHERE
        (
            lab_type = 'HBA1C'
            AND value_as_number >= 6.5
            AND unit_name IN (
                '%',
                'percent',
                'percentage',
                'percentage unit'
            )
        )
        OR
        (
            lab_type = 'FASTING_GLUCOSE'
            AND (
                (
                    value_as_number >= 126
                    AND unit_name IN (
                        'mg/dl',
                        'milligram per deciliter'
                    )
                )
                OR
                (
                    value_as_number >= 7.0
                    AND unit_name IN (
                        'mmol/l',
                        'millimole per liter'
                    )
                )
            )
        )
),

-- 10. Summarize distinct diagnostic and laboratory dates.
diagnosis_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS diagnosis_count
    FROM t2dm_diagnoses
    GROUP BY person_id
),

lab_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS abnormal_lab_count
    FROM abnormal_labs
    GROUP BY person_id
),

-- 11. Assemble all patients with qualifying evidence.
patient_evidence AS (
    SELECT person_id FROM diagnosis_summary
    UNION
    SELECT person_id FROM lab_summary
    UNION
    SELECT person_id FROM diabetes_medications
)

-- 12. Final T2DM phenotype.
SELECT DISTINCT
    p.person_id
FROM public.person p
JOIN patient_evidence e
  ON p.person_id = e.person_id
LEFT JOIN diagnosis_summary d
  ON p.person_id = d.person_id
LEFT JOIN lab_summary l
  ON p.person_id = l.person_id
LEFT JOIN diabetes_medications med
  ON p.person_id = med.person_id
WHERE
       COALESCE(d.diagnosis_count, 0) >= 2
    OR COALESCE(l.abnormal_lab_count, 0) >= 2
    OR (
        COALESCE(d.diagnosis_count, 0) >= 1
        AND COALESCE(l.abnormal_lab_count, 0) >= 1
    )
    OR (
        COALESCE(d.diagnosis_count, 0) >= 1
        AND med.person_id IS NOT NULL
    )
    OR (
        COALESCE(l.abnormal_lab_count, 0) >= 1
        AND med.person_id IS NOT NULL
    )
ORDER BY p.person_id;
