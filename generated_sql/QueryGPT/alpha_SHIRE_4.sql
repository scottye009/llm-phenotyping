/* SHIRE/OMOP-lite DuckDB rewrite of QueryGPT/a4.sql
   - Replace all concept mapping and descendants with source_value matching
   - Keep inclusion arms: two dx, dx+rx, two labs, lab+rx
   - Apply exclusions: T1, gestational, secondary
   - Output: person_id, index_date
*/

WITH
adults AS (
  SELECT person_id
  FROM memory.person
  WHERE (EXTRACT(YEAR FROM CURRENT_DATE) - year_of_birth) >= 18
),

dx_t2 AS (
  SELECT
    co.person_id,
    try_cast(co.condition_start_date AS DATE) AS dx_date
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'E11%'
    OR co.condition_source_value LIKE '250.%0'
    OR co.condition_source_value LIKE '250.%2'
),
dx_t1 AS (
  SELECT
    co.person_id,
    try_cast(co.condition_start_date AS DATE) AS dx_date
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'E10%'
    OR co.condition_source_value LIKE '250.%1'
    OR co.condition_source_value LIKE '250.%3'
),
dx_gest AS (
  SELECT
    co.person_id,
    try_cast(co.condition_start_date AS DATE) AS dx_date
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'O24.4%'
    OR co.condition_source_value ILIKE '648.8%'
),
dx_secondary AS (
  SELECT
    co.person_id,
    try_cast(co.condition_start_date AS DATE) AS dx_date
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'E08%'
    OR co.condition_source_value ILIKE 'E09%'
    OR co.condition_source_value ILIKE 'E13%'
    OR co.condition_source_value ILIKE '249%'
),

rx_t2 AS (
  SELECT
    de.person_id,
    try_cast(COALESCE(de.drug_exposure_start_date, de.drug_exposure_start_datetime) AS DATE) AS rx_date
  FROM memory.drug_exposure de
  WHERE
    (
      de.drug_source_value ILIKE '%metformin%' OR de.drug_source_value ILIKE '%glucophage%' OR
      de.drug_source_value ILIKE '%glipizide%' OR de.drug_source_value ILIKE '%glyburide%' OR de.drug_source_value ILIKE '%glimepiride%' OR
      de.drug_source_value ILIKE '%pioglitazone%' OR de.drug_source_value ILIKE '%rosiglitazone%' OR
      de.drug_source_value ILIKE '%sitagliptin%' OR de.drug_source_value ILIKE '%saxagliptin%' OR de.drug_source_value ILIKE '%linagliptin%' OR de.drug_source_value ILIKE '%alogliptin%' OR
      de.drug_source_value ILIKE '%liraglutide%' OR de.drug_source_value ILIKE '%dulaglutide%' OR de.drug_source_value ILIKE '%semaglutide%' OR de.drug_source_value ILIKE '%exenatide%' OR de.drug_source_value ILIKE '%tirzepatide%' OR
      de.drug_source_value ILIKE '%empagliflozin%' OR de.drug_source_value ILIKE '%canagliflozin%' OR de.drug_source_value ILIKE '%dapagliflozin%' OR de.drug_source_value ILIKE '%ertugliflozin%' OR
      de.drug_source_value ILIKE '%januvia%' OR de.drug_source_value ILIKE '%ozempic%' OR de.drug_source_value ILIKE '%rybelsus%' OR
      de.drug_source_value ILIKE '%jardiance%' OR de.drug_source_value ILIKE '%invokana%' OR de.drug_source_value ILIKE '%farxiga%' OR de.drug_source_value ILIKE '%steglatro%'
    )
    AND de.drug_source_value NOT ILIKE '%insulin%'
),

abnl_any AS (
  SELECT
    m.person_id,
    try_cast(m.measurement_date AS DATE) AS lab_date
  FROM memory.measurement m
  WHERE
    m.value_as_number IS NOT NULL
    AND (
      (
        (m.measurement_source_value ILIKE '%hemoglobin a1c%'
         OR m.measurement_source_value ILIKE '%hba1c%'
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
        AND m.value_as_number >= 200
      )
    )
),

/* inclusions */
inc_A_two_dx AS (
  SELECT person_id, MIN(dx_date) AS index_date
  FROM (SELECT DISTINCT person_id, dx_date FROM dx_t2) s
  GROUP BY person_id
  HAVING COUNT(*) >= 2
),
inc_B_dx_plus_rx AS (
  SELECT d.person_id, MIN(LEAST(d.dx_date, r.rx_date)) AS index_date
  FROM dx_t2 d
  JOIN rx_t2 r ON r.person_id = d.person_id
  GROUP BY d.person_id
),
inc_C_two_labs AS (
  SELECT person_id, MIN(lab_date) AS index_date
  FROM (SELECT DISTINCT person_id, lab_date FROM abnl_any) a
  GROUP BY person_id
  HAVING COUNT(*) >= 2
),
inc_D_lab_plus_rx AS (
  SELECT a.person_id, MIN(LEAST(a.lab_date, r.rx_date)) AS index_date
  FROM abnl_any a
  JOIN rx_t2 r ON r.person_id = a.person_id
  GROUP BY a.person_id
),

incl_union AS (
  SELECT * FROM inc_A_two_dx
  UNION ALL SELECT * FROM inc_B_dx_plus_rx
  UNION ALL SELECT * FROM inc_C_two_labs
  UNION ALL SELECT * FROM inc_D_lab_plus_rx
),
incl_by_person AS (
  SELECT person_id, MIN(index_date) AS index_date
  FROM incl_union
  GROUP BY person_id
),

exc_any AS (
  SELECT DISTINCT person_id
  FROM (
    SELECT person_id FROM dx_t1
    UNION ALL SELECT person_id FROM dx_gest
    UNION ALL SELECT person_id FROM dx_secondary
  ) x
)

SELECT i.person_id, i.index_date
FROM incl_by_person i
JOIN adults a ON a.person_id = i.person_id
LEFT JOIN exc_any e ON e.person_id = i.person_id
WHERE e.person_id IS NULL
ORDER BY i.person_id;