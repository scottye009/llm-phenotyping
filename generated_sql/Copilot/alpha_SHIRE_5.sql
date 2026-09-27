
/* SHIRE / OMOP-lite rewrite of Copilot/alpha_5.sql
   - Remove concept logic
   - Use source fields
   - Preserve overall phenotype inclusion/exclusion structure and index_date definition
   - Replace observation_period with visit-occurrence window
*/

WITH
op AS (
  SELECT
    person_id,
    MIN(try_cast(visit_start_date AS DATE)) AS op_start,
    MAX(try_cast(COALESCE(visit_end_date, visit_start_date) AS DATE)) AS op_end
  FROM memory.visit_occurrence
  GROUP BY person_id
),

t2dm_dx AS (
  SELECT
    co.person_id,
    try_cast(co.condition_start_date AS DATE) AS event_date
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'E11%'
    OR co.condition_source_value LIKE '250.%0'
    OR co.condition_source_value LIKE '250.%2'
),

t1dm_dx AS (
  SELECT
    co.person_id,
    try_cast(co.condition_start_date AS DATE) AS event_date
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'E10%'
    OR co.condition_source_value LIKE '250.%1'
    OR co.condition_source_value LIKE '250.%3'
),

gdm_secondary_dx AS (
  SELECT
    co.person_id,
    try_cast(co.condition_start_date AS DATE) AS event_date
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'O24%'
    OR co.condition_source_value ILIKE '648.0%'
    OR co.condition_source_value ILIKE '648.8%'
    OR co.condition_source_value ILIKE '249%'
    OR co.condition_source_value ILIKE 'E08%'
    OR co.condition_source_value ILIKE 'E09%'
    OR co.condition_source_value ILIKE 'E13%'
),

antidiabetic_rx AS (
  SELECT
    de.person_id,
    try_cast(COALESCE(de.drug_exposure_start_date, de.drug_exposure_start_datetime) AS DATE) AS event_date,
    de.drug_source_value
  FROM memory.drug_exposure de
  WHERE
    (
      de.drug_source_value ILIKE '%metformin%'
      OR de.drug_source_value ILIKE '%glucophage%'
      OR de.drug_source_value ILIKE '%fortamet%'
      OR de.drug_source_value ILIKE '%glumetza%'
      OR de.drug_source_value ILIKE '%riomet%'
      OR de.drug_source_value ILIKE '%glipizide%'
      OR de.drug_source_value ILIKE '%glucotrol%'
      OR de.drug_source_value ILIKE '%glyburide%'
      OR de.drug_source_value ILIKE '%diabeta%'
      OR de.drug_source_value ILIKE '%micronase%'
      OR de.drug_source_value ILIKE '%glimepiride%'
      OR de.drug_source_value ILIKE '%amaryl%'
      OR de.drug_source_value ILIKE '%sitagliptin%'
      OR de.drug_source_value ILIKE '%januvia%'
      OR de.drug_source_value ILIKE '%saxagliptin%'
      OR de.drug_source_value ILIKE '%onglyza%'
      OR de.drug_source_value ILIKE '%linagliptin%'
      OR de.drug_source_value ILIKE '%tradjenta%'
      OR de.drug_source_value ILIKE '%alogliptin%'
      OR de.drug_source_value ILIKE '%nesina%'
      OR de.drug_source_value ILIKE '%exenatide%'
      OR de.drug_source_value ILIKE '%byetta%'
      OR de.drug_source_value ILIKE '%bydureon%'
      OR de.drug_source_value ILIKE '%liraglutide%'
      OR de.drug_source_value ILIKE '%victoza%'
      OR de.drug_source_value ILIKE '%dulaglutide%'
      OR de.drug_source_value ILIKE '%trulicity%'
      OR de.drug_source_value ILIKE '%semaglutide%'
      OR de.drug_source_value ILIKE '%ozempic%'
      OR de.drug_source_value ILIKE '%rybelsus%'
      OR de.drug_source_value ILIKE '%lixisenatide%'
      OR de.drug_source_value ILIKE '%adlyxin%'
      OR de.drug_source_value ILIKE '%canagliflozin%'
      OR de.drug_source_value ILIKE '%invokana%'
      OR de.drug_source_value ILIKE '%dapagliflozin%'
      OR de.drug_source_value ILIKE '%farxiga%'
      OR de.drug_source_value ILIKE '%empagliflozin%'
      OR de.drug_source_value ILIKE '%jardiance%'
      OR de.drug_source_value ILIKE '%ertugliflozin%'
      OR de.drug_source_value ILIKE '%steglatro%'
      OR de.drug_source_value ILIKE '%pioglitazone%'
      OR de.drug_source_value ILIKE '%actos%'
      OR de.drug_source_value ILIKE '%rosiglitazone%'
      OR de.drug_source_value ILIKE '%avandia%'
      OR de.drug_source_value ILIKE '%insulin%'
    )
),

abnormal_hba1c AS (
  SELECT
    m.person_id,
    try_cast(m.measurement_date AS DATE) AS event_date
  FROM memory.measurement m
  WHERE
    m.value_as_number IS NOT NULL
    AND (m.measurement_source_value ILIKE '%hemoglobin a1c%'
         OR m.measurement_source_value ILIKE '%hba1c%'
         OR m.measurement_source_value ILIKE '%a1c%')
    AND m.value_as_number >= 6.5
),

