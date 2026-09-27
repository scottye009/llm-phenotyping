-- ============================================================================
-- minimal performance/debug changes made
-- ============================================================================
-- 1. kept the same phenotype intent:
--      T2DM diagnosis OR abnormal diabetes lab OR T2DM medication
--      minus type 1 diabetes
--      minus exclusive insulin use
--
-- 2. replaced repeated p.person_id IN (...) subqueries with CTEs and UNION.
--    This avoids repeatedly checking each person against large subqueries.
--
-- 3. replaced NOT IN exclusions with LEFT JOIN ... IS NULL.
--    This is usually faster and avoids NULL-related NOT IN behavior.
--
-- 4. rewrote exclusive insulin use as grouped person-level flags:
--      has_insulin = true
--      has_non_insulin = false
--    This preserves the same exclusion intent but avoids nested NOT IN over drug_exposure.
--
-- 5. no phenotype criteria were intentionally changed.
-- ============================================================================

WITH diagnosis_people AS (
  SELECT DISTINCT co.person_id
  FROM public.condition_occurrence co
  JOIN public.concept c 
    ON co.condition_concept_id = c.concept_id
  WHERE (
    c.vocabulary_id = 'ICD9CM'
    AND c.concept_code LIKE '250.%'
    AND c.concept_code NOT LIKE '250.__1'
    AND c.concept_code NOT LIKE '250.__3'
  )
  OR (
    c.vocabulary_id = 'ICD10CM'
    AND (
      c.concept_code = 'E11'
      OR c.concept_code LIKE 'E11.%'
    )
  )
),

lab_people AS (
  SELECT DISTINCT m.person_id
  FROM public.measurement m
  JOIN public.concept c 
    ON m.measurement_concept_id = c.concept_id
  WHERE (
    LOWER(c.concept_name) LIKE '%a1c%'
    AND m.value_as_number > 6.5
  )
  OR (
    LOWER(c.concept_name) LIKE '%fasting glucose%'
    AND m.value_as_number > 126
  )
  OR (
    (
      LOWER(c.concept_name) LIKE '%2-hour plasma glucose%'
      OR LOWER(c.concept_name) LIKE '%2 hour plasma glucose%'
      OR LOWER(c.concept_name) LIKE '%2-hour%'
      OR LOWER(c.concept_name) LIKE '%2 hour%'
    )
    AND m.value_as_number > 200
  )
),

medication_people AS (
  SELECT DISTINCT de.person_id
  FROM public.drug_exposure de
  JOIN public.concept c 
    ON de.drug_concept_id = c.concept_id
  WHERE LOWER(c.concept_name) LIKE '%metformin%'
     OR LOWER(c.concept_name) LIKE '%glipizide%'
     OR LOWER(c.concept_name) LIKE '%glimepiride%'
     OR LOWER(c.concept_name) LIKE '%pioglitazone%'
     OR LOWER(c.concept_name) LIKE '%sitagliptin%'
     OR LOWER(c.concept_name) LIKE '%metformin hydrochloride%'
     OR LOWER(c.concept_name) LIKE '%glipizide extended release%'
     OR LOWER(c.concept_name) LIKE '%januvia%'
),

included_people AS (
  SELECT person_id FROM diagnosis_people
  UNION
  SELECT person_id FROM lab_people
  UNION
  SELECT person_id FROM medication_people
),

type1_exclusion AS (
  SELECT DISTINCT co.person_id
  FROM public.condition_occurrence co
  JOIN public.concept c 
    ON co.condition_concept_id = c.concept_id
  WHERE (
    c.vocabulary_id = 'ICD9CM'
    AND (
      c.concept_code LIKE '250.__1'
      OR c.concept_code LIKE '250.__3'
    )
  )
  OR (
    c.vocabulary_id = 'ICD10CM'
    AND (
      c.concept_code = 'E10'
      OR c.concept_code LIKE 'E10.%'
    )
  )
),

drug_flags AS (
  SELECT
    de.person_id,
    BOOL_OR(LOWER(c.concept_name) LIKE '%insulin%') AS has_insulin,
    BOOL_OR(LOWER(c.concept_name) NOT LIKE '%insulin%') AS has_non_insulin
  FROM public.drug_exposure de
  JOIN public.concept c 
    ON de.drug_concept_id = c.concept_id
  GROUP BY de.person_id
),

exclusive_insulin_exclusion AS (
  SELECT person_id
  FROM drug_flags
  WHERE has_insulin = TRUE
    AND has_non_insulin = FALSE
)

SELECT DISTINCT p.person_id
FROM included_people ip
JOIN public.person p
  ON p.person_id = ip.person_id
LEFT JOIN type1_exclusion t1
  ON p.person_id = t1.person_id
LEFT JOIN exclusive_insulin_exclusion ei
  ON p.person_id = ei.person_id
WHERE t1.person_id IS NULL
  AND ei.person_id IS NULL;