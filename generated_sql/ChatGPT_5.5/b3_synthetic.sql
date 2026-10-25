
-- T2DM phenotyping | Synthetic OMOP CDM | PostgreSQL
--
-- Inclusion:
-- 1. >=2 T2DM diagnosis dates
-- 2. >=1 T2DM diagnosis + non-insulin antidiabetic medication
-- 3. >=1 T2DM diagnosis + diabetes-range laboratory result
-- 4. >=2 abnormal laboratory dates + medication,
--    without documented T1DM
--
-- Medication alone and laboratory evidence alone are insufficient.
-- This is an operational phenotype, not a validated gold standard.

WITH

-- 1. Identify source ICD concepts for T1DM and T2DM.
icd_diabetes AS (
    SELECT
        concept_id,
        concept_code,
        CASE
            WHEN vocabulary_id = 'ICD10CM'
                 AND concept_code ~* '^E11(\.|$)'
                THEN 'T2DM'
            WHEN vocabulary_id = 'ICD9CM'
                 AND concept_code ~ '^250\.[0-9][02]$'
                THEN 'T2DM'
            WHEN vocabulary_id = 'ICD10CM'
                 AND concept_code ~* '^E10(\.|$)'
                THEN 'T1DM'
            WHEN vocabulary_id = 'ICD9CM'
                 AND concept_code ~ '^250\.[0-9][13]$'
                THEN 'T1DM'
        END AS diabetes_type
    FROM public.concept
    WHERE vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND invalid_reason IS NULL
      AND valid_start_date <= CURRENT_DATE
      AND valid_end_date >= CURRENT_DATE
),

-- 2. Resolve ICD concepts to standard condition concepts.
mapped_diabetes AS (
    SELECT DISTINCT
        cr.concept_id_2 AS concept_id,
        i.diabetes_type
    FROM icd_diabetes i
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = i.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
     AND CURRENT_DATE BETWEEN
         cr.valid_start_date AND cr.valid_end_date
    JOIN public.concept std
      ON std.concept_id = cr.concept_id_2
     AND std.standard_concept = 'S'
     AND std.domain_id = 'Condition'
     AND std.invalid_reason IS NULL
    WHERE i.diabetes_type IS NOT NULL
      AND (
          (i.diabetes_type = 'T2DM'
           AND (
               std.concept_name ~* 'type (2|ii) diabetes'
               OR std.concept_name ~*
                  '(non.insulin.dependent diabetes|niddm)'
           ))
          OR
          (i.diabetes_type = 'T1DM'
           AND std.concept_name ~* 'type (1|i) diabetes')
      )
),

-- 3. Include explicitly named standard diabetes concepts.
named_diabetes AS (
    SELECT
        concept_id,
        CASE
            WHEN concept_name ~* 'type (2|ii) diabetes'
              OR concept_name ~*
                 '(non.insulin.dependent diabetes|niddm)'
                THEN 'T2DM'
            WHEN concept_name ~* 'type (1|i) diabetes'
                THEN 'T1DM'
        END AS diabetes_type
    FROM public.concept
    WHERE standard_concept = 'S'
      AND domain_id = 'Condition'
      AND invalid_reason IS NULL
      AND (
          concept_name ~* 'type (2|ii) diabetes'
          OR concept_name ~* 'type (1|i) diabetes'
          OR concept_name ~*
             '(non.insulin.dependent diabetes|niddm)'
      )
),

-- 4. Expand standard condition concepts through hierarchy.
diabetes_seeds AS (
    SELECT concept_id, diabetes_type
    FROM mapped_diabetes

    UNION

    SELECT concept_id, diabetes_type
    FROM named_diabetes
    WHERE diabetes_type IS NOT NULL
),

diabetes_concepts AS (
    SELECT concept_id, diabetes_type
    FROM diabetes_seeds

    UNION

    SELECT
        ca.descendant_concept_id,
        s.diabetes_type
    FROM diabetes_seeds s
    JOIN public.concept_ancestor ca
      ON ca.ancestor_concept_id = s.concept_id
    JOIN public.concept c
      ON c.concept_id = ca.descendant_concept_id
     AND c.standard_concept = 'S'
     AND c.domain_id = 'Condition'
     AND c.invalid_reason IS NULL
),

