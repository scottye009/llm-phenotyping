-- ============================================================================
-- Phenotype: Type 2 Diabetes Mellitus (T2DM)
-- Target Engine: PostgreSQL (pgAdmin 4) / OMOP CDM v5.x+
-- Output: Distinct person_id of patients meeting diagnostic criteria
-- ============================================================================

WITH t2d_condition_concepts AS (
    -- Retrieve standard T2DM concepts and descendants (SNOMED 201820: 'Diabetes mellitus type 2')
    SELECT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    WHERE ca.ancestor_concept_id = 201820

    UNION

    -- Include ICD-9-CM and ICD-10-CM codes mapped to standard concepts
    SELECT cr.concept_id_2 AS concept_id
    FROM public.concept c
    JOIN public.concept_relationship cr 
      ON c.concept_id = cr.concept_id_1
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
    WHERE c.vocabulary_id IN ('ICD10CM', 'ICD9CM')
      AND (
          c.concept_code ILIKE 'E11%'
          OR c.concept_code ~ '^250\.[0-9][02]'
      )
),

t2d_medication_concepts AS (
    -- RxNorm ingredients for T2DM medications and their clinical descendants
    -- 1503297: Metformin, 1502809: Glipizide, 1502855: Glyburide, 1547504: Glimepiride
    -- 1530014: Pioglitazone, 1580747: Sitagliptin, 1515249: Empagliflozin, 45774751: Semaglutide
    SELECT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    WHERE ca.ancestor_concept_id IN (
        1503297, -- Metformin
        1502809, -- Glipizide
        1502855, -- Glyburide
        1547504, -- Glimepiride
        1530014, -- Pioglitazone
        1580747, -- Sitagliptin
        1515249, -- Empagliflozin
        45774751 -- Semaglutide
    )
),

t2d_hba1c_concepts AS (
    -- Standard LOINC measurement concepts for HbA1c
    SELECT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    WHERE ca.ancestor_concept_id = 3004410 -- 'Hemoglobin A1c/Hemoglobin.total in Blood'
),

t2d_glucose_concepts AS (
    -- Standard LOINC measurement concepts for Fasting Blood Glucose
    SELECT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    WHERE ca.ancestor_concept_id = 3004297 -- 'Glucose [Mass/volume] in Blood'
),

-- Criterion 1: Diagnosis of T2DM
cohort_conditions AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN t2d_condition_concepts tcc
      ON co.condition_concept_id = tcc.concept_id
),

-- Criterion 2: Exposure to T2DM-specific antidiabetic medication
cohort_medications AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN t2d_medication_concepts tmc
      ON de.drug_concept_id = tmc.concept_id
),

-- Criterion 3: Laboratory evidence of elevated HbA1c (>= 6.5%) or Glucose (>= 126 mg/dL)
cohort_measurements AS (
    -- Elevated HbA1c >= 6.5%
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN t2d_hba1c_concepts thc 
      ON m.measurement_concept_id = thc.concept_id
    WHERE m.value_as_number >= 6.5

    UNION

    -- Elevated Fasting Glucose >= 126 mg/dL
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN t2d_glucose_concepts tgc 
      ON m.measurement_concept_id = tgc.concept_id
    WHERE m.value_as_number >= 126
)

-- Final unified cohort: Union of all distinct patients meeting any criteria
SELECT DISTINCT p.person_id
FROM public.person p
WHERE p.person_id IN (
    SELECT person_id FROM cohort_conditions
    UNION
    SELECT person_id FROM cohort_medications
    UNION
    SELECT person_id FROM cohort_measurements
)
ORDER BY p.person_id;