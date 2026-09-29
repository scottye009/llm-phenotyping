
/* SHIRE / OMOP-lite rewrite of Llama-3.3-70B-Instruct/alpha_3.sql
   - remove INTO (DuckDB runner typically expects SELECT)
   - remove concept/vocabulary joins
   - preserve structure:
       (dx OR labs OR meds) AND NOT (T1DM dx)
*/

WITH
dx_t2dm AS (
  SELECT DISTINCT co.person_id
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'E11%'
    OR co.condition_source_value LIKE '250.%0'
    OR co.condition_source_value LIKE '250.%2'
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
        AND m.measurement_source_value ILIKE '%fast%'
        AND m.value_as_number >= 126
      )
      OR (
        m.measurement_source_value ILIKE '%glucose%'
        AND (
          m.measurement_source_value ILIKE '%2 hour%'
          OR m.measurement_source_value ILIKE '%2-hour%'
          OR m.measurement_source_value ILIKE '%tolerance%'
          OR m.measurement_source_value ILIKE '%ogtt%'
        )
        AND m.value_as_number >= 200
      )
    )
),

meds_t2dm AS (
  SELECT DISTINCT de.person_id
  FROM memory.drug_exposure de
  WHERE
    de.drug_source_value ILIKE '%metformin%'
    OR de.drug_source_value ILIKE '%glipizide%'
    OR de.drug_source_value ILIKE '%pioglitazone%'
    OR de.drug_source_value ILIKE '%empagliflozin%'
    OR de.drug_source_value ILIKE '%jardiance%'
),

dx_t1dm AS (
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
  p.person_id IN (
    SELECT person_id FROM dx_t2dm
    UNION
    SELECT person_id FROM labs_t2dm
    UNION
    SELECT person_id FROM meds_t2dm
  )
  AND p.person_id NOT IN (SELECT person_id FROM dx_t1dm)
;