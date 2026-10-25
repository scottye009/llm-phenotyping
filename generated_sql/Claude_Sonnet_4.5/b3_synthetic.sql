-- T2DM phenotype: synthetic OMOP CDM (PostgreSQL / pgAdmin 4)
-- Case definition:
--   (>=2 distinct T2DM diagnosis dates)
--   OR (>=1 T2DM diagnosis AND (diabetic-range lab OR glucose-lowering drug))
--   AND no T1DM diagnosis

WITH
-- 1. ICD source concepts (ICD-10-CM E11.x; ICD-9-CM 250.x0 / 250.x2, with or without decimal)
icd_t2 AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE (c.vocabulary_id = 'ICD10CM' AND c.concept_code ILIKE 'E11%')
       OR (c.vocabulary_id = 'ICD9CM'  AND c.concept_code ~ '^250\.?[0-9][02]$')
),
-- 2. ICD source concepts for T1DM (exclusion): E10.x; 250.x1 / 250.x3
icd_t1 AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE (c.vocabulary_id = 'ICD10CM' AND c.concept_code ILIKE 'E10%')
       OR (c.vocabulary_id = 'ICD9CM'  AND c.concept_code ~ '^250\.?[0-9][13]$')
),
-- 3. Standard T2DM condition concepts: SNOMED 201826 hierarchy + ICD 'Maps to' targets
t2_concepts AS (
    SELECT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    WHERE ca.ancestor_concept_id = 201826
    UNION
    SELECT cr.concept_id_2
    FROM public.concept_relationship cr
    JOIN icd_t2 i ON i.concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'
      AND cr.invalid_reason IS NULL
),
-- 4. Standard T1DM condition concepts (exclusion)
t1_concepts AS (
    SELECT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    WHERE ca.ancestor_concept_id = 201254
    UNION
    SELECT cr.concept_id_2
    FROM public.concept_relationship cr
    JOIN icd_t1 i ON i.concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'
      AND cr.invalid_reason IS NULL
),
-- 5. T2DM diagnosis events (standard concept or ICD source concept), distinct dates per person
dx_t2 AS (
    SELECT co.person_id,
           COUNT(DISTINCT co.condition_start_date) AS dx_dates
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (SELECT concept_id FROM t2_concepts)
       OR co.condition_source_concept_id IN (SELECT concept_id FROM icd_t2)
    GROUP BY co.person_id
),
-- 6. T1DM diagnosis persons (exclusion)
dx_t1 AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (SELECT concept_id FROM t1_concepts)
       OR co.condition_source_concept_id IN (SELECT concept_id FROM icd_t1)
),
-- 7. Glucose-lowering drugs: match ingredients via drug_strength (RxNorm Ingredient)
t2_ingredients AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id = 'RxNorm'
      AND c.concept_class_id = 'Ingredient'
      AND (
            c.concept_name ~* '^(metformin|glipizide|glyburide|glibenclamide|glimepiride|sitagliptin|linagliptin|saxagliptin|alogliptin|empagliflozin|dapagliflozin|canagliflozin|pioglitazone|semaglutide|liraglutide|dulaglutide|exenatide|repaglinide|nateglinide|insulin)'
          )
),
drug_t2 AS (
    SELECT de.person_id,
           COUNT(DISTINCT de.drug_exposure_start_date) AS drug_dates
    FROM public.drug_exposure de
    JOIN public.drug_strength ds
      ON ds.drug_concept_id = de.drug_concept_id
    JOIN t2_ingredients ti
      ON ti.concept_id = ds.ingredient_concept_id
    GROUP BY de.person_id
),
-- 8. Diabetic-range labs (LOINC; unit-aware)
--    HbA1c >= 6.5 % (or >= 48 mmol/mol); fasting or random glucose >= 126 / 200 mg/dL
lab_t2 AS (
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    WHERE m.value_as_number IS NOT NULL
      AND m.value_as_number > 0
      AND (
            -- HbA1c in percent
            (m.measurement_source_value IN ('4548-4', '17856-6', '41995-2')
             AND m.value_as_number >= 6.5
             AND (m.unit_concept_id = 8554
                  OR m.unit_source_value ILIKE '%\%%'
                  OR m.unit_source_value ILIKE '%percent%'))
         OR
            -- HbA1c in mmol/mol (IFCC)
            (m.measurement_source_value = '59261-8'
             AND m.value_as_number >= 48
             AND (m.unit_source_value ILIKE '%mmol%'
                  OR m.unit_concept_id = 8523))
         OR
            -- Fasting glucose >= 126 mg/dL (convert mmol/L)
            (m.measurement_source_value = '1558-6'
             AND (CASE WHEN m.unit_concept_id = 8753 OR m.unit_source_value ILIKE '%mmol%'
                       THEN m.value_as_number * 18.016
                       ELSE m.value_as_number END) >= 126)
         OR
            -- Random glucose >= 200 mg/dL (convert mmol/L)
            (m.measurement_source_value IN ('2345-7', '2339-0')
             AND (CASE WHEN m.unit_concept_id = 8753 OR m.unit_source_value ILIKE '%mmol%'
                       THEN m.value_as_number * 18.016
                       ELSE m.value_as_number END) >= 200)
          )
),
-- 9. Cohort assembly
t2dm_cohort AS (
    SELECT p.person_id
    FROM public.person p
    LEFT JOIN dx_t2   d  ON d.person_id  = p.person_id
    WHERE COALESCE(d.dx_dates, 0) >= 2
       OR (
            COALESCE(d.dx_dates, 0) >= 1
        AND (
              p.person_id IN (SELECT person_id FROM lab_t2)
           OR p.person_id IN (SELECT person_id FROM drug_t2)
            )
          )
)
-- Final: distinct persons, excluding T1DM evidence
SELECT DISTINCT tc.person_id
FROM t2dm_cohort tc
WHERE tc.person_id NOT IN (SELECT person_id FROM dx_t1)
ORDER BY tc.person_id;