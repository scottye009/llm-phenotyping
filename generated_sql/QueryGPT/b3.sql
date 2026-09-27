WITH
/* -------------------------------------------------------------------------
   1. Normalize diagnosis source fields.
   Preserve cohort because person_id may not be globally unique.
   ------------------------------------------------------------------------- */
condition_base AS (
    SELECT
        cohort,
        person_id,
        condition_occurrence_id,
        COALESCE(
            CAST(condition_start_date AS DATE),
            CAST(condition_start_datetime AS DATE)
        ) AS event_date,

        UPPER(
            regexp_replace(
                COALESCE(condition_source_value, ''),
                '[^A-Za-z0-9]',
                '',
                'g'
            )
        ) AS code_norm,

        LOWER(
            CONCAT_WS(
                ' ',
                COALESCE(condition_source_value, ''),
                COALESCE(condition_source_concept_name, ''),
                COALESCE(condition_concept_name, '')
            )
        ) AS diagnosis_text
    FROM condition_occurrence
),

condition_flags AS (
    SELECT
        cohort,
        person_id,
        event_date,

        (
            /* ICD-10-CM E11.* with or without a vocabulary prefix. */
            regexp_matches(
                code_norm,
                '^(ICD10CM|ICD10)?E11[0-9A-Z]*$'
            )

            /* ICD-9-CM 250.x0 or 250.x2. */
            OR regexp_matches(
                code_norm,
                '^(ICD9CM|ICD9)?250[0-9][02]$'
            )

            /* Explicit source-text fallback. */
            OR diagnosis_text ILIKE '%type 2 diabetes%'
            OR diagnosis_text ILIKE '%type ii diabetes%'
            OR diagnosis_text ILIKE '%type 2 dm%'
            OR diagnosis_text ILIKE '%diabetes mellitus type 2%'
            OR diagnosis_text ILIKE '%diabetes mellitus type ii%'
            OR diagnosis_text ILIKE '%non-insulin-dependent diabetes%'
            OR diagnosis_text ILIKE '%non insulin dependent diabetes%'
            OR diagnosis_text ILIKE '%t2dm%'
            OR diagnosis_text ILIKE '%niddm%'
        )
        AND diagnosis_text NOT ILIKE '%family history%'
        AND diagnosis_text NOT ILIKE '%rule out%'
        AND diagnosis_text NOT ILIKE '%ruled out%'
        AND diagnosis_text NOT ILIKE '%screening%'
        AS is_t2d,

        (
            /* Type 1, secondary, drug-induced, or other specified diabetes. */
            regexp_matches(
                code_norm,
                '^(ICD10CM|ICD10)?E10[0-9A-Z]*$'
            )
            OR regexp_matches(
                code_norm,
                '^(ICD10CM|ICD10)?E08[0-9A-Z]*$'
            )
            OR regexp_matches(
                code_norm,
                '^(ICD10CM|ICD10)?E09[0-9A-Z]*$'
            )
            OR regexp_matches(
                code_norm,
                '^(ICD10CM|ICD10)?E13[0-9A-Z]*$'
            )

            /* ICD-9-CM type 1 diabetes: 250.x1 or 250.x3. */
            OR regexp_matches(
                code_norm,
                '^(ICD9CM|ICD9)?250[0-9][13]$'
            )

            OR diagnosis_text ILIKE '%type 1 diabetes%'
            OR diagnosis_text ILIKE '%type i diabetes%'
            OR diagnosis_text ILIKE '%diabetes mellitus type 1%'
            OR diagnosis_text ILIKE '%insulin-dependent diabetes%'
            OR diagnosis_text ILIKE '%insulin dependent diabetes%'
            OR diagnosis_text ILIKE '%t1dm%'
            OR diagnosis_text ILIKE '%secondary diabetes%'
            OR diagnosis_text ILIKE '%drug-induced diabetes%'
            OR diagnosis_text ILIKE '%drug induced diabetes%'
        )
        AND diagnosis_text NOT ILIKE '%family history%'
        AND diagnosis_text NOT ILIKE '%rule out%'
        AND diagnosis_text NOT ILIKE '%ruled out%'
        AS is_non_gestational_competing_diabetes,

        (
            regexp_matches(
                code_norm,
                '^(ICD10CM|ICD10)?O24[0-9A-Z]*$'
            )
            OR diagnosis_text ILIKE '%gestational diabetes%'
        )
        AND diagnosis_text NOT ILIKE '%family history%'
        AND diagnosis_text NOT ILIKE '%rule out%'
        AND diagnosis_text NOT ILIKE '%ruled out%'
        AS is_gestational_diabetes
    FROM condition_base
),

