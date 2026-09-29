-- Claude beta (minimal changes) - DuckDB / OMOP-lite compatible
-- Logic unchanged:
--   (C1 OR C2 OR C3 OR C4) AND NOT(T1) AND NOT(Gest) AND NOT(Secondary)
-- Only fix: move LEFT JOINs before WHERE (SQL grammar), remove concept joins, use *_source_value

WITH
co_dx AS (
  SELECT
    person_id,
    MIN(try_cast(condition_start_date AS DATE)) AS first_dx_date
  FROM condition_occurrence
  WHERE
    condition_source_value ILIKE 'E11%'
    OR condition_source_value IN (
      '250.00','250.02','250.10','250.12','250.20','250.22','250.30','250.32','250.40','250.42',
      '250.50','250.52','250.60','250.62','250.70','250.72','250.80','250.82','250.90','250.92'
    )
  GROUP BY person_id
),
de_med AS (
  SELECT
    person_id,
    MIN(try_cast(drug_exposure_start_date AS DATE)) AS first_med_date
  FROM drug_exposure
  WHERE
    drug_source_value ILIKE '%metformin%'
    OR drug_source_value ILIKE '%glucophage%'
    OR drug_source_value ILIKE '%fortamet%'
    OR drug_source_value ILIKE '%glumetza%'
    OR drug_source_value ILIKE '%riomet%'
    OR drug_source_value ILIKE '%glipizide%'
    OR drug_source_value ILIKE '%glucotrol%'
    OR drug_source_value ILIKE '%glyburide%'
    OR drug_source_value ILIKE '%diabeta%'
    OR drug_source_value ILIKE '%micronase%'
    OR drug_source_value ILIKE '%glimepiride%'
    OR drug_source_value ILIKE '%amaryl%'
    OR drug_source_value ILIKE '%gliclazide%'
    OR drug_source_value ILIKE '%sitagliptin%'
    OR drug_source_value ILIKE '%januvia%'
    OR drug_source_value ILIKE '%saxagliptin%'
    OR drug_source_value ILIKE '%onglyza%'
    OR drug_source_value ILIKE '%linagliptin%'
    OR drug_source_value ILIKE '%tradjenta%'
    OR drug_source_value ILIKE '%alogliptin%'
    OR drug_source_value ILIKE '%nesina%'
    OR drug_source_value ILIKE '%exenatide%'
    OR drug_source_value ILIKE '%byetta%'
    OR drug_source_value ILIKE '%bydureon%'
    OR drug_source_value ILIKE '%liraglutide%'
    OR drug_source_value ILIKE '%victoza%'
    OR drug_source_value ILIKE '%saxenda%'
    OR drug_source_value ILIKE '%dulaglutide%'
    OR drug_source_value ILIKE '%trulicity%'
    OR drug_source_value ILIKE '%semaglutide%'
    OR drug_source_value ILIKE '%ozempic%'
    OR drug_source_value ILIKE '%wegovy%'
    OR drug_source_value ILIKE '%rybelsus%'
    OR drug_source_value ILIKE '%canagliflozin%'
    OR drug_source_value ILIKE '%invokana%'
    OR drug_source_value ILIKE '%dapagliflozin%'
    OR drug_source_value ILIKE '%farxiga%'
    OR drug_source_value ILIKE '%empagliflozin%'
    OR drug_source_value ILIKE '%jardiance%'
    OR drug_source_value ILIKE '%ertugliflozin%'
    OR drug_source_value ILIKE '%steglatro%'
    OR drug_source_value ILIKE '%pioglitazone%'
    OR drug_source_value ILIKE '%actos%'
    OR drug_source_value ILIKE '%rosiglitazone%'
    OR drug_source_value ILIKE '%avandia%'
    OR drug_source_value ILIKE '%repaglinide%'
    OR drug_source_value ILIKE '%prandin%'
    OR drug_source_value ILIKE '%nateglinide%'
    OR drug_source_value ILIKE '%starlix%'
    OR drug_source_value ILIKE '%acarbose%'
    OR drug_source_value ILIKE '%precose%'
    OR drug_source_value ILIKE '%miglitol%'
    OR drug_source_value ILIKE '%glyset%'
  GROUP BY person_id
),
m_lab AS (
  SELECT
    person_id,
    MIN(try_cast(measurement_date AS DATE)) AS first_lab_date
  FROM measurement
  WHERE
    value_as_number IS NOT NULL
    AND (
      (
        (
          measurement_source_value ILIKE '%hemoglobin%a1c%'
          OR measurement_source_value ILIKE '%hba1c%'
          OR measurement_source_value ILIKE '%glycohemoglobin%'
          OR measurement_source_value ILIKE '%glycated hemoglobin%'
          OR measurement_source_value ILIKE '%a1c%'
        )
        AND value_as_number >= 6.5
      )
      OR (
        (
          measurement_source_value ILIKE '%fasting glucose%'
          OR measurement_source_value ILIKE '%fasting blood glucose%'
          OR measurement_source_value ILIKE '%fasting plasma glucose%'
        )
        AND value_as_number >= 126
      )
      OR (
        (
          measurement_source_value ILIKE '%glucose%'
          AND measurement_source_value NOT ILIKE '%fasting%'
          AND (
            measurement_source_value ILIKE '%2 hour%'
            OR measurement_source_value ILIKE '%2-hour%'
            OR measurement_source_value ILIKE '%ogtt%'
            OR measurement_source_value ILIKE '%oral glucose tolerance%'
          )
        )
        AND value_as_number >= 200
      )
    )
  GROUP BY person_id
)

