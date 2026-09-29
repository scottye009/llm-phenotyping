-- Fixes:
-- 1. Replaced ICD source-concept matching with OMOP 'Maps to' standard concept matching.
-- 2. Compared mapped ICD concepts against condition_occurrence.condition_concept_id.
-- 3. Applied the same mapping fix to T2DM inclusion, Type 1 diabetes exclusion, gestational diabetes exclusion, and secondary diabetes exclusion.
-- 4. Kept medication, lab, timing, adult eligibility, and exclusion logic unchanged.

WITH t2dm_dx_concepts AS (
  SELECT DISTINCT cr.concept_id_2 AS concept_id
  FROM public.concept c
  JOIN public.concept_relationship cr
    ON c.concept_id = cr.concept_id_1
  WHERE cr.relationship_id = 'Maps to'
    AND c.vocabulary_id IN ('ICD10CM','ICD9CM')
    AND (
         (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E11%')
      OR (c.vocabulary_id = 'ICD9CM'  AND (c.concept_code ~ '^250\.[0-9]0$' OR c.concept_code ~ '^250\.[0-9]2$'))
    )
    AND c.invalid_reason IS NULL
),

t1_dx_concepts AS (
  SELECT DISTINCT cr.concept_id_2 AS concept_id
  FROM public.concept c
  JOIN public.concept_relationship cr
    ON c.concept_id = cr.concept_id_1
  WHERE cr.relationship_id = 'Maps to'
    AND c.vocabulary_id IN ('ICD10CM','ICD9CM')
    AND (
         (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E10%')
      OR (c.vocabulary_id = 'ICD9CM'  AND (c.concept_code ~ '^250\.[0-9]1$' OR c.concept_code ~ '^250\.[0-9]3$'))
    )
    AND c.invalid_reason IS NULL
),

gdm_dx_concepts AS (
  SELECT DISTINCT cr.concept_id_2 AS concept_id
  FROM public.concept c
  JOIN public.concept_relationship cr
    ON c.concept_id = cr.concept_id_1
  WHERE cr.relationship_id = 'Maps to'
    AND c.vocabulary_id IN ('ICD10CM','ICD9CM')
    AND (
         (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'O24.4%')
      OR (c.vocabulary_id = 'ICD9CM'  AND c.concept_code LIKE '648.8%')
    )
    AND c.invalid_reason IS NULL
),

secondary_dx_concepts AS (
  SELECT DISTINCT cr.concept_id_2 AS concept_id
  FROM public.concept c
  JOIN public.concept_relationship cr
    ON c.concept_id = cr.concept_id_1
  WHERE cr.relationship_id = 'Maps to'
    AND c.vocabulary_id IN ('ICD10CM','ICD9CM')
    AND (
         (c.vocabulary_id = 'ICD10CM' AND (c.concept_code LIKE 'E08%' OR c.concept_code LIKE 'E09%' OR c.concept_code LIKE 'E13%'))
      OR (c.vocabulary_id = 'ICD9CM'  AND c.concept_code LIKE '249%')
    )
    AND c.invalid_reason IS NULL
),

candidate_evidence AS (

  /* --- T2DM diagnosis evidence: mapped ICD source codes to standard concepts --- */
  SELECT d2.person_id, MIN(d2.dx_date) AS index_date
  FROM (
    SELECT DISTINCT co.person_id, co.condition_start_date::date AS dx_date
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (
      SELECT concept_id FROM t2dm_dx_concepts
    )
  ) d2
  GROUP BY d2.person_id
  HAVING COUNT(*) >= 2

  UNION ALL

  /* --- T2DM diagnosis + non-insulin drug within ±365d --- */
  SELECT d.person_id, MIN(LEAST(d.dx_date, rx.rx_date)) AS index_date
  FROM (
    SELECT DISTINCT co.person_id, co.condition_start_date::date AS dx_date
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (
      SELECT concept_id FROM t2dm_dx_concepts
    )
  ) d
  JOIN (
    /* Non-insulin antihyperglycemics: ingredients + brand names → descendants */
    SELECT de.person_id, COALESCE(de.drug_exposure_start_date, de.drug_exposure_start_datetime)::date AS rx_date
    FROM public.drug_exposure de
    WHERE de.drug_concept_id IN (
      SELECT DISTINCT ca.descendant_concept_id
      FROM (
        /* Ingredients */
        SELECT concept_id FROM public.concept
        WHERE vocabulary_id = 'RxNorm'
          AND concept_class_id = 'Ingredient'
          AND standard_concept = 'S'
          AND concept_name IN (
            'Metformin',
            'Glipizide','Glyburide','Glimepiride',
            'Repaglinide','Nateglinide',
            'Pioglitazone','Rosiglitazone',
            'Sitagliptin','Saxagliptin','Linagliptin','Alogliptin',
            'Exenatide','Liraglutide','Semaglutide','Dulaglutide','Lixisenatide','Tirzepatide',
            'Canagliflozin','Dapagliflozin','Empagliflozin','Ertugliflozin',
            'Acarbose','Miglitol'
          )

        UNION

        /* Brand names */
        SELECT concept_id FROM public.concept
        WHERE vocabulary_id = 'RxNorm'
          AND concept_class_id IN ('Brand Name','Branded Drug','Branded Drug Form')
          AND standard_concept IS NOT NULL
          AND concept_name IN (
            'Glucophage','Glumetza','Riomet','Fortamet',
            'Glucotrol','Diabeta','Micronase','Glynase','Amaryl',
            'Actos','Avandia',
            'Januvia','Onglyza','Tradjenta','Nesina',
            'Byetta','Bydureon','Victoza','Ozempic','Rybelsus','Trulicity','Adlyxin','Mounjaro',
            'Invokana','Farxiga','Jardiance','Steglatro'
          )
      ) seed
      JOIN public.concept_ancestor ca
        ON ca.ancestor_concept_id = seed.concept_id
    )
  ) rx
    ON rx.person_id = d.person_id
   AND rx.rx_date BETWEEN d.dx_date - INTERVAL '365 days'
                      AND d.dx_date + INTERVAL '365 days'
  GROUP BY d.person_id

  UNION ALL

  /* --- Labs: ≥2 positive labs on distinct dates --- */
  SELECT l.person_id, MIN(l.lab_date) AS index_date
  FROM (
    SELECT m.person_id,
           m.measurement_date::date AS lab_date
    FROM public.measurement m
    JOIN public.concept lc
      ON lc.concept_id = m.measurement_concept_id
    WHERE lc.vocabulary_id = 'LOINC'
      AND lc.standard_concept = 'S'
      AND lc.concept_name ILIKE '%hemoglobin a1c%'
      AND m.value_as_number IS NOT NULL
      AND (
        m.unit_concept_id IN (
          SELECT concept_id FROM public.concept
          WHERE lower(concept_name) IN ('percent','percent [ratio]','%')
        )
        OR m.unit_concept_id IS NULL
      )
      AND m.value_as_number >= 6.5

    UNION ALL

    SELECT m.person_id,
           m.measurement_date::date AS lab_date
    FROM public.measurement m
    JOIN public.concept lc
      ON lc.concept_id = m.measurement_concept_id
    WHERE lc.vocabulary_id = 'LOINC'
      AND lc.standard_concept = 'S'
      AND lc.concept_name ILIKE '%glucose%'
      AND lc.concept_name ILIKE '%fast%'
      AND m.value_as_number IS NOT NULL
      AND (
        (
          m.unit_concept_id IN (
            SELECT concept_id FROM public.concept
            WHERE lower(concept_name) LIKE 'milligram per deciliter%'
          )
          AND m.value_as_number >= 126
        )
        OR
        (
          m.unit_concept_id IN (
            SELECT concept_id FROM public.concept
            WHERE lower(concept_name) LIKE 'millimole per liter%'
          )
          AND (m.value_as_number * 18.0) >= 126
        )
      )

    UNION ALL

    SELECT m.person_id,
           m.measurement_date::date AS lab_date
    FROM public.measurement m
    JOIN public.concept lc
      ON lc.concept_id = m.measurement_concept_id
    WHERE lc.vocabulary_id = 'LOINC'
      AND lc.standard_concept = 'S'
      AND lc.concept_name ILIKE '%glucose%'
      AND (lc.concept_name ILIKE '%tolerance%' OR lc.concept_name ILIKE '%2 hour%')
      AND m.value_as_number IS NOT NULL
      AND (
        (
          m.unit_concept_id IN (
            SELECT concept_id FROM public.concept
            WHERE lower(concept_name) LIKE 'milligram per deciliter%'
          )
          AND m.value_as_number >= 200
        )
        OR
        (
          m.unit_concept_id IN (
            SELECT concept_id FROM public.concept
            WHERE lower(concept_name) LIKE 'millimole per liter%'
          )
          AND (m.value_as_number * 18.0) >= 200
        )
      )

    UNION ALL

    SELECT m.person_id,
           m.measurement_date::date AS lab_date
    FROM public.measurement m
    JOIN public.concept lc
      ON lc.concept_id = m.measurement_concept_id
    WHERE lc.vocabulary_id = 'LOINC'
      AND lc.standard_concept = 'S'
      AND lc.concept_name ILIKE '%glucose%'
      AND lc.concept_name NOT ILIKE '%fast%'
      AND lc.concept_name NOT ILIKE '%tolerance%'
      AND lc.concept_name NOT ILIKE '%2 hour%'
      AND m.value_as_number IS NOT NULL
      AND (
        (
          m.unit_concept_id IN (
            SELECT concept_id FROM public.concept
            WHERE lower(concept_name) LIKE 'milligram per deciliter%'
          )
          AND m.value_as_number >= 200
        )
        OR
        (
          m.unit_concept_id IN (
            SELECT concept_id FROM public.concept
            WHERE lower(concept_name) LIKE 'millimole per liter%'
          )
          AND (m.value_as_number * 18.0) >= 200
        )
      )
  ) l
  GROUP BY l.person_id
  HAVING COUNT(DISTINCT l.lab_date) >= 2

  UNION ALL

  /* --- Labs + non-insulin drug within ±365d --- */
  SELECT l.person_id, MIN(LEAST(l.lab_date, rx.rx_date)) AS index_date
  FROM (
    SELECT m.person_id,
           m.measurement_date::date AS lab_date
    FROM public.measurement m
    JOIN public.concept lc
      ON lc.concept_id = m.measurement_concept_id
    WHERE lc.vocabulary_id = 'LOINC'
      AND lc.standard_concept = 'S'
      AND lc.concept_name ILIKE '%hemoglobin a1c%'
      AND m.value_as_number IS NOT NULL
      AND (
        m.unit_concept_id IN (
          SELECT concept_id FROM public.concept
          WHERE lower(concept_name) IN ('percent','percent [ratio]','%')
        )
        OR m.unit_concept_id IS NULL
      )
      AND m.value_as_number >= 6.5

    UNION ALL

    SELECT m.person_id,
           m.measurement_date::date AS lab_date
    FROM public.measurement m
    JOIN public.concept lc
      ON lc.concept_id = m.measurement_concept_id
    WHERE lc.vocabulary_id = 'LOINC'
      AND lc.standard_concept = 'S'
      AND lc.concept_name ILIKE '%glucose%'
      AND lc.concept_name ILIKE '%fast%'
      AND m.value_as_number IS NOT NULL
      AND (
        (
          m.unit_concept_id IN (
            SELECT concept_id FROM public.concept
            WHERE lower(concept_name) LIKE 'milligram per deciliter%'
          )
          AND m.value_as_number >= 126
        )
        OR
        (
          m.unit_concept_id IN (
            SELECT concept_id FROM public.concept
            WHERE lower(concept_name) LIKE 'millimole per liter%'
          )
          AND (m.value_as_number * 18.0) >= 126
        )
      )

    UNION ALL

    SELECT m.person_id,
           m.measurement_date::date AS lab_date
    FROM public.measurement m
    JOIN public.concept lc
      ON lc.concept_id = m.measurement_concept_id
    WHERE lc.vocabulary_id = 'LOINC'
      AND lc.standard_concept = 'S'
      AND lc.concept_name ILIKE '%glucose%'
      AND (lc.concept_name ILIKE '%tolerance%' OR lc.concept_name ILIKE '%2 hour%')
      AND m.value_as_number IS NOT NULL
      AND (
        (
          m.unit_concept_id IN (
            SELECT concept_id FROM public.concept
            WHERE lower(concept_name) LIKE 'milligram per deciliter%'
          )
          AND m.value_as_number >= 200
        )
        OR
        (
          m.unit_concept_id IN (
            SELECT concept_id FROM public.concept
            WHERE lower(concept_name) LIKE 'millimole per liter%'
          )
          AND (m.value_as_number * 18.0) >= 200
        )
      )

    UNION ALL

    SELECT m.person_id,
           m.measurement_date::date AS lab_date
    FROM public.measurement m
    JOIN public.concept lc
      ON lc.concept_id = m.measurement_concept_id
    WHERE lc.vocabulary_id = 'LOINC'
      AND lc.standard_concept = 'S'
      AND lc.concept_name ILIKE '%glucose%'
      AND lc.concept_name NOT ILIKE '%fast%'
      AND lc.concept_name NOT ILIKE '%tolerance%'
      AND lc.concept_name NOT ILIKE '%2 hour%'
      AND m.value_as_number IS NOT NULL
      AND (
        (
          m.unit_concept_id IN (
            SELECT concept_id FROM public.concept
            WHERE lower(concept_name) LIKE 'milligram per deciliter%'
          )
          AND m.value_as_number >= 200
        )
        OR
        (
          m.unit_concept_id IN (
            SELECT concept_id FROM public.concept
            WHERE lower(concept_name) LIKE 'millimole per liter%'
          )
          AND (m.value_as_number * 18.0) >= 200
        )
      )
  ) l
  JOIN (
    SELECT de.person_id, COALESCE(de.drug_exposure_start_date, de.drug_exposure_start_datetime)::date AS rx_date
    FROM public.drug_exposure de
    WHERE de.drug_concept_id IN (
      SELECT DISTINCT ca.descendant_concept_id
      FROM (
        SELECT concept_id FROM public.concept
        WHERE vocabulary_id = 'RxNorm'
          AND concept_class_id = 'Ingredient'
          AND standard_concept = 'S'
          AND concept_name IN (
            'Metformin',
            'Glipizide','Glyburide','Glimepiride',
            'Repaglinide','Nateglinide',
            'Pioglitazone','Rosiglitazone',
            'Sitagliptin','Saxagliptin','Linagliptin','Alogliptin',
            'Exenatide','Liraglutide','Semaglutide','Dulaglutide','Lixisenatide','Tirzepatide',
            'Canagliflozin','Dapagliflozin','Empagliflozin','Ertugliflozin',
            'Acarbose','Miglitol'
          )

        UNION

        SELECT concept_id FROM public.concept
        WHERE vocabulary_id = 'RxNorm'
          AND concept_class_id IN ('Brand Name','Branded Drug','Branded Drug Form')
          AND standard_concept IS NOT NULL
          AND concept_name IN (
            'Glucophage','Glumetza','Riomet','Fortamet',
            'Glucotrol','Diabeta','Micronase','Glynase','Amaryl',
            'Actos','Avandia',
            'Januvia','Onglyza','Tradjenta','Nesina',
            'Byetta','Bydureon','Victoza','Ozempic','Rybelsus','Trulicity','Adlyxin','Mounjaro',
            'Invokana','Farxiga','Jardiance','Steglatro'
          )
      ) seed
      JOIN public.concept_ancestor ca
        ON ca.ancestor_concept_id = seed.concept_id
    )
  ) rx
    ON rx.person_id = l.person_id
   AND rx.rx_date BETWEEN l.lab_date - INTERVAL '365 days'
                      AND l.lab_date + INTERVAL '365 days'
  GROUP BY l.person_id
),

candidate_index AS (
  SELECT
    person_id,
    MIN(index_date) AS index_date
  FROM candidate_evidence
  GROUP BY person_id
)

SELECT
  idx.person_id,
  idx.index_date
FROM candidate_index idx

JOIN public.person p
  ON p.person_id = idx.person_id

JOIN public.observation_period op
  ON op.person_id = idx.person_id
 AND idx.index_date BETWEEN op.observation_period_start_date
                        AND op.observation_period_end_date

LEFT JOIN (
  SELECT DISTINCT co.person_id, co.condition_start_date::date AS t1_date
  FROM public.condition_occurrence co
  WHERE co.condition_concept_id IN (
    SELECT concept_id FROM t1_dx_concepts
  )
) t1
  ON t1.person_id = idx.person_id
 AND t1.t1_date <= idx.index_date

LEFT JOIN (
  SELECT DISTINCT co.person_id, co.condition_start_date::date AS gdm_date
  FROM public.condition_occurrence co
  WHERE co.condition_concept_id IN (
    SELECT concept_id FROM gdm_dx_concepts
  )
) gdm
  ON gdm.person_id = idx.person_id
 AND gdm.gdm_date <= idx.index_date

LEFT JOIN (
  SELECT DISTINCT co.person_id, co.condition_start_date::date AS sec_date
  FROM public.condition_occurrence co
  WHERE co.condition_concept_id IN (
    SELECT concept_id FROM secondary_dx_concepts
  )
) sec
  ON sec.person_id = idx.person_id
 AND sec.sec_date <= idx.index_date

WHERE
  t1.person_id IS NULL
  AND gdm.person_id IS NULL
  AND sec.person_id IS NULL
  AND DATE_PART('year', AGE(idx.index_date, p.birth_datetime)) >= 18

ORDER BY idx.person_id;