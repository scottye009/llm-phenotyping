WITH
/* =========================================================
   Evidence arms (same 4 arms as your original, UNION ALL)
   ========================================================= */
z_raw AS (

  /* --- Arm 1: T2DM diagnosis evidence: ≥2 dx dates --- */
  SELECT d2.person_id, MIN(d2.dx_date) AS index_date
  FROM (
    SELECT DISTINCT
      co.person_id,
      try_cast(co.condition_start_date AS DATE) AS dx_date
    FROM memory.condition_occurrence co
    WHERE
      co.condition_source_value ILIKE 'E11%'
      OR co.condition_source_value IN (
        '250.00','250.02','250.10','250.12','250.20','250.22',
        '250.30','250.32','250.40','250.42','250.50','250.52',
        '250.60','250.62','250.70','250.72','250.80','250.82',
        '250.90','250.92'
      )
  ) d2
  GROUP BY d2.person_id
  HAVING COUNT(*) >= 2

  UNION ALL

  /* --- Arm 2: T2DM diagnosis + non-insulin drug within ±365d --- */
  SELECT d.person_id, MIN(LEAST(d.dx_date, rx.rx_date)) AS index_date
  FROM (
    SELECT DISTINCT
      co.person_id,
      try_cast(co.condition_start_date AS DATE) AS dx_date
    FROM memory.condition_occurrence co
    WHERE
      co.condition_source_value ILIKE 'E11%'
      OR co.condition_source_value IN (
        '250.00','250.02','250.10','250.12','250.20','250.22',
        '250.30','250.32','250.40','250.42','250.50','250.52',
        '250.60','250.62','250.70','250.72','250.80','250.82',
        '250.90','250.92'
      )
  ) d
  JOIN (
    /* Non-insulin antihyperglycemics by source text (no RxNorm/ancestors in OMOP-lite) */
    SELECT
      de.person_id,
      try_cast(COALESCE(de.drug_exposure_start_date, de.drug_exposure_start_datetime) AS DATE) AS rx_date
    FROM memory.drug_exposure de
    WHERE
      (
        -- generics
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
        -- brands
        OR de.drug_source_value ILIKE '%glucophage%'
        OR de.drug_source_value ILIKE '%glumetza%'
        OR de.drug_source_value ILIKE '%riomet%'
        OR de.drug_source_value ILIKE '%fortamet%'
        OR de.drug_source_value ILIKE '%glucotrol%'
        OR de.drug_source_value ILIKE '%diabeta%'
        OR de.drug_source_value ILIKE '%micronase%'
        OR de.drug_source_value ILIKE '%glynase%'
        OR de.drug_source_value ILIKE '%amaryl%'
        OR de.drug_source_value ILIKE '%actos%'
        OR de.drug_source_value ILIKE '%avandia%'
        OR de.drug_source_value ILIKE '%januvia%'
        OR de.drug_source_value ILIKE '%onglyza%'
        OR de.drug_source_value ILIKE '%tradjenta%'
        OR de.drug_source_value ILIKE '%nesina%'
        OR de.drug_source_value ILIKE '%byetta%'
        OR de.drug_source_value ILIKE '%bydureon%'
        OR de.drug_source_value ILIKE '%victoza%'
        OR de.drug_source_value ILIKE '%ozempic%'
        OR de.drug_source_value ILIKE '%rybelsus%'
        OR de.drug_source_value ILIKE '%trulicity%'
        OR de.drug_source_value ILIKE '%adlyxin%'
        OR de.drug_source_value ILIKE '%mounjaro%'
        OR de.drug_source_value ILIKE '%invokana%'
        OR de.drug_source_value ILIKE '%farxiga%'
        OR de.drug_source_value ILIKE '%jardiance%'
        OR de.drug_source_value ILIKE '%steglatro%'
      )
      AND de.drug_source_value NOT ILIKE '%insulin%'
  ) rx
    ON rx.person_id = d.person_id
   AND rx.rx_date BETWEEN d.dx_date - INTERVAL 365 DAY AND d.dx_date + INTERVAL 365 DAY
  GROUP BY d.person_id

  UNION ALL

  /* --- Arm 3: Labs: ≥2 positive labs on distinct dates --- */
  SELECT l.person_id, MIN(l.lab_date) AS index_date
  FROM (
    SELECT
      m.person_id,
      try_cast(m.measurement_date AS DATE) AS lab_date
    FROM memory.measurement m
    WHERE
      m.value_as_number IS NOT NULL
      AND (
        (
          (
            m.measurement_source_value ILIKE '%hemoglobin a1c%'
            OR m.measurement_source_value ILIKE '%hba1c%'
            OR m.measurement_source_value ILIKE '%a1c%'
          )
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
            OR m.measurement_source_value ILIKE '%2 hour%'
            OR m.measurement_source_value ILIKE '%2-hour%'
            OR m.measurement_source_value ILIKE '%ogtt%'
          )
          AND m.value_as_number >= 200
        )
        OR (
          m.measurement_source_value ILIKE '%glucose%'
          AND m.measurement_source_value NOT ILIKE '%fast%'
          AND m.measurement_source_value NOT ILIKE '%tolerance%'
          AND m.measurement_source_value NOT ILIKE '%2 hour%'
          AND m.measurement_source_value NOT ILIKE '%2-hour%'
          AND m.value_as_number >= 200
        )
      )
  ) l
  GROUP BY l.person_id
  HAVING COUNT(DISTINCT l.lab_date) >= 2

  UNION ALL

  /* --- Arm 4: Labs + non-insulin drug within ±365d --- */
  SELECT l.person_id, MIN(LEAST(l.lab_date, rx.rx_date)) AS index_date
  FROM (
    SELECT
      m.person_id,
      try_cast(m.measurement_date AS DATE) AS lab_date
    FROM memory.measurement m
    WHERE
      m.value_as_number IS NOT NULL
      AND (
        (
          (
            m.measurement_source_value ILIKE '%hemoglobin a1c%'
            OR m.measurement_source_value ILIKE '%hba1c%'
            OR m.measurement_source_value ILIKE '%a1c%'
          )
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
            OR m.measurement_source_value ILIKE '%2 hour%'
            OR m.measurement_source_value ILIKE '%2-hour%'
            OR m.measurement_source_value ILIKE '%ogtt%'
          )
          AND m.value_as_number >= 200
        )
        OR (
          m.measurement_source_value ILIKE '%glucose%'
          AND m.measurement_source_value NOT ILIKE '%fast%'
          AND m.measurement_source_value NOT ILIKE '%tolerance%'
          AND m.measurement_source_value NOT ILIKE '%2 hour%'
          AND m.measurement_source_value NOT ILIKE '%2-hour%'
          AND m.value_as_number >= 200
        )
      )
  ) l
  JOIN (
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
        OR de.drug_source_value ILIKE '%glumetza%'
        OR de.drug_source_value ILIKE '%riomet%'
        OR de.drug_source_value ILIKE '%fortamet%'
        OR de.drug_source_value ILIKE '%glucotrol%'
        OR de.drug_source_value ILIKE '%diabeta%'
        OR de.drug_source_value ILIKE '%micronase%'
        OR de.drug_source_value ILIKE '%glynase%'
        OR de.drug_source_value ILIKE '%amaryl%'
        OR de.drug_source_value ILIKE '%actos%'
        OR de.drug_source_value ILIKE '%avandia%'
        OR de.drug_source_value ILIKE '%januvia%'
        OR de.drug_source_value ILIKE '%onglyza%'
        OR de.drug_source_value ILIKE '%tradjenta%'
        OR de.drug_source_value ILIKE '%nesina%'
        OR de.drug_source_value ILIKE '%byetta%'
        OR de.drug_source_value ILIKE '%bydureon%'
        OR de.drug_source_value ILIKE '%victoza%'
        OR de.drug_source_value ILIKE '%ozempic%'
        OR de.drug_source_value ILIKE '%rybelsus%'
        OR de.drug_source_value ILIKE '%trulicity%'
        OR de.drug_source_value ILIKE '%adlyxin%'
        OR de.drug_source_value ILIKE '%mounjaro%'
        OR de.drug_source_value ILIKE '%invokana%'
        OR de.drug_source_value ILIKE '%farxiga%'
        OR de.drug_source_value ILIKE '%jardiance%'
        OR de.drug_source_value ILIKE '%steglatro%'
      )
      AND de.drug_source_value NOT ILIKE '%insulin%'
  ) rx
    ON rx.person_id = l.person_id
   AND rx.rx_date BETWEEN l.lab_date - INTERVAL 365 DAY AND l.lab_date + INTERVAL 365 DAY
  GROUP BY l.person_id
),

