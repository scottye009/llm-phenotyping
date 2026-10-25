
WITH
-- =========================================================
-- 1. Identify T2DM and T1DM ICD concepts.
-- =========================================================
icd_seeds AS MATERIALIZED (
    SELECT
        concept_id,
        concept_code,
        CASE
            WHEN vocabulary_id = 'ICD10CM'
             AND concept_code ~ '^E11(\.|$)'
                THEN 'T2DM'
            WHEN vocabulary_id = 'ICD9CM'
             AND concept_code ~ '^250\.[0-9][02]$'
                THEN 'T2DM'
            WHEN vocabulary_id = 'ICD10CM'
             AND concept_code ~ '^E10(\.|$)'
                THEN 'T1DM'
            WHEN vocabulary_id = 'ICD9CM'
             AND concept_code ~ '^250\.[0-9][13]$'
                THEN 'T1DM'
        END AS dm_type
    FROM public.concept
    WHERE vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND invalid_reason IS NULL
),

-- 2. Standard SNOMED diabetes concepts.
snomed_seeds AS MATERIALIZED (
    SELECT
        concept_id,
        CASE
            WHEN concept_code = '44054006' THEN 'T2DM'
            WHEN concept_code = '46635009' THEN 'T1DM'
        END AS dm_type
    FROM public.concept
    WHERE vocabulary_id = 'SNOMED'
      AND standard_concept = 'S'
      AND domain_id = 'Condition'
      AND invalid_reason IS NULL
      AND concept_code IN ('44054006', '46635009')
),

-- 3. Resolve source-to-standard diagnosis mappings.
standard_dx AS MATERIALIZED (
    SELECT DISTINCT
        cr.concept_id_2 AS concept_id,
        i.dm_type
    FROM icd_seeds i
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = i.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
    JOIN public.concept c
      ON c.concept_id = cr.concept_id_2
     AND c.domain_id = 'Condition'
     AND c.standard_concept = 'S'
     AND c.invalid_reason IS NULL
    WHERE i.dm_type IS NOT NULL

    UNION

    SELECT concept_id, dm_type
    FROM snomed_seeds

    UNION

    SELECT ca.descendant_concept_id, s.dm_type
    FROM snomed_seeds s
    JOIN public.concept_ancestor ca
      ON ca.ancestor_concept_id = s.concept_id
    JOIN public.concept c
      ON c.concept_id = ca.descendant_concept_id
     AND c.domain_id = 'Condition'
     AND c.standard_concept = 'S'
     AND c.invalid_reason IS NULL
),

-- 4. Extract diagnoses using indexed concept IDs.
-- Include coded source evidence when standard mapping
-- is missing.
dx_events AS MATERIALIZED (
    SELECT
        co.person_id,
        co.condition_start_date::date AS event_date,
        d.dm_type
    FROM public.condition_occurrence co
    JOIN standard_dx d
      ON co.condition_concept_id = d.concept_id
    WHERE co.condition_start_date IS NOT NULL

    UNION

    SELECT
        co.person_id,
        co.condition_start_date::date,
        i.dm_type
    FROM public.condition_occurrence co
    JOIN icd_seeds i
      ON co.condition_source_concept_id = i.concept_id
    WHERE co.condition_start_date IS NOT NULL
      AND i.dm_type IS NOT NULL

    UNION

    SELECT
        co.person_id,
        co.condition_start_date::date,
        s.dm_type
    FROM public.condition_occurrence co
    JOIN standard_dx s
      ON co.condition_source_concept_id = s.concept_id
    WHERE co.condition_start_date IS NOT NULL

    UNION

    SELECT
        co.person_id,
        co.condition_start_date::date,
        i.dm_type
    FROM public.condition_occurrence co
    JOIN icd_seeds i
      ON co.condition_source_value = i.concept_code
    WHERE co.condition_start_date IS NOT NULL
      AND i.dm_type IS NOT NULL

    UNION

    SELECT
        co.person_id,
        co.condition_start_date::date,
        s.dm_type
    FROM public.condition_occurrence co
    JOIN public.concept c
      ON co.condition_source_value = c.concept_code
     AND c.vocabulary_id = 'SNOMED'
     AND c.invalid_reason IS NULL
    JOIN standard_dx s
      ON s.concept_id = c.concept_id
    WHERE co.condition_start_date IS NOT NULL
),

