-- Fixes:
-- 1. Replaced ICD source-concept diagnosis/exclusion matching with OMOP 'Maps to' standard concept matching.
-- 2. Compared mapped ICD concepts against condition_occurrence.condition_concept_id.
-- 3. Fixed invalid alias g.person_id -> co.person_id by rewriting gestational diabetes exclusion as a mapped CTE.
-- 4. Moved MIN(index_date) into inc_index CTE so adult age and gestational window checks use precomputed index_date.
-- 5. Kept the original inclusion rules, medication logic, lab thresholds, timing windows, and exclusion intent unchanged.

WITH t2dm_dx_concepts AS (
  SELECT DISTINCT cr.concept_id_2 AS concept_id
  FROM public.concept c
  JOIN public.concept_relationship cr
    ON cr.concept_id_1 = c.concept_id
  WHERE cr.relationship_id = 'Maps to'
    AND c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
    AND (
         (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E11%')
      OR (c.vocabulary_id = 'ICD9CM'  AND (c.concept_code ~ '^250\.[0-9]0$' OR c.concept_code ~ '^250\.[0-9]2$'))
    )
),

t1dm_dx_concepts AS (
  SELECT DISTINCT cr.concept_id_2 AS concept_id
  FROM public.concept c
  JOIN public.concept_relationship cr
    ON cr.concept_id_1 = c.concept_id
  WHERE cr.relationship_id = 'Maps to'
    AND c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
    AND (
         (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E10%')
      OR (c.vocabulary_id = 'ICD9CM'  AND (c.concept_code ~ '^250\.[0-9]1$' OR c.concept_code ~ '^250\.[0-9]3$'))
    )
),

secondary_dx_concepts AS (
  SELECT DISTINCT cr.concept_id_2 AS concept_id
  FROM public.concept c
  JOIN public.concept_relationship cr
    ON cr.concept_id_1 = c.concept_id
  WHERE cr.relationship_id = 'Maps to'
    AND c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
    AND (
         (c.vocabulary_id = 'ICD10CM' AND (c.concept_code LIKE 'E08%' OR c.concept_code LIKE 'E09%' OR c.concept_code LIKE 'E13%'))
      OR (c.vocabulary_id = 'ICD9CM'  AND c.concept_code LIKE '249%')
    )
),

gdm_dx_concepts AS (
  SELECT DISTINCT cr.concept_id_2 AS concept_id
  FROM public.concept c
  JOIN public.concept_relationship cr
    ON cr.concept_id_1 = c.concept_id
  WHERE cr.relationship_id = 'Maps to'
    AND c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
    AND (
         (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'O24.4%')
      OR (c.vocabulary_id = 'ICD9CM'  AND c.concept_code LIKE '648.8%')
    )
),

t2dm_dx_dates AS (
  SELECT DISTINCT
    co.person_id,
    DATE(co.condition_start_date) AS cond_date,
    co.visit_occurrence_id
  FROM public.condition_occurrence co
  WHERE co.condition_concept_id IN (
    SELECT concept_id FROM t2dm_dx_concepts
  )
),

positive_labs AS (
  SELECT
    m.person_id,
    DATE(m.measurement_date) AS meas_date
  FROM public.measurement m
  LEFT JOIN public.concept u
    ON u.concept_id = m.unit_concept_id
  WHERE m.value_as_number IS NOT NULL
    AND (
      /* HbA1c ≥6.5% or ≥48 mmol/mol */
      (
        m.measurement_concept_id IN (
          SELECT concept_id
          FROM public.concept
          WHERE vocabulary_id = 'LOINC'
            AND concept_code IN ('4548-4', '17856-6', '41995-2', '4549-2')
        )
        AND (
             ((u.concept_name ILIKE '%percent%' OR COALESCE(m.unit_source_value, '') ILIKE '%percent%' OR COALESCE(m.unit_source_value, '') = '%') AND m.value_as_number >= 6.5)
          OR ((u.concept_name ILIKE '%mmol/mol%' OR COALESCE(m.unit_source_value, '') ILIKE '%mmol/mol%') AND m.value_as_number >= 48)
        )
      )

      OR

      /* FPG ≥126 mg/dL or ≥7.0 mmol/L */
      (
        m.measurement_concept_id IN (
          SELECT concept_id
          FROM public.concept
          WHERE vocabulary_id = 'LOINC'
            AND concept_code IN ('1558-6', '14771-0', '35217-9')
        )
        AND (
             ((u.concept_name ILIKE '%mg/dl%' OR COALESCE(m.unit_source_value, '') ILIKE '%mg/dl%') AND m.value_as_number >= 126)
          OR ((u.concept_name ILIKE '%mmol/l%' OR COALESCE(m.unit_source_value, '') ILIKE '%mmol/l%') AND m.value_as_number >= 7.0)
        )
      )

      OR

      /* 2h OGTT ≥200 mg/dL or ≥11.1 mmol/L */
      (
        m.measurement_concept_id IN (
          SELECT concept_id
          FROM public.concept
          WHERE vocabulary_id = 'LOINC'
            AND concept_code IN ('20436-2', '1518-0', '14763-7')
        )
        AND (
             ((u.concept_name ILIKE '%mg/dl%' OR COALESCE(m.unit_source_value, '') ILIKE '%mg/dl%') AND m.value_as_number >= 200)
          OR ((u.concept_name ILIKE '%mmol/l%' OR COALESCE(m.unit_source_value, '') ILIKE '%mmol/l%') AND m.value_as_number >= 11.1)
        )
      )

      OR

      /* Random glucose ≥200 mg/dL or ≥11.1 mmol/L */
      (
        m.measurement_concept_id IN (
          SELECT concept_id
          FROM public.concept
          WHERE vocabulary_id = 'LOINC'
            AND concept_code IN ('2345-7', '2339-0')
        )
        AND (
             ((u.concept_name ILIKE '%mg/dl%' OR COALESCE(m.unit_source_value, '') ILIKE '%mg/dl%') AND m.value_as_number >= 200)
          OR ((u.concept_name ILIKE '%mmol/l%' OR COALESCE(m.unit_source_value, '') ILIKE '%mmol/l%') AND m.value_as_number >= 11.1)
        )
      )
    )
),

non_insulin_rx_dates AS (
  SELECT
    de.person_id,
    DATE(de.drug_exposure_start_date) AS rx_date
  FROM public.drug_exposure de
  WHERE de.drug_concept_id IN (
    SELECT DISTINCT COALESCE(ca.descendant_concept_id, s.concept_id)
    FROM (
      SELECT concept_id
      FROM public.concept
      WHERE vocabulary_id = 'RxNorm'
        AND (
          (
            concept_class_id = 'Ingredient'
            AND lower(concept_name) IN (
              'metformin',
              'glipizide', 'glyburide', 'glimepiride',
              'repaglinide', 'nateglinide',
              'pioglitazone', 'rosiglitazone',
              'sitagliptin', 'saxagliptin', 'linagliptin', 'alogliptin',
              'empagliflozin', 'canagliflozin', 'dapagliflozin', 'ertugliflozin',
              'semaglutide', 'liraglutide', 'dulaglutide', 'exenatide', 'lixisenatide',
              'acarbose', 'miglitol', 'colesevelam', 'bromocriptine', 'tirzepatide'
            )
          )
          OR
          (
            concept_class_id = 'Brand Name'
            AND lower(concept_name) IN (
              'glucophage', 'glumetza', 'fortamet', 'riomet',
              'glucotrol', 'diabeta', 'micronase', 'glynase', 'amaryl',
              'prandin', 'starlix',
              'actos', 'avandia',
              'januvia', 'onglyza', 'tradjenta', 'nesina',
              'jardiance', 'invokana', 'farxiga', 'steglatro',
              'ozempic', 'rybelsus', 'victoza', 'trulicity', 'byetta', 'bydureon', 'adlyxin',
              'precose', 'glyset', 'welchol', 'cycloset', 'mounjaro'
            )
          )
        )
    ) s
    LEFT JOIN public.concept_ancestor ca
      ON ca.ancestor_concept_id = s.concept_id
  )
),

inc AS (
  /* -----------------------------------------------
     RULE A: Diagnosis-only
     ≥1 Inpatient OR ≥2 Outpatient/ER T2DM diagnoses
     on distinct dates ≥30 days apart
     ----------------------------------------------- */
  SELECT z.person_id,
         MIN(z.cond_date) AS index_date
  FROM (
    /* Inpatient: visit_concept_id = 9201 */
    SELECT d.person_id, d.cond_date
    FROM t2dm_dx_dates d
    JOIN public.visit_occurrence vo
      ON vo.visit_occurrence_id = d.visit_occurrence_id
    WHERE vo.visit_concept_id = 9201

    UNION ALL

    /* Outpatient/ER: visit_concept_id IN (9202,9203), need ≥2 dates ≥30d apart */
    SELECT d1.person_id, d1.cond_date
    FROM (
      SELECT d.person_id, d.cond_date
      FROM t2dm_dx_dates d
      JOIN public.visit_occurrence vo
        ON vo.visit_occurrence_id = d.visit_occurrence_id
      WHERE vo.visit_concept_id IN (9202, 9203)
      GROUP BY d.person_id, d.cond_date
    ) d1
    JOIN (
      SELECT d.person_id, d.cond_date
      FROM t2dm_dx_dates d
      JOIN public.visit_occurrence vo
        ON vo.visit_occurrence_id = d.visit_occurrence_id
      WHERE vo.visit_concept_id IN (9202, 9203)
      GROUP BY d.person_id, d.cond_date
    ) d2
      ON d1.person_id = d2.person_id
     AND d2.cond_date >= d1.cond_date + INTERVAL '30 day'
  ) z
  GROUP BY z.person_id

  UNION ALL

  /* -----------------------------------------------
     RULE B: Diagnosis + Lab
     ----------------------------------------------- */
  SELECT d.person_id,
         LEAST(MIN(d.cond_date), MIN(l.meas_date)) AS index_date
  FROM t2dm_dx_dates d
  JOIN positive_labs l
    ON l.person_id = d.person_id
  GROUP BY d.person_id

  UNION ALL

  /* -----------------------------------------------
     RULE C: Medication-only
     ≥2 fills ≥30 days apart
     ----------------------------------------------- */
  SELECT rx.person_id,
         MIN(rx.first_fill) AS index_date
  FROM (
    SELECT
      r.person_id,
      MIN(r.rx_date) AS first_fill,
      MAX(r.rx_date) AS last_fill,
      COUNT(*) AS n_fills
    FROM non_insulin_rx_dates r
    GROUP BY r.person_id
    HAVING COUNT(*) >= 2
       AND (MAX(r.rx_date) - MIN(r.rx_date)) >= 30
  ) rx
  GROUP BY rx.person_id

  UNION ALL

  /* -----------------------------------------------
     RULE D: Lab + Medication within ±365d
     ----------------------------------------------- */
  SELECT lm.person_id,
         MIN(lm.index_dt) AS index_date
  FROM (
    SELECT
      l.person_id,
      LEAST(l.meas_date, r.rx_date) AS index_dt
    FROM positive_labs l
    JOIN non_insulin_rx_dates r
      ON r.person_id = l.person_id
     AND r.rx_date BETWEEN l.meas_date - INTERVAL '365 days'
                       AND l.meas_date + INTERVAL '365 days'
  ) lm
  GROUP BY lm.person_id
),

inc_index AS (
  SELECT
    person_id,
    MIN(index_date) AS index_date
  FROM inc
  GROUP BY person_id
),

secondary_diabetes AS (
  SELECT DISTINCT co.person_id
  FROM public.condition_occurrence co
  WHERE co.condition_concept_id IN (
    SELECT concept_id FROM secondary_dx_concepts
  )
),

t1dm_patients AS (
  SELECT DISTINCT co.person_id
  FROM public.condition_occurrence co
  WHERE co.condition_concept_id IN (
    SELECT concept_id FROM t1dm_dx_concepts
  )
),

t2dm_patients AS (
  SELECT DISTINCT co.person_id
  FROM public.condition_occurrence co
  WHERE co.condition_concept_id IN (
    SELECT concept_id FROM t2dm_dx_concepts
  )
),

t1only AS (
  /* Type 1 only: any T1 and no T2 ever */
  SELECT t1.person_id
  FROM t1dm_patients t1
  LEFT JOIN t2dm_patients t2
    ON t2.person_id = t1.person_id
  WHERE t2.person_id IS NULL
),

gestational_diabetes_dates AS (
  SELECT DISTINCT
    co.person_id,
    DATE(co.condition_start_date) AS g_date
  FROM public.condition_occurrence co
  WHERE co.condition_concept_id IN (
    SELECT concept_id FROM gdm_dx_concepts
  )
)

SELECT
  idx.person_id,
  idx.index_date
FROM inc_index idx
JOIN public.person p
  ON p.person_id = idx.person_id
LEFT JOIN secondary_diabetes sec
  ON sec.person_id = idx.person_id
LEFT JOIN t1only t1
  ON t1.person_id = idx.person_id
WHERE sec.person_id IS NULL
  AND t1.person_id IS NULL
  AND NOT EXISTS (
    SELECT 1
    FROM gestational_diabetes_dates gest
    WHERE gest.person_id = idx.person_id
      AND gest.g_date BETWEEN idx.index_date - INTERVAL '270 days'
                          AND idx.index_date + INTERVAL '270 days'
  )
  AND DATE_PART('year', AGE(idx.index_date, p.birth_datetime)) >= 18
ORDER BY idx.person_id;