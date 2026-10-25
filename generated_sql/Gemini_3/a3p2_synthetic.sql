-- Phenotype Algorithm: Type 2 Diabetes Mellitus (T2DM)
-- Database: PostgreSQL (OMOP CDM v5.x / Synthetic OMOP L3)

WITH t2d_diagnosis AS (
    -- 1. Patients with a standardized T2D diagnosis code or mapped ICD-9/ICD-10 codes
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    WHERE 
        -- Descendants of standard SNOMED concept for 'Type 2 diabetes mellitus' (201826)
        co.condition_concept_id IN (
            SELECT ca.descendant_concept_id
            FROM public.concept_ancestor ca
            WHERE ca.ancestor_concept_id = 201826
        )
        OR co.condition_source_concept_id IN (
            SELECT cr.concept_id_1
            FROM public.concept_relationship cr
            JOIN public.concept_ancestor ca ON cr.concept_id_2 = ca.descendant_concept_id
            WHERE ca.ancestor_concept_id = 201826
              AND cr.relationship_id = 'Maps to'
              AND cr.invalid_reason IS NULL
        )
        -- Fallback to ICD-10 (E11) and ICD-9 (250.x0, 250.x2) source values
        OR co.condition_source_value ~* '^E11'
        OR co.condition_source_value ~* '^250\.[0-9][02]'
),

t2d_medications AS (
    -- 2. Patients prescribed T2D-specific anti-hyperglycemic medications
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN public.concept_ancestor ca ON de.drug_concept_id = ca.descendant_concept_id
    JOIN public.concept c ON ca.ancestor_concept_id = c.concept_id
    WHERE c.concept_class_id = 'Ingredient'
      AND c.standard_concept = 'S'
      AND c.concept_name ILIKE ANY (ARRAY[
          '%metformin%',
          '%glipizide%',
          '%glyburide%',
          '%glimepiride%',
          '%pioglitazone%',
          '%rosiglitazone%',
          '%sitagliptin%',
          '%saxagliptin%',
          '%linagliptin%',
          '%alogliptin%',
          '%empagliflozin%',
          '%dapagliflozin%',
          '%canagliflozin%',
          '%liraglutide%',
          '%dulaglutide%',
          '%semaglutide%',
          '%exenatide%',
          '%repaglinide%',
          '%nateglinide%'
      ])
),

t2d_lab_measurements AS (
    -- 3. Patients with diagnostic laboratory results:
    --    HbA1c >= 6.5% or Fasting Blood Glucose >= 126 mg/dL
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN public.concept c ON m.measurement_concept_id = c.concept_id
    WHERE m.value_as_number IS NOT NULL
      AND (
          -- Hemoglobin A1c threshold (>= 6.5% or >= 48 mmol/mol)
          (
              (c.concept_name ILIKE '%hemoglobin a1c%' OR m.measurement_source_value ILIKE '%4548-4%')
              AND (
                  (m.value_as_number >= 6.5 AND m.value_as_number < 25.0) -- Percent (%)
                  OR (m.value_as_number >= 48.0 AND m.value_as_number <= 200.0) -- mmol/mol (IFCC)
              )
          )
          -- Fasting Glucose threshold (>= 126 mg/dL or >= 7.0 mmol/L)
          OR (
              (c.concept_name ILIKE '%glucose%fasting%' OR c.concept_name ILIKE '%fasting glucose%')
              AND (
                  (m.value_as_number >= 126.0 AND m.value_as_number <= 1000.0) -- mg/dL
                  OR (m.value_as_number >= 7.0 AND m.value_as_number <= 60.0) -- mmol/L
              )
          )
      )
),

combined_cohort AS (
    SELECT person_id FROM t2d_diagnosis
    UNION
    SELECT person_id FROM t2d_medications
    UNION
    SELECT person_id FROM t2d_lab_measurements
)

-- Return distinct person_ids belonging to the target cohort
SELECT DISTINCT p.person_id
FROM public.person p
JOIN combined_cohort c ON p.person_id = c.person_id
ORDER BY p.person_id;