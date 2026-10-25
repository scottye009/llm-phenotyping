
WITH
-- 1. Identify ICD-9-CM and ICD-10-CM T2DM source concepts.
t2_icd AS (
    SELECT concept_id
    FROM public.concept
    WHERE (
        (
            vocabulary_id = 'ICD10CM'
            AND concept_code ~* '^E11(\.|[0-9]|$)'
        )
        OR (
            vocabulary_id = 'ICD9CM'
            AND concept_code ~ '^250\.?[0-9][02]$'
        )
    )
    AND invalid_reason IS NULL
),

-- 2. Resolve ICD concepts to standardized OMOP concepts.
t2_standard AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM t2_icd i
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = i.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
    JOIN public.concept c
      ON c.concept_id = cr.concept_id_2
     AND c.domain_id = 'Condition'
     AND c.standard_concept = 'S'
     AND c.invalid_reason IS NULL

    UNION

    SELECT concept_id
    FROM t2_icd
),

-- 3. Retrieve T2DM diagnoses from standardized or source concepts.
t2_diagnoses AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date AS event_date
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (
        SELECT concept_id FROM t2_standard
    )
    OR co.condition_source_concept_id IN (
        SELECT concept_id FROM t2_icd
    )
),

-- 4. Identify generic and brand antidiabetic medications.
-- Insulin is excluded because it is not T2DM-specific.
drug_seeds AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'RxNorm'
      AND invalid_reason IS NULL
      AND concept_name ~* (
          '(^|[^a-z])(' ||
          'metformin|glucophage|glumetza|fortamet|riomet|' ||
          'glipizide|glucotrol|glyburide|glibenclamide|diabeta|glynase|' ||
          'glimepiride|amaryl|repaglinide|prandin|nateglinide|starlix|' ||
          'pioglitazone|actos|rosiglitazone|avandia|' ||
          'sitagliptin|januvia|janumet|linagliptin|tradjenta|' ||
          'alogliptin|nesina|saxagliptin|onglyza|' ||
          'empagliflozin|jardiance|synjardy|canagliflozin|invokana|' ||
          'dapagliflozin|farxiga|xigduo|ertugliflozin|steglatro|' ||
          'liraglutide|victoza|semaglutide|ozempic|rybelsus|' ||
          'dulaglutide|trulicity|exenatide|byetta|bydureon|' ||
          'lixisenatide|adlyxin|tirzepatide|mounjaro|' ||
          'acarbose|precose|miglitol|glyset|' ||
          ')([^a-z]|$)'
      )
),

-- 5. Expand medication ingredients/products using OMOP hierarchy.
t2_drugs AS (
    SELECT concept_id
    FROM drug_seeds

    UNION

    SELECT DISTINCT ca.descendant_concept_id
    FROM public.concept_ancestor ca
    JOIN drug_seeds ds
      ON ca.ancestor_concept_id = ds.concept_id
),

-- 6. Identify patients with antidiabetic medication exposures.
drug_evidence AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    WHERE de.drug_concept_id IN (
        SELECT concept_id FROM t2_drugs
    )
    OR de.drug_source_concept_id IN (
        SELECT concept_id FROM t2_drugs
    )
),

-- 7. Identify diagnostic laboratory tests using LOINC.
lab_concepts AS (
    SELECT
        concept_id,
        CASE
            WHEN concept_code IN (
                '4548-4', '17856-6', '4549-2'
            ) THEN 'HBA1C'
            WHEN concept_code IN (
                '1558-6'
            ) THEN 'FASTING_GLUCOSE'
        END AS lab_type
    FROM public.concept
    WHERE vocabulary_id = 'LOINC'
      AND concept_code IN (
          '4548-4', '17856-6', '4549-2',
          '1558-6'
      )
      AND invalid_reason IS NULL
),

-- 8. Match LOINC tests to standardized measurement concepts.
lab_mappings AS (
    SELECT concept_id, lab_type
    FROM lab_concepts

    UNION

    SELECT
        cr.concept_id_2,
        lc.lab_type
    FROM lab_concepts lc
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = lc.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
),

