-- Type 2 diabetes mellitus phenotype
-- Criteria:
--   1. >=2 T2DM diagnoses on distinct dates; OR
--   2. >=1 T2DM diagnosis plus antidiabetic medication or abnormal lab; OR
--   3. >=2 diabetes-range laboratory results on distinct dates.
-- Medication exposure alone does not qualify.
-- ICD9CM/ICD10CM source concepts are mapped to standard concepts.

WITH
-- 1. Identify T2DM diagnosis concepts using ICD9CM/ICD10CM.
t2dm_icd AS (
    SELECT concept_id
    FROM public.concept
    WHERE (
        (vocabulary_id = 'ICD10CM'
         AND concept_code ~ '^E11(\.|$)')
        OR
        (vocabulary_id = 'ICD9CM'
         AND concept_code ~ '^250\.?[0-9][02]$')
    )
      AND invalid_reason IS NULL
),

-- Resolve ICD concepts to standard condition concepts.
t2dm_standard AS (
    SELECT concept_id
    FROM t2dm_icd

    UNION

    SELECT cr.concept_id_2
    FROM public.concept_relationship cr
    JOIN t2dm_icd i
      ON cr.concept_id_1 = i.concept_id
    WHERE cr.relationship_id = 'Maps to'
      AND cr.invalid_reason IS NULL
      AND cr.valid_start_date <= CURRENT_DATE
      AND cr.valid_end_date >= CURRENT_DATE
),

-- Include descendants of mapped standard concepts where available.
t2dm_concepts AS (
    SELECT concept_id
    FROM t2dm_standard

    UNION

    SELECT ca.descendant_concept_id
    FROM public.concept_ancestor ca
    JOIN t2dm_standard s
      ON ca.ancestor_concept_id = s.concept_id
),

-- 2. Find T2DM diagnosis events.
t2dm_diagnoses AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date AS event_date
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (
        SELECT concept_id FROM t2dm_concepts
    )
       OR co.condition_source_concept_id IN (
        SELECT concept_id FROM t2dm_icd
    )
       OR (
           co.condition_source_value ~* '^E11(\.|$)'
           OR co.condition_source_value ~ '^250\.?[0-9][02]$'
       )
),

diagnosis_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS diagnosis_days,
        COUNT(*) AS diagnosis_events
    FROM t2dm_diagnoses
    GROUP BY person_id
),

-- 3. Identify antidiabetic medications using standardized
-- drug concept names and generic/brand ingredient names.
antidiabetic_drugs AS (
    SELECT
        de.person_id,
        de.drug_exposure_start_date AS event_date
    FROM public.drug_exposure de
    LEFT JOIN public.concept dc
      ON de.drug_concept_id = dc.concept_id
    LEFT JOIN public.concept sc
      ON de.drug_source_concept_id = sc.concept_id
    WHERE
        -- Generic names and common brand names.
        (
            COALESCE(dc.concept_name, '') ~* (
            '(metformin|glucophage|glumetza|fortamet|riomet|'
            || 'glipizide|glucotrol|glyburide|micronase|diabeta|'
            || 'glimepiride|amaryl|'
            || 'pioglitazone|actos|rosiglitazone|avandia|'
            || 'sitagliptin|januvia|linagliptin|tradjenta|'
            || 'saxagliptin|onglyza|alogliptin|nesina|'
            || 'empagliflozin|jardiance|dapagliflozin|farxiga|'
            || 'canagliflozin|invokana|ertugliflozin|steglatro|'
            || 'liraglutide|victoza|semaglutide|ozempic|rybelsus|'
            || 'dulaglutide|trulicity|exenatide|byetta|bydureon|'
            || 'tirzepatide|mounjaro|'
            || 'acarbose|precose|miglitol|glyset|'
            || 'repaglinide|prandin|nateglinide|starlix)')
            OR
            COALESCE(sc.concept_name, '') ~* (
            '(metformin|glipizide|glyburide|glimepiride|'
            || 'pioglitazone|rosiglitazone|sitagliptin|'
            || 'linagliptin|saxagliptin|alogliptin|'
            || 'empagliflozin|dapagliflozin|canagliflozin|'
            || 'ertugliflozin|liraglutide|semaglutide|'
            || 'dulaglutide|exenatide|tirzepatide|'
            || 'acarbose|miglitol|repaglinide|nateglinide)')
        )
),

