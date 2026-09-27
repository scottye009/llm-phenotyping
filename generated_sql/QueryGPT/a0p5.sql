WITH t2dm_dx AS (
  SELECT person_id, condition_start_date AS event_date
  FROM condition_occurrence
  WHERE
    condition_source_concept_id IN (
      SELECT concept_id
      FROM concept
      WHERE vocabulary_id IN ('ICD9CM','ICD10CM')
        AND concept_code IN (
          '250.00','250.02','250.10','250.12','250.20','250.22',
          '250.30','250.32','250.40','250.42','250.50','250.52',
          '250.60','250.62','250.70','250.72','250.80','250.82',
          '250.90','250.92',
          'E11','E11.0','E11.1','E11.2','E11.3','E11.4',
          'E11.5','E11.6','E11.8','E11.9'
        )
    )
),

t2dm_med AS (
  SELECT person_id, drug_exposure_start_date AS event_date
  FROM drug_exposure
  WHERE drug_concept_id IN (
    SELECT descendant_concept_id
    FROM concept_ancestor
    WHERE ancestor_concept_id IN (
      /* RxNorm ingredient concept_ids for:
         metformin, glipizide, glyburide, glimepiride,
         pioglitazone, rosiglitazone,
         sitagliptin, saxagliptin, linagliptin, alogliptin,
         exenatide, liraglutide, dulaglutide, semaglutide,
         lixisenatide,
         canagliflozin, dapagliflozin, empagliflozin, ertugliflozin,
         repaglinide, nateglinide, acarbose, miglitol, pramlintide
      */
    )
  )
),

diabetes_lab AS (
  SELECT person_id, measurement_date AS event_date
  FROM measurement
  WHERE
    (
      measurement_concept_id IN (
        SELECT descendant_concept_id
        FROM concept_ancestor
        WHERE ancestor_concept_id = /* HbA1c concept_id */
      )
      AND value_as_number >= 6.5
    )
    OR (
      measurement_concept_id IN (
        SELECT descendant_concept_id
        FROM concept_ancestor
        WHERE ancestor_concept_id = /* fasting glucose concept_id */
      )
      AND value_as_number >= 126
    )
    OR (
      measurement_concept_id IN (
        SELECT descendant_concept_id
        FROM concept_ancestor
        WHERE ancestor_concept_id = /* 2-hour OGTT glucose concept_id */
      )
      AND value_as_number >= 200
    )
    OR (
      measurement_concept_id IN (
        SELECT descendant_concept_id
        FROM concept_ancestor
        WHERE ancestor_concept_id = /* random glucose concept_id */
      )
      AND value_as_number >= 200
    )
),

exclusions AS (
  SELECT person_id
  FROM condition_occurrence co
  JOIN concept c
    ON co.condition_source_concept_id = c.concept_id
  WHERE
    (
      c.vocabulary_id = 'ICD10CM'
      AND (
        c.concept_code LIKE 'E10%'
        OR c.concept_code LIKE 'O24.4%'
        OR c.concept_code LIKE 'E08%'
        OR c.concept_code LIKE 'E09%'
        OR c.concept_code LIKE 'E13%'
        OR c.concept_code = 'P70.2'
      )
    )
    OR
    (
      c.vocabulary_id = 'ICD9CM'
      AND (
        c.concept_code LIKE '250.%1'
        OR c.concept_code LIKE '250.%3'
        OR c.concept_code LIKE '648.8%'
      )
    )
),

candidate_cases AS (
  SELECT
    p.person_id,
    MIN(COALESCE(dx.event_date, med.event_date, lab.event_date)) AS index_date,
    COUNT(DISTINCT dx.event_date) AS dx_count,
    COUNT(DISTINCT med.event_date) AS med_count,
    COUNT(DISTINCT lab.event_date) AS lab_count
  FROM person p
  LEFT JOIN t2dm_dx dx ON p.person_id = dx.person_id
  LEFT JOIN t2dm_med med ON p.person_id = med.person_id
  LEFT JOIN diabetes_lab lab ON p.person_id = lab.person_id
  GROUP BY p.person_id
)

SELECT cc.person_id, cc.index_date
FROM candidate_cases cc
JOIN person p
  ON cc.person_id = p.person_id
LEFT JOIN exclusions e
  ON cc.person_id = e.person_id
WHERE
  (
    cc.dx_count >= 2
    OR (cc.dx_count >= 1 AND cc.med_count >= 1)
    OR (cc.lab_count >= 2 AND cc.med_count >= 1)
  )
  AND YEAR(cc.index_date) - p.year_of_birth >= 18
  AND e.person_id IS NULL;

  --error