/* Per-person earliest index date (same meaning as outer MIN in your original) */
z AS (
  SELECT person_id, MIN(index_date) AS index_date
  FROM z_raw
  GROUP BY person_id
),

/* Visit-based observation window replacement for observation_period */
op AS (
  SELECT
    person_id,
    MIN(try_cast(visit_start_date AS DATE)) AS op_start,
    MAX(try_cast(COALESCE(visit_end_date, visit_start_date) AS DATE)) AS op_end
  FROM memory.visit_occurrence
  GROUP BY person_id
)

SELECT
  z.person_id,
  z.index_date
FROM z
JOIN memory.person p
  ON p.person_id = z.person_id
JOIN op
  ON op.person_id = z.person_id
 AND z.index_date BETWEEN op.op_start AND op.op_end
LEFT JOIN (
  /* Any Type 1 diabetes ICD source code on/before index */
  SELECT DISTINCT
    co.person_id,
    try_cast(co.condition_start_date AS DATE) AS t1_date
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'E10%'
    OR co.condition_source_value IN (
      '250.01','250.03','250.11','250.13','250.21','250.23',
      '250.31','250.33','250.41','250.43','250.51','250.53',
      '250.61','250.63','250.71','250.73','250.81','250.83',
      '250.91','250.93'
    )
) t1
  ON t1.person_id = z.person_id
 AND t1.t1_date <= z.index_date