t2d_diagnosis_dates AS (
    SELECT DISTINCT
        cohort,
        person_id,
        event_date
    FROM condition_flags
    WHERE event_date IS NOT NULL
      AND is_t2d
),

non_gestational_competing_dates AS (
    SELECT DISTINCT
        cohort,
        person_id,
        event_date
    FROM condition_flags
    WHERE event_date IS NOT NULL
      AND is_non_gestational_competing_diabetes
),

gestational_diabetes_dates AS (
    SELECT DISTINCT
        cohort,
        person_id,
        event_date
    FROM condition_flags
    WHERE event_date IS NOT NULL
      AND is_gestational_diabetes
),

/* -------------------------------------------------------------------------
   2. Normalize measurement source fields.
   Strong lab evidence is separated from supportive random-glucose evidence.
   ------------------------------------------------------------------------- */
measurement_base AS (
    SELECT
        cohort,
        person_id,
        COALESCE(
            CAST(measurement_date AS DATE),
            CAST(measurement_datetime AS DATE)
        ) AS event_date,

        LOWER(
            CONCAT_WS(
                ' ',
                COALESCE(measurement_source_value, ''),
                COALESCE(measurement_concept_name, '')
            )
        ) AS test_text,

        LOWER(
            CONCAT_WS(
                ' ',
                COALESCE(unit_source_value, ''),
                COALESCE(unit_concept_name, '')
            )
        ) AS unit_text,

        value_as_number
    FROM measurement
    WHERE value_as_number IS NOT NULL
),

strong_lab_dates AS (
    SELECT DISTINCT
        cohort,
        person_id,
        event_date
    FROM measurement_base
    WHERE event_date IS NOT NULL
      AND (
          /* HbA1c >= 6.5% or >= 48 mmol/mol. */
          (
              (
                  test_text ILIKE '%hba1c%'
                  OR test_text ILIKE '%hb a1c%'
                  OR test_text ILIKE '%hemoglobin a1c%'
                  OR test_text ILIKE '%haemoglobin a1c%'
                  OR test_text ILIKE '%glycated hemoglobin%'
                  OR test_text ILIKE '%glycated haemoglobin%'
                  OR test_text ILIKE '%glycohemoglobin%'
                  OR test_text ILIKE '%glycosylated hemoglobin%'
              )
              AND (
                  (
                      (
                          unit_text = ''
                          OR strpos(unit_text, '%') > 0
                          OR unit_text ILIKE '%percent%'
                      )
                      AND value_as_number >= 6.5
                      AND value_as_number <= 25
                  )
                  OR (
                      (
                          unit_text ILIKE '%mmol/mol%'
                          OR unit_text ILIKE '%mmol per mol%'
                      )
                      AND value_as_number >= 48
                      AND value_as_number <= 250
                  )
              )
          )

          /* Fasting plasma or blood glucose >= 126 mg/dL or >= 7.0 mmol/L. */
          OR (
              test_text ILIKE '%glucose%'
              AND (
                  test_text ILIKE '%fasting%'
                  OR test_text ILIKE '%fasted%'
                  OR test_text ILIKE '%fasting plasma%'
                  OR test_text ILIKE '%fpg%'
                  OR test_text ILIKE '%fbs%'
              )
              AND test_text NOT ILIKE '%urine%'
              AND test_text NOT ILIKE '%csf%'
              AND test_text NOT ILIKE '%fluid%'
              AND (
                  (
                      (
                          unit_text = ''
                          OR unit_text ILIKE '%mg/dl%'
                          OR unit_text ILIKE '%mg dl%'
                          OR unit_text ILIKE '%mg per dl%'
                          OR unit_text ILIKE '%mgdl%'
                      )
                      AND value_as_number >= 126
                      AND value_as_number <= 2000
                  )
                  OR (
                      (
                          unit_text ILIKE '%mmol/l%'
                          OR unit_text ILIKE '%mmol per l%'
                          OR unit_text ILIKE '%mmol l%'
                      )
                      AND value_as_number >= 7.0
                      AND value_as_number <= 100
                  )
              )
          )

          /* Two-hour OGTT glucose >= 200 mg/dL or >= 11.1 mmol/L. */
          OR (
              test_text ILIKE '%glucose%'
              AND (
                  test_text ILIKE '%ogtt%'
                  OR test_text ILIKE '%oral glucose tolerance%'
                  OR test_text ILIKE '%2 hour%'
                  OR test_text ILIKE '%2-hour%'
                  OR test_text ILIKE '%2 hr%'
                  OR test_text ILIKE '%two hour%'
                  OR test_text ILIKE '%120 min%'
                  OR test_text ILIKE '%post load%'
                  OR test_text ILIKE '%post-load%'
              )
              AND test_text NOT ILIKE '%urine%'
              AND test_text NOT ILIKE '%csf%'
              AND test_text NOT ILIKE '%fluid%'
              AND (
                  (
                      (
                          unit_text = ''
                          OR unit_text ILIKE '%mg/dl%'
                          OR unit_text ILIKE '%mg dl%'
                          OR unit_text ILIKE '%mg per dl%'
                          OR unit_text ILIKE '%mgdl%'
                      )
                      AND value_as_number >= 200
                      AND value_as_number <= 2000
                  )
                  OR (
                      (
                          unit_text ILIKE '%mmol/l%'
                          OR unit_text ILIKE '%mmol per l%'
                          OR unit_text ILIKE '%mmol l%'
                      )
                      AND value_as_number >= 11.1
                      AND value_as_number <= 100
                  )
              )
          )
      )
),