-- 5. Summarize diagnosis dates.
dx_summary AS MATERIALIZED (
    SELECT
        person_id,
        COUNT(DISTINCT event_date)
            FILTER (WHERE dm_type = 'T2DM') AS t2_days,
        COUNT(DISTINCT event_date)
            FILTER (WHERE dm_type = 'T1DM') AS t1_days
    FROM dx_events
    GROUP BY person_id
),

-- 6. Restrict downstream work to patients with T2DM.
candidate_patients AS MATERIALIZED (
    SELECT person_id, t2_days, t1_days
    FROM dx_summary
    WHERE t2_days >= 1
      AND NOT (
          t1_days >= 2
          AND t1_days >= t2_days
      )
),

t2_dates AS MATERIALIZED (
    SELECT DISTINCT d.person_id, d.event_date
    FROM dx_events d
    JOIN candidate_patients p
      ON d.person_id = p.person_id
    WHERE d.dm_type = 'T2DM'
),

-- =========================================================
-- 7. Non-insulin antidiabetic medication concepts.
-- =========================================================
drug_ingredients AS MATERIALIZED (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id IN ('RxNorm', 'RxNorm Extension')
      AND concept_class_id = 'Ingredient'
      AND standard_concept = 'S'
      AND invalid_reason IS NULL
      AND LOWER(concept_name) IN (
          'metformin',
          'glipizide', 'glyburide', 'glimepiride',
          'gliclazide', 'chlorpropamide',
          'tolbutamide', 'tolazamide',
          'pioglitazone', 'rosiglitazone',
          'repaglinide', 'nateglinide',
          'acarbose', 'miglitol',
          'sitagliptin', 'saxagliptin',
          'linagliptin', 'alogliptin',
          'empagliflozin', 'dapagliflozin',
          'canagliflozin', 'ertugliflozin',
          'semaglutide', 'liraglutide',
          'dulaglutide', 'exenatide',
          'lixisenatide', 'tirzepatide'
      )
),

drug_concepts AS MATERIALIZED (
    SELECT concept_id FROM drug_ingredients

    UNION

    SELECT ca.descendant_concept_id
    FROM public.concept_ancestor ca
    JOIN drug_ingredients i
      ON ca.ancestor_concept_id = i.concept_id
),

drug_source_mappings AS MATERIALIZED (
    SELECT DISTINCT cr.concept_id_1 AS concept_id
    FROM public.concept_relationship cr
    JOIN drug_concepts d
      ON cr.concept_id_2 = d.concept_id
    WHERE cr.relationship_id = 'Maps to'
      AND cr.invalid_reason IS NULL
),

-- 8. Check medication corroboration only for
-- candidate T2DM patients.
medication_confirmed AS (
    SELECT DISTINCT t.person_id
    FROM t2_dates t
    JOIN public.drug_exposure de
      ON de.person_id = t.person_id
     AND de.drug_exposure_start_date BETWEEN
         t.event_date - 365
         AND t.event_date + 365
    WHERE
        de.drug_concept_id IN (
            SELECT concept_id FROM drug_concepts
        )
        OR de.drug_source_concept_id IN (
            SELECT concept_id FROM drug_concepts
        )
        OR de.drug_source_concept_id IN (
            SELECT concept_id FROM drug_source_mappings
        )
),

-- =========================================================
-- 9. Laboratory test concepts.
-- =========================================================
lab_seeds AS MATERIALIZED (
    SELECT
        concept_id,
        concept_code,
        CASE
            WHEN concept_code IN ('4548-4', '17856-6')
                THEN 'HBA1C'
            WHEN concept_code = '1558-6'
                THEN 'FASTING_GLUCOSE'
        END AS lab_type
    FROM public.concept
    WHERE vocabulary_id = 'LOINC'
      AND invalid_reason IS NULL
      AND concept_code IN (
          '4548-4', '17856-6', '1558-6'
      )
),

lab_concepts AS MATERIALIZED (
    SELECT concept_id, lab_type
    FROM lab_seeds

    UNION

    SELECT cr.concept_id_2, s.lab_type
    FROM lab_seeds s
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = s.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
    JOIN public.concept c
      ON c.concept_id = cr.concept_id_2
     AND c.domain_id = 'Measurement'
     AND c.standard_concept = 'S'
     AND c.invalid_reason IS NULL
),