-- 5. Classify diagnosis events from standard and source codes.
diagnosis_flags AS (
    SELECT
        co.person_id,
        COALESCE(
            co.condition_start_date,
            co.condition_start_datetime::date
        ) AS event_date,

        (
            EXISTS (
                SELECT 1
                FROM diabetes_concepts dc
                WHERE dc.concept_id = co.condition_concept_id
                  AND dc.diabetes_type = 'T2DM'
            )
            OR EXISTS (
                SELECT 1
                FROM icd_diabetes i
                WHERE i.diabetes_type = 'T2DM'
                  AND i.concept_id = co.condition_source_concept_id
            )
            OR co.condition_source_value ~*
               '^E11(\.|$)'
            OR co.condition_source_value ~
               '^250\.[0-9][02]$'
        ) AS is_t2dm,

        (
            EXISTS (
                SELECT 1
                FROM diabetes_concepts dc
                WHERE dc.concept_id = co.condition_concept_id
                  AND dc.diabetes_type = 'T1DM'
            )
            OR EXISTS (
                SELECT 1
                FROM icd_diabetes i
                WHERE i.diabetes_type = 'T1DM'
                  AND i.concept_id = co.condition_source_concept_id
            )
            OR co.condition_source_value ~*
               '^E10(\.|$)'
            OR co.condition_source_value ~
               '^250\.[0-9][13]$'
        ) AS is_t1dm

    FROM public.condition_occurrence co
),

diagnosis_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date)
            FILTER (WHERE is_t2dm) AS t2dm_dx_dates,
        COUNT(*) FILTER (WHERE is_t1dm) AS t1dm_dx_count
    FROM diagnosis_flags
    WHERE event_date IS NOT NULL
    GROUP BY person_id
),

-- 6. Identify non-insulin antidiabetic drug concepts.
-- Match standard drug concept names, not numeric source values.
drug_concepts AS (
    SELECT concept_id
    FROM public.concept
    WHERE domain_id = 'Drug'
      AND invalid_reason IS NULL
      AND (
          concept_name ~*
          '(^|[^a-z])(metformin|glipizide|glyburide|glimepiride|gliclazide|repaglinide|nateglinide|pioglitazone|rosiglitazone|sitagliptin|saxagliptin|linagliptin|alogliptin|vildagliptin|canagliflozin|dapagliflozin|empagliflozin|ertugliflozin|bexagliflozin|exenatide|liraglutide|dulaglutide|semaglutide|lixisenatide|tirzepatide|acarbose|miglitol)([^a-z]|$)'
          OR
          concept_name ~*
          '(^|[^a-z])(glucophage|glumetza|fortamet|riomet|glucotrol|diabeta|glynase|amaryl|prandin|actos|avandia|januvia|janumet|onglyza|tradjenta|nesina|invokana|farxiga|jardiance|steglatro|synjardy|xigduo|invokamet|byetta|bydureon|victoza|trulicity|ozempic|rybelsus|mounjaro|glyset|starlix)([^a-z]|$)'
      )
),

medication_evidence AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    WHERE de.drug_concept_id IN (
        SELECT concept_id FROM drug_concepts
    )
),