SELECT DISTINCT
  p.person_id,
  LEAST(
    COALESCE(co_dx.first_dx_date,   DATE '9999-12-31'),
    COALESCE(de_med.first_med_date, DATE '9999-12-31'),
    COALESCE(m_lab.first_lab_date,  DATE '9999-12-31')
  ) AS index_date,
  p.year_of_birth,
  p.gender_concept_id,
  p.race_concept_id,
  p.ethnicity_concept_id
FROM person p
LEFT JOIN co_dx  ON p.person_id = co_dx.person_id
LEFT JOIN de_med ON p.person_id = de_med.person_id
LEFT JOIN m_lab  ON p.person_id = m_lab.person_id
WHERE
(
  -- Criterion 1: >=2 T2DM dx dates
  EXISTS (
    SELECT 1
    FROM condition_occurrence co1
    WHERE co1.person_id = p.person_id
      AND (
        co1.condition_source_value ILIKE 'E11%'
        OR co1.condition_source_value IN (
          '250.00','250.02','250.10','250.12','250.20','250.22','250.30','250.32','250.40','250.42',
          '250.50','250.52','250.60','250.62','250.70','250.72','250.80','250.82','250.90','250.92'
        )
      )
    GROUP BY co1.person_id
    HAVING COUNT(DISTINCT try_cast(co1.condition_start_date AS DATE)) >= 2
  )
)
OR
(
  -- Criterion 2: >=1 dx AND >=1 med
  EXISTS (
    SELECT 1
    FROM condition_occurrence co2
    WHERE co2.person_id = p.person_id
      AND (
        co2.condition_source_value ILIKE 'E11%'
        OR co2.condition_source_value IN (
          '250.00','250.02','250.10','250.12','250.20','250.22','250.30','250.32','250.40','250.42',
          '250.50','250.52','250.60','250.62','250.70','250.72','250.80','250.82','250.90','250.92'
        )
      )
  )
  AND EXISTS (
    SELECT 1
    FROM drug_exposure de
    WHERE de.person_id = p.person_id
      AND (
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
        OR de.drug_source_value ILIKE '%gliclazide%'
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
        OR de.drug_source_value ILIKE '%saxenda%'
        OR de.drug_source_value ILIKE '%dulaglutide%'
        OR de.drug_source_value ILIKE '%trulicity%'
        OR de.drug_source_value ILIKE '%semaglutide%'
        OR de.drug_source_value ILIKE '%ozempic%'
        OR de.drug_source_value ILIKE '%wegovy%'
        OR de.drug_source_value ILIKE '%rybelsus%'
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
        OR de.drug_source_value ILIKE '%repaglinide%'
        OR de.drug_source_value ILIKE '%prandin%'
        OR de.drug_source_value ILIKE '%nateglinide%'
        OR de.drug_source_value ILIKE '%starlix%'
        OR de.drug_source_value ILIKE '%acarbose%'
        OR de.drug_source_value ILIKE '%precose%'
        OR de.drug_source_value ILIKE '%miglitol%'
        OR de.drug_source_value ILIKE '%glyset%'
      )
  )
)
OR
(
  -- Criterion 3: >=1 dx AND abnormal labs
  EXISTS (
    SELECT 1
    FROM condition_occurrence co3
    WHERE co3.person_id = p.person_id
      AND (
        co3.condition_source_value ILIKE 'E11%'
        OR co3.condition_source_value IN (
          '250.00','250.02','250.10','250.12','250.20','250.22','250.30','250.32','250.40','250.42',
          '250.50','250.52','250.60','250.62','250.70','250.72','250.80','250.82','250.90','250.92'
        )
      )
  )
  AND EXISTS (
    SELECT 1
    FROM measurement m
    WHERE m.person_id = p.person_id
      AND m.value_as_number IS NOT NULL
      AND (
        (
          (
            m.measurement_source_value ILIKE '%hemoglobin%a1c%'
            OR m.measurement_source_value ILIKE '%hba1c%'
            OR m.measurement_source_value ILIKE '%glycohemoglobin%'
            OR m.measurement_source_value ILIKE '%glycated hemoglobin%'
            OR m.measurement_source_value ILIKE '%a1c%'
          )
          AND m.value_as_number >= 6.5
        )
        OR (
          (
            m.measurement_source_value ILIKE '%fasting glucose%'
            OR m.measurement_source_value ILIKE '%fasting blood glucose%'
            OR m.measurement_source_value ILIKE '%fasting plasma glucose%'
          )
          AND m.value_as_number >= 126
        )
        OR (
          (
            m.measurement_source_value ILIKE '%glucose%'
            AND m.measurement_source_value NOT ILIKE '%fasting%'
            AND (
              m.measurement_source_value ILIKE '%2 hour%'
              OR m.measurement_source_value ILIKE '%2-hour%'
              OR m.measurement_source_value ILIKE '%ogtt%'
              OR m.measurement_source_value ILIKE '%oral glucose tolerance%'
            )
          )
          AND m.value_as_number >= 200
        )
      )
  )
)
OR
(
  -- Criterion 4: diabetes medication AND abnormal labs
  EXISTS (
    SELECT 1
    FROM drug_exposure de2
    WHERE de2.person_id = p.person_id
      AND (
        de2.drug_source_value ILIKE '%metformin%'
        OR de2.drug_source_value ILIKE '%glucophage%'
        OR de2.drug_source_value ILIKE '%fortamet%'
        OR de2.drug_source_value ILIKE '%glumetza%'
        OR de2.drug_source_value ILIKE '%riomet%'
        OR de2.drug_source_value ILIKE '%glipizide%'
        OR de2.drug_source_value ILIKE '%glucotrol%'
        OR de2.drug_source_value ILIKE '%glyburide%'
        OR de2.drug_source_value ILIKE '%diabeta%'
        OR de2.drug_source_value ILIKE '%micronase%'
        OR de2.drug_source_value ILIKE '%glimepiride%'
        OR de2.drug_source_value ILIKE '%amaryl%'
        OR de2.drug_source_value ILIKE '%gliclazide%'
        OR de2.drug_source_value ILIKE '%sitagliptin%'
        OR de2.drug_source_value ILIKE '%januvia%'
        OR de2.drug_source_value ILIKE '%saxagliptin%'
        OR de2.drug_source_value ILIKE '%onglyza%'
        OR de2.drug_source_value ILIKE '%linagliptin%'
        OR de2.drug_source_value ILIKE '%tradjenta%'
        OR de2.drug_source_value ILIKE '%alogliptin%'
        OR de2.drug_source_value ILIKE '%nesina%'
        OR de2.drug_source_value ILIKE '%exenatide%'
        OR de2.drug_source_value ILIKE '%byetta%'
        OR de2.drug_source_value ILIKE '%bydureon%'
        OR de2.drug_source_value ILIKE '%liraglutide%'
        OR de2.drug_source_value ILIKE '%victoza%'
        OR de2.drug_source_value ILIKE '%saxenda%'
        OR de2.drug_source_value ILIKE '%dulaglutide%'
        OR de2.drug_source_value ILIKE '%trulicity%'
        OR de2.drug_source_value ILIKE '%semaglutide%'
        OR de2.drug_source_value ILIKE '%ozempic%'
        OR de2.drug_source_value ILIKE '%wegovy%'
        OR de2.drug_source_value ILIKE '%rybelsus%'
        OR de2.drug_source_value ILIKE '%canagliflozin%'
        OR de2.drug_source_value ILIKE '%invokana%'
        OR de2.drug_source_value ILIKE '%dapagliflozin%'
        OR de2.drug_source_value ILIKE '%farxiga%'
        OR de2.drug_source_value ILIKE '%empagliflozin%'
        OR de2.drug_source_value ILIKE '%jardiance%'
        OR de2.drug_source_value ILIKE '%ertugliflozin%'
        OR de2.drug_source_value ILIKE '%steglatro%'
        OR de2.drug_source_value ILIKE '%pioglitazone%'
        OR de2.drug_source_value ILIKE '%actos%'
        OR de2.drug_source_value ILIKE '%rosiglitazone%'
        OR de2.drug_source_value ILIKE '%avandia%'
        OR de2.drug_source_value ILIKE '%repaglinide%'
        OR de2.drug_source_value ILIKE '%prandin%'
        OR de2.drug_source_value ILIKE '%nateglinide%'
        OR de2.drug_source_value ILIKE '%starlix%'
        OR de2.drug_source_value ILIKE '%acarbose%'
        OR de2.drug_source_value ILIKE '%precose%'
        OR de2.drug_source_value ILIKE '%miglitol%'
        OR de2.drug_source_value ILIKE '%glyset%'
      )
  )
  AND EXISTS (
    SELECT 1
    FROM measurement m2
    WHERE m2.person_id = p.person_id
      AND m2.value_as_number IS NOT NULL
      AND (
        (
          (
            m2.measurement_source_value ILIKE '%hemoglobin%a1c%'
            OR m2.measurement_source_value ILIKE '%hba1c%'
            OR m2.measurement_source_value ILIKE '%glycohemoglobin%'
            OR m2.measurement_source_value ILIKE '%glycated hemoglobin%'
            OR m2.measurement_source_value ILIKE '%a1c%'
          )
          AND m2.value_as_number >= 6.5
        )
        OR (
          (
            m2.measurement_source_value ILIKE '%fasting glucose%'
            OR m2.measurement_source_value ILIKE '%fasting blood glucose%'
            OR m2.measurement_source_value ILIKE '%fasting plasma glucose%'
          )
          AND m2.value_as_number >= 126
        )
        OR (
          (
            m2.measurement_source_value ILIKE '%glucose%'
            AND m2.measurement_source_value NOT ILIKE '%fasting%'
            AND (
              m2.measurement_source_value ILIKE '%2 hour%'
              OR m2.measurement_source_value ILIKE '%2-hour%'
              OR m2.measurement_source_value ILIKE '%ogtt%'
              OR m2.measurement_source_value ILIKE '%oral glucose tolerance%'
            )
          )
          AND m2.value_as_number >= 200
        )
      )
  )
)
AND NOT EXISTS (
  -- Exclude Type 1 Diabetes
  SELECT 1
  FROM condition_occurrence co_excl
  WHERE co_excl.person_id = p.person_id
    AND (
      co_excl.condition_source_value ILIKE 'E10%'
      OR co_excl.condition_source_value IN (
        '250.01','250.03','250.11','250.13','250.21','250.23','250.31','250.33','250.41','250.43',
        '250.51','250.53','250.61','250.63','250.71','250.73','250.81','250.83','250.91','250.93'
      )
    )
)
AND NOT EXISTS (
  -- Exclude Gestational Diabetes
  SELECT 1
  FROM condition_occurrence co_gest
  WHERE co_gest.person_id = p.person_id
    AND (co_gest.condition_source_value ILIKE 'O24%' OR co_gest.condition_source_value ILIKE '648.8%')
)
AND NOT EXISTS (
  -- Exclude Secondary Diabetes
  SELECT 1
  FROM condition_occurrence co_sec
  WHERE co_sec.person_id = p.person_id
    AND (
      co_sec.condition_source_value ILIKE 'E08%'
      OR co_sec.condition_source_value ILIKE 'E09%'
      OR co_sec.condition_source_value ILIKE 'E13%'
    )
)
ORDER BY p.person_id;
