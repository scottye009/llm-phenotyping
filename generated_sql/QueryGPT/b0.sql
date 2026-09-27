/* ============================================================
   OMOP CDM TYPE 2 DIABETES PHENOTYPE
   Dialect: PostgreSQL
   Cohort type: prevalent adult T2DM cases

   Diagnosis source codes:
     T2DM:
       ICD10CM E11.*
       ICD9CM  250.x0 OR 250.x2

     T1DM:
       ICD10CM E10.*
       ICD9CM  250.x1 OR 250.x3

     Secondary or other specified diabetes:
       ICD10CM E08.* OR E09.* OR E13.*
       ICD9CM  249.*

     Gestational diabetes:
       ICD10CM O24.4*
       ICD9CM  648.8*

   Non-insulin medication concepts include generic and brand names:
     metformin (Glucophage, Glumetza, Fortamet, Riomet)
     glipizide (Glucotrol)
     glyburide (DiaBeta, Glynase, Micronase)
     glimepiride (Amaryl)
     chlorpropamide, tolbutamide, tolazamide
     repaglinide (Prandin)
     nateglinide (Starlix)
     pioglitazone (Actos)
     rosiglitazone (Avandia)
     acarbose (Precose)
     miglitol (Glyset)
     sitagliptin (Januvia)
     saxagliptin (Onglyza)
     linagliptin (Tradjenta)
     alogliptin (Nesina)
     canagliflozin (Invokana)
     dapagliflozin (Farxiga)
     empagliflozin (Jardiance)
     ertugliflozin (Steglatro)
     exenatide (Byetta, Bydureon)
     liraglutide (Victoza)
     dulaglutide (Trulicity)
     semaglutide (Ozempic, Rybelsus)
     lixisenatide (Adlyxin)
     tirzepatide (Mounjaro)
     colesevelam (Welchol)
     bromocriptine (Cycloset)

   Notes:
     - Medication evidence is supportive, not sufficient on its own.
     - Random glucose is used only with temporally related symptoms
       or hyperglycemic crisis.
     - Materialize and version-control the resolved concept sets
       after local vocabulary validation for production deployment.
   ============================================================ */

SELECT
    phenotype.person_id,
    'T2DM_CASE' AS phenotype_status
