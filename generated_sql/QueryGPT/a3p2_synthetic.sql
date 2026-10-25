WITH
-- 1. Identify ICD-9-CM and ICD-10-CM T2DM concepts.
t2dm_icd AS (
    SELECT concept_id, concept_code
    FROM public.concept
    WHERE invalid_reason IS NULL
      AND (
          (
              vocabulary_id = 'ICD10CM'
              AND (
                  concept_code = 'E11'
                  OR concept_code LIKE 'E11.%'
              )
          )
          OR
          (
              vocabulary_id = 'ICD9CM'
              AND concept_code ~ '^250\.?[0-9][02]$'
          )
      )
),

-- 2. Resolve ICD diagnoses to standardized OMOP concepts.
t2dm_mapped AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM t2dm_icd i
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = i.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
     AND CURRENT_DATE BETWEEN
         cr.valid_start_date AND cr.valid_end_date
    JOIN public.concept c
      ON c.concept_id = cr.concept_id_2
     AND c.standard_concept = 'S'
     AND c.domain_id = 'Condition'
     AND c.invalid_reason IS NULL
),

-- 3. Identify standardized SNOMED T2DM concepts.
t2dm_snomed AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'SNOMED'
      AND standard_concept = 'S'
      AND invalid_reason IS NULL
      AND (
          concept_name ILIKE 'Type 2 diabetes mellitus'
          OR concept_name ILIKE 'Diabetes mellitus type 2'
      )
),

-- 4. Expand T2DM concepts through OMOP hierarchy.
t2dm_standard AS (
    SELECT concept_id FROM t2dm_mapped

    UNION

    SELECT ca.descendant_concept_id
    FROM public.concept_ancestor ca
    JOIN t2dm_snomed s
      ON ca.ancestor_concept_id = s.concept_id

    UNION

    SELECT concept_id FROM t2dm_snomed
),

-- 5. Identify patients with qualifying T2DM diagnoses.
t2dm_diagnoses AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date AS event_date
    FROM public.condition_occurrence co

    LEFT JOIN public.concept sc
      ON sc.concept_id = co.condition_source_concept_id

    LEFT JOIN public.concept src_code
      ON src_code.concept_code = co.condition_source_value
     AND src_code.vocabulary_id IN ('ICD9CM', 'ICD10CM')
     AND src_code.invalid_reason IS NULL

    WHERE
        co.condition_concept_id IN (
            SELECT concept_id FROM t2dm_standard
        )
        OR co.condition_source_concept_id IN (
            SELECT concept_id FROM t2dm_icd
        )
        OR sc.concept_id IN (
            SELECT concept_id FROM t2dm_standard
        )
        OR src_code.concept_id IN (
            SELECT concept_id FROM t2dm_icd
        )
),

-- 6. Identify non-insulin antidiabetic ingredients,
-- including common generic and brand drug names.
diabetes_drug_concepts AS (
    SELECT concept_id
    FROM public.concept
    WHERE domain_id = 'Drug'
      AND invalid_reason IS NULL
      AND (
          concept_name ~* '(^|[^a-z])(metformin|glipizide|glyburide|glimepiride|pioglitazone|rosiglitazone|sitagliptin|saxagliptin|linagliptin|alogliptin|empagliflozin|dapagliflozin|canagliflozin|ertugliflozin|semaglutide|liraglutide|dulaglutide|exenatide|tirzepatide|acarbose|miglitol|repaglinide|nateglinide|pramlintide|tolbutamide|chlorpropamide)([^a-z]|$)'
          OR
          concept_name ~* '(^|[^a-z])(Glucophage|Glucotrol|DiaBeta|Amaryl|Actos|Avandia|Januvia|Onglyza|Tradjenta|Nesina|Jardiance|Farxiga|Invokana|Steglatro|Ozempic|Rybelsus|Victoza|Trulicity|Byetta|Bydureon|Mounjaro|Zepbound|Precose|Glyset|Prandin|Starlix|Symlin)([^a-z]|$)'
      )
),

