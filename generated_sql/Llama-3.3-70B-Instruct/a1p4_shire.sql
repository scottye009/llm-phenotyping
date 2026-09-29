
/* SHIRE / OMOP-lite rewrite of Llama-3.3-70B-Instruct/alpha_4.sql
   - remove concept/vocabulary joins and incorrect column references (co.concept_id, de.concept_id)
   - preserve intent: (dx OR labs OR meds) EXCEPT (secondary diabetes)
*/

WITH
dx_t2dm AS (
  SELECT DISTINCT co.person_id
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'E11%'
    OR co.condition_source_value IN ('250.00','250.02')
),

labs_t2dm AS (
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
        AND m.value_as_number >= 126
      )
    )
),

meds_dm AS (
  SELECT DISTINCT de.person_id
  FROM memory.drug_exposure de
  WHERE
    de.drug_source_value ILIKE '%metformin%'
    OR de.drug_source_value ILIKE '%glipizide%'
    OR de.drug_source_value ILIKE '%glimepiride%'
    OR de.drug_source_value ILIKE '%pioglitazone%'
    OR de.drug_source_value ILIKE '%sitagliptin%'
    OR de.drug_source_value ILIKE '%empagliflozin%'
    OR de.drug_source_value ILIKE '%insulin%'
    OR de.drug_source_value ILIKE '%novolog%'
    OR de.drug_source_value ILIKE '%humalog%'
    OR de.drug_source_value ILIKE '%lantus%'
    OR de.drug_source_value ILIKE '%levemir%'
),

secondary_dm AS (
  SELECT DISTINCT co.person_id
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'E08%'
    OR co.condition_source_value ILIKE 'E09%'
    OR co.condition_source_value ILIKE 'E13%'
    OR co.condition_source_value ILIKE '249%'
)

SELECT DISTINCT person_id
FROM (
  SELECT person_id FROM dx_t2dm
  UNION
  SELECT person_id FROM labs_t2dm
  UNION
  SELECT person_id FROM meds_dm
) x
WHERE person_id NOT IN (SELECT person_id FROM secondary_dm)
;