-- ============================================================================
-- Phenotype: Type 2 Diabetes Mellitus (T2D)
-- Database Engine: PostgreSQL / pgAdmin 4 (OMOP CDM v5.x / Synthetic OMOP L3)
-- ============================================================================

WITH t2d_conditions AS (
    -- 1. Patients with Type 2 Diabetes diagnoses
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    WHERE 
        -- Standard OMOP SNOMED hierarchy for 'Type 2 diabetes mellitus' (concept_id: 201826)
        co.condition_concept_id IN (
            SELECT ca.descendant_concept_id
            FROM public.concept_ancestor ca
            WHERE ca.ancestor_concept_id = 201826
        )
        -- Fallback to source concepts mapped from ICD-9 / ICD-10
        OR co.condition_source_concept_id IN (
            SELECT c.concept_id
            FROM public.concept c
            WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
              AND (
                  c.concept_code LIKE 'E11%'
                  OR c.concept_code ~ '^250\.[0-9][02]'
              )
        )
        -- Fallback to source value code patterns
        OR co.condition_source_value ~* '^(E11|250\.[0-9][02])'
),

t2d_medications AS (
    -- 2. Patients prescribed T2D-specific antihyperglycemic drugs
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    WHERE de.drug_concept_id IN (
        SELECT ca.descendant_concept_id
        FROM public.concept c
        JOIN public.concept_ancestor ca 
            ON ca.ancestor_concept_id = c.concept_id
        WHERE c.vocabulary_id = 'RxNorm'
          AND c.concept_class_id = 'Ingredient'
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
              OR c.concept_name ILIKE '%semaglutide%'
              OR c.concept_name ILIKE '%dulaglutide%'
              OR c.concept_name ILIKE '%liraglutide%'
              OR c.concept_name ILIKE '%exenatide%'
              OR c.concept_name ILIKE '%repaglinide%'
              OR c.concept_name ILIKE '%nateglinide%'
              OR c.concept_name ILIKE '%acarbose%'
          )
    )
),

t2d_labs AS (
    -- 3. Patients with lab measurements meeting T2D diagnostic thresholds
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    WHERE (
        -- HbA1c >= 6.5%
        (
            m.measurement_concept_id IN (
                SELECT c.concept_id
                FROM public.concept c
                WHERE (c.vocabulary_id = 'LOINC' AND c.concept_code IN ('4548-4', '17856-6', '4549-2', '59261-8'))
                   OR c.concept_name ILIKE '%hemoglobin a1c%'
                   OR c.concept_name ILIKE '%glycated hemoglobin%'
            )
            OR m.measurement_source_value ~* '^(4548-4|17856-6|4549-2|59261-8)'
        )
        AND m.value_as_number >= 6.5
        AND m.value_as_number <= 25.0 -- Upper bound sanity check
    )
    OR (
        -- Fasting / Random Blood Glucose thresholds
        (
            m.measurement_concept_id IN (
                SELECT c.concept_id
                FROM public.concept c
                WHERE (c.vocabulary_id = 'LOINC' AND c.concept_code IN ('1558-6', '1557-8', '2345-7', '2339-0'))
                   OR c.concept_name ILIKE '%glucose%serum%'
                   OR c.concept_name ILIKE '%glucose%plasma%'
                   OR c.concept_name ILIKE '%glucose%blood%'
            )
            OR m.measurement_source_value ~* '^(1558-6|1557-8|2345-7|2339-0)'
        )
        AND (
            -- Fasting glucose >= 126 mg/dL or Casual/Random glucose >= 200 mg/dL
            m.value_as_number >= 200.0
            OR (
                m.value_as_number >= 126.0 
                AND (
                    m.measurement_concept_id IN (
                        SELECT c.concept_id 
                        FROM public.concept c 
                        WHERE c.concept_name ILIKE '%fasting%' OR c.concept_code IN ('1558-6', '1557-8')
                    )
                    OR m.measurement_source_value ILIKE '%fasting%'
                )
            )
        )
        AND m.value_as_number <= 1500.0 -- Upper bound sanity check
    )
)

-- Return distinct cohort of patients meeting any T2D criterion
SELECT DISTINCT p.person_id
FROM public.person p
WHERE p.person_id IN (
    SELECT person_id FROM t2d_conditions
    UNION
    SELECT person_id FROM t2d_medications
    UNION
    SELECT person_id FROM t2d_labs
)
ORDER BY p.person_id;