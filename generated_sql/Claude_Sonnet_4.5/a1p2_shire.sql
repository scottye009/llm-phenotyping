
-- Type 2 Diabetes Phenotyping Algorithm (SHIRE / OMOP-lite, DuckDB)
-- Changes:
--   * remove concept dependencies
--   * DuckDB does not support AGE(), ARRAY/ILIKE ANY like Postgres; rewrite
--   * keep intent: dx (>=2) or meds (>=2) or (labs + meds), then exclusions

WITH
t2dm_diagnosis AS (
  SELECT
    co.person_id
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'E11%'
    OR co.condition_source_value IN (
      '250.00','250.02','250.10','250.12','250.20','250.22','250.30','250.32','250.40','250.42',
      '250.50','250.52','250.60','250.62','250.70','250.72','250.80','250.82','250.90','250.92'
    )
  GROUP BY co.person_id
  HAVING COUNT(DISTINCT co.condition_occurrence_id) >= 2
),

t2dm_medications AS (
  SELECT
    de.person_id
  FROM memory.drug_exposure de
  WHERE
    (
      de.drug_source_value ILIKE '%metformin%'
      OR de.drug_source_value ILIKE '%glucophage%'
      OR de.drug_source_value ILIKE '%fortamet%'
      OR de.drug_source_value ILIKE '%glumetza%'

      OR de.drug_source_value ILIKE '%glyburide%'
      OR de.drug_source_value ILIKE '%glipizide%'
      OR de.drug_source_value ILIKE '%glimepiride%'
      OR de.drug_source_value ILIKE '%diabeta%'
      OR de.drug_source_value ILIKE '%glucotrol%'
      OR de.drug_source_value ILIKE '%amaryl%'

      OR de.drug_source_value ILIKE '%sitagliptin%'
      OR de.drug_source_value ILIKE '%saxagliptin%'
      OR de.drug_source_value ILIKE '%linagliptin%'
      OR de.drug_source_value ILIKE '%alogliptin%'
      OR de.drug_source_value ILIKE '%januvia%'
      OR de.drug_source_value ILIKE '%onglyza%'
      OR de.drug_source_value ILIKE '%tradjenta%'
      OR de.drug_source_value ILIKE '%nesina%'

      OR de.drug_source_value ILIKE '%exenatide%'
      OR de.drug_source_value ILIKE '%liraglutide%'
      OR de.drug_source_value ILIKE '%dulaglutide%'
      OR de.drug_source_value ILIKE '%semaglutide%'
      OR de.drug_source_value ILIKE '%byetta%'
      OR de.drug_source_value ILIKE '%victoza%'
      OR de.drug_source_value ILIKE '%trulicity%'
      OR de.drug_source_value ILIKE '%ozempic%'
      OR de.drug_source_value ILIKE '%wegovy%'

      OR de.drug_source_value ILIKE '%canagliflozin%'
      OR de.drug_source_value ILIKE '%dapagliflozin%'
      OR de.drug_source_value ILIKE '%empagliflozin%'
      OR de.drug_source_value ILIKE '%invokana%'
      OR de.drug_source_value ILIKE '%farxiga%'
      OR de.drug_source_value ILIKE '%jardiance%'

      OR de.drug_source_value ILIKE '%pioglitazone%'
      OR de.drug_source_value ILIKE '%rosiglitazone%'
      OR de.drug_source_value ILIKE '%actos%'
      OR de.drug_source_value ILIKE '%avandia%'
    )
  GROUP BY de.person_id
  HAVING COUNT(DISTINCT de.drug_exposure_id) >= 2
),

t2dm_labs AS (
  SELECT DISTINCT m.person_id
  FROM memory.measurement m
  WHERE
    m.value_as_number IS NOT NULL
    AND (
      (
        (m.measurement_source_value ILIKE '%hba1c%'
         OR m.measurement_source_value ILIKE '%hemoglobin a1c%'
         OR m.measurement_source_value ILIKE '%glycohemoglobin%'
         OR m.measurement_source_value ILIKE '%a1c%')
        AND m.value_as_number >= 6.5
      )
      OR (
        (m.measurement_source_value ILIKE '%fasting glucose%'
         OR m.measurement_source_value ILIKE '%fasting blood glucose%'
         OR (m.measurement_source_value ILIKE '%glucose%' AND m.measurement_source_value ILIKE '%fast%'))
        AND m.value_as_number >= 126
      )
      OR (
        (m.measurement_source_value ILIKE '%glucose%' OR m.measurement_source_value ILIKE '%blood glucose%')
        AND m.measurement_source_value NOT ILIKE '%fast%'
        AND m.value_as_number >= 200
      )
    )
),

exclusions AS (
  SELECT DISTINCT co.person_id
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'E10%'
    OR co.condition_source_value IN (
      '250.01','250.03','250.11','250.13','250.21','250.23',
      '250.31','250.33','250.41','250.43','250.51','250.53',
      '250.61','250.63','250.71','250.73','250.81','250.83',
      '250.91','250.93'
    )
    OR co.condition_source_value ILIKE 'O24%'
    OR co.condition_source_value ILIKE '648.8%'
),

t2dm_cohort AS (
  SELECT DISTINCT person_id
  FROM (
    SELECT person_id FROM t2dm_diagnosis
    UNION
    SELECT person_id FROM t2dm_medications
    UNION
    SELECT l.person_id
    FROM t2dm_labs l
    JOIN t2dm_medications m
      ON m.person_id = l.person_id
  ) combined
  WHERE person_id NOT IN (SELECT person_id FROM exclusions)
)

SELECT
  tc.person_id,
  p.gender_concept_id,
  p.birth_datetime,
  EXTRACT(YEAR FROM current_date) - p.year_of_birth AS age,
  CASE WHEN EXISTS (SELECT 1 FROM t2dm_diagnosis d WHERE d.person_id = tc.person_id) THEN 'Yes' ELSE 'No' END AS has_diagnosis,
  CASE WHEN EXISTS (SELECT 1 FROM t2dm_medications m WHERE m.person_id = tc.person_id) THEN 'Yes' ELSE 'No' END AS has_medication,
  CASE WHEN EXISTS (SELECT 1 FROM t2dm_labs l WHERE l.person_id = tc.person_id) THEN 'Yes' ELSE 'No' END AS has_abnormal_labs
FROM t2dm_cohort tc
JOIN memory.person p
  ON p.person_id = tc.person_id
ORDER BY tc.person_id
;