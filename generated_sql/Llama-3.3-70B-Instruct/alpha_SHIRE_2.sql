
/* SHIRE / OMOP-lite rewrite of Llama-3.3-70B-Instruct/alpha_2.sql
   Notes:
   - original mixes OR/AND without parentheses; this rewrite preserves the most likely intent:
       ( (T2DM diagnosis) OR (symptoms AND abnormal labs) ) AND (T2DM meds) AND NOT (T1DM)
   - symptoms concept_name not available; approximate via condition_source_value text search
*/

WITH
t2dm_dx AS (
  SELECT DISTINCT co.person_id
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'E11%'
    OR co.condition_source_value LIKE '250.%0'
    OR co.condition_source_value LIKE '250.%2'
),

symptoms AS (
  SELECT DISTINCT co.person_id
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE '%polyuria%'
    OR co.condition_source_value ILIKE '%polydipsia%'
    OR co.condition_source_value ILIKE '%weight loss%'
),

abnormal_labs AS (
  SELECT DISTINCT m.person_id
  FROM memory.measurement m
  WHERE m.value_as_number IS NOT NULL
    AND (
      (
        (m.measurement_source_value ILIKE '%hba1c%'
         OR m.measurement_source_value ILIKE '%hemoglobin a1c%'
         OR m.measurement_source_value ILIKE '%a1c%')
        AND m.value_as_number >= 6.5
      )
      OR (
        m.measurement_source_value ILIKE '%glucose%'
        AND m.measurement_source_value ILIKE '%fast%'
        AND m.value_as_number >= 126
      )
    )
),

t2dm_meds AS (
  SELECT DISTINCT de.person_id
  FROM memory.drug_exposure de
  WHERE
    de.drug_source_value ILIKE '%metformin%'
    OR de.drug_source_value ILIKE '%glucophage%'
    OR de.drug_source_value ILIKE '%glyburide%'
    OR de.drug_source_value ILIKE '%diabeta%'
    OR de.drug_source_value ILIKE '%repaglinide%'
    OR de.drug_source_value ILIKE '%prandin%'
    OR de.drug_source_value ILIKE '%sulfonylurea%'
    OR de.drug_source_value ILIKE '%meglitinide%'
),

t1dm_exclude AS (
  SELECT DISTINCT co.person_id
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'E10%'
    OR co.condition_source_value LIKE '250.%1'
    OR co.condition_source_value LIKE '250.%3'
)

SELECT DISTINCT p.person_id
FROM memory.person p
WHERE
  (
    p.person_id IN (SELECT person_id FROM t2dm_dx)
    OR (
      p.person_id IN (SELECT person_id FROM symptoms)
      AND p.person_id IN (SELECT person_id FROM abnormal_labs)
    )
  )
  AND p.person_id IN (SELECT person_id FROM t2dm_meds)
  AND p.person_id NOT IN (SELECT person_id FROM t1dm_exclude)
;