-- 7. Identify HbA1c and fasting glucose tests.
-- Use standard concepts, source concepts, LOINC source codes,
-- and explicit standardized test names.
lab_candidates AS (
    SELECT
        m.person_id,
        m.measurement_id,
        COALESCE(
            m.measurement_date,
            m.measurement_datetime::date
        ) AS event_date,
        m.value_as_number,

        LOWER(TRIM(COALESCE(
            NULLIF(m.unit_source_value, ''),
            NULLIF(uc.concept_code, ''),
            uc.concept_name,
            ''
        ))) AS unit_name,

        CASE
            WHEN (
                mc.concept_code IN (
                    '4548-4', '17856-6', '59261-8'
                )
                OR sc.concept_code IN (
                    '4548-4', '17856-6', '59261-8'
                )
                OR m.measurement_source_value IN (
                    '4548-4', '17856-6', '59261-8'
                )
                OR mc.concept_name ~*
                   '(hemoglobin a1c|haemoglobin a1c|hba1c|glycated hemoglobin|hemoglobin\.a1c)'
            ) THEN 'HBA1C'

            WHEN (
                mc.concept_code IN ('1558-6', '14771-0')
                OR sc.concept_code IN ('1558-6', '14771-0')
                OR m.measurement_source_value IN (
                    '1558-6', '14771-0'
                )
                OR mc.concept_name ~*
                   '(fasting.*glucose|glucose.*fasting)'
            ) THEN 'FASTING_GLUCOSE'
        END AS lab_type

    FROM public.measurement m
    LEFT JOIN public.concept mc
      ON mc.concept_id = m.measurement_concept_id
    LEFT JOIN public.concept sc
      ON sc.concept_id = m.measurement_source_concept_id
    LEFT JOIN public.concept uc
      ON uc.concept_id = m.unit_concept_id
    WHERE m.value_as_number IS NOT NULL
      AND m.value_as_number > 0
),

-- 8. Apply diagnostic thresholds with explicit units.
abnormal_labs AS (
    SELECT DISTINCT
        person_id,
        event_date
    FROM lab_candidates
    WHERE event_date IS NOT NULL
      AND (
          -- HbA1c >=6.5%
          (
              lab_type = 'HBA1C'
              AND value_as_number >= 6.5
              AND (
                  unit_name IN (
                      '%', 'percent', 'percentage'
                  )
                  OR unit_name LIKE '%percent%'
              )
          )

          OR

          -- HbA1c >=48 mmol/mol
          (
              lab_type = 'HBA1C'
              AND value_as_number >= 48
              AND (
                  unit_name LIKE '%mmol/mol%'
                  OR unit_name LIKE '%millimole per mole%'
                  OR unit_name LIKE '%millimoles per mole%'
              )
          )

          OR

          -- Fasting glucose >=126 mg/dL
          (
              lab_type = 'FASTING_GLUCOSE'
              AND value_as_number >= 126
              AND (
                  unit_name LIKE '%mg/dl%'
                  OR unit_name LIKE '%mg per deciliter%'
                  OR unit_name LIKE '%milligram per deciliter%'
                  OR unit_name LIKE '%milligrams per deciliter%'
              )
          )

          OR

          -- Fasting glucose >=7.0 mmol/L
          (
              lab_type = 'FASTING_GLUCOSE'
              AND value_as_number >= 7.0
              AND (
                  unit_name IN ('mmol/l', 'mmol/liter')
                  OR unit_name LIKE '%millimole per liter%'
                  OR unit_name LIKE '%millimoles per liter%'
              )
          )
      )
),

lab_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS abnormal_lab_dates
    FROM abnormal_labs
    GROUP BY person_id
),

-- 9. Combine patient-level evidence.
phenotype_evidence AS (
    SELECT
        p.person_id,
        COALESCE(d.t2dm_dx_dates, 0) AS dx_dates,
        COALESCE(d.t1dm_dx_count, 0) AS t1dm_count,
        COALESCE(l.abnormal_lab_dates, 0) AS lab_dates,
        CASE WHEN med.person_id IS NOT NULL
             THEN 1 ELSE 0
        END AS has_medication
    FROM public.person p
    LEFT JOIN diagnosis_summary d
      ON d.person_id = p.person_id
    LEFT JOIN lab_summary l
      ON l.person_id = p.person_id
    LEFT JOIN medication_evidence med
      ON med.person_id = p.person_id
)

-- 10. Return unique T2DM patient IDs.
SELECT DISTINCT person_id
FROM phenotype_evidence
WHERE
    dx_dates >= 2

    OR (
        dx_dates >= 1
        AND has_medication = 1
    )

    OR (
        dx_dates >= 1
        AND lab_dates >= 1
    )

    OR (
        lab_dates >= 2
        AND has_medication = 1
        AND t1dm_count = 0
    )
ORDER BY person_id;
