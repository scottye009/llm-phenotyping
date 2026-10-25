-- Type 2 Diabetes Mellitus (T2DM) Phenotyping
-- Synthetic OMOP CDM | PostgreSQL / pgAdmin 4
--
-- Inclusion criteria (at least one):
--   1. Two T2DM diagnoses on distinct dates.
--   2. One T2DM diagnosis plus an antidiabetic medication.
--   3. One T2DM diagnosis plus an abnormal diabetes laboratory result.
--   4. Two abnormal diabetes laboratory results on distinct dates
--      plus an antidiabetic medication.
--
-- Laboratory thresholds:
--   HbA1c >= 6.5% (48 mmol/mol).
--   Fasting plasma glucose >= 126 mg/dL (7.0 mmol/L).
--
-- Insulin alone is not treated as T2DM-specific medication evidence.
-- Medication and laboratory evidence are insufficient individually.
-- These are operational phenotype rules, not a validated gold standard.

WITH

-- 1. Identify ICD-9-CM and ICD-10-CM T2DM diagnosis concepts.
t2dm_icd AS (
    SELECT concept_id
    FROM public.concept
    WHERE invalid_reason IS NULL
      AND (
          (
              vocabulary_id = 'ICD10CM'
              AND concept_code ~* '^E11(\.|$)'
          )
          OR
          (
              vocabulary_id = 'ICD9CM'
              AND concept_code ~* '^250\.[0-9][02]$'
          )
      )
),

-- 2. Map ICD concepts to standardized OMOP concepts.
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

    UNION

    SELECT concept_id
    FROM public.concept
    WHERE invalid_reason IS NULL
      AND domain_id = 'Condition'
      AND (
          concept_name ILIKE '%type 2 diabetes%'
          OR concept_name ILIKE '%type II diabetes%'
          OR concept_name ILIKE '%non-insulin-dependent diabetes%'
          OR concept_name ILIKE '%noninsulin dependent diabetes%'
      )
),

-- 3. Expand standardized diagnosis concepts through OMOP hierarchy.
t2dm_concepts AS (
    SELECT concept_id
    FROM t2dm_standard

    UNION

    SELECT ca.descendant_concept_id
    FROM public.concept_ancestor ca
    JOIN t2dm_standard s
      ON ca.ancestor_concept_id = s.concept_id
),

-- 4. Retrieve T2DM diagnosis events.
t2dm_diagnoses AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date AS event_date
    FROM public.condition_occurrence co
    LEFT JOIN public.concept src
      ON co.condition_source_concept_id = src.concept_id
    WHERE co.condition_start_date IS NOT NULL
      AND (
          co.condition_concept_id IN (
              SELECT concept_id FROM t2dm_concepts
          )
          OR co.condition_source_concept_id IN (
              SELECT concept_id FROM t2dm_icd
          )
          OR (
              src.vocabulary_id = 'ICD10CM'
              AND src.concept_code ~* '^E11(\.|$)'
          )
          OR (
              src.vocabulary_id = 'ICD9CM'
              AND src.concept_code ~* '^250\.[0-9][02]$'
          )
          OR co.condition_source_value ~* '^E11(\.|$)'
          OR co.condition_source_value ~* '^250\.[0-9][02]$'
      )
),

-- 5. Count distinct dates with T2DM diagnoses.
diagnosis_counts AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS diagnosis_count
    FROM t2dm_diagnoses
    GROUP BY person_id
),

-- 6. Identify non-insulin antidiabetic medications,
-- including generic ingredients and selected brand names.
antidiabetic_drug_concepts AS (
    SELECT concept_id
    FROM public.concept
    WHERE invalid_reason IS NULL
      AND domain_id = 'Drug'
      AND (
          concept_name ~* '(^|[^a-z])(metformin|glucophage|glumetza|fortamet)([^a-z]|$)'
          OR concept_name ~* '(^|[^a-z])(glipizide|glucotrol|glyburide|diabeta|glynase|glimepiride|amaryl)([^a-z]|$)'
          OR concept_name ~* '(^|[^a-z])(pioglitazone|actos|rosiglitazone|avandia)([^a-z]|$)'
          OR concept_name ~* '(^|[^a-z])(sitagliptin|januvia|saxagliptin|onglyza|linagliptin|tradjenta|alogliptin|nesina)([^a-z]|$)'
          OR concept_name ~* '(^|[^a-z])(empagliflozin|jardiance|dapagliflozin|farxiga|canagliflozin|invokana|ertugliflozin|steglatro)([^a-z]|$)'
          OR concept_name ~* '(^|[^a-z])(liraglutide|victoza|semaglutide|ozempic|rybelsus|wegovy|dulaglutide|trulicity|exenatide|byetta|bydureon|tirzepatide|mounjaro|zepbound)([^a-z]|$)'
          OR concept_name ~* '(^|[^a-z])(acarbose|precose|miglitol|glyset|repaglinide|prandin|nateglinide|starlix)([^a-z]|$)'
      )
),

-- 7. Include mapped and descendant drug concepts.
antidiabetic_drugs AS (
    SELECT concept_id
    FROM antidiabetic_drug_concepts

    UNION

    SELECT ca.descendant_concept_id
    FROM public.concept_ancestor ca
    JOIN antidiabetic_drug_concepts d
      ON ca.ancestor_concept_id = d.concept_id

    UNION

    SELECT cr.concept_id_2
    FROM public.concept_relationship cr
    JOIN antidiabetic_drug_concepts d
      ON cr.concept_id_1 = d.concept_id
    WHERE cr.relationship_id = 'Maps to'
      AND cr.invalid_reason IS NULL
),