-- 7. Expand drug concepts to descendant formulations.
diabetes_drug_descendants AS (
    SELECT concept_id
    FROM diabetes_drug_concepts

    UNION

    SELECT ca.descendant_concept_id
    FROM public.concept_ancestor ca
    JOIN diabetes_drug_concepts dc
      ON ca.ancestor_concept_id = dc.concept_id
),

-- 8. Identify antidiabetic drug exposures.
diabetes_medications AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    WHERE de.drug_concept_id IN (
        SELECT concept_id
        FROM diabetes_drug_descendants
    )
    OR de.drug_source_concept_id IN (
        SELECT concept_id
        FROM diabetes_drug_descendants
    )
),

-- 9. Identify diabetes-related LOINC laboratory tests.
diabetes_lab_loinc AS (
    SELECT
        concept_id,
        concept_code,
        CASE
            WHEN concept_code IN ('4548-4', '17856-6')
                THEN 'HBA1C'
            WHEN concept_code = '1558-6'
                THEN 'FASTING_GLUCOSE'
            WHEN concept_code IN ('2345-7', '2339-0')
                THEN 'GLUCOSE'
        END AS lab_type
    FROM public.concept
    WHERE vocabulary_id = 'LOINC'
      AND invalid_reason IS NULL
      AND concept_code IN (
          '4548-4',
          '17856-6',
          '1558-6',
          '2345-7',
          '2339-0'
      )
),

-- 10. Map source laboratory concepts to standard measurements.
diabetes_lab_concepts AS (
    SELECT
        concept_id,
        lab_type
    FROM diabetes_lab_loinc

    UNION

    SELECT DISTINCT
        cr.concept_id_2,
        l.lab_type
    FROM diabetes_lab_loinc l
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = l.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
     AND CURRENT_DATE BETWEEN
         cr.valid_start_date AND cr.valid_end_date
),

-- 11. Resolve numeric laboratory measurements and units.
lab_measurements AS (
    SELECT DISTINCT
        m.person_id,
        m.measurement_id,
        m.measurement_date,
        m.value_as_number,
        l.lab_type,
        LOWER(
            TRIM(
                COALESCE(
                    NULLIF(m.unit_source_value, ''),
                    u.concept_code,
                    ''
                )
            )
        ) AS unit_value
    FROM public.measurement m

    JOIN diabetes_lab_concepts l
      ON m.measurement_concept_id = l.concept_id
      OR m.measurement_source_concept_id = l.concept_id
      OR m.measurement_source_value IN (
          SELECT concept_code
          FROM diabetes_lab_loinc
          WHERE lab_type = l.lab_type
      )

    LEFT JOIN public.concept u
      ON u.concept_id = m.unit_concept_id

    WHERE m.value_as_number IS NOT NULL
      AND m.value_as_number >= 0
),

-- 12. Apply clinically relevant laboratory thresholds.
abnormal_diabetes_labs AS (
    SELECT DISTINCT
        person_id,
        measurement_date
    FROM lab_measurements
    WHERE
        (
            -- HbA1c >= 6.5%.
            lab_type = 'HBA1C'
            AND value_as_number >= 6.5
            AND unit_value IN ('%', 'percent')
        )
        OR
        (
            -- Fasting plasma glucose >= 126 mg/dL.
            lab_type = 'FASTING_GLUCOSE'
            AND (
                (
                    unit_value IN ('mg/dl', 'mg/100ml')
                    AND value_as_number >= 126
                )
                OR
                (
                    unit_value IN ('mmol/l', 'mmol/liter')
                    AND value_as_number >= 7.0
                )
            )
        )
        OR
        (
            -- Unspecified glucose >= 200 mg/dL.
            -- Requires corroboration in final phenotype.
            lab_type = 'GLUCOSE'
            AND (
                (
                    unit_value IN ('mg/dl', 'mg/100ml')
                    AND value_as_number >= 200
                )
                OR
                (
                    unit_value IN ('mmol/l', 'mmol/liter')
                    AND value_as_number >= 11.1
                )
            )
        )
),