medication_summary AS (
    SELECT DISTINCT person_id
    FROM antidiabetic_drugs
),

-- 4. Identify diabetes-range laboratory measurements.
-- HbA1c >=6.5%
-- Fasting plasma glucose >=126 mg/dL (7.0 mmol/L)
-- Random/unspecified glucose >=200 mg/dL (11.1 mmol/L)
-- For specificity, random glucose alone is not used.
lab_candidates AS (
    SELECT
        m.person_id,
        m.measurement_date AS event_date,
        m.value_as_number,
        LOWER(TRIM(COALESCE(
            NULLIF(m.unit_source_value, ''),
            uc.concept_name,
            ''
        ))) AS unit_name,
        LOWER(COALESCE(mc.concept_name, '')) AS test_name,
        COALESCE(src.concept_code, '') AS source_code,
        COALESCE(mc.concept_code, '') AS standard_code
    FROM public.measurement m
    LEFT JOIN public.concept mc
      ON m.measurement_concept_id = mc.concept_id
    LEFT JOIN public.concept src
      ON m.measurement_source_concept_id = src.concept_id
    LEFT JOIN public.concept uc
      ON m.unit_concept_id = uc.concept_id
    WHERE m.value_as_number IS NOT NULL
      AND m.value_as_number >= 0
),

abnormal_labs AS (
    SELECT DISTINCT
        person_id,
        event_date
    FROM lab_candidates
    WHERE
        -- HbA1c (percentage).
        (
            (
                standard_code IN ('4548-4', '17856-6')
                OR source_code IN ('4548-4', '17856-6')
                OR test_name ~ '(hemoglobin a1c|haemoglobin a1c|hba1c|glycated hemoglobin)'
            )
            AND value_as_number >= 6.5
            AND (
                unit_name IN ('%', 'percent', 'percentage')
                OR unit_name = ''
            )
        )

        OR

        -- Fasting glucose, mg/dL.
        (
            (
                standard_code IN ('1558-6', '14771-0')
                OR source_code IN ('1558-6', '14771-0')
                OR test_name ~ '(glucose.*fasting|fasting.*glucose)'
            )
            AND value_as_number >= 126
            AND unit_name IN ('mg/dl', 'milligram per deciliter',
                              'milligrams per deciliter')
        )

        OR

        -- Fasting glucose, mmol/L.
        (
            (
                standard_code IN ('1558-6', '14771-0')
                OR source_code IN ('1558-6', '14771-0')
                OR test_name ~ '(glucose.*fasting|fasting.*glucose)'
            )
            AND value_as_number >= 7.0
            AND unit_name IN ('mmol/l', 'mmol/liter',
                              'millimole per liter',
                              'millimoles per liter')
        )
),

lab_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS abnormal_lab_days
    FROM abnormal_labs
    GROUP BY person_id
)

-- 5. Combine clinical evidence to identify T2DM patients.
SELECT DISTINCT p.person_id
FROM public.person p
LEFT JOIN diagnosis_summary dx
  ON p.person_id = dx.person_id
LEFT JOIN medication_summary med
  ON p.person_id = med.person_id
LEFT JOIN lab_summary lab
  ON p.person_id = lab.person_id
WHERE
    -- Two T2DM diagnosis dates.
    COALESCE(dx.diagnosis_days, 0) >= 2

    OR

    -- At least one T2DM diagnosis with additional evidence.
    (
        COALESCE(dx.diagnosis_events, 0) >= 1
        AND (
            med.person_id IS NOT NULL
            OR COALESCE(lab.abnormal_lab_days, 0) >= 1
        )
    )

    OR

    -- Repeated diabetes-range laboratory evidence.
    COALESCE(lab.abnormal_lab_days, 0) >= 2

ORDER BY p.person_id;