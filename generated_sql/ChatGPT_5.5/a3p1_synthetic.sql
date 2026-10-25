-- Type 2 diabetes mellitus phenotype, synthetic OMOP CDM (PostgreSQL)
-- Inclusion: repeated T2DM diagnoses, inpatient T2DM diagnosis,
-- repeated diagnostic laboratory results, or corroborating clinical evidence.
-- Exclusion: documented type 1 diabetes.

WITH
-- 1. Identify ICD-9-CM and ICD-10-CM diabetes concepts.
icd_concepts AS (
    SELECT
        concept_id,
        concept_code,
        CASE
            WHEN vocabulary_id = 'ICD10CM'
                 AND concept_code ~* '^E11(\.|$)' THEN 'T2DM'
            WHEN vocabulary_id = 'ICD9CM'
                 AND concept_code ~ '^250(\.|$)'
                 AND (
                     concept_code = '250'
                     OR concept_code ~ '^250\.[0-9][02]$'
                 ) THEN 'T2DM'
            WHEN vocabulary_id = 'ICD10CM'
                 AND concept_code ~* '^E10(\.|$)' THEN 'T1DM'
            WHEN vocabulary_id = 'ICD9CM'
                 AND concept_code ~ '^250\.[0-9][13]$' THEN 'T1DM'
        END AS diabetes_type
    FROM public.concept
    WHERE vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND invalid_reason IS NULL
),

-- 2. Map ICD concepts to standardized OMOP concepts.
diabetes_concepts AS (
    SELECT DISTINCT
        cr.concept_id_2 AS concept_id,
        ic.diabetes_type
    FROM icd_concepts ic
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = ic.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
     AND CURRENT_DATE BETWEEN cr.valid_start_date AND cr.valid_end_date
    JOIN public.concept std
      ON std.concept_id = cr.concept_id_2
     AND std.standard_concept = 'S'
     AND std.invalid_reason IS NULL
    WHERE ic.diabetes_type IS NOT NULL

    UNION

    SELECT concept_id, diabetes_type
    FROM icd_concepts
    WHERE diabetes_type IS NOT NULL
),

-- 3. Expand standardized diagnosis concepts through OMOP hierarchy.
expanded_diabetes_concepts AS (
    SELECT DISTINCT
        dc.concept_id,
        dc.diabetes_type
    FROM diabetes_concepts dc

    UNION

    SELECT DISTINCT
        ca.descendant_concept_id AS concept_id,
        dc.diabetes_type
    FROM diabetes_concepts dc
    JOIN public.concept_ancestor ca
      ON ca.ancestor_concept_id = dc.concept_id
),

-- 4. Collect all diabetes concept IDs and source codes for filtering.
all_diabetes_concept_ids AS (
    SELECT concept_id FROM expanded_diabetes_concepts
),
all_diabetes_source_codes AS (
    SELECT concept_code FROM icd_concepts WHERE diabetes_type IS NOT NULL
),

-- 5. Identify relevant diagnosis records, including source ICD codes.
diabetes_diagnoses AS (
    SELECT DISTINCT
        co.condition_occurrence_id,
        co.person_id,
        co.condition_start_date,
        co.visit_occurrence_id,
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM expanded_diabetes_concepts edc
                WHERE edc.diabetes_type = 'T1DM'
                  AND edc.concept_id IN (
                      co.condition_concept_id,
                      co.condition_source_concept_id
                  )
            )
            OR EXISTS (
                SELECT 1
                FROM icd_concepts ic
                WHERE ic.diabetes_type = 'T1DM'
                  AND ic.concept_code = co.condition_source_value
            )
            THEN 'T1DM'

            WHEN EXISTS (
                SELECT 1
                FROM expanded_diabetes_concepts edc
                WHERE edc.diabetes_type = 'T2DM'
                  AND edc.concept_id IN (
                      co.condition_concept_id,
                      co.condition_source_concept_id
                  )
            )
            OR EXISTS (
                SELECT 1
                FROM icd_concepts ic
                WHERE ic.diabetes_type = 'T2DM'
                  AND ic.concept_code = co.condition_source_value
            )
            THEN 'T2DM'
        END AS diabetes_type
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (SELECT concept_id FROM all_diabetes_concept_ids)
       OR co.condition_source_concept_id IN (SELECT concept_id FROM all_diabetes_concept_ids)
       OR co.condition_source_value IN (SELECT concept_code FROM all_diabetes_source_codes)
),

