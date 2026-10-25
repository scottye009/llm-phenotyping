-- Type 2 diabetes mellitus phenotyping in synthetic OMOP CDM.
-- Inclusion: (1) >=2 T2DM diagnoses on different dates;
-- (2) T2DM diagnosis plus antidiabetic medication;
-- (3) T2DM diagnosis plus diabetic-range laboratory result; or
-- (4) >=2 diabetic-range laboratory results on different dates.
-- Medication alone is insufficient for cohort inclusion.

WITH icd_t2dm AS (
    -- Identify ICD-10-CM E11.* and ICD-9-CM 250.x0 / 250.x2.
    SELECT concept_id
    FROM public.concept
    WHERE (
        (vocabulary_id = 'ICD10CM'
         AND (concept_code = 'E11' OR concept_code LIKE 'E11.%'))
        OR
        (vocabulary_id = 'ICD9CM'
         AND concept_code ~ '^250\.[0-9][02]$')
    )
    AND invalid_reason IS NULL
),

t2dm_concepts AS (
    -- Map ICD source concepts to standard OMOP concepts.
    SELECT concept_id
    FROM icd_t2dm

    UNION

    SELECT cr.concept_id_2
    FROM public.concept_relationship cr
    JOIN icd_t2dm i
      ON cr.concept_id_1 = i.concept_id
    WHERE cr.relationship_id = 'Maps to'
      AND cr.invalid_reason IS NULL
      AND CURRENT_DATE BETWEEN cr.valid_start_date
                           AND cr.valid_end_date

    UNION

    -- Expand mapped standardized concepts through OMOP ancestry.
    SELECT ca.descendant_concept_id
    FROM public.concept_ancestor ca
    JOIN public.concept_relationship cr
      ON ca.ancestor_concept_id = cr.concept_id_2
    JOIN icd_t2dm i
      ON cr.concept_id_1 = i.concept_id
    WHERE cr.relationship_id = 'Maps to'
      AND cr.invalid_reason IS NULL
      AND CURRENT_DATE BETWEEN cr.valid_start_date
                           AND cr.valid_end_date
),

t2dm_diagnoses AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date AS event_date
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (
        SELECT concept_id FROM t2dm_concepts
    )
    OR co.condition_source_concept_id IN (
        SELECT concept_id FROM icd_t2dm
    )
    OR (
        co.condition_source_value ~* '^E11(\.|$)'
        OR co.condition_source_value ~ '^250\.[0-9][02]$'
    )
),

drug_ingredients AS (
    -- Generic ingredients used for T2DM management.
    -- Include major medication classes and their brand formulations.
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id IN ('RxNorm', 'RxNorm Extension')
      AND concept_class_id = 'Ingredient'
      AND (
          concept_name ~* '^(metformin|glipizide|glyburide|glimepiride|gliclazide|repaglinide|nateglinide|pioglitazone|rosiglitazone|sitagliptin|saxagliptin|linagliptin|alogliptin|vildagliptin|canagliflozin|dapagliflozin|empagliflozin|ertugliflozin|bexagliflozin|exenatide|liraglutide|dulaglutide|semaglutide|lixisenatide|tirzepatide|acarbose|miglitol)( |$)'
      )
      AND invalid_reason IS NULL
),

antidiabetic_drugs AS (
    -- Recognize standardized drugs through their ingredients.
    SELECT DISTINCT ds.drug_concept_id
    FROM public.drug_strength ds
    JOIN drug_ingredients di
      ON ds.ingredient_concept_id = di.concept_id

    UNION

    SELECT concept_id
    FROM drug_ingredients

    UNION

    -- Match generic and brand names when ingredient links are incomplete.
    SELECT concept_id
    FROM public.concept
    WHERE domain_id = 'Drug'
      AND (
          concept_name ~* '(metformin|glipizide|glyburide|glimepiride|gliclazide|repaglinide|nateglinide|pioglitazone|rosiglitazone|sitagliptin|saxagliptin|linagliptin|alogliptin|vildagliptin|canagliflozin|dapagliflozin|empagliflozin|ertugliflozin|bexagliflozin|exenatide|liraglutide|dulaglutide|semaglutide|lixisenatide|tirzepatide|acarbose|miglitol)'
          OR
          concept_name ~* '(Glucophage|Glumetza|Fortamet|Glucotrol|DiaBeta|Amaryl|Prandin|Actos|Avandia|Januvia|Onglyza|Tradjenta|Nesina|Invokana|Farxiga|Jardiance|Steglatro|Byetta|Bydureon|Victoza|Trulicity|Ozempic|Rybelsus|Mounjaro|Janumet|Synjardy|Xigduo|Invokamet)'
      )
      AND invalid_reason IS NULL
),