abnormal_fpg AS (
  SELECT
    m.person_id,
    try_cast(m.measurement_date AS DATE) AS event_date
  FROM memory.measurement m
  WHERE
    m.value_as_number IS NOT NULL
    AND m.measurement_source_value ILIKE '%glucose%'
    AND m.measurement_source_value ILIKE '%fast%'
    AND m.value_as_number >= 126
),

abnormal_ogtt AS (
  SELECT
    m.person_id,
    try_cast(m.measurement_date AS DATE) AS event_date
  FROM memory.measurement m
  WHERE
    m.value_as_number IS NOT NULL
    AND m.measurement_source_value ILIKE '%glucose%'
    AND (
      m.measurement_source_value ILIKE '%tolerance%'
      OR m.measurement_source_value ILIKE '%ogtt%'
      OR m.measurement_source_value ILIKE '%2 hour%'
      OR m.measurement_source_value ILIKE '%2-hour%'
      OR m.measurement_source_value ILIKE '%random%'
    )
    AND m.value_as_number >= 200
),

all_abnormal_labs AS (
  SELECT * FROM abnormal_hba1c
  UNION ALL
  SELECT * FROM abnormal_fpg
  UNION ALL
  SELECT * FROM abnormal_ogtt
),

t2dm_dx_agg AS (
  SELECT
    person_id,
    MIN(event_date) AS first_t2dm_dx_date,
    COUNT(DISTINCT event_date) AS distinct_t2dm_dx_dates
  FROM t2dm_dx
  GROUP BY person_id
),

t1dm_dx_agg AS (
  SELECT
    person_id,
    MIN(event_date) AS first_t1dm_dx_date
  FROM t1dm_dx
  GROUP BY person_id
),

gdm_secondary_agg AS (
  SELECT
    person_id,
    MIN(event_date) AS first_gdm_secondary_date
  FROM gdm_secondary_dx
  GROUP BY person_id
),

antidiabetic_rx_agg AS (
  SELECT
    person_id,
    MIN(event_date) AS first_rx_date,
    COUNT(DISTINCT event_date) AS distinct_rx_dates
  FROM antidiabetic_rx
  GROUP BY person_id
),

abnormal_labs_agg AS (
  SELECT
    person_id,
    MIN(event_date) AS first_abnormal_lab_date,
    COUNT(DISTINCT event_date) AS distinct_abnormal_lab_dates
  FROM all_abnormal_labs
  GROUP BY person_id
),

candidate_cases AS (
  SELECT
    p.person_id,
    t2.first_t2dm_dx_date,
    t2.distinct_t2dm_dx_dates,
    rx.first_rx_date,
    rx.distinct_rx_dates,
    lab.first_abnormal_lab_date,
    lab.distinct_abnormal_lab_dates,
    t1.first_t1dm_dx_date,
    gdm.first_gdm_secondary_date
  FROM memory.person p
  LEFT JOIN t2dm_dx_agg t2 ON p.person_id = t2.person_id
  LEFT JOIN antidiabetic_rx_agg rx ON p.person_id = rx.person_id
  LEFT JOIN abnormal_labs_agg lab ON p.person_id = lab.person_id
  LEFT JOIN t1dm_dx_agg t1 ON p.person_id = t1.person_id
  LEFT JOIN gdm_secondary_agg gdm ON p.person_id = gdm.person_id
),

candidate_with_index AS (
  SELECT
    c.*,
    LEAST(
      COALESCE(first_t2dm_dx_date, DATE '9999-12-31'),
      COALESCE(first_rx_date, DATE '9999-12-31'),
      COALESCE(first_abnormal_lab_date, DATE '9999-12-31')
    ) AS index_date
  FROM candidate_cases c
),

phenotype_logic AS (
  SELECT
    c.person_id,
    c.index_date,

    (
      (COALESCE(c.distinct_t2dm_dx_dates, 0) >= 2)
      OR (COALESCE(c.distinct_t2dm_dx_dates, 0) >= 1 AND COALESCE(c.distinct_rx_dates, 0) >= 1)
      OR (COALESCE(c.distinct_rx_dates, 0) >= 2)
      OR (COALESCE(c.distinct_abnormal_lab_dates, 0) >= 2)
      OR (COALESCE(c.distinct_abnormal_lab_dates, 0) >= 1 AND COALESCE(c.distinct_t2dm_dx_dates, 0) >= 1)
    ) AS inclusion_flag,

    (c.first_t1dm_dx_date IS NOT NULL AND c.first_t1dm_dx_date <= c.index_date) AS has_t1dm_on_or_before_index,
    (c.first_gdm_secondary_date IS NOT NULL AND c.first_gdm_secondary_date <= c.index_date) AS has_gdm_secondary_on_or_before_index
  FROM candidate_with_index c
),

phenotype_with_observation AS (
  SELECT
    pl.person_id,
    pl.index_date,
    pl.inclusion_flag,
    pl.has_t1dm_on_or_before_index,
    pl.has_gdm_secondary_on_or_before_index
  FROM phenotype_logic pl
  JOIN op
    ON pl.person_id = op.person_id
   AND pl.index_date BETWEEN op.op_start AND op.op_end
)

SELECT DISTINCT
  person_id,
  index_date
FROM phenotype_with_observation
WHERE
  inclusion_flag = TRUE
  AND NOT has_t1dm_on_or_before_index
  AND NOT has_gdm_secondary_on_or_before_index
;