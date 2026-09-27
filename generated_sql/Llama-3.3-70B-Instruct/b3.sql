WITH type2_diagnosis AS (
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE condition_source_value ILIKE '%diabetes%'
      AND condition_source_value NOT ILIKE '%type 1%'
      AND condition_source_value NOT ILIKE '%gestational%'
      AND condition_source_value NOT ILIKE '%secondary%'
      OR condition_source_value ILIKE '%E11%'
),
type2_lab AS (
    SELECT DISTINCT person_id
    FROM measurement
    WHERE (measurement_source_value ILIKE '%HbA1c%' AND value_as_number > 6.5)
      OR (measurement_source_value ILIKE '%fasting plasma glucose%' AND value_as_number > 126)
),
type2_med AS (
    SELECT DISTINCT person_id
    FROM drug_exposure
    WHERE drug_source_value ILIKE '%metformin%'
      OR drug_source_value ILIKE '%sulfonylurea%'
      OR drug_source_value ILIKE '%pioglitazone%'
      OR drug_source_value ILIKE '%sitagliptin%'
      OR drug_source_value ILIKE '%linagliptin%'
      OR drug_source_value ILIKE '%empagliflozin%'
      OR drug_source_value ILIKE '%canagliflozin%'
),
type1_exclusion AS (
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE condition_source_value ILIKE '%type 1 diabetes%'
      OR condition_source_value ILIKE '%E10%'
),
gestational_exclusion AS (
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE condition_source_value ILIKE '%gestational diabetes%'
      OR condition_source_value ILIKE '%O24%'
)

SELECT DISTINCT person_id
FROM (
    SELECT person_id,
           CASE
               WHEN person_id IN (SELECT person_id FROM type2_diagnosis) THEN 1
               ELSE 0
           END AS has_diagnosis,
           CASE
               WHEN person_id IN (SELECT person_id FROM type2_lab) THEN 1
               ELSE 0
           END AS has_lab,
           CASE
               WHEN person_id IN (SELECT person_id FROM type2_med) THEN 1
               ELSE 0
           END AS has_med,
           CASE
               WHEN person_id IN (SELECT person_id FROM type1_exclusion) THEN 1
               ELSE 0
           END AS has_type1,
           CASE
               WHEN person_id IN (SELECT person_id FROM gestational_exclusion) THEN 1
               ELSE 0
           END AS has_gestational
    FROM person
) AS combined
WHERE (has_diagnosis = 1 OR has_lab = 1 OR has_med = 1)
  AND has_type1 = 0
  AND has_gestational = 0;