/* Explicitly labeled random or casual glucose is supportive, but not used
   alone as strong laboratory evidence because symptom context is incomplete. */
random_glucose_support_dates AS (
    SELECT DISTINCT
        cohort,
        person_id,
        event_date
    FROM measurement_base
    WHERE event_date IS NOT NULL
      AND test_text ILIKE '%glucose%'
      AND (
          test_text ILIKE '%random%'
          OR test_text ILIKE '%casual%'
      )
      AND test_text NOT ILIKE '%urine%'
      AND test_text NOT ILIKE '%csf%'
      AND test_text NOT ILIKE '%fluid%'
      AND (
          (
              (
                  unit_text = ''
                  OR unit_text ILIKE '%mg/dl%'
                  OR unit_text ILIKE '%mg dl%'
                  OR unit_text ILIKE '%mg per dl%'
                  OR unit_text ILIKE '%mgdl%'
              )
              AND value_as_number >= 200
              AND value_as_number <= 2000
          )
          OR (
              (
                  unit_text ILIKE '%mmol/l%'
                  OR unit_text ILIKE '%mmol per l%'
                  OR unit_text ILIKE '%mmol l%'
              )
              AND value_as_number >= 11.1
              AND value_as_number <= 100
          )
      )
),

supportive_lab_dates AS (
    SELECT cohort, person_id, event_date
    FROM strong_lab_dates

    UNION

    SELECT cohort, person_id, event_date
    FROM random_glucose_support_dates
),

/* -------------------------------------------------------------------------
   3. Normalize medications.
   These are corroborating signals only, not sufficient evidence alone.
   ------------------------------------------------------------------------- */
t2d_drug_terms(term) AS (
    VALUES
        ('metformin'), ('glucophage'), ('fortamet'), ('glumetza'), ('riomet'),
        ('glipizide'), ('glucotrol'),
        ('glimepiride'), ('amaryl'),
        ('glyburide'), ('glibenclamide'), ('diabeta'), ('micronase'), ('glynase'),
        ('chlorpropamide'), ('tolbutamide'),
        ('repaglinide'), ('prandin'),
        ('nateglinide'), ('starlix'),
        ('pioglitazone'), ('actos'),
        ('rosiglitazone'), ('avandia'),
        ('sitagliptin'), ('januvia'),
        ('saxagliptin'), ('onglyza'),
        ('linagliptin'), ('tradjenta'),
        ('alogliptin'), ('nesina'),
        ('empagliflozin'), ('jardiance'),
        ('dapagliflozin'), ('farxiga'), ('forxiga'),
        ('canagliflozin'), ('invokana'),
        ('ertugliflozin'), ('steglatro'),
        ('liraglutide'), ('victoza'),
        ('dulaglutide'), ('trulicity'),
        ('semaglutide'), ('ozempic'), ('rybelsus'),
        ('exenatide'), ('byetta'), ('bydureon'),
        ('lixisenatide'), ('adlyxin'),
        ('albiglutide'), ('tanzeum'),
        ('tirzepatide'), ('mounjaro'),
        ('acarbose'), ('precose'),
        ('miglitol'), ('glyset'),
        ('janumet'), ('jentadueto'), ('kombiglyze'), ('kazano'),
        ('synjardy'), ('glyxambi'), ('xigduo'), ('invokamet'),
        ('qtern'), ('segluromet'), ('steglujan'), ('trijardy'),
        ('glucovance'), ('metaglip'), ('duetact'), ('avandamet'), ('avandaryl')
),