FROM
(
    SELECT
        features.*,

        CASE
            WHEN features.t1dm_dx_date_count >= 2
             AND features.t1dm_dx_date_count > features.t2dm_dx_date_count
             AND features.has_non_insulin_dm_drug = 0
            THEN 1
            ELSE 0
        END AS has_strong_t1dm_pattern

    FROM
    (
        SELECT
            p.person_id,

            /* -----------------------------------------------
               Observation history
               ----------------------------------------------- */
            CASE
                WHEN EXISTS
                (
                    SELECT 1
                    FROM observation_period op
                    WHERE op.person_id = p.person_id
                      AND op.observation_period_end_date
                          >= op.observation_period_start_date
                             + INTERVAL '365 days'
                )
                THEN 1
                ELSE 0
            END AS has_minimum_observation_history,

            /* -----------------------------------------------
               T2DM diagnoses: ICD10CM E11.* or ICD9CM 250.x0/x2
               ----------------------------------------------- */
            (
                SELECT COUNT(DISTINCT co.condition_start_date)
                FROM condition_occurrence co
                JOIN concept source_dx
                  ON source_dx.concept_id = co.condition_source_concept_id
                WHERE co.person_id = p.person_id
                  AND
                  (
                      (
                          source_dx.vocabulary_id = 'ICD10CM'
                          AND
                          (
                              source_dx.concept_code = 'E11'
                              OR source_dx.concept_code LIKE 'E11.%'
                          )
                      )
                      OR
                      (
                          source_dx.vocabulary_id = 'ICD9CM'
                          AND source_dx.concept_code LIKE '250.__'
                          AND RIGHT(source_dx.concept_code, 1) IN ('0', '2')
                      )
                  )
            ) AS t2dm_dx_date_count,

            /* -----------------------------------------------
               T1DM diagnoses: ICD10CM E10.* or ICD9CM 250.x1/x3
               ----------------------------------------------- */
            (
                SELECT COUNT(DISTINCT co.condition_start_date)
                FROM condition_occurrence co
                JOIN concept source_dx
                  ON source_dx.concept_id = co.condition_source_concept_id
                WHERE co.person_id = p.person_id
                  AND
                  (
                      (
                          source_dx.vocabulary_id = 'ICD10CM'
                          AND
                          (
                              source_dx.concept_code = 'E10'
                              OR source_dx.concept_code LIKE 'E10.%'
                          )
                      )
                      OR
                      (
                          source_dx.vocabulary_id = 'ICD9CM'
                          AND source_dx.concept_code LIKE '250.__'
                          AND RIGHT(source_dx.concept_code, 1) IN ('1', '3')
                      )
                  )
            ) AS t1dm_dx_date_count,

            /* -----------------------------------------------
               Gestational diabetes
               ----------------------------------------------- */
            CASE
                WHEN EXISTS
                (
                    SELECT 1
                    FROM condition_occurrence co
                    JOIN concept source_dx
                      ON source_dx.concept_id = co.condition_source_concept_id
                    WHERE co.person_id = p.person_id
                      AND
                      (
                          (
                              source_dx.vocabulary_id = 'ICD10CM'
                              AND
                              (
                                  source_dx.concept_code = 'O24.4'
                                  OR source_dx.concept_code LIKE 'O24.4%'
                              )
                          )
                          OR
                          (
                              source_dx.vocabulary_id = 'ICD9CM'
                              AND source_dx.concept_code LIKE '648.8%'
                          )
                      )
                )
                THEN 1
                ELSE 0
            END AS has_gestational_dm_dx,

            /* -----------------------------------------------
               Secondary or other specified diabetes
               ----------------------------------------------- */
            CASE
                WHEN EXISTS
                (
                    SELECT 1
                    FROM condition_occurrence co
                    JOIN concept source_dx
                      ON source_dx.concept_id = co.condition_source_concept_id
                    WHERE co.person_id = p.person_id
                      AND
                      (
                          (
                              source_dx.vocabulary_id = 'ICD10CM'
                              AND
                              (
                                  source_dx.concept_code = 'E08'
                                  OR source_dx.concept_code LIKE 'E08.%'
                                  OR source_dx.concept_code = 'E09'
                                  OR source_dx.concept_code LIKE 'E09.%'
                                  OR source_dx.concept_code = 'E13'
                                  OR source_dx.concept_code LIKE 'E13.%'
                              )
                          )
                          OR
                          (
                              source_dx.vocabulary_id = 'ICD9CM'
                              AND source_dx.concept_code LIKE '249.%'
                          )
                      )
                )
                THEN 1
                ELSE 0
            END AS has_secondary_or_other_dm_dx,

            /* -----------------------------------------------
               Non-insulin antihyperglycemic medication evidence

               Ingredient descendants capture generic products and
               combination products. Brand-name matching is retained
               explicitly to satisfy source-vocabulary variation.
               ----------------------------------------------- */
            CASE
                WHEN EXISTS
                (
                    SELECT 1
                    FROM drug_exposure de
                    WHERE de.person_id = p.person_id
                      AND de.drug_concept_id IN
                      (
                          SELECT ca.descendant_concept_id
                          FROM concept_ancestor ca
                          WHERE ca.ancestor_concept_id IN
                          (
                              SELECT drug_seed.concept_id
                              FROM concept drug_seed
                              WHERE drug_seed.vocabulary_id = 'RxNorm'
                                AND drug_seed.invalid_reason IS NULL
                                AND
                                (
                                    LOWER(drug_seed.concept_name) IN
                                    (
                                        'metformin',
                                        'glipizide',
                                        'glyburide',
                                        'glimepiride',
                                        'chlorpropamide',
                                        'tolbutamide',
                                        'tolazamide',
                                        'repaglinide',
                                        'nateglinide',
                                        'pioglitazone',
                                        'rosiglitazone',
                                        'acarbose',
                                        'miglitol',
                                        'sitagliptin',
                                        'saxagliptin',
                                        'linagliptin',
                                        'alogliptin',
                                        'canagliflozin',
                                        'dapagliflozin',
                                        'empagliflozin',
                                        'ertugliflozin',
                                        'exenatide',
                                        'liraglutide',
                                        'dulaglutide',
                                        'semaglutide',
                                        'lixisenatide',
                                        'tirzepatide',
                                        'colesevelam',
                                        'bromocriptine'
                                    )
                                    OR LOWER(drug_seed.concept_name) LIKE '%glucophage%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%glumetza%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%fortamet%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%riomet%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%glucotrol%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%diabeta%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%glynase%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%micronase%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%amaryl%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%prandin%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%starlix%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%actos%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%avandia%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%precose%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%glyset%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%januvia%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%onglyza%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%tradjenta%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%nesina%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%invokana%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%farxiga%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%jardiance%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%steglatro%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%byetta%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%bydureon%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%victoza%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%trulicity%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%ozempic%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%rybelsus%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%adlyxin%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%mounjaro%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%welchol%'
                                    OR LOWER(drug_seed.concept_name) LIKE '%cycloset%'
                                )
                          )
                      )
                )
                THEN 1
                ELSE 0
            END AS has_non_insulin_dm_drug,

            /* -----------------------------------------------
               Confirmatory laboratory evidence

               Random glucose is deliberately excluded here.
               It is evaluated separately with symptom linkage.
               ----------------------------------------------- */
            (
                SELECT COUNT(DISTINCT normalized_labs.measurement_date)
                FROM
                (
                    SELECT
                        m.measurement_date,

                        CASE
                            WHEN
                            (
                                LOWER(mc.concept_name) LIKE '%hemoglobin a1c%'
                                OR LOWER(mc.concept_name) LIKE '%glycated hemoglobin%'
                            )
                            AND
                            (
                                CASE
                                    WHEN LOWER(COALESCE(uc.concept_name, m.unit_source_value, ''))
                                         IN ('percent', '%')
                                    THEN m.value_as_number

                                    WHEN LOWER(COALESCE(uc.concept_name, m.unit_source_value, ''))
                                         IN ('millimole per mole', 'mmol/mol')
                                    THEN m.value_as_number / 10.929

                                    ELSE NULL
                                END
                            ) >= 6.5
                            THEN 1

                            WHEN
                                LOWER(mc.concept_name) LIKE '%glucose%'
                                AND
                                (
                                    LOWER(mc.concept_name) LIKE '%fasting%'
                                    OR LOWER(mc.concept_name) LIKE '%pre-meal%'
                                    OR LOWER(mc.concept_name) LIKE '%pre-breakfast%'
                                )
                                AND
                                (
                                    CASE
                                        WHEN LOWER(COALESCE(uc.concept_name, m.unit_source_value, ''))
                                             IN ('milligram per deciliter', 'mg/dl')
                                        THEN m.value_as_number

                                        WHEN LOWER(COALESCE(uc.concept_name, m.unit_source_value, ''))
                                             IN ('millimole per liter', 'mmol/l')
                                        THEN m.value_as_number * 18.0

                                        ELSE NULL
                                    END
                                ) >= 126
                            THEN 1

                            WHEN
                                LOWER(mc.concept_name) LIKE '%glucose%'
                                AND
                                (
                                    LOWER(mc.concept_name) LIKE '%2 hour%'
                                    OR LOWER(mc.concept_name) LIKE '%2-hour%'
                                    OR LOWER(mc.concept_name) LIKE '%two hour%'
                                )
                                AND
                                (
                                    LOWER(mc.concept_name) LIKE '%tolerance%'
                                    OR LOWER(mc.concept_name) LIKE '%oral glucose%'
                                    OR LOWER(mc.concept_name) LIKE '%post dose%'
                                )
                                AND
                                (
                                    CASE
                                        WHEN LOWER(COALESCE(uc.concept_name, m.unit_source_value, ''))
                                             IN ('milligram per deciliter', 'mg/dl')
                                        THEN m.value_as_number

                                        WHEN LOWER(COALESCE(uc.concept_name, m.unit_source_value, ''))
                                             IN ('millimole per liter', 'mmol/l')
                                        THEN m.value_as_number * 18.0

                                        ELSE NULL
                                    END
                                ) >= 200
                            THEN 1

                            ELSE 0
                        END AS is_confirmatory_abnormal_lab

                    FROM measurement m
                    JOIN concept mc
                      ON mc.concept_id = m.measurement_concept_id
                    LEFT JOIN concept uc
                      ON uc.concept_id = m.unit_concept_id
                    WHERE m.person_id = p.person_id
                      AND m.value_as_number IS NOT NULL
                ) normalized_labs
                WHERE normalized_labs.is_confirmatory_abnormal_lab = 1
            ) AS confirmatory_lab_date_count,

            /* -----------------------------------------------
               Symptomatic random glucose:
               random glucose >= 200 mg/dL or >= 11.1 mmol/L
               plus symptom or crisis within +/- 30 days.

               Symptoms:
                 ICD10CM R35.*, R63.1, R63.4
                 ICD9CM  788.42, 783.5, 783.21

               Hyperglycemic crisis:
                 ICD10CM E10.0*, E10.1*, E11.0*, E11.1*,
                         E13.0*, E13.1*
                 ICD9CM  250.1*, 250.2*
               ----------------------------------------------- */
            CASE
                WHEN EXISTS
                (
                    SELECT 1
                    FROM measurement random_glucose
                    JOIN concept random_glucose_name
                      ON random_glucose_name.concept_id
                       = random_glucose.measurement_concept_id
                    LEFT JOIN concept random_glucose_unit
                      ON random_glucose_unit.concept_id
                       = random_glucose.unit_concept_id
                    WHERE random_glucose.person_id = p.person_id
                      AND random_glucose.value_as_number IS NOT NULL
                      AND LOWER(random_glucose_name.concept_name) LIKE '%glucose%'
                      AND LOWER(random_glucose_name.concept_name) LIKE '%random%'
                      AND
                      (
                          CASE
                              WHEN LOWER
                                   (
                                       COALESCE
                                       (
                                           random_glucose_unit.concept_name,
                                           random_glucose.unit_source_value,
                                           ''
                                       )
                                   ) IN ('milligram per deciliter', 'mg/dl')
                              THEN random_glucose.value_as_number

                              WHEN LOWER
                                   (
                                       COALESCE
                                       (
                                           random_glucose_unit.concept_name,
                                           random_glucose.unit_source_value,
                                           ''
                                       )
                                   ) IN ('millimole per liter', 'mmol/l')
                              THEN random_glucose.value_as_number * 18.0

                              ELSE NULL
                          END
                      ) >= 200
                      AND EXISTS
                      (
                          SELECT 1
                          FROM condition_occurrence symptom
                          JOIN concept symptom_source
                            ON symptom_source.concept_id
                             = symptom.condition_source_concept_id
                          WHERE symptom.person_id = p.person_id
                            AND symptom.condition_start_date
                                BETWEEN random_glucose.measurement_date
                                        - INTERVAL '30 days'
                                    AND random_glucose.measurement_date
                                        + INTERVAL '30 days'
                            AND
                            (
                                (
                                    symptom_source.vocabulary_id = 'ICD10CM'
                                    AND
                                    (
                                        symptom_source.concept_code = 'R35'
                                        OR symptom_source.concept_code LIKE 'R35.%'
                                        OR symptom_source.concept_code = 'R63.1'
                                        OR symptom_source.concept_code = 'R63.4'
                                        OR symptom_source.concept_code LIKE 'E10.0%'
                                        OR symptom_source.concept_code LIKE 'E10.1%'
                                        OR symptom_source.concept_code LIKE 'E11.0%'
                                        OR symptom_source.concept_code LIKE 'E11.1%'
                                        OR symptom_source.concept_code LIKE 'E13.0%'
                                        OR symptom_source.concept_code LIKE 'E13.1%'
                                    )
                                )
                                OR
                                (
                                    symptom_source.vocabulary_id = 'ICD9CM'
                                    AND
                                    (
                                        symptom_source.concept_code = '788.42'
                                        OR symptom_source.concept_code = '783.5'
                                        OR symptom_source.concept_code = '783.21'
                                        OR symptom_source.concept_code LIKE '250.1%'
                                        OR symptom_source.concept_code LIKE '250.2%'
                                    )
                                )
                            )
                      )
                )
                THEN 1
                ELSE 0
            END AS has_symptomatic_random_glucose

        FROM person p
        WHERE p.year_of_birth IS NOT NULL
          AND p.year_of_birth <= EXTRACT(YEAR FROM CURRENT_DATE) - 18
    ) features
) phenotype
WHERE phenotype.has_minimum_observation_history = 1

  AND
  (
      /* Path A: repeated T2DM diagnoses */
      phenotype.t2dm_dx_date_count >= 2

      OR

      /* Path B: T2DM diagnosis plus laboratory evidence */
      (
          phenotype.t2dm_dx_date_count >= 1
          AND phenotype.confirmatory_lab_date_count >= 1
      )

      OR

      /* Path C: T2DM diagnosis plus non-insulin medication */
      (
          phenotype.t2dm_dx_date_count >= 1
          AND phenotype.has_non_insulin_dm_drug = 1
      )

      OR

      /* Path D: non-insulin medication plus confirmed labs */
      (
          phenotype.has_non_insulin_dm_drug = 1
          AND phenotype.confirmatory_lab_date_count >= 2
      )

      OR

      /* Path E: symptomatic random glucose plus T2DM support */
      (
          phenotype.has_symptomatic_random_glucose = 1
          AND
          (
              phenotype.t2dm_dx_date_count >= 1
              OR phenotype.has_non_insulin_dm_drug = 1
          )
      )
  )

  /* Exclude gestational-only diabetes */
  AND NOT
  (
      phenotype.has_gestational_dm_dx = 1
      AND phenotype.t2dm_dx_date_count = 0
  )

  /* Exclude secondary-only or other-specified-only diabetes */
  AND NOT
  (
      phenotype.has_secondary_or_other_dm_dx = 1
      AND phenotype.t2dm_dx_date_count = 0
  )

  /* Exclude a strong T1DM pattern */
  AND phenotype.has_strong_t1dm_pattern = 0;