-- 6. Count T2DM diagnoses and inpatient encounters.
diagnosis_evidence AS (
    SELECT
        dd.person_id,
        COUNT(DISTINCT dd.condition_occurrence_id)
            FILTER (WHERE dd.diabetes_type = 'T2DM') AS t2dm_dx_count,
        COUNT(DISTINCT dd.condition_start_date)
            FILTER (WHERE dd.diabetes_type = 'T2DM') AS t2dm_dx_dates,
        COUNT(DISTINCT dd.condition_occurrence_id)
            FILTER (
                WHERE dd.diabetes_type = 'T2DM'
                  AND v.visit_concept_id IN (9201, 262)
            ) AS inpatient_t2dm_dx_count,
        COUNT(DISTINCT dd.condition_occurrence_id)
            FILTER (WHERE dd.diabetes_type = 'T1DM') AS t1dm_dx_count
    FROM diabetes_diagnoses dd
    LEFT JOIN public.visit_occurrence v
      ON v.visit_occurrence_id = dd.visit_occurrence_id
    WHERE dd.diabetes_type IS NOT NULL
    GROUP BY dd.person_id
),

-- 7. Identify diabetes-related medication exposures.
-- Generic and brand names are resolved using RxNorm concept names.
diabetes_medications AS (
    SELECT DISTINCT
        de.person_id,
        de.drug_exposure_id,
        de.drug_exposure_start_date
    FROM public.drug_exposure de
    JOIN public.concept c
      ON c.concept_id = de.drug_concept_id
    WHERE c.domain_id = 'Drug'
      AND (
          c.concept_name ~* '\m(metformin|glucophage|glumetza|fortamet|riomet)\M'
          OR c.concept_name ~* '\m(glipizide|glucotrol|glyburide|micronase|glynase|glimepiride|amaryl)\M'
          OR c.concept_name ~* '\m(pioglitazone|actos|rosiglitazone|avandia)\M'
          OR c.concept_name ~* '\m(sitagliptin|januvia|janumet|linagliptin|tradjenta|alogliptin|nesina|saxagliptin|onglyza)\M'
          OR c.concept_name ~* '\m(empagliflozin|jardiance|synjardy|dapagliflozin|farxiga|xigduo|canagliflozin|invokana|ertugliflozin|steglatro)\M'
          OR c.concept_name ~* '\m(semaglutide|ozempic|rybelsus|wegovy|liraglutide|victoza|saxenda|dulaglutide|trulicity|exenatide|byetta|bydureon|tirzepatide|mounjaro|zepbound)\M'
          OR c.concept_name ~* '\m(acarbose|precose|miglitol|glyset|repaglinide|prandin|nateglinide|starlix)\M'
      )
),

medication_evidence AS (
    SELECT
        person_id,
        COUNT(DISTINCT drug_exposure_id) AS diabetes_drug_count
    FROM diabetes_medications
    GROUP BY person_id
),

