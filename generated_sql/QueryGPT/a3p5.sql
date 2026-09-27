WITH
-- Non-insulin glucose-lowering medications: generic and brand names.
t2d_drug_terms(term) AS (
    VALUES
        ('metformin'), ('glucophage'), ('fortamet'), ('glumetza'), ('riomet'),
        ('glipizide'), ('glucotrol'),
        ('glimepiride'), ('amaryl'),
        ('glyburide'), ('glibenclamide'), ('diabeta'), ('micronase'), ('glynase'),
        ('repaglinide'), ('prandin'),
        ('nateglinide'), ('starlix'),
        ('pioglitazone'), ('actos'),
        ('rosiglitazone'), ('avandia'),
        ('sitagliptin'), ('januvia'),
        ('saxagliptin'), ('onglyza'),
        ('linagliptin'), ('tradjenta'),
        ('alogliptin'), ('nesina'),
        ('empagliflozin'), ('jardiance'),
        ('canagliflozin'), ('invokana'),
        ('dapagliflozin'), ('farxiga'),
        ('ertugliflozin'), ('steglatro'),
        ('liraglutide'), ('victoza'),
        ('semaglutide'), ('ozempic'), ('rybelsus'),
        ('dulaglutide'), ('trulicity'),
        ('exenatide'), ('byetta'), ('bydureon'),
        ('lixisenatide'), ('adlyxin'),
        ('tirzepatide'), ('mounjaro'),
        ('acarbose'), ('precose'),
        ('miglitol'), ('glyset'),
        ('janumet'), ('jentadueto'), ('kombiglyze'), ('kazano'),
        ('synjardy'), ('glyxambi'), ('xigduo'), ('invokamet'),
        ('qtern'), ('segluromet'), ('steglujan'), ('trijardy'),
        ('glucovance'), ('metaglip'), ('duetact'), ('avandamet'), ('avandaryl')
),

-- Normalize diagnosis source fields.
condition_text AS (
    SELECT
        person_id,
        COALESCE(
            condition_start_date,
            CAST(condition_start_datetime AS DATE)
        ) AS event_date,
        UPPER(COALESCE(condition_source_value, '')) AS source_code,
        LOWER(
            CONCAT_WS(
                ' ',
                COALESCE(condition_source_concept_name, ''),
                COALESCE(condition_concept_name, '')
            )
        ) AS source_name
    FROM condition_occurrence
),

-- Direct type 2 diabetes diagnosis evidence.
t2d_diagnosis_dates AS (
    SELECT DISTINCT
        person_id,
        event_date
    FROM condition_text
    WHERE event_date IS NOT NULL
      AND (
          -- ICD-10-CM E11.*
          regexp_matches(
              source_code,
              '(^|[^A-Z0-9])E11([.]?[0-9A-Z]+)?([^A-Z0-9]|$)'
          )

          -- ICD-9-CM 250.x0 or 250.x2
          OR regexp_matches(
              source_code,
              '(^|[^0-9])250[.]?[0-9][02]([^0-9]|$)'
          )

          -- Source-name fallback when source coding is incomplete.
          OR source_name ILIKE '%type 2 diabetes%'
          OR source_name ILIKE '%type ii diabetes%'
          OR source_name ILIKE '%type 2 dm%'
          OR source_name ILIKE '%t2dm%'
          OR source_name ILIKE '%non-insulin-dependent diabetes%'
          OR source_name ILIKE '%non insulin dependent diabetes%'
          OR source_name ILIKE '%niddm%'
      )
      AND source_name NOT ILIKE '%family history%'
      AND source_name NOT ILIKE '%rule out%'
),

-- Competing diabetes diagnoses used to prevent false-positive lab-only phenotypes.
competing_diabetes_dates AS (
    SELECT DISTINCT
        person_id,
        event_date
    FROM condition_text
    WHERE event_date IS NOT NULL
      AND (
          -- ICD-10-CM: type 1, secondary, drug-induced, other, or gestational.
          regexp_matches(
              source_code,
              '(^|[^A-Z0-9])(E10|E08|E09|E13|O24)([.]?[0-9A-Z]+)?([^A-Z0-9]|$)'
          )

          -- ICD-9-CM type I diabetes: 250.x1 or 250.x3.
          OR regexp_matches(
              source_code,
              '(^|[^0-9])250[.]?[0-9][13]([^0-9]|$)'
          )

          OR source_name ILIKE '%type 1 diabetes%'
          OR source_name ILIKE '%type i diabetes%'
          OR source_name ILIKE '%t1dm%'
          OR source_name ILIKE '%gestational diabetes%'
          OR source_name ILIKE '%secondary diabetes%'
          OR source_name ILIKE '%drug-induced diabetes%'
      )
),

