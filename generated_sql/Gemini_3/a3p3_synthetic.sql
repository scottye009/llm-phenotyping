-- =============================================================================
-- Phenotype: Type 2 Diabetes Mellitus (T2DM)
-- Database: Synthetic OMOP CDM (PostgreSQL / pgAdmin 4)
-- =============================================================================

WITH t2d_condition_concepts AS (
    -- Standard SNOMED concepts for T2DM and all descendant concepts
    SELECT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    WHERE ca.ancestor_concept_id = 201826 -- Type 2 diabetes mellitus (SNOMED)
    
    UNION
    
    -- Mapped ICD-9-CM and ICD-10-CM diagnosis concepts
    SELECT cr.concept_id_2 AS concept_id
    FROM public.concept c
    JOIN public.concept_relationship cr 
      ON c.concept_id = cr.concept_id_1
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
    WHERE (
        (c.vocabulary_id = 'ICD10CM' AND (c.concept_code ILIKE 'E11%'))
        OR
        (c.vocabulary_id = 'ICD9CM' AND (c.concept_code ~ '^250\.[0-9][02]'))
    )
),

t2d_diagnoses AS (
    -- Criterion 1: Presence of standard or source diagnosis for T2DM
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (SELECT concept_id FROM t2d_condition_concepts)
       OR co.condition_source_concept_id IN (SELECT concept_id FROM t2d_condition_concepts)
       OR co.condition_source_value ~* '^(E11|250\.[0-9][02])'
),

t2d_medication_ingredients AS (
    -- RxNorm ingredients specific to T2DM non-insulin antihyperglycemics
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Drug'
      AND c.concept_class_id = 'Ingredient'
      AND c.standard_concept = 'S'
      AND (
          c.concept_name ILIKE '%metformin%'
          OR c.concept_name ILIKE '%glipizide%'
          OR c.concept_name ILIKE '%glyburide%'
          OR c.concept_name ILIKE '%glimepiride%'
          OR c.concept_name ILIKE '%sitagliptin%'
          OR c.concept_name ILIKE '%saxagliptin%'
          OR c.concept_name ILIKE '%linagliptin%'
          OR c.concept_name ILIKE '%alogliptin%'
          OR c.concept_name ILIKE '%empagliflozin%'
          OR c.concept_name ILIKE '%dapagliflozin%'
          OR c.concept_name ILIKE '%canagliflozin%'
          OR c.concept_name ILIKE '%pioglitazone%'
          OR c.concept_name ILIKE '%rosiglitazone%'
          OR c.concept_name ILIKE '%semaglutide%'
          OR c.concept_name ILIKE '%liraglutide%'
          OR c.concept_name ILIKE '%dulaglutide%'
          OR c.concept_name ILIKE '%exenatide%'
          OR c.concept_name ILIKE '%repaglinide%'
          OR c.concept_name ILIKE '%nateglinide%'
          OR c.concept_name ILIKE '%acarbose%'
      )
),

t2d_medications AS (
    -- Criterion 2: Prescription / exposure to T2DM-specific medications
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN public.concept_ancestor ca 
      ON de.drug_concept_id = ca.descendant_concept_id
    JOIN t2d_medication_ingredients tmi 
      ON ca.ancestor_concept_id = tmi.concept_id
),

t2d_lab_measurements AS (
    -- Criterion 3: Laboratory test evidence (HbA1c >= 6.5% or Fasting/Random Glucose thresholds)
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN public.concept c 
      ON m.measurement_concept_id = c.concept_id
    WHERE m.value_as_number IS NOT NULL
      AND (
          -- HbA1c >= 6.5% (or >= 48 mmol/mol)
          (
              (c.concept_name ILIKE '%hemoglobin a1c%' OR c.concept_name ILIKE '%glycated hemoglobin%' OR m.measurement_source_value ~* '^(4548-4|17856-6)')
              AND (
                  (m.value_as_number >= 6.5 AND (m.unit_source_value ILIKE '% %' OR m.unit_source_value ILIKE '%%' OR m.unit_source_value IS NULL OR m.unit_concept_id IN (8554, 0)))
                  OR (m.value_as_number >= 48 AND (m.unit_source_value ILIKE '%mmol/mol%' OR m.unit_concept_id = 8713))
              )
          )
          -- Fasting Glucose >= 126 mg/dL or Random Glucose >= 200 mg/dL
          OR (
              (c.concept_name ILIKE '%fasting glucose%' OR m.measurement_source_value = '1558-6')
              AND (
                  (m.value_as_number >= 126 AND (m.unit_source_value ILIKE '%mg/dL%' OR m.unit_source_value IS NULL OR m.unit_concept_id IN (8840, 0)))
                  OR (m.value_as_number >= 7.0 AND (m.unit_source_value ILIKE '%mmol/L%' OR m.unit_concept_id = 8753))
              )
          )
          OR (
              (c.concept_name ILIKE '%glucose%' AND c.concept_name NOT ILIKE '%fasting%')
              AND (
                  (m.value_as_number >= 200 AND (m.unit_source_value ILIKE '%mg/dL%' OR m.unit_source_value IS NULL OR m.unit_concept_id IN (8840, 0)))
                  OR (m.value_as_number >= 11.1 AND (m.unit_source_value ILIKE '%mmol/L%' OR m.unit_concept_id = 8753))
              )
          )
      )
)

-- Final Cohort: Union of all distinct patients satisfying any of the criteria
SELECT DISTINCT p.person_id
FROM public.person p
WHERE p.person_id IN (SELECT person_id FROM t2d_diagnoses)
   OR p.person_id IN (SELECT person_id FROM t2d_medications)
   OR p.person_id IN (SELECT person_id FROM t2d_lab_measurements)
ORDER BY p.person_id;