-- 13. Count diagnoses on distinct dates.
diagnosis_counts AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS diagnosis_days
    FROM t2dm_diagnoses
    GROUP BY person_id
),

-- 14. Count abnormal laboratory results on distinct dates.
lab_counts AS (
    SELECT
        person_id,
        COUNT(DISTINCT measurement_date) AS abnormal_lab_days
    FROM abnormal_diabetes_labs
    GROUP BY person_id
),

-- 15. Identify explicit type 1 or gestational diabetes diagnoses.
other_diabetes_diagnoses AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    LEFT JOIN public.concept c
      ON c.concept_id = co.condition_concept_id
    LEFT JOIN public.concept sc
      ON sc.concept_id = co.condition_source_concept_id
    LEFT JOIN public.concept ic
      ON ic.concept_code = co.condition_source_value
     AND ic.vocabulary_id IN ('ICD9CM', 'ICD10CM')
     AND ic.invalid_reason IS NULL
    WHERE
        c.concept_name ILIKE 'Type 1 diabetes mellitus%'
        OR c.concept_name ILIKE 'Gestational diabetes%'
        OR sc.concept_name ILIKE 'Type 1 diabetes mellitus%'
        OR sc.concept_name ILIKE 'Gestational diabetes%'
        OR EXISTS (
            SELECT 1
            FROM public.concept x
            WHERE x.concept_id IN (
                co.condition_source_concept_id,
                ic.concept_id
            )
              AND (
                  (
                      x.vocabulary_id = 'ICD10CM'
                      AND (
                          x.concept_code = 'E10'
                          OR x.concept_code LIKE 'E10.%'
                          OR x.concept_code = 'O24.4'
                          OR x.concept_code LIKE 'O24.4%'
                      )
                  )
                  OR
                  (
                      x.vocabulary_id = 'ICD9CM'
                      AND (
                          x.concept_code ~ '^250\.?[0-9][13]$'
                          OR x.concept_code LIKE '648.8%'
                      )
                  )
              )
        )
),

-- 16. Combine diagnosis, laboratory and medication evidence.
phenotype_candidates AS (
    SELECT
        p.person_id,
        COALESCE(d.diagnosis_days, 0) AS diagnosis_days,
        COALESCE(l.abnormal_lab_days, 0) AS abnormal_lab_days,
        CASE
            WHEN dm.person_id IS NOT NULL THEN 1
            ELSE 0
        END AS medication_evidence,
        CASE
            WHEN od.person_id IS NOT NULL THEN 1
            ELSE 0
        END AS competing_diabetes_evidence
    FROM public.person p
    LEFT JOIN diagnosis_counts d
      ON d.person_id = p.person_id
    LEFT JOIN lab_counts l
      ON l.person_id = p.person_id
    LEFT JOIN diabetes_medications dm
      ON dm.person_id = p.person_id
    LEFT JOIN other_diabetes_diagnoses od
      ON od.person_id = p.person_id
)

-- 17. Final T2DM phenotype: return distinct patient IDs.
SELECT DISTINCT person_id
FROM phenotype_candidates
WHERE
    -- Two T2DM diagnosis dates.
    diagnosis_days >= 2

    -- One T2DM diagnosis plus corroborating evidence.
    OR (
        diagnosis_days >= 1
        AND (
            abnormal_lab_days >= 1
            OR medication_evidence = 1
        )
    )

    -- Repeated diabetes-range laboratory evidence,
    -- without documented competing diabetes diagnoses.
    OR (
        abnormal_lab_days >= 2
        AND competing_diabetes_evidence = 0
    )
ORDER BY person_id;