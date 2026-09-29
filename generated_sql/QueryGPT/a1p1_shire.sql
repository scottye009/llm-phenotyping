/* SHIRE/OMOP-lite DuckDB rewrite of QueryGPT/a1.sql
   - No concept / concept_ancestor / concept_relationship
   - Use memory.* views over CSV
   - Use *_source_value pattern matching
   - Replace observation_period with visit_occurrence-derived window
   - DuckDB-safe age (year diff) and date math (INTERVAL .. DAY)
*/

WITH
/* ----------------------------
   DX sets (source strings)
   ---------------------------- */
t2_dx AS (
  SELECT
    co.person_id,
    try_cast(co.condition_start_date AS DATE) AS dx_date
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'E11%'
    OR co.condition_source_value LIKE '250.%0'
    OR co.condition_source_value LIKE '250.%2'
),
t1_dx AS (
  SELECT
    co.person_id,
    try_cast(co.condition_start_date AS DATE) AS dx_date
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'E10%'
    OR co.condition_source_value LIKE '250.%1'
    OR co.condition_source_value LIKE '250.%3'
),
gestational_dx AS (
  SELECT
    co.person_id,
    try_cast(co.condition_start_date AS DATE) AS dx_date
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'O24%'
    OR co.condition_source_value ILIKE '648.8%'
),
secondary_dx AS (
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

/* ----------------------------
   Labs (source text)
   ---------------------------- */
a1c_pos AS (
  SELECT
    m.person_id,
    try_cast(m.measurement_date AS DATE) AS meas_date
  FROM memory.measurement m
  WHERE
    m.value_as_number IS NOT NULL
    AND (m.measurement_source_value ILIKE '%hemoglobin a1c%'
         OR m.measurement_source_value ILIKE '%hba1c%'
         OR m.measurement_source_value ILIKE '%a1c%')
    AND m.value_as_number >= 6.5
),
fpg_pos AS (
  SELECT
    m.person_id,
    try_cast(m.measurement_date AS DATE) AS meas_date
  FROM memory.measurement m
  WHERE
    m.value_as_number IS NOT NULL
    AND m.measurement_source_value ILIKE '%glucose%'
    AND m.measurement_source_value ILIKE '%fast%'
    AND m.value_as_number >= 126
),
ogtt2h_pos AS (
  SELECT
    m.person_id,
    try_cast(m.measurement_date AS DATE) AS meas_date
  FROM memory.measurement m
  WHERE
    m.value_as_number IS NOT NULL
    AND m.measurement_source_value ILIKE '%glucose%'
    AND (
      m.measurement_source_value ILIKE '%tolerance%'
      OR m.measurement_source_value ILIKE '%ogtt%'
      OR m.measurement_source_value ILIKE '%2 hour%'
      OR m.measurement_source_value ILIKE '%2-hour%'
    )
    AND m.value_as_number >= 200
),

/* require TWO distinct dates for fasting glucose or OGTT */
fpg_pair AS (
  SELECT person_id, MIN(meas_date) AS first_date
  FROM (SELECT DISTINCT person_id, meas_date FROM fpg_pos) x
  GROUP BY person_id
  HAVING COUNT(*) >= 2
),
ogtt_pair AS (
  SELECT person_id, MIN(meas_date) AS first_date
  FROM (SELECT DISTINCT person_id, meas_date FROM ogtt2h_pos) x
  GROUP BY person_id
  HAVING COUNT(*) >= 2
),

/* ----------------------------
   Meds: antihyperglycemics by source string (non-insulin)
   ---------------------------- */
antihyper_rx_hits AS (
  SELECT
    de.person_id,
    try_cast(COALESCE(de.drug_exposure_start_date, de.drug_exposure_start_datetime) AS DATE) AS rx_date
  FROM memory.drug_exposure de
  WHERE
    (
      -- generics
      de.drug_source_value ILIKE '%metformin%'
      OR de.drug_source_value ILIKE '%glimepiride%'
      OR de.drug_source_value ILIKE '%glipizide%'
      OR de.drug_source_value ILIKE '%glyburide%'
      OR de.drug_source_value ILIKE '%pioglitazone%'
      OR de.drug_source_value ILIKE '%rosiglitazone%'
      OR de.drug_source_value ILIKE '%sitagliptin%'
      OR de.drug_source_value ILIKE '%saxagliptin%'
      OR de.drug_source_value ILIKE '%linagliptin%'
      OR de.drug_source_value ILIKE '%alogliptin%'
      OR de.drug_source_value ILIKE '%liraglutide%'
      OR de.drug_source_value ILIKE '%dulaglutide%'
      OR de.drug_source_value ILIKE '%semaglutide%'
      OR de.drug_source_value ILIKE '%exenatide%'
      OR de.drug_source_value ILIKE '%tirzepatide%'
      OR de.drug_source_value ILIKE '%empagliflozin%'
      OR de.drug_source_value ILIKE '%canagliflozin%'
      OR de.drug_source_value ILIKE '%dapagliflozin%'
      OR de.drug_source_value ILIKE '%ertugliflozin%'
      -- brands
      OR de.drug_source_value ILIKE '%glucophage%'
      OR de.drug_source_value ILIKE '%glumetza%'
      OR de.drug_source_value ILIKE '%riomet%'
      OR de.drug_source_value ILIKE '%fortamet%'
      OR de.drug_source_value ILIKE '%amaryl%'
      OR de.drug_source_value ILIKE '%glucotrol%'
      OR de.drug_source_value ILIKE '%glynase%'
      OR de.drug_source_value ILIKE '%actos%'
      OR de.drug_source_value ILIKE '%avandia%'
      OR de.drug_source_value ILIKE '%januvia%'
      OR de.drug_source_value ILIKE '%onglyza%'
      OR de.drug_source_value ILIKE '%tradjenta%'
      OR de.drug_source_value ILIKE '%nesina%'
      OR de.drug_source_value ILIKE '%victoza%'
      OR de.drug_source_value ILIKE '%trulicity%'
      OR de.drug_source_value ILIKE '%ozempic%'
      OR de.drug_source_value ILIKE '%rybelsus%'
      OR de.drug_source_value ILIKE '%byetta%'
      OR de.drug_source_value ILIKE '%bydureon%'
      OR de.drug_source_value ILIKE '%mounjaro%'
      OR de.drug_source_value ILIKE '%jardiance%'
      OR de.drug_source_value ILIKE '%invokana%'
      OR de.drug_source_value ILIKE '%farxiga%'
      OR de.drug_source_value ILIKE '%steglatro%'
    )
    AND de.drug_source_value NOT ILIKE '%insulin%'
),

/* ----------------------------
   Rule A: >=2 T2 dx dates
   (Inpatient sub-rule removed because visit_concept_id needs vocab;
    if you want, we can add a visit_source_value ILIKE '%hospital%' heuristic.)
   ---------------------------- */
ruleA AS (
  SELECT person_id, MIN(dx_date) AS index_date
  FROM (SELECT DISTINCT person_id, dx_date FROM t2_dx) d
  GROUP BY person_id
  HAVING COUNT(*) >= 2
),

/* Rule B: dx + labs */
ruleB AS (
  SELECT person_id, MIN(evidence_date) AS index_date
  FROM (
    SELECT d.person_id, LEAST(d.dx_date, a.meas_date) AS evidence_date
    FROM t2_dx d
    JOIN a1c_pos a ON a.person_id = d.person_id

    UNION ALL
    SELECT d.person_id, LEAST(d.dx_date, f.first_date) AS evidence_date
    FROM t2_dx d
    JOIN fpg_pair f ON f.person_id = d.person_id

    UNION ALL
    SELECT d.person_id, LEAST(d.dx_date, o.first_date) AS evidence_date
    FROM t2_dx d
    JOIN ogtt_pair o ON o.person_id = d.person_id
  ) u
  GROUP BY person_id
),

/* Rule C: dx + meds */
ruleC AS (
  SELECT d.person_id, MIN(LEAST(d.dx_date, r.rx_date)) AS index_date
  FROM t2_dx d
  JOIN antihyper_rx_hits r
    ON r.person_id = d.person_id
  GROUP BY d.person_id
),

base_inclusions AS (
  SELECT person_id, MIN(index_date) AS index_date
  FROM (
    SELECT * FROM ruleA
    UNION ALL
    SELECT * FROM ruleB
    UNION ALL
    SELECT * FROM ruleC
  ) z
  GROUP BY person_id
),

/* exclusions */
t1_predominant AS (
  SELECT x.person_id
  FROM (
    SELECT person_id, COUNT(DISTINCT dx_date) AS n
    FROM t1_dx
    GROUP BY person_id
  ) x
  LEFT JOIN (SELECT DISTINCT person_id FROM t2_dx) t2 USING (person_id)
  WHERE x.n >= 2 AND t2.person_id IS NULL
),
has_gestational AS (
  SELECT DISTINCT person_id FROM gestational_dx
),
has_secondary AS (
  SELECT DISTINCT person_id FROM secondary_dx
),

/* visit-based window replacing observation_period */
op AS (
  SELECT
    person_id,
    MIN(try_cast(visit_start_date AS DATE)) AS op_start,
    MAX(try_cast(COALESCE(visit_end_date, visit_start_date) AS DATE)) AS op_end
  FROM memory.visit_occurrence
  GROUP BY person_id
),

eligible_base AS (
  SELECT b.person_id, b.index_date
  FROM base_inclusions b
  JOIN op
    ON op.person_id = b.person_id
   AND b.index_date BETWEEN op.op_start AND op.op_end
  JOIN memory.person p
    ON p.person_id = b.person_id
  WHERE (EXTRACT(YEAR FROM b.index_date) - p.year_of_birth) >= 18
)

SELECT e.person_id,
       e.index_date
FROM eligible_base e
LEFT JOIN t1_predominant t1 ON t1.person_id = e.person_id
LEFT JOIN has_gestational g ON g.person_id = e.person_id
LEFT JOIN has_secondary s ON s.person_id = e.person_id
WHERE t1.person_id IS NULL
  AND g.person_id IS NULL
  AND s.person_id IS NULL
ORDER BY e.person_id;