-- Prepare measurement source text and units.
measurement_text AS (
    SELECT
        person_id,
        COALESCE(
            measurement_date,
            CAST(measurement_datetime AS DATE)
        ) AS event_date,
        value_as_number,
        LOWER(
            CONCAT_WS(
                ' ',
                COALESCE(measurement_source_value, ''),
                COALESCE(measurement_concept_name, '')
            )
        ) AS test_name,
        LOWER(
            CONCAT_WS(
                ' ',
                COALESCE(unit_source_value, ''),
                COALESCE(unit_concept_name, '')
            )
        ) AS unit_name
    FROM measurement
    WHERE value_as_number IS NOT NULL
),

-- Abnormal diabetes-related laboratory dates.
abnormal_lab_dates AS (
    SELECT DISTINCT
        person_id,
        event_date
    FROM measurement_text
    WHERE event_date IS NOT NULL
      AND (
          -- HbA1c >= 6.5% or >= 48 mmol/mol.
          (
              (
                  test_name ILIKE '%hba1c%'
                  OR test_name ILIKE '%hemoglobin a1c%'
                  OR test_name ILIKE '%haemoglobin a1c%'
                  OR test_name ILIKE '%glycated hemoglobin%'
                  OR test_name ILIKE '%glycated haemoglobin%'
                  OR test_name ILIKE '%glycohemoglobin%'
                  OR test_name ILIKE '%4548-4%'
                  OR test_name ILIKE '%17856-6%'
              )
              AND (
                  (
                      value_as_number >= 48
                      AND unit_name ILIKE '%mmol/mol%'
                  )
                  OR (
                      value_as_number >= 6.5
                      AND (
                          unit_name = ''
                          OR unit_name = '%'
                          OR unit_name ILIKE '%percent%'
                      )
                  )
              )
          )

          -- Fasting glucose >= 126 mg/dL or >= 7.0 mmol/L.
          OR (
              test_name ILIKE '%glucose%'
              AND (
                  test_name ILIKE '%fasting%'
                  OR test_name ILIKE '%fasted%'
                  OR test_name ILIKE '%1558-6%'
              )
              AND (
                  (
                      value_as_number >= 126
                      AND (
                          unit_name = ''
                          OR unit_name ILIKE '%mg/dl%'
                          OR unit_name ILIKE '%mg per dl%'
                      )
                  )
                  OR (
                      value_as_number >= 7.0
                      AND unit_name ILIKE '%mmol/l%'
                  )
              )
          )

          -- Random, plasma, or two-hour glucose >= 200 mg/dL or >= 11.1 mmol/L.
          OR (
              test_name ILIKE '%glucose%'
              AND (
                  (
                      value_as_number >= 200
                      AND (
                          unit_name = ''
                          OR unit_name ILIKE '%mg/dl%'
                          OR unit_name ILIKE '%mg per dl%'
                      )
                  )
                  OR (
                      value_as_number >= 11.1
                      AND unit_name ILIKE '%mmol/l%'
                  )
              )
          )
      )
),

-- Prepare medication text from available source-oriented fields.
drug_text AS (
    SELECT
        person_id,
        COALESCE(
            drug_exposure_start_date,
            CAST(drug_exposure_start_datetime AS DATE)
        ) AS event_date,
        LOWER(
            CONCAT_WS(
                ' ',
                COALESCE(drug_source_value, ''),
                COALESCE(drug_concept_name, ''),
                COALESCE(drug_source_concept_code, '')
            )
        ) AS medication_name
    FROM drug_exposure
),

-- Medication dates are corroborating evidence, not sufficient alone.
t2d_medication_dates AS (
    SELECT DISTINCT
        d.person_id,
        d.event_date
    FROM drug_text d
    WHERE d.event_date IS NOT NULL
      AND EXISTS (
          SELECT 1
          FROM t2d_drug_terms t
          WHERE d.medication_name ILIKE '%' || t.term || '%'
      )
),