medication_evidence AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    WHERE de.drug_concept_id IN (
        SELECT drug_concept_id FROM antidiabetic_drugs
    )
    OR de.drug_source_concept_id IN (
        SELECT drug_concept_id FROM antidiabetic_drugs
    )
    -- Insulin alone is not used as T2DM-specific evidence.
),

lab_concepts AS (
    -- LOINC-coded HbA1c and fasting plasma glucose.
    SELECT
        concept_id,
        CASE
            WHEN concept_code IN ('4548-4', '17856-6')
                THEN 'HBA1C'
            WHEN concept_code IN ('1558-6', '14771-0')
                THEN 'FASTING_GLUCOSE'
        END AS lab_type
    FROM public.concept
    WHERE vocabulary_id = 'LOINC'
      AND concept_code IN (
          '4548-4', '17856-6',
          '1558-6', '14771-0'
      )
),

diabetic_labs AS (
    SELECT DISTINCT
        m.person_id,
        m.measurement_date AS event_date
    FROM public.measurement m
    LEFT JOIN lab_concepts lc
      ON m.measurement_concept_id = lc.concept_id
    LEFT JOIN public.concept uc
      ON m.unit_concept_id = uc.concept_id
    WHERE m.value_as_number IS NOT NULL
      AND (
          -- HbA1c >=6.5%.
          (
              (
                  lc.lab_type = 'HBA1C'
                  OR m.measurement_source_value IN ('4548-4', '17856-6')
              )
              AND (
                  (
                      m.value_as_number >= 6.5
                      AND (
                          uc.concept_name ILIKE '%percent%'
                          OR uc.concept_code = '%'
                          OR m.unit_source_value IN ('%', 'percent')
                      )
                  )
                  OR
                  (
                      m.value_as_number >= 48
                      AND (
                          uc.concept_name ILIKE '%millimole per mole%'
                          OR uc.concept_code = 'mmol/mol'
                          OR m.unit_source_value = 'mmol/mol'
                      )
                  )
              )
          )

          OR

          -- Fasting plasma glucose >=126 mg/dL or >=7.0 mmol/L.
          (
              (
                  lc.lab_type = 'FASTING_GLUCOSE'
                  OR m.measurement_source_value IN ('1558-6', '14771-0')
              )
              AND (
                  (
                      m.value_as_number >= 126
                      AND (
                          uc.concept_name ILIKE '%milligram per deciliter%'
                          OR uc.concept_code = 'mg/dL'
                          OR m.unit_source_value ILIKE 'mg/dL'
                      )
                  )
                  OR
                  (
                      m.value_as_number >= 7.0
                      AND (
                          uc.concept_name ILIKE '%millimole per liter%'
                          OR uc.concept_code = 'mmol/L'
                          OR m.unit_source_value ILIKE 'mmol/L'
                      )
                  )
              )
          )
      )
),

diagnosis_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS diagnosis_dates
    FROM t2dm_diagnoses
    WHERE event_date IS NOT NULL
    GROUP BY person_id
),

lab_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS abnormal_lab_dates
    FROM diabetic_labs
    WHERE event_date IS NOT NULL
    GROUP BY person_id
),

eligible_patients AS (
    -- Criterion 1: At least two T2DM diagnosis dates.
    SELECT person_id
    FROM diagnosis_summary
    WHERE diagnosis_dates >= 2

    UNION

    -- Criterion 2: T2DM diagnosis plus diabetes medication.
    SELECT d.person_id
    FROM diagnosis_summary d
    JOIN medication_evidence med
      ON d.person_id = med.person_id
    WHERE d.diagnosis_dates >= 1

    UNION

    -- Criterion 3: T2DM diagnosis plus diabetic-range laboratory evidence.
    SELECT d.person_id
    FROM diagnosis_summary d
    JOIN lab_summary l
      ON d.person_id = l.person_id
    WHERE d.diagnosis_dates >= 1
      AND l.abnormal_lab_dates >= 1

    UNION

    -- Criterion 4: Repeated diabetic-range results on different dates.
    SELECT person_id
    FROM lab_summary
    WHERE abnormal_lab_dates >= 2
)

SELECT DISTINCT p.person_id
FROM public.person p
JOIN eligible_patients e
  ON p.person_id = e.person_id
ORDER BY p.person_id;