-- 10. Check relevant measurements for candidates.
-- Use all three available test-identification fields.
lab_values AS MATERIALIZED (
    SELECT
        m.person_id,
        m.measurement_date::date AS event_date,
        m.value_as_number,
        LOWER(TRIM(COALESCE(u.concept_code, '')))
            AS unit_code,
        LOWER(TRIM(COALESCE(u.concept_name, '')))
            AS unit_name,
        LOWER(TRIM(COALESCE(m.unit_source_value, '')))
            AS unit_source,
        COALESCE(lc.lab_type, sc.lab_type, ls.lab_type)
            AS lab_type
    FROM candidate_patients p
    JOIN public.measurement m
      ON m.person_id = p.person_id
    LEFT JOIN lab_concepts lc
      ON m.measurement_concept_id = lc.concept_id
    LEFT JOIN lab_concepts sc
      ON m.measurement_source_concept_id = sc.concept_id
    LEFT JOIN lab_seeds ls
      ON m.measurement_source_value = ls.concept_code
    LEFT JOIN public.concept u
      ON m.unit_concept_id = u.concept_id
    WHERE m.value_as_number IS NOT NULL
      AND m.measurement_date IS NOT NULL
      AND (
          lc.concept_id IS NOT NULL
          OR sc.concept_id IS NOT NULL
          OR ls.concept_id IS NOT NULL
      )
),

-- 11. Normalize measurement units.
normalized_labs AS (
    SELECT
        person_id,
        event_date,
        value_as_number,
        lab_type,
        CASE
            WHEN unit_code IN (
                '%', 'mmol/mol', 'mg/dl',
                'mg/100ml', 'mmol/l'
            )
                THEN unit_code
            WHEN unit_name IN (
                'percent', 'percentage',
                'percentage unit'
            )
                THEN '%'
            WHEN unit_name IN (
                'millimole per mole',
                'millimole per mol'
            )
                THEN 'mmol/mol'
            WHEN unit_name = 'milligram per deciliter'
                THEN 'mg/dl'
            WHEN unit_name = 'millimole per liter'
                THEN 'mmol/l'
            WHEN unit_source IN (
                '%', 'percent', 'percentage'
            )
                THEN '%'
            WHEN unit_source IN (
                'mmol/mol', 'mmol per mol'
            )
                THEN 'mmol/mol'
            WHEN unit_source IN (
                'mg/dl', 'mg/100ml',
                'milligram per deciliter'
            )
                THEN 'mg/dl'
            WHEN unit_source IN (
                'mmol/l', 'mmol/liter',
                'millimole per liter'
            )
                THEN 'mmol/l'
        END AS normalized_unit
    FROM lab_values
),

-- 12. Apply diabetes-range laboratory thresholds.
abnormal_labs AS MATERIALIZED (
    SELECT DISTINCT person_id, event_date
    FROM normalized_labs
    WHERE (
        lab_type = 'HBA1C'
        AND (
            (
                normalized_unit = '%'
                AND value_as_number BETWEEN 6.5 AND 20
            )
            OR (
                normalized_unit = 'mmol/mol'
                AND value_as_number BETWEEN 48 AND 195
            )
        )
    )
    OR (
        lab_type = 'FASTING_GLUCOSE'
        AND (
            (
                normalized_unit IN ('mg/dl', 'mg/100ml')
                AND value_as_number BETWEEN 126 AND 1000
            )
            OR (
                normalized_unit = 'mmol/l'
                AND value_as_number BETWEEN 7.0 AND 55.5
            )
        )
    )
),

-- 13. Confirm T2DM with abnormal laboratory evidence.
laboratory_confirmed AS (
    SELECT DISTINCT t.person_id
    FROM t2_dates t
    JOIN abnormal_labs l
      ON l.person_id = t.person_id
     AND l.event_date BETWEEN
         t.event_date - 365
         AND t.event_date + 365
),

-- 14. Combine all three eligibility pathways.
confirmed_t2dm AS (
    -- Two independent T2DM diagnosis dates.
    SELECT person_id
    FROM candidate_patients
    WHERE t2_days >= 2

    UNION

    -- Diagnosis plus medication.
    SELECT person_id
    FROM medication_confirmed

    UNION

    -- Diagnosis plus abnormal lab.
    SELECT person_id
    FROM laboratory_confirmed
)

-- 15. Final unique T2DM cohort.
SELECT p.person_id
FROM public.person p
JOIN confirmed_t2dm c
  ON c.person_id = p.person_id
ORDER BY p.person_id;