LEFT JOIN (
  /* Any gestational diabetes ICD source code on/before index */
  SELECT DISTINCT
    co.person_id,
    try_cast(co.condition_start_date AS DATE) AS gdm_date
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'O24.4%'
    OR co.condition_source_value ILIKE '648.8%'
) gdm
  ON gdm.person_id = z.person_id
 AND gdm.gdm_date <= z.index_date
LEFT JOIN (
  /* Any secondary diabetes ICD source code on/before index */
  SELECT DISTINCT
    co.person_id,
    try_cast(co.condition_start_date AS DATE) AS sec_date
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'E08%'
    OR co.condition_source_value ILIKE 'E09%'
    OR co.condition_source_value ILIKE 'E13%'
    OR co.condition_source_value ILIKE '249%'
) sec
  ON sec.person_id = z.person_id
 AND sec.sec_date <= z.index_date
WHERE
  -- Exclusions
  t1.person_id IS NULL
  AND gdm.person_id IS NULL
  AND sec.person_id IS NULL
  -- Adults at index (DuckDB-safe)
  AND (
    EXTRACT(YEAR FROM z.index_date) - p.year_of_birth
    - CASE
        WHEN strftime(z.index_date, '%m%d')
             < lpad(CAST(COALESCE(p.month_of_birth, 1) AS VARCHAR), 2, '0')
               || lpad(CAST(COALESCE(p.day_of_birth, 1) AS VARCHAR), 2, '0')
        THEN 1 ELSE 0
      END
  ) >= 18
ORDER BY z.person_id;
