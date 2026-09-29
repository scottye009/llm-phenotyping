
SELECT inc.person_id,
       MIN(inc.index_date) AS index_date
FROM (
  /* -----------------------------------------------
     RULE A: Diagnosis-only
     ≥1 Inpatient OR ≥2 Outpatient/ER T2DM diagnoses
     on distinct dates ≥30 days apart
     ----------------------------------------------- */
  SELECT z.person_id,
         MIN(z.cond_date) AS index_date
  FROM (
    /* Inpatient: visit_concept_id = 9201 */
    SELECT co.person_id, DATE(co.condition_start_date) AS cond_date
    FROM public.condition_occurrence co
    JOIN public.visit_occurrence vo
      ON vo.visit_occurrence_id = co.visit_occurrence_id
    WHERE (co.condition_source_concept_id IN (
             SELECT concept_id FROM public.concept
             WHERE vocabulary_id IN ('ICD9CM','ICD10CM')
               AND (
                 (vocabulary_id='ICD10CM' AND concept_code LIKE 'E11%') OR
                 (vocabulary_id='ICD9CM'  AND (concept_code ~ '^250\\.[0-9]0$' OR concept_code ~ '^250\\.[0-9]2$'))
               )
           )
           OR co.condition_concept_id IN (
             SELECT DISTINCT cr.concept_id_2
             FROM public.concept_relationship cr
             JOIN public.concept c1 ON c1.concept_id = cr.concept_id_1
             WHERE cr.relationship_id = 'Maps to'
               AND c1.vocabulary_id IN ('ICD9CM','ICD10CM')
               AND (
                 (c1.vocabulary_id='ICD10CM' AND c1.concept_code LIKE 'E11%') OR
                 (c1.vocabulary_id='ICD9CM'  AND (c1.concept_code ~ '^250\\.[0-9]0$' OR c1.concept_code ~ '^250\\.[0-9]2$'))
               )
           )
          )
      AND vo.visit_concept_id = 9201

    UNION ALL

    /* Outpatient/ER: visit_concept_id IN (9202,9203), need ≥2 dates ≥30d apart */
    SELECT d1.person_id, d1.cond_date
    FROM (
      SELECT co.person_id, DATE(co.condition_start_date) AS cond_date
      FROM public.condition_occurrence co
      JOIN public.visit_occurrence vo
        ON vo.visit_occurrence_id = co.visit_occurrence_id
      WHERE (co.condition_source_concept_id IN (
               SELECT concept_id FROM public.concept
               WHERE vocabulary_id IN ('ICD9CM','ICD10CM')
                 AND (
                   (vocabulary_id='ICD10CM' AND concept_code LIKE 'E11%') OR
                   (vocabulary_id='ICD9CM'  AND (concept_code ~ '^250\\.[0-9]0$' OR concept_code ~ '^250\\.[0-9]2$'))
                 )
             )
             OR co.condition_concept_id IN (
               SELECT DISTINCT cr.concept_id_2
               FROM public.concept_relationship cr
               JOIN public.concept c1 ON c1.concept_id = cr.concept_id_1
               WHERE cr.relationship_id = 'Maps to'
                 AND c1.vocabulary_id IN ('ICD9CM','ICD10CM')
                 AND (
                   (c1.vocabulary_id='ICD10CM' AND c1.concept_code LIKE 'E11%') OR
                   (c1.vocabulary_id='ICD9CM'  AND (c1.concept_code ~ '^250\\.[0-9]0$' OR c1.concept_code ~ '^250\\.[0-9]2$'))
                 )
             )
            )
        AND vo.visit_concept_id IN (9202,9203)
      GROUP BY co.person_id, DATE(co.condition_start_date)
    ) d1
    JOIN (
      SELECT co.person_id, DATE(co.condition_start_date) AS cond_date
      FROM public.condition_occurrence co
      JOIN public.visit_occurrence vo
        ON vo.visit_occurrence_id = co.visit_occurrence_id
      WHERE (co.condition_source_concept_id IN (
               SELECT concept_id FROM public.concept
               WHERE vocabulary_id IN ('ICD9CM','ICD10CM')
                 AND (
                   (vocabulary_id='ICD10CM' AND concept_code LIKE 'E11%') OR
                   (vocabulary_id='ICD9CM'  AND (concept_code ~ '^250\\.[0-9]0$' OR concept_code ~ '^250\\.[0-9]2$'))
                 )
             )
             OR co.condition_concept_id IN (
               SELECT DISTINCT cr.concept_id_2
               FROM public.concept_relationship cr
               JOIN public.concept c1 ON c1.concept_id = cr.concept_id_1
               WHERE cr.relationship_id = 'Maps to'
                 AND c1.vocabulary_id IN ('ICD9CM','ICD10CM')
                 AND (
                   (c1.vocabulary_id='ICD10CM' AND c1.concept_code LIKE 'E11%') OR
                   (c1.vocabulary_id='ICD9CM'  AND (c1.concept_code ~ '^250\\.[0-9]0$' OR c1.concept_code ~ '^250\\.[0-9]2$'))
                 )
             )
            )
        AND vo.visit_concept_id IN (9202,9203)
      GROUP BY co.person_id, DATE(co.condition_start_date)
    ) d2
      ON d1.person_id = d2.person_id
     AND d2.cond_date >= (d1.cond_date + INTERVAL '30 day')
  ) z
  GROUP BY z.person_id

  UNION ALL

  /* -----------------------------------------------
     RULE B: Diagnosis + Lab (any abnormal A1c/FPG/OGTT/RPG)
     ----------------------------------------------- */
  SELECT d.person_id,
         LEAST(MIN(d.dx_date), MIN(l.meas_date)) AS index_date
  FROM (
    SELECT co.person_id, DATE(co.condition_start_date) AS dx_date
    FROM public.condition_occurrence co
    WHERE co.condition_source_concept_id IN (
            SELECT concept_id FROM public.concept
            WHERE vocabulary_id IN ('ICD9CM','ICD10CM')
              AND (
                (vocabulary_id='ICD10CM' AND concept_code LIKE 'E11%') OR
                (vocabulary_id='ICD9CM'  AND (concept_code ~ '^250\\.[0-9]0$' OR concept_code ~ '^250\\.[0-9]2$'))
              )
          )
       OR co.condition_concept_id IN (
            SELECT DISTINCT cr.concept_id_2
            FROM public.concept_relationship cr
            JOIN public.concept c1 ON c1.concept_id = cr.concept_id_1
            WHERE cr.relationship_id='Maps to'
              AND c1.vocabulary_id IN ('ICD9CM','ICD10CM')
              AND (
                (c1.vocabulary_id='ICD10CM' AND c1.concept_code LIKE 'E11%') OR
                (c1.vocabulary_id='ICD9CM'  AND (c1.concept_code ~ '^250\\.[0-9]0$' OR c1.concept_code ~ '^250\\.[0-9]2$'))
              )
          )
  ) d
  JOIN (
    SELECT m.person_id, DATE(m.measurement_date) AS meas_date
    FROM public.measurement m
    LEFT JOIN public.concept u ON u.concept_id = m.unit_concept_id
    WHERE m.value_as_number IS NOT NULL
      AND (
        /* HbA1c ≥6.5% or ≥48 mmol/mol */
        (m.measurement_concept_id IN (SELECT concept_id FROM public.concept WHERE vocabulary_id='LOINC' AND concept_code IN ('4548-4','17856-6','41995-2','4549-2'))
         AND (
              ((u.concept_name ILIKE '%percent%' OR COALESCE(m.unit_source_value,'') ILIKE '%percent%' OR COALESCE(m.unit_source_value,'') = '%') AND m.value_as_number >= 6.5)
           OR ((u.concept_name ILIKE '%mmol/mol%' OR COALESCE(m.unit_source_value,'') ILIKE '%mmol/mol%') AND m.value_as_number >= 48)
         )
        )
        OR
        /* FPG ≥126 mg/dL or ≥7.0 mmol/L */
        (m.measurement_concept_id IN (SELECT concept_id FROM public.concept WHERE vocabulary_id='LOINC' AND concept_code IN ('1558-6','14771-0','35217-9'))
         AND (
              ((u.concept_name ILIKE '%mg/dl%' OR COALESCE(m.unit_source_value,'') ILIKE '%mg/dl%') AND m.value_as_number >= 126)
           OR ((u.concept_name ILIKE '%mmol/l%' OR COALESCE(m.unit_source_value,'') ILIKE '%mmol/l%') AND m.value_as_number >= 7.0)
         )
        )
        OR
        /* 2h OGTT ≥200 mg/dL or ≥11.1 mmol/L */
        (m.measurement_concept_id IN (SELECT concept_id FROM public.concept WHERE vocabulary_id='LOINC' AND concept_code IN ('20436-2','1518-0','14763-7'))
         AND (
              ((u.concept_name ILIKE '%mg/dl%' OR COALESCE(m.unit_source_value,'') ILIKE '%mg/dl%') AND m.value_as_number >= 200)
           OR ((u.concept_name ILIKE '%mmol/l%' OR COALESCE(m.unit_source_value,'') ILIKE '%mmol/l%') AND m.value_as_number >= 11.1)
         )
        )
        OR
        /* Random glucose ≥200 mg/dL or ≥11.1 mmol/L */
        (m.measurement_concept_id IN (SELECT concept_id FROM public.concept WHERE vocabulary_id='LOINC' AND concept_code IN ('2345-7','2339-0'))
         AND (
              ((u.concept_name ILIKE '%mg/dl%' OR COALESCE(m.unit_source_value,'') ILIKE '%mg/dl%') AND m.value_as_number >= 200)
           OR ((u.concept_name ILIKE '%mmol/l%' OR COALESCE(m.unit_source_value,'') ILIKE '%mmol/l%') AND m.value_as_number >= 11.1)
         )
        )
      )
  ) l
    ON l.person_id = d.person_id
  GROUP BY d.person_id

  UNION ALL

  /* -----------------------------------------------
     RULE C: Medication-only (non-insulin antihyperglycemics)
     ≥2 fills ≥30 days apart
     ----------------------------------------------- */
  SELECT rx.person_id,
         MIN(rx.first_fill) AS index_date
  FROM (
    SELECT de.person_id,
           MIN(DATE(de.drug_exposure_start_date)) AS first_fill,
           MAX(DATE(de.drug_exposure_start_date)) AS last_fill,
           COUNT(*) AS n_fills
    FROM public.drug_exposure de
    WHERE de.drug_concept_id IN (
      /* All descendants of the following RxNorm ingredients/brands */
      SELECT DISTINCT COALESCE(ca.descendant_concept_id, s.concept_id)
      FROM (
        SELECT concept_id
        FROM public.concept
        WHERE vocabulary_id='RxNorm'
          AND (
            (concept_class_id='Ingredient' AND lower(concept_name) IN (
              /* Biguanide */        'metformin',
              /* Sulfonylureas */    'glipizide','glyburide','glimepiride',
              /* Meglitinides */     'repaglinide','nateglinide',
              /* TZDs */             'pioglitazone','rosiglitazone',
              /* DPP-4 */            'sitagliptin','saxagliptin','linagliptin','alogliptin',
              /* SGLT2 */            'empagliflozin','canagliflozin','dapagliflozin','ertugliflozin',
              /* GLP-1 RA */         'semaglutide','liraglutide','dulaglutide','exenatide','lixisenatide',
              /* Others often used */ 'acarbose','miglitol','colesevelam','bromocriptine','tirzepatide'
            ))
            OR (concept_class_id='Brand Name' AND lower(concept_name) IN (
              /* Biguanide brands */    'glucophage','glumetza','fortamet','riomet',
              /* SUs brands */          'glucotrol','diabeta','micronase','glynase','amaryl',
              /* Meglitinides brands */ 'prandin','starlix',
              /* TZD brands */          'actos','avandia',
              /* DPP-4 brands */        'januvia','onglyza','tradjenta','nesina',
              /* SGLT2 brands */        'jardiance','invokana','farxiga','steglatro',
              /* GLP-1 RA brands */     'ozempic','rybelsus','victoza','trulicity','byetta','bydureon','adlyxin',
              /* Others brands */       'precose','glyset','welchol','cycloset','mounjaro'
            ))
          )
      ) s
      LEFT JOIN public.concept_ancestor ca ON ca.ancestor_concept_id = s.concept_id
    )
    GROUP BY de.person_id
    HAVING COUNT(*) >= 2
       AND (MAX(DATE(de.drug_exposure_start_date)) - MIN(DATE(de.drug_exposure_start_date))) >= 30
  ) rx
  GROUP BY rx.person_id

  UNION ALL

  /* -----------------------------------------------
     RULE D: Lab + Medication within ±365d
     ----------------------------------------------- */
  SELECT lm.person_id,
         MIN(lm.index_dt) AS index_date
  FROM (
    SELECT l.person_id,
           LEAST(l.meas_date, d.rx_date) AS index_dt
    FROM (
      SELECT m.person_id, DATE(m.measurement_date) AS meas_date
      FROM public.measurement m
      LEFT JOIN public.concept u ON u.concept_id = m.unit_concept_id
      WHERE m.value_as_number IS NOT NULL
        AND (
          (m.measurement_concept_id IN (SELECT concept_id FROM public.concept WHERE vocabulary_id='LOINC' AND concept_code IN ('4548-4','17856-6','41995-2','4549-2'))
           AND (
                ((u.concept_name ILIKE '%percent%' OR COALESCE(m.unit_source_value,'') ILIKE '%percent%' OR COALESCE(m.unit_source_value,'') = '%') AND m.value_as_number >= 6.5)
             OR ((u.concept_name ILIKE '%mmol/mol%' OR COALESCE(m.unit_source_value,'') ILIKE '%mmol/mol%') AND m.value_as_number >= 48)
           )
          )
          OR
          (m.measurement_concept_id IN (SELECT concept_id FROM public.concept WHERE vocabulary_id='LOINC' AND concept_code IN ('1558-6','14771-0','35217-9'))
           AND (
                ((u.concept_name ILIKE '%mg/dl%' OR COALESCE(m.unit_source_value,'') ILIKE '%mg/dl%') AND m.value_as_number >= 126)
             OR ((u.concept_name ILIKE '%mmol/l%' OR COALESCE(m.unit_source_value,'') ILIKE '%mmol/l%') AND m.value_as_number >= 7.0)
           )
          )
          OR
          (m.measurement_concept_id IN (SELECT concept_id FROM public.concept WHERE vocabulary_id='LOINC' AND concept_code IN ('20436-2','1518-0','14763-7'))
           AND (
                ((u.concept_name ILIKE '%mg/dl%' OR COALESCE(m.unit_source_value,'') ILIKE '%mg/dl%') AND m.value_as_number >= 200)
             OR ((u.concept_name ILIKE '%mmol/l%' OR COALESCE(m.unit_source_value,'') ILIKE '%mmol/l%') AND m.value_as_number >= 11.1)
           )
          )
          OR
          (m.measurement_concept_id IN (SELECT concept_id FROM public.concept WHERE vocabulary_id='LOINC' AND concept_code IN ('2345-7','2339-0'))
           AND (
                ((u.concept_name ILIKE '%mg/dl%' OR COALESCE(m.unit_source_value,'') ILIKE '%mg/dl%') AND m.value_as_number >= 200)
             OR ((u.concept_name ILIKE '%mmol/l%' OR COALESCE(m.unit_source_value,'') ILIKE '%mmol/l%') AND m.value_as_number >= 11.1)
           )
          )
        )
    ) l
    JOIN (
      SELECT de.person_id, DATE(de.drug_exposure_start_date) AS rx_date
      FROM public.drug_exposure de
      WHERE de.drug_concept_id IN (
        SELECT DISTINCT COALESCE(ca.descendant_concept_id, s.concept_id)
        FROM (
          SELECT concept_id
          FROM public.concept
          WHERE vocabulary_id='RxNorm'
            AND (
              (concept_class_id='Ingredient' AND lower(concept_name) IN (
                'metformin','glipizide','glyburide','glimepiride',
                'repaglinide','nateglinide',
                'pioglitazone','rosiglitazone',
                'sitagliptin','saxagliptin','linagliptin','alogliptin',
                'empagliflozin','canagliflozin','dapagliflozin','ertugliflozin',
                'semaglutide','liraglutide','dulaglutide','exenatide','lixisenatide',
                'acarbose','miglitol','colesevelam','bromocriptine','tirzepatide'
              ))
              OR (concept_class_id='Brand Name' AND lower(concept_name) IN (
                'glucophage','glumetza','fortamet','riomet',
                'glucotrol','diabeta','micronase','glynase','amaryl',
                'prandin','starlix',
                'actos','avandia',
                'januvia','onglyza','tradjenta','nesina',
                'jardiance','invokana','farxiga','steglatro',
                'ozempic','rybelsus','victoza','trulicity','byetta','bydureon','adlyxin',
                'precose','glyset','welchol','cycloset','mounjaro'
              ))
            )
        ) s
        LEFT JOIN public.concept_ancestor ca ON ca.ancestor_concept_id = s.concept_id
      )
    ) d
      ON d.person_id = l.person_id
     AND d.rx_date BETWEEN (l.meas_date - INTERVAL '365 days') AND (l.meas_date + INTERVAL '365 days')
  ) lm
  GROUP BY lm.person_id
) inc
JOIN public.person p ON p.person_id = inc.person_id
LEFT JOIN (
  /* ---------------- Exclusions ---------------- */

  /* Secondary diabetes ever (ICD10 E08/E09/E13; ICD9 249.*) */
  SELECT DISTINCT co.person_id
  FROM public.condition_occurrence co
  WHERE co.condition_source_concept_id IN (
          SELECT concept_id FROM public.concept
          WHERE (vocabulary_id='ICD10CM' AND (concept_code LIKE 'E08%' OR concept_code LIKE 'E09%' OR concept_code LIKE 'E13%'))
             OR (vocabulary_id='ICD9CM'  AND concept_code LIKE '249%')
        )
     OR co.condition_concept_id IN (
          SELECT DISTINCT cr.concept_id_2
          FROM public.concept_relationship cr
          JOIN public.concept c1 ON c1.concept_id = cr.concept_id_1
          WHERE cr.relationship_id='Maps to'
            AND (
              (c1.vocabulary_id='ICD10CM' AND (c1.concept_code LIKE 'E08%' OR c1.concept_code LIKE 'E09%' OR c1.concept_code LIKE 'E13%'))
              OR (c1.vocabulary_id='ICD9CM'  AND c1.concept_code LIKE '249%')
            )
        )
) sec ON sec.person_id = inc.person_id
LEFT JOIN (
  /* Type 1 only: any T1 and no T2 ever */
  SELECT t1.person_id
  FROM (
    SELECT DISTINCT person_id
    FROM public.condition_occurrence
    WHERE condition_source_concept_id IN (
            SELECT concept_id FROM public.concept
            WHERE (vocabulary_id='ICD10CM' AND concept_code LIKE 'E10%')
               OR (vocabulary_id='ICD9CM'  AND (concept_code ~ '^250\\.[0-9]1$' OR concept_code ~ '^250\\.[0-9]3$'))
          )
       OR condition_concept_id IN (
            SELECT DISTINCT cr.concept_id_2
            FROM public.concept_relationship cr
            JOIN public.concept c1 ON c1.concept_id = cr.concept_id_1
            WHERE cr.relationship_id='Maps to'
              AND (
                (c1.vocabulary_id='ICD10CM' AND c1.concept_code LIKE 'E10%')
                OR (c1.vocabulary_id='ICD9CM'  AND (c1.concept_code ~ '^250\\.[0-9]1$' OR c1.concept_code ~ '^250\\.[0-9]3$'))
              )
          )
  ) t1
  LEFT JOIN (
    SELECT DISTINCT person_id
    FROM public.condition_occurrence
    WHERE condition_source_concept_id IN (
            SELECT concept_id FROM public.concept
            WHERE (vocabulary_id='ICD10CM' AND concept_code LIKE 'E11%')
               OR (vocabulary_id='ICD9CM'  AND (concept_code ~ '^250\\.[0-9]0$' OR concept_code ~ '^250\\.[0-9]2$'))
          )
       OR condition_concept_id IN (
            SELECT DISTINCT cr.concept_id_2
            FROM public.concept_relationship cr
            JOIN public.concept c1 ON c1.concept_id = cr.concept_id_1
            WHERE cr.relationship_id='Maps to'
              AND (
                (c1.vocabulary_id='ICD10CM' AND c1.concept_code LIKE 'E11%')
                OR (c1.vocabulary_id='ICD9CM'  AND (c1.concept_code ~ '^250\\.[0-9]0$' OR c1.concept_code ~ '^250\\.[0-9]2$'))
              )
          )
  ) t2 ON t2.person_id = t1.person_id
  WHERE t2.person_id IS NULL
) t1only ON t1only.person_id = inc.person_id
LEFT JOIN (
  /* Gestational diabetes ±270 days around index */
  SELECT g.person_id, DATE(co.condition_start_date) AS g_date
  FROM public.condition_occurrence co
  JOIN (
    SELECT concept_id FROM public.concept
    WHERE (vocabulary_id='ICD10CM' AND concept_code LIKE 'O24.4%')
       OR (vocabulary_id='ICD9CM'  AND concept_code LIKE '648.8%')
  ) gsrc ON gsrc.concept_id = co.condition_source_concept_id
  /* mapping to standard also acceptable, but source is sufficient for time window check */
) gest ON gest.person_id = inc.person_id
WHERE sec.person_id IS NULL
  AND t1only.person_id IS NULL
  AND (
        gest.person_id IS NULL
        OR NOT EXISTS (
             SELECT 1
             FROM (
               SELECT MIN(inc2.index_date) AS idx
               FROM (
                 SELECT person_id, MIN(index_date) AS index_date
                 FROM (
                   SELECT * FROM (SELECT inc.person_id, inc.index_date) AS tmp WHERE inc.person_id = gest.person_id
                 ) q
                 GROUP BY person_id
               ) inc2
             ) x
             WHERE gest.g_date BETWEEN (x.idx - INTERVAL '270 days') AND (x.idx + INTERVAL '270 days')
        )
      )
  AND DATE_PART('year', AGE(MIN(inc.index_date), p.birth_datetime)) >= 18
GROUP BY inc.person_id;



