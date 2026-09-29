
/* SHIRE / OMOP-lite rewrite of Llama-3.3-70B-Instruct/alpha_1.sql
   Changes:
   - remove concept/vocabulary joins
   - use *_source_value matching
   - preserve logic:
       confirmed_t2d = ( (T2DM dx OR T2DM meds) INTERSECT hyperglycemia )
       exclude: any T1DM dx
       exclude: exclusive insulin use (insulin exposures AND no non-insulin exposures)
*/

WITH
type2_diabetes_diagnoses AS (
  SELECT DISTINCT person_id
  FROM memory.condition_occurrence
  WHERE
    condition_source_value ILIKE 'E11%'
    OR condition_source_value LIKE '250.%0'
    OR condition_source_value LIKE '250.%2'
),

type2_diabetes_medications AS (
  SELECT DISTINCT person_id
  FROM memory.drug_exposure
  WHERE
    (
      drug_source_value ILIKE '%metformin%'
      OR drug_source_value ILIKE '%glipizide%'
      OR drug_source_value ILIKE '%glimepiride%'
      OR drug_source_value ILIKE '%pioglitazone%'
      OR drug_source_value ILIKE '%sitagliptin%'
      OR drug_source_value ILIKE '%januvia%'
      OR drug_source_value ILIKE '%metformin hydrochloride%'
      OR drug_source_value ILIKE '%glipizide%extended%'
    )
    AND drug_source_value NOT ILIKE '%insulin%'
),

hyperglycemia AS (
  SELECT DISTINCT person_id
  FROM memory.measurement
  WHERE value_as_number IS NOT NULL
    AND (
      (
        (measurement_source_value ILIKE '%hemoglobin a1c%'
         OR measurement_source_value ILIKE '%hba1c%'
         OR measurement_source_value ILIKE '%a1c%')
        AND value_as_number >= 6.5
      )
      OR (
        measurement_source_value ILIKE '%glucose%'
        AND measurement_source_value ILIKE '%fast%'
        AND value_as_number >= 126
      )
      OR (
        measurement_source_value ILIKE '%glucose%'
        AND (
          measurement_source_value ILIKE '%2 hour%'
          OR measurement_source_value ILIKE '%2-hour%'
          OR measurement_source_value ILIKE '%tolerance%'
          OR measurement_source_value ILIKE '%ogtt%'
        )
        AND value_as_number >= 200
      )
    )
),

type1_diabetes_exclusion AS (
  SELECT DISTINCT person_id
  FROM memory.condition_occurrence
  WHERE
    condition_source_value ILIKE 'E10%'
    OR condition_source_value LIKE '250.%1'
    OR condition_source_value LIKE '250.%3'
),

exclusive_insulin_use AS (
  SELECT DISTINCT i.person_id
  FROM (
    SELECT DISTINCT person_id
    FROM memory.drug_exposure
    WHERE drug_source_value ILIKE '%insulin%'
  ) i
  WHERE NOT EXISTS (
    SELECT 1
    FROM memory.drug_exposure de2
    WHERE de2.person_id = i.person_id
      AND de2.drug_source_value NOT ILIKE '%insulin%'
  )
)

SELECT DISTINCT person_id
FROM (
  (
    SELECT person_id FROM type2_diabetes_diagnoses
    UNION
    SELECT person_id FROM type2_diabetes_medications
  )
  INTERSECT
  SELECT person_id FROM hyperglycemia
) AS confirmed_t2d
WHERE person_id NOT IN (SELECT person_id FROM type1_diabetes_exclusion)
  AND person_id NOT IN (SELECT person_id FROM exclusive_insulin_use)
;