-- 9. Extract quantitative laboratory results and their units.
lab_values AS (
    SELECT
        m.person_id,
        m.measurement_date AS event_date,
        lm.lab_type,
        m.value_as_number,
        LOWER(TRIM(COALESCE(m.unit_source_value, '')))
            AS source_unit,
        LOWER(TRIM(COALESCE(u.concept_code, '')))
            AS standard_unit
    FROM public.measurement m
    JOIN lab_mappings lm
      ON m.measurement_concept_id = lm.concept_id
    LEFT JOIN public.concept u
      ON m.unit_concept_id = u.concept_id
    WHERE m.value_as_number IS NOT NULL

    UNION

    SELECT
        m.person_id,
        m.measurement_date AS event_date,
        lc.lab_type,
        m.value_as_number,
        LOWER(TRIM(COALESCE(m.unit_source_value, '')))
            AS source_unit,
        LOWER(TRIM(COALESCE(u.concept_code, '')))
            AS standard_unit
    FROM public.measurement m
    JOIN lab_concepts lc
      ON m.measurement_source_concept_id = lc.concept_id
      OR m.measurement_source_value = (
          SELECT c.concept_code
          FROM public.concept c
          WHERE c.concept_id = lc.concept_id
      )
    LEFT JOIN public.concept u
      ON m.unit_concept_id = u.concept_id
    WHERE m.value_as_number IS NOT NULL
),

-- 10. Apply diagnostic thresholds with explicit unit handling.
abnormal_labs AS (
    SELECT DISTINCT person_id, event_date
    FROM lab_values
    WHERE (
        lab_type = 'HBA1C'
        AND (
            (
                (source_unit = '%' OR standard_unit = '%')
                AND value_as_number >= 6.5
            )
            OR (
                (
                    source_unit IN ('1', 'fraction')
                    OR standard_unit = '1'
                )
                AND value_as_number >= 0.065
            )
        )
    )
    OR (
        lab_type = 'FASTING_GLUCOSE'
        AND (
            (
                (
                    source_unit IN ('mg/dl', 'mg/100ml')
                    OR standard_unit = 'mg/dl'
                )
                AND value_as_number >= 126
            )
            OR (
                (
                    source_unit IN ('mmol/l', 'mmol/liter')
                    OR standard_unit = 'mmol/l'
                )
                AND value_as_number >= 7.0
            )
        )
    )
),

-- 11. Summarize distinct diagnosis dates.
diagnosis_counts AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS diagnosis_days
    FROM t2_diagnoses
    GROUP BY person_id
),

-- 12. Summarize distinct abnormal laboratory dates.
lab_counts AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS abnormal_lab_days
    FROM abnormal_labs
    GROUP BY person_id
),

-- 13. Apply the combined T2DM phenotyping algorithm.
qualified_patients AS (

    -- Criterion A: At least two diagnoses on separate dates.
    SELECT person_id
    FROM diagnosis_counts
    WHERE diagnosis_days >= 2

    UNION

    -- Criterion B: Diagnosis plus antidiabetic medication.
    SELECT dc.person_id
    FROM diagnosis_counts dc
    JOIN drug_evidence de
      ON dc.person_id = de.person_id
    WHERE dc.diagnosis_days >= 1

    UNION

    -- Criterion C: Diagnosis plus abnormal laboratory evidence.
    SELECT dc.person_id
    FROM diagnosis_counts dc
    JOIN lab_counts lc
      ON dc.person_id = lc.person_id
    WHERE dc.diagnosis_days >= 1
      AND lc.abnormal_lab_days >= 1

    UNION

    -- Criterion D: Two abnormal laboratory dates.
    SELECT person_id
    FROM lab_counts
    WHERE abnormal_lab_days >= 2
)

-- 14. Return unique patients satisfying the phenotype.
SELECT DISTINCT person_id
FROM qualified_patients
ORDER BY person_id;