-- Positive observation text can support incomplete diagnosis coding.
t2d_observation_dates AS (
    SELECT DISTINCT
        person_id,
        COALESCE(
            observation_date,
            CAST(observation_datetime AS DATE)
        ) AS event_date
    FROM observation
    WHERE COALESCE(
              observation_date,
              CAST(observation_datetime AS DATE)
          ) IS NOT NULL
      AND (
          LOWER(
              CONCAT_WS(
                  ' ',
                  COALESCE(observation_source_value, ''),
                  COALESCE(value_as_string, ''),
                  COALESCE(value_source_value, ''),
                  COALESCE(observation_concept_name, '')
              )
          ) ILIKE '%type 2 diabetes%'
          OR LOWER(
              CONCAT_WS(
                  ' ',
                  COALESCE(observation_source_value, ''),
                  COALESCE(value_as_string, ''),
                  COALESCE(value_source_value, ''),
                  COALESCE(observation_concept_name, '')
              )
          ) ILIKE '%type ii diabetes%'
          OR LOWER(
              CONCAT_WS(
                  ' ',
                  COALESCE(observation_source_value, ''),
                  COALESCE(value_as_string, ''),
                  COALESCE(value_source_value, ''),
                  COALESCE(observation_concept_name, '')
              )
          ) ILIKE '%t2dm%'
          OR LOWER(
              CONCAT_WS(
                  ' ',
                  COALESCE(observation_source_value, ''),
                  COALESCE(value_as_string, ''),
                  COALESCE(value_source_value, ''),
                  COALESCE(observation_concept_name, '')
              )
          ) ILIKE '%niddm%'
      )
      AND LOWER(
              CONCAT_WS(
                  ' ',
                  COALESCE(observation_source_value, ''),
                  COALESCE(value_as_string, ''),
                  COALESCE(value_source_value, ''),
                  COALESCE(observation_concept_name, '')
              )
          ) NOT ILIKE '%family history%'
      AND LOWER(
              CONCAT_WS(
                  ' ',
                  COALESCE(observation_source_value, ''),
                  COALESCE(value_as_string, ''),
                  COALESCE(value_source_value, ''),
                  COALESCE(observation_concept_name, '')
              )
          ) NOT ILIKE '%rule out%'
      AND LOWER(
              CONCAT_WS(
                  ' ',
                  COALESCE(observation_source_value, ''),
                  COALESCE(value_as_string, ''),
                  COALESCE(value_source_value, ''),
                  COALESCE(observation_concept_name, '')
              )
          ) NOT ILIKE '%denies%'
),

-- Count distinct evidence dates by person.
diagnosis_counts AS (
    SELECT person_id, COUNT(DISTINCT event_date) AS t2d_diagnosis_dates
    FROM t2d_diagnosis_dates
    GROUP BY person_id
),
competing_counts AS (
    SELECT person_id, COUNT(DISTINCT event_date) AS competing_diabetes_dates
    FROM competing_diabetes_dates
    GROUP BY person_id
),
lab_counts AS (
    SELECT person_id, COUNT(DISTINCT event_date) AS abnormal_lab_dates
    FROM abnormal_lab_dates
    GROUP BY person_id
),
medication_counts AS (
    SELECT person_id, COUNT(DISTINCT event_date) AS t2d_medication_dates
    FROM t2d_medication_dates
    GROUP BY person_id
),
observation_counts AS (
    SELECT person_id, COUNT(DISTINCT event_date) AS t2d_observation_dates
    FROM t2d_observation_dates
    GROUP BY person_id
),

-- Use the person view as the final patient universe.
person_ids AS (
    SELECT DISTINCT person_id
    FROM person
),

person_evidence AS (
    SELECT
        p.person_id,
        COALESCE(d.t2d_diagnosis_dates, 0) AS t2d_diagnosis_dates,
        COALESCE(c.competing_diabetes_dates, 0) AS competing_diabetes_dates,
        COALESCE(l.abnormal_lab_dates, 0) AS abnormal_lab_dates,
        COALESCE(m.t2d_medication_dates, 0) AS t2d_medication_dates,
        COALESCE(o.t2d_observation_dates, 0) AS t2d_observation_dates
    FROM person_ids p
    LEFT JOIN diagnosis_counts d USING (person_id)
    LEFT JOIN competing_counts c USING (person_id)
    LEFT JOIN lab_counts l USING (person_id)
    LEFT JOIN medication_counts m USING (person_id)
    LEFT JOIN observation_counts o USING (person_id)
)

SELECT person_id
FROM person_evidence
WHERE
    (
        -- Repeated direct diagnosis evidence.
        t2d_diagnosis_dates >= 2

        -- One direct diagnosis plus corroboration.
        OR (
            t2d_diagnosis_dates >= 1
            AND (
                abnormal_lab_dates >= 1
                OR t2d_medication_dates >= 1
                OR t2d_observation_dates >= 1
            )
        )

        -- Repeated abnormal labs plus a non-insulin medication.
        OR (
            abnormal_lab_dates >= 2
            AND t2d_medication_dates >= 1
        )

        -- Repeated positive observation text plus clinical corroboration.
        OR (
            t2d_observation_dates >= 2
            AND (
                abnormal_lab_dates >= 1
                OR t2d_medication_dates >= 1
            )
        )
    )

    -- Prevent competing-diagnosis-only cases from qualifying through labs or drugs.
    AND NOT (
        competing_diabetes_dates >= 1
        AND t2d_diagnosis_dates = 0
    )
ORDER BY person_id;