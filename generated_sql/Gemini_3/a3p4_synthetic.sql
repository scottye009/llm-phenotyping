-- ============================================================================
-- Phenotype Algorithm: Type 2 Diabetes Mellitus (T2DM)
-- Database: PostgreSQL (OMOP CDM v5.x compatible)
-- Description:
--   Identifies patients with Type 2 Diabetes Mellitus based on:
--   1. Diagnosis: Standard/mapped ICD-9/ICD-10/SNOMED concepts for T2DM
--   2. Medication: Exposure to antidiabetic medications (metformin, sulfonylureas,
--      DPP-4 inhibitors, SGLT2 inhibitors, GLP-1 agonists, TZDs, insulin)
--   3. Laboratory: HbA1c >= 6.5% OR Fasting Blood Glucose >= 126 mg/dL OR 
--      Random Blood Glucose >= 200 mg/dL
-- ============================================================================

WITH t2d_diagnosis_concepts AS (
    -- Identify standard T2DM concept IDs and descendants
    SELECT descendant_concept_id AS concept_id
    FROM public.concept_ancestor
    WHERE ancestor_concept_id = 201820 -- SNOMED / OMOP standard concept for 'Type 2 diabetes mellitus'
    
    UNION
    
    -- Map source ICD-9 and ICD-10 codes to standard concepts
    SELECT cr.concept_id_2 AS concept_id
    FROM public.concept c
    JOIN public.concept_relationship cr 
      ON c.concept_id = cr.concept_id_1 
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
    WHERE (
        (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E11%')
        OR (c.vocabulary_id = 'ICD9CM' AND (c.concept_code LIKE '250.%0' OR c.concept_code LIKE '250.%2'))
    )
),

t2d_condition_patients AS (
    -- Patients meeting condition occurrence criteria
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN t2d_diagnosis_concepts dc 
      ON co.condition_concept_id = dc.concept_id
),

t2d_drug_concepts AS (
    -- Identify antidiabetic drug concepts by ingredient/concept ancestor
    SELECT DISTINCT ca.descendant_concept_id AS drug_concept_id
    FROM public.concept c
    JOIN public.concept_ancestor ca 
      ON c.concept_id = ca.ancestor_concept_id
    WHERE c.domain_id = 'Drug'
      AND c.standard_concept = 'S'
      AND (
          c.concept_name ILIKE '%metformin%'
          OR c.concept_name ILIKE '%glipizide%'
          OR c.concept_name ILIKE '%glyburide%'
          OR c.concept_name ILIKE '%glimepiride%'
          OR c.concept_name ILIKE '%pioglitazone%'
          OR c.concept_name ILIKE '%rosiglitazone%'
          OR c.concept_name ILIKE '%sitagliptin%'
          OR c.concept_name ILIKE '%saxagliptin%'
          OR c.concept_name ILIKE '%linagliptin%'
          OR c.concept_name ILIKE '%alogliptin%'
          OR c.concept_name ILIKE '%empagliflozin%'
          OR c.concept_name ILIKE '%dapagliflozin%'
          OR c.concept_name ILIKE '%canagliflozin%'
          OR c.concept_name ILIKE '%liraglutide%'
          OR c.concept_name ILIKE '%dulaglutide%'
          OR c.concept_name ILIKE '%semaglutide%'
          OR c.concept_name ILIKE '%exenatide%'
          OR c.concept_name ILIKE '%repaglinide%'
          OR c.concept_name ILIKE '%nateglinide%'
          OR c.concept_name ILIKE '%acarbose%'
      )
),

t2d_medication_patients AS (
    -- Patients with antidiabetic drug exposures
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN t2d_drug_concepts dc 
      ON de.drug_concept_id = dc.drug_concept_id
),

t2d_lab_patients AS (
    -- Patients with abnormal laboratory values diagnostic of diabetes
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN public.concept c 
      ON m.measurement_concept_id = c.concept_id
    WHERE m.value_as_number IS NOT NULL
      AND (
          -- HbA1c >= 6.5% (or fraction >= 0.065)
          (
              (c.concept_name ILIKE '%hemoglobin a1c%' OR c.concept_name ILIKE '%glycated hemoglobin%' OR m.measurement_source_value IN ('4548-4', '17856-6', '4549-2'))
              AND (
                  (m.value_as_number >= 6.5 AND m.value_as_number <= 25.0)
                  OR (m.value_as_number >= 0.065 AND m.value_as_number <= 0.25)
              )
          )
          -- Fasting glucose >= 126 mg/dL
          OR (
              (c.concept_name ILIKE '%fasting glucose%' OR m.measurement_source_value IN ('1558-6', '14771-0'))
              AND m.value_as_number >= 126.0
              AND m.value_as_number <= 1000.0
          )
          -- Random / serum / plasma glucose >= 200 mg/dL
          OR (
              (c.concept_name ILIKE '%glucose%' AND c.concept_name ILIKE '%serum%' OR m.measurement_source_value IN ('2345-7', '2339-0'))
              AND m.value_as_number >= 200.0
              AND m.value_as_number <= 1500.0
          )
      )
)

-- Final Cohort: Union of all qualifying criteria
SELECT DISTINCT p.person_id
FROM public.person p
WHERE p.person_id IN (
    SELECT person_id FROM t2d_condition_patients
    UNION
    SELECT person_id FROM t2d_medication_patients
    UNION
    SELECT person_id FROM t2d_lab_patients
)
ORDER BY p.person_id;