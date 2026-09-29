/* SHIRE/OMOP-lite DuckDB rewrite of QueryGPT/a3.sql
   - Replace concept logic with source_value matching
   - Keep the same inclusion arms and exclusions
   - Output: person_id, index_date
*/

WITH
t2dm_dx AS (
  SELECT
    co.person_id,
    try_cast(co.condition_start_date AS DATE) AS dx_date
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'E11%'
    OR co.condition_source_value LIKE '250.%0'
    OR co.condition_source_value LIKE '250.%2'
),
t1dm_dx AS (
  SELECT
    co.person_id,
    try_cast(co.condition_start_date AS DATE) AS dx_date
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'E10%'
    OR co.condition_source_value LIKE '250.%1'
    OR co.condition_source_value LIKE '250.%3'
),
secondary_dm_dx AS (
  SELECT DISTINCT co.person_id
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'E08%'
    OR co.condition_source_value ILIKE 'E09%'
    OR co.condition_source_value ILIKE 'E13%'
    OR co.condition_source_value ILIKE '249%'
),
gestational_dm_dx AS (
  SELECT DISTINCT co.person_id
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'O24.4%'
    OR co.condition_source_value ILIKE '648.8%'
),

antidiab_rx AS (
  SELECT
    de.person_id,
    try_cast(COALESCE(de.drug_exposure_start_date, de.drug_exposure_start_datetime) AS DATE) AS rx_date
  FROM memory.drug_exposure de
  WHERE
    (
      de.drug_source_value ILIKE '%metformin%'
      OR de.drug_source_value ILIKE '%glipizide%'
      OR de.drug_source_value ILIKE '%glyburide%'
      OR de.drug_source_value ILIKE '%glimepiride%'
      OR de.drug_source_value ILIKE '%repaglinide%'
      OR de.drug_source_value ILIKE '%nateglinide%'
      OR de.drug_source_value ILIKE '%pioglitazone%'
      OR de.drug_source_value ILIKE '%rosiglitazone%'
      OR de.drug_source_value ILIKE '%sitagliptin%'
      OR de.drug_source_value ILIKE '%saxagliptin%'
      OR de.drug_source_value ILIKE '%linagliptin%'
      OR de.drug_source_value ILIKE '%alogliptin%'
      OR de.drug_source_value ILIKE '%exenatide%'
      OR de.drug_source_value ILIKE '%liraglutide%'
      OR de.drug_source_value ILIKE '%semaglutide%'
      OR de.drug_source_value ILIKE '%dulaglutide%'
      OR de.drug_source_value ILIKE '%lixisenatide%'
      OR de.drug_source_value ILIKE '%tirzepatide%'
      OR de.drug_source_value ILIKE '%canagliflozin%'
      OR de.drug_source_value ILIKE '%dapagliflozin%'
      OR de.drug_source_value ILIKE '%empagliflozin%'
      OR de.drug_source_value ILIKE '%ertugliflozin%'
      OR de.drug_source_value ILIKE '%acarbose%'
      OR de.drug_source_value ILIKE '%miglitol%'
      OR de.drug_source_value ILIKE '%glucophage%'
      OR de.drug_source_value ILIKE '%januvia%'
      OR de.drug_source_value ILIKE '%jardiance%'
      OR de.drug_source_value ILIKE '%invokana%'
      OR de.drug_source_value ILIKE '%farxiga%'
      OR de.drug_source_value ILIKE '%ozempic%'
      OR de.drug_source_value ILIKE '%rybelsus%'
      OR de.drug_source_value ILIKE '%trulicity%'
      OR de.drug_source_value ILIKE '%victoza%'
    )
    AND de.drug_source_value NOT ILIKE '%insulin%'
),

lab_evidence AS (
  SELECT person_id, lab_date
  FROM (
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
          AND (
            m.measurement_source_value ILIKE '%tolerance%'
            OR m.measurement_source_value ILIKE '%ogtt%'
            OR m.measurement_source_value ILIKE '%2 hour%'
            OR m.measurement_source_value ILIKE '%2-hour%'
          )
          AND m.value_as_number >= 200
        )
        OR (
          m.measurement_source_value ILIKE '%glucose%'
          AND m.value_as_number >= 200
        )
      )
  ) u
),

/* inclusions */
inc_A_two_dx AS (
  SELECT person_id, MIN(dx_date) AS index_date
  FROM (SELECT DISTINCT person_id, dx_date FROM t2dm_dx) d
  GROUP BY person_id
  HAVING COUNT(*) >= 2
),
inc_B_dx_plus_rx AS (
  SELECT d.person_id, MIN(LEAST(d.dx_date, r.rx_date)) AS index_date
  FROM t2dm_dx d
  JOIN antidiab_rx r
    ON r.person_id = d.person_id
   AND r.rx_date BETWEEN d.dx_date - INTERVAL 365 DAY AND d.dx_date + INTERVAL 365 DAY
  GROUP BY d.person_id
),
inc_C_two_labs AS (
  SELECT person_id, MIN(lab_date) AS index_date
  FROM (SELECT DISTINCT person_id, lab_date FROM lab_evidence) l
  GROUP BY person_id
  HAVING COUNT(*) >= 2
),
inc_D_lab_plus_rx AS (
  SELECT l.person_id, MIN(LEAST(l.lab_date, r.rx_date)) AS index_date
  FROM lab_evidence l
  JOIN antidiab_rx r
    ON r.person_id = l.person_id
   AND r.rx_date BETWEEN l.lab_date - INTERVAL 365 DAY AND l.lab_date + INTERVAL 365 DAY
  GROUP BY l.person_id
),

inclusions AS (
  SELECT person_id, MIN(index_date) AS index_date
  FROM (
    SELECT * FROM inc_A_two_dx
    UNION ALL SELECT * FROM inc_B_dx_plus_rx
    UNION ALL SELECT * FROM inc_C_two_labs
    UNION ALL SELECT * FROM inc_D_lab_plus_rx
  ) x
  GROUP BY person_id
),

/* exclusions */
excl_any AS (
  SELECT DISTINCT person_id
  FROM (
    SELECT person_id FROM t1dm_dx
    UNION ALL SELECT person_id FROM secondary_dm_dx
    UNION ALL SELECT person_id FROM gestational_dm_dx
  ) e
),

/* age >=18 at index */
age_ok AS (
  SELECT i.person_id, i.index_date
  FROM inclusions i
  JOIN memory.person p ON p.person_id = i.person_id
  WHERE (EXTRACT(YEAR FROM i.index_date) - p.year_of_birth) >= 18
)

SELECT a.person_id, a.index_date
FROM age_ok a
LEFT JOIN excl_any e ON e.person_id = a.person_id
WHERE e.person_id IS NULL
ORDER BY a.person_id;