-- 8. Identify patients with antidiabetic medication exposure.
medication_evidence AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    WHERE de.drug_concept_id IN (
        SELECT concept_id FROM antidiabetic_drugs
    )
    OR de.drug_source_concept_id IN (
        SELECT concept_id FROM antidiabetic_drugs
    )
),

-- 9. Identify HbA1c and fasting glucose measurements
-- through LOINC and OMOP concept mappings.
lab_seed_concepts AS (
    SELECT
        concept_id,
        CASE
            WHEN concept_code IN ('4548-4', '17856-6')
                THEN 'HBA1C'
            WHEN concept_code IN ('1558-6')
                THEN 'FASTING_GLUCOSE'
        END AS lab_type
    FROM public.concept
    WHERE vocabulary_id = 'LOINC'
      AND invalid_reason IS NULL
      AND concept_code IN (
          '4548-4',
          '17856-6',
          '1558-6'
      )
),

lab_concepts AS (
    SELECT concept_id, lab_type
    FROM lab_seed_concepts

    UNION

    SELECT
        cr.concept_id_2,
        l.lab_type
    FROM public.concept_relationship cr
    JOIN lab_seed_concepts l
      ON cr.concept_id_1 = l.concept_id
    WHERE cr.relationship_id = 'Maps to'
      AND cr.invalid_reason IS NULL
),

-- 10. Collect numeric laboratory results with units.
lab_values AS (
    SELECT DISTINCT
        m.person_id,
        m.measurement_date AS event_date,
        lc.lab_type,
        m.value_as_number,
        LOWER(
            COALESCE(
                NULLIF(TRIM(m.unit_source_value), ''),
                u.concept_name,
                ''
            )
        ) AS unit_name
    FROM public.measurement m
    JOIN lab_concepts lc
      ON m.measurement_concept_id = lc.concept_id
      OR m.measurement_source_concept_id = lc.concept_id
    LEFT JOIN public.concept u
      ON m.unit_concept_id = u.concept_id
    WHERE m.value_as_number IS NOT NULL
      AND m.measurement_date IS NOT NULL

    UNION

    SELECT DISTINCT
        m.person_id,
        m.measurement_date,
        l.lab_type,
        m.value_as_number,
        LOWER(
            COALESCE(
                NULLIF(TRIM(m.unit_source_value), ''),
                u.concept_name,
                ''
            )
        )
    FROM public.measurement m
    JOIN lab_seed_concepts l
      ON m.measurement_source_value = (
          SELECT c.concept_code
          FROM public.concept c
          WHERE c.concept_id = l.concept_id
      )
    LEFT JOIN public.concept u
      ON m.unit_concept_id = u.concept_id
    WHERE m.value_as_number IS NOT NULL
      AND m.measurement_date IS NOT NULL
),

-- 11. Apply diabetes-specific laboratory thresholds.
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
                    (
                        unit_name IN ('%', 'percent', 'percentage')
                        OR unit_name LIKE '%percent%'
                    )
                    AND value_as_number >= 6.5
                )
                OR
                (
                    (
                        unit_name LIKE '%mmol/mol%'
                        OR unit_name LIKE '%millimole per mole%'
                    )
                    AND value_as_number >= 48
                )
            )
        )
        OR
        (
            lab_type = 'FASTING_GLUCOSE'
            AND (
                (
                    (
                        unit_name LIKE '%mg/dl%'
                        OR unit_name LIKE '%milligram per deciliter%'
                    )
                    AND value_as_number >= 126
                )
                OR
                (
                    (
                        unit_name LIKE '%mmol/l%'
                        OR unit_name LIKE '%millimole per liter%'
                    )
                    AND value_as_number >= 7.0
                )
            )
        )
),

-- 12. Count distinct dates with abnormal laboratory results.
lab_counts AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS abnormal_lab_count
    FROM abnormal_labs
    GROUP BY person_id
),

-- 13. Combine diagnosis, medication, and laboratory evidence.
phenotype_evidence AS (
    SELECT
        p.person_id,
        COALESCE(d.diagnosis_count, 0) AS diagnosis_count,
        COALESCE(l.abnormal_lab_count, 0) AS abnormal_lab_count,
        CASE
            WHEN med.person_id IS NOT NULL THEN 1
            ELSE 0
        END AS has_antidiabetic_medication
    FROM public.person p
    LEFT JOIN diagnosis_counts d
      ON p.person_id = d.person_id
    LEFT JOIN lab_counts l
      ON p.person_id = l.person_id
    LEFT JOIN medication_evidence med
      ON p.person_id = med.person_id
)

-- 14. Final T2DM phenotype cohort.
SELECT DISTINCT person_id
FROM phenotype_evidence
WHERE
       diagnosis_count >= 2

    OR (
        diagnosis_count >= 1
        AND has_antidiabetic_medication = 1
    )

    OR (
        diagnosis_count >= 1
        AND abnormal_lab_count >= 1
    )

    OR (
        abnormal_lab_count >= 2
        AND has_antidiabetic_medication = 1
    )
ORDER BY person_id;