drug_base AS (
    SELECT
        cohort,
        person_id,
        COALESCE(
            CAST(drug_exposure_start_date AS DATE),
            CAST(drug_exposure_start_datetime AS DATE)
        ) AS event_date,

        LOWER(
            CONCAT_WS(
                ' ',
                COALESCE(drug_source_value, ''),
                COALESCE(drug_concept_name, ''),
                COALESCE(drug_source_concept_code, '')
            )
        ) AS drug_text
    FROM drug_exposure
),

t2d_medication_dates AS (
    SELECT DISTINCT
        d.cohort,
        d.person_id,
        d.event_date
    FROM drug_base AS d
    WHERE d.event_date IS NOT NULL

      /* Prevent insulin-containing combination products from matching
         non-insulin drug terms such as lixisenatide. */
      AND d.drug_text NOT ILIKE '%insulin%'

      AND EXISTS (
          SELECT 1
          FROM t2d_drug_terms AS t
          WHERE d.drug_text ILIKE '%' || t.term || '%'
      )
),

/* -------------------------------------------------------------------------
   4. Positive observation text can support incomplete diagnosis coding.
   It is not treated as sufficient evidence by itself.
   ------------------------------------------------------------------------- */
observation_base AS (
    SELECT
        cohort,
        person_id,
        COALESCE(
            CAST(observation_date AS DATE),
            CAST(observation_datetime AS DATE)
        ) AS event_date,

        LOWER(
            CONCAT_WS(
                ' ',
                COALESCE(observation_source_value, ''),
                COALESCE(value_as_string, ''),
                COALESCE(value_source_value, ''),
                COALESCE(observation_concept_name, '')
            )
        ) AS observation_text
    FROM observation
),

t2d_observation_dates AS (
    SELECT DISTINCT
        cohort,
        person_id,
        event_date
    FROM observation_base
    WHERE event_date IS NOT NULL
      AND (
          observation_text ILIKE '%type 2 diabetes%'
          OR observation_text ILIKE '%type ii diabetes%'
          OR observation_text ILIKE '%type 2 dm%'
          OR observation_text ILIKE '%t2dm%'
          OR observation_text ILIKE '%niddm%'
      )
      AND observation_text NOT ILIKE '%family history%'
      AND observation_text NOT ILIKE '%rule out%'
      AND observation_text NOT ILIKE '%ruled out%'
      AND observation_text NOT ILIKE '%denies%'
      AND observation_text NOT ILIKE '%screening%'
      AND observation_text NOT ILIKE '%risk of%'
),

/* -------------------------------------------------------------------------
   5. Aggregate distinct evidence dates.
   ------------------------------------------------------------------------- */
t2d_diagnosis_summary AS (
    SELECT
        cohort,
        person_id,
        COUNT(DISTINCT event_date) AS t2d_diagnosis_dates
    FROM t2d_diagnosis_dates
    GROUP BY cohort, person_id
),

non_gestational_competing_summary AS (
    SELECT
        cohort,
        person_id,
        COUNT(DISTINCT event_date) AS non_gestational_competing_dates
    FROM non_gestational_competing_dates
    GROUP BY cohort, person_id
),

gestational_summary AS (
    SELECT
        cohort,
        person_id,
        COUNT(DISTINCT event_date) AS gestational_diabetes_dates
    FROM gestational_diabetes_dates
    GROUP BY cohort, person_id
),

strong_lab_summary AS (
    SELECT
        cohort,
        person_id,
        COUNT(DISTINCT event_date) AS strong_lab_dates
    FROM strong_lab_dates
    GROUP BY cohort, person_id
),

supportive_lab_summary AS (
    SELECT
        cohort,
        person_id,
        COUNT(DISTINCT event_date) AS supportive_lab_dates
    FROM supportive_lab_dates
    GROUP BY cohort, person_id
),

