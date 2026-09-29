
/* SHIRE / OMOP-lite rewrite of Llama-3.3-70B-Instruct/alpha_5.sql
   - remove INTO / DDL
   - remove concept joins
   - preserve inclusion: dx OR meds OR abnormal labs (HbA1c / fasting glucose)
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

meds_t2dm AS (
  SELECT DISTINCT de.person_id
  FROM memory.drug_exposure de
  WHERE
    de.drug_source_value ILIKE '%metformin%'
    OR de.drug_source_value ILIKE '%glucophage%'
    OR de.drug_source_value ILIKE '%glyburide%'
    OR de.drug_source_value ILIKE '%diabeta%'
),

labs_abnormal AS (
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
        m.measurement_source_value ILIKE '%fast%'
        AND m.measurement_source_value ILIKE '%glucose%'
        AND m.value_as_number >= 126
      )
    )
)

SELECT DISTINCT p.person_id
FROM memory.person p
WHERE
  p.person_id IN (SELECT person_id FROM dx_t2dm)
  OR p.person_id IN (SELECT person_id FROM meds_t2dm)
  OR p.person_id IN (SELECT person_id FROM labs_abnormal)
;