-- 8. Retrieve HbA1c and plasma glucose laboratory measurements.
-- Identify tests through standard concept names and LOINC codes.
laboratory_measurements AS (
    SELECT
        m.person_id,
        m.measurement_id,
        m.measurement_date,
        m.value_as_number,
        COALESCE(NULLIF(uc.concept_name, ''), m.unit_source_value, '') AS unit_name,
        CASE
            WHEN mc.concept_code IN ('4548-4', '17856-6', '59261-8', '41995-2')
              OR sc.concept_code IN ('4548-4', '17856-6', '59261-8', '41995-2')
              OR m.measurement_source_value IN ('4548-4', '17856-6', '59261-8', '41995-2')
              OR mc.concept_name ILIKE '%hemoglobin a1c%'
              OR mc.concept_name ILIKE '%hemoglobin a1c%'
              OR mc.concept_name ILIKE '%glycated hemoglobin%'
              OR mc.concept_name ILIKE '%hba1c%'
            THEN 'HBA1C'

            WHEN mc.concept_code IN ('1558-6', '14771-0')
              OR sc.concept_code IN ('1558-6', '14771-0')
              OR m.measurement_source_value IN ('1558-6', '14771-0')
              OR mc.concept_name ILIKE '%glucose%fasting%'
            THEN 'FASTING_GLUCOSE'

            WHEN mc.concept_code IN ('2339-0', '2345-7')
              OR sc.concept_code IN ('2339-0', '2345-7')
              OR m.measurement_source_value IN ('2339-0', '2345-7')
            THEN 'GLUCOSE'
        END AS test_type
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

-- 9. Apply diagnostic laboratory thresholds with unit validation.
-- HbA1c >= 6.5%; fasting glucose >= 126 mg/dL (7.0 mmol/L).
-- Random glucose >= 200 mg/dL (11.1 mmol/L) is supportive evidence.
abnormal_labs AS (
    SELECT
        person_id,
        measurement_id,
        measurement_date,
        CASE
            WHEN test_type = 'HBA1C'
                 AND value_as_number >= 6.5
                 AND (
                     unit_name ILIKE '%percent%'
                     OR unit_name IN ('%', '')
                 )
            THEN 'DIAGNOSTIC'

            WHEN test_type = 'FASTING_GLUCOSE'
                 AND (
                     (
                         value_as_number >= 126
                         AND (
                             unit_name ILIKE '%mg/dl%'
                             OR unit_name ILIKE '%mg per deciliter%'
                         )
                     )
                     OR (
                         value_as_number >= 7.0
                         AND unit_name ILIKE '%mmol/l%'
                     )
                 )
            THEN 'DIAGNOSTIC'

            WHEN test_type = 'GLUCOSE'
                 AND (
                     (
                         value_as_number >= 200
                         AND (
                             unit_name ILIKE '%mg/dl%'
                             OR unit_name ILIKE '%mg per deciliter%'
                         )
                     )
                     OR (
                         value_as_number >= 11.1
                         AND unit_name ILIKE '%mmol/l%'
                     )
                 )
            THEN 'SUPPORTIVE'
        END AS evidence_type
    FROM laboratory_measurements
    WHERE test_type IS NOT NULL
),

laboratory_evidence AS (
    SELECT
        person_id,
        COUNT(DISTINCT measurement_date)
            FILTER (WHERE evidence_type = 'DIAGNOSTIC')
            AS diagnostic_lab_dates,
        COUNT(DISTINCT measurement_id)
            FILTER (WHERE evidence_type = 'SUPPORTIVE')
            AS supportive_lab_count
    FROM abnormal_labs
    WHERE evidence_type IS NOT NULL
    GROUP BY person_id
),

-- 10. Combine diagnosis, laboratory, and medication evidence.
phenotype_evidence AS (
    SELECT
        p.person_id,
        COALESCE(d.t2dm_dx_count, 0) AS t2dm_dx_count,
        COALESCE(d.t2dm_dx_dates, 0) AS t2dm_dx_dates,
        COALESCE(d.inpatient_t2dm_dx_count, 0) AS inpatient_t2dm_dx_count,
        COALESCE(d.t1dm_dx_count, 0) AS t1dm_dx_count,
        COALESCE(m.diabetes_drug_count, 0) AS diabetes_drug_count,
        COALESCE(l.diagnostic_lab_dates, 0) AS diagnostic_lab_dates,
        COALESCE(l.supportive_lab_count, 0) AS supportive_lab_count
    FROM public.person p
    LEFT JOIN diagnosis_evidence d ON d.person_id = p.person_id
    LEFT JOIN medication_evidence m ON m.person_id = p.person_id
    LEFT JOIN laboratory_evidence l ON l.person_id = p.person_id
)

-- 11. Final T2DM phenotype: multiple independent evidence pathways.
SELECT DISTINCT person_id
FROM phenotype_evidence
WHERE t1dm_dx_count = 0
  AND (
      -- Two or more T2DM diagnosis dates
      t2dm_dx_dates >= 2

      -- At least one inpatient T2DM diagnosis
      OR inpatient_t2dm_dx_count >= 1

      -- Repeated diagnostic laboratory abnormalities
      OR diagnostic_lab_dates >= 2

      -- T2DM diagnosis supported by diagnostic laboratory result
      OR (t2dm_dx_count >= 1 AND diagnostic_lab_dates >= 1)

      -- T2DM diagnosis supported by diabetes medication
      OR (t2dm_dx_count >= 1 AND diabetes_drug_count >= 1)

      -- Diagnostic laboratory result supported by medication
      OR (diagnostic_lab_dates >= 1 AND diabetes_drug_count >= 1)

      -- T2DM diagnosis supported by high random glucose
      OR (t2dm_dx_count >= 1 AND supportive_lab_count >= 1)
  )
ORDER BY person_id;