medication_summary AS (
    SELECT
        cohort,
        person_id,
        COUNT(DISTINCT event_date) AS t2d_medication_dates
    FROM t2d_medication_dates
    GROUP BY cohort, person_id
),

observation_summary AS (
    SELECT
        cohort,
        person_id,
        COUNT(DISTINCT event_date) AS t2d_observation_dates
    FROM t2d_observation_dates
    GROUP BY cohort, person_id
),

person_ids AS (
    SELECT DISTINCT
        cohort,
        person_id
    FROM person
),

person_evidence AS (
    SELECT
        p.cohort,
        p.person_id,

        COALESCE(d.t2d_diagnosis_dates, 0) AS t2d_diagnosis_dates,
        COALESCE(c.non_gestational_competing_dates, 0)
            AS non_gestational_competing_dates,
        COALESCE(g.gestational_diabetes_dates, 0)
            AS gestational_diabetes_dates,
        COALESCE(sl.strong_lab_dates, 0) AS strong_lab_dates,
        COALESCE(al.supportive_lab_dates, 0) AS supportive_lab_dates,
        COALESCE(m.t2d_medication_dates, 0) AS t2d_medication_dates,
        COALESCE(o.t2d_observation_dates, 0) AS t2d_observation_dates
    FROM person_ids AS p

    LEFT JOIN t2d_diagnosis_summary AS d
        ON d.cohort = p.cohort
       AND d.person_id = p.person_id

    LEFT JOIN non_gestational_competing_summary AS c
        ON c.cohort = p.cohort
       AND c.person_id = p.person_id

    LEFT JOIN gestational_summary AS g
        ON g.cohort = p.cohort
       AND g.person_id = p.person_id

    LEFT JOIN strong_lab_summary AS sl
        ON sl.cohort = p.cohort
       AND sl.person_id = p.person_id

    LEFT JOIN supportive_lab_summary AS al
        ON al.cohort = p.cohort
       AND al.person_id = p.person_id

    LEFT JOIN medication_summary AS m
        ON m.cohort = p.cohort
       AND m.person_id = p.person_id

    LEFT JOIN observation_summary AS o
        ON o.cohort = p.cohort
       AND o.person_id = p.person_id
),

classified AS (
    SELECT
        cohort,
        person_id,
        t2d_diagnosis_dates,
        non_gestational_competing_dates,
        gestational_diabetes_dates,
        strong_lab_dates,
        supportive_lab_dates,
        t2d_medication_dates,
        t2d_observation_dates,

        CASE
            /* Route 1: repeated explicit T2D diagnoses outweigh competing codes. */
            WHEN t2d_diagnosis_dates >= 2
             AND t2d_diagnosis_dates > non_gestational_competing_dates
                THEN 'repeated_t2d_diagnoses'

            /* Route 2: one explicit T2D diagnosis with corroborating evidence. */
            WHEN t2d_diagnosis_dates >= 1
             AND non_gestational_competing_dates = 0
             AND (
                 supportive_lab_dates >= 1
                 OR t2d_medication_dates >= 1
                 OR t2d_observation_dates >= 1
             )
                THEN 't2d_diagnosis_plus_support'

            /* Route 3: indirect inference requires repeated strong labs,
               medication support, and no competing diabetes classification. */
            WHEN strong_lab_dates >= 2
             AND t2d_medication_dates >= 1
             AND non_gestational_competing_dates = 0
             AND gestational_diabetes_dates = 0
                THEN 'repeated_strong_labs_plus_medication'

            /* Route 4: repeated positive observation text plus corroboration. */
            WHEN t2d_observation_dates >= 2
             AND (
                 strong_lab_dates >= 1
                 OR t2d_medication_dates >= 1
             )
             AND non_gestational_competing_dates = 0
             AND gestational_diabetes_dates = 0
                THEN 'repeated_t2d_observations_plus_support'

            ELSE NULL
        END AS phenotype_route
    FROM person_evidence
)

/* Keep evidence columns during validation. */
SELECT
    cohort,
    person_id,
    phenotype_route,
    t2d_diagnosis_dates,
    non_gestational_competing_dates,
    gestational_diabetes_dates,
    strong_lab_dates,
    supportive_lab_dates,
    t2d_medication_dates,
    t2d_observation_dates
FROM classified
WHERE phenotype_route IS NOT NULL
ORDER BY cohort, person_id;