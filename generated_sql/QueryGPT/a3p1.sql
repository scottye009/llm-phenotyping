WITH
/* Normalize diagnosis source codes and retain source diagnosis text. */
condition_base AS (
    SELECT
        cohort,
        person_id,
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
            COALESCE(condition_source_concept_name, '') || ' ' ||
            COALESCE(condition_concept_name, '')
        ) AS diagnosis_text
    FROM condition_occurrence
),

/* Explicit type 2 diabetes diagnoses: ICD-10-CM E11% or ICD-9-CM 250.x0 / 250.x2. */
t2dm_diagnosis_dates AS (
    SELECT DISTINCT
        cohort,
        person_id,
        event_date
    FROM condition_base
    WHERE event_date IS NOT NULL
      AND (
          regexp_matches(code_norm, '^E11')
          OR regexp_matches(code_norm, '^250[0-9][02]$')
          OR diagnosis_text ILIKE '%type 2 diabetes%'
          OR diagnosis_text ILIKE '%type ii diabetes%'
          OR diagnosis_text ILIKE '%diabetes mellitus type 2%'
          OR diagnosis_text ILIKE '%diabetes mellitus type ii%'
          OR diagnosis_text ILIKE '%non-insulin-dependent diabetes%'
          OR diagnosis_text ILIKE '%non insulin dependent diabetes%'
      )
),

/* Competing diabetes diagnoses used for conservative exclusions. */
competing_diabetes_dates AS (
    SELECT DISTINCT
        cohort,
        person_id,
        event_date
    FROM condition_base
    WHERE event_date IS NOT NULL
      AND (
          /* Type 1 diabetes. */
          regexp_matches(code_norm, '^E10')
          OR regexp_matches(code_norm, '^250[0-9][13]$')
          OR diagnosis_text ILIKE '%type 1 diabetes%'
          OR diagnosis_text ILIKE '%type i diabetes%'
          OR diagnosis_text ILIKE '%diabetes mellitus type 1%'
          OR diagnosis_text ILIKE '%diabetes mellitus type i%'
          OR diagnosis_text ILIKE '%juvenile diabetes%'

          /* Secondary or other specified diabetes. */
          OR regexp_matches(code_norm, '^E08')
          OR regexp_matches(code_norm, '^E09')
          OR regexp_matches(code_norm, '^E13')
          OR regexp_matches(code_norm, '^249')
          OR diagnosis_text ILIKE '%secondary diabetes%'

          /* Gestational diabetes. */
          OR regexp_matches(code_norm, '^O24')
          OR diagnosis_text ILIKE '%gestational diabetes%'
      )
),

/* Normalize laboratory source names and units. */
measurement_base AS (
    SELECT
        cohort,
        person_id,
        COALESCE(
            CAST(measurement_date AS DATE),
            CAST(measurement_datetime AS DATE)
        ) AS event_date,
        LOWER(
            COALESCE(measurement_source_value, '') || ' ' ||
            COALESCE(measurement_concept_name, '')
        ) AS measurement_text,
        LOWER(
            COALESCE(unit_source_value, '') || ' ' ||
            COALESCE(unit_concept_name, '')
        ) AS unit_text,
        value_as_number
    FROM measurement
    WHERE value_as_number IS NOT NULL
),

/* Diabetes-range HbA1c and glucose results. */
abnormal_lab_dates AS (
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
                  measurement_text ILIKE '%hba1c%'
                  OR measurement_text ILIKE '%hb a1c%'
                  OR measurement_text ILIKE '%hemoglobin a1c%'
                  OR measurement_text ILIKE '%haemoglobin a1c%'
                  OR measurement_text ILIKE '%glycated hemoglobin%'
                  OR measurement_text ILIKE '%glycated haemoglobin%'
                  OR measurement_text ILIKE '%glycohemoglobin%'
              )
              AND (
                  (
                      value_as_number >= 6.5
                      AND value_as_number <= 25
                      AND (
                          unit_text ILIKE '%%%'
                          OR unit_text ILIKE '%percent%'
                          OR unit_text = ''
                      )
                  )
                  OR (
                      value_as_number >= 48
                      AND unit_text ILIKE '%mmol/mol%'
                  )
              )
          )

          /* Fasting glucose >= 126 mg/dL or >= 7.0 mmol/L. */
          OR (
              measurement_text ILIKE '%glucose%'
              AND (
                  measurement_text ILIKE '%fasting%'
                  OR measurement_text ILIKE '%fasted%'
                  OR measurement_text ILIKE '%fbs%'
              )
              AND (
                  (
                      value_as_number >= 126
                      AND (
                          unit_text ILIKE '%mg/dl%'
                          OR unit_text ILIKE '%mg dl%'
                      )
                  )
                  OR (
                      value_as_number >= 7.0
                      AND unit_text ILIKE '%mmol/l%'
                  )
              )
          )

          /* Two-hour oral glucose tolerance test >= 200 mg/dL or >= 11.1 mmol/L. */
          OR (
              measurement_text ILIKE '%glucose%'
              AND (
                  measurement_text ILIKE '%2 hour%'
                  OR measurement_text ILIKE '%2-hour%'
                  OR measurement_text ILIKE '%two hour%'
                  OR measurement_text ILIKE '%ogtt%'
                  OR measurement_text ILIKE '%oral glucose tolerance%'
              )
              AND (
                  (
                      value_as_number >= 200
                      AND (
                          unit_text ILIKE '%mg/dl%'
                          OR unit_text ILIKE '%mg dl%'
                      )
                  )
                  OR (
                      value_as_number >= 11.1
                      AND unit_text ILIKE '%mmol/l%'
                  )
              )
          )

          /* Random or unspecified glucose >= 200 mg/dL or >= 11.1 mmol/L. */
          OR (
              measurement_text ILIKE '%glucose%'
              AND measurement_text NOT ILIKE '%fasting%'
              AND measurement_text NOT ILIKE '%fasted%'
              AND measurement_text NOT ILIKE '%fbs%'
              AND (
                  (
                      value_as_number >= 200
                      AND (
                          unit_text ILIKE '%mg/dl%'
                          OR unit_text ILIKE '%mg dl%'
                      )
                  )
                  OR (
                      value_as_number >= 11.1
                      AND unit_text ILIKE '%mmol/l%'
                  )
              )
          )
      )
),

/* Generic and brand-name non-insulin antihyperglycemic medications. */
antihyperglycemic_keywords(keyword) AS (
    VALUES
        ('metformin'), ('glucophage'), ('fortamet'), ('glumetza'), ('riomet'),
        ('glipizide'), ('glucotrol'),
        ('glyburide'), ('glibenclamide'), ('diabeta'), ('micronase'), ('glynase'),
        ('glimepiride'), ('amaryl'),
        ('chlorpropamide'), ('tolbutamide'),
        ('pioglitazone'), ('actos'),
        ('rosiglitazone'), ('avandia'),
        ('sitagliptin'), ('januvia'),
        ('saxagliptin'), ('onglyza'),
        ('linagliptin'), ('tradjenta'),
        ('alogliptin'), ('nesina'),
        ('repaglinide'), ('prandin'),
        ('nateglinide'), ('starlix'),
        ('acarbose'), ('precose'),
        ('miglitol'), ('glyset'),
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
        ('tirzepatide'), ('mounjaro')
),

/* Match medication source fields and exclude insulin-containing products. */
non_insulin_medication_dates AS (
    SELECT DISTINCT
        d.cohort,
        d.person_id,
        COALESCE(
            CAST(d.drug_exposure_start_date AS DATE),
            CAST(d.drug_exposure_start_datetime AS DATE)
        ) AS event_date
    FROM drug_exposure AS d
    WHERE COALESCE(
              CAST(d.drug_exposure_start_date AS DATE),
              CAST(d.drug_exposure_start_datetime AS DATE)
          ) IS NOT NULL
      AND LOWER(
              COALESCE(d.drug_source_value, '') || ' ' ||
              COALESCE(d.drug_concept_name, '') || ' ' ||
              COALESCE(d.drug_source_concept_code, '')
          ) NOT ILIKE '%insulin%'
      AND EXISTS (
          SELECT 1
          FROM antihyperglycemic_keywords AS k
          WHERE LOWER(
                    COALESCE(d.drug_source_value, '') || ' ' ||
                    COALESCE(d.drug_concept_name, '') || ' ' ||
                    COALESCE(d.drug_source_concept_code, '')
                ) ILIKE '%' || k.keyword || '%'
      )
),

/* Aggregate evidence using distinct calendar dates. */
t2dm_diagnosis_summary AS (
    SELECT
        cohort,
        person_id,
        COUNT(DISTINCT event_date) AS t2dm_diagnosis_date_count
    FROM t2dm_diagnosis_dates
    GROUP BY cohort, person_id
),

competing_diabetes_summary AS (
    SELECT
        cohort,
        person_id,
        COUNT(DISTINCT event_date) AS competing_diabetes_date_count
    FROM competing_diabetes_dates
    GROUP BY cohort, person_id
),

abnormal_lab_summary AS (
    SELECT
        cohort,
        person_id,
        COUNT(DISTINCT event_date) AS abnormal_lab_date_count
    FROM abnormal_lab_dates
    GROUP BY cohort, person_id
),

medication_summary AS (
    SELECT
        cohort,
        person_id,
        COUNT(DISTINCT event_date) AS medication_date_count
    FROM non_insulin_medication_dates
    GROUP BY cohort, person_id
),

/* Build one evidence row per patient and cohort. */
patient_evidence AS (
    SELECT DISTINCT
        p.cohort,
        p.person_id,
        COALESCE(dx.t2dm_diagnosis_date_count, 0) AS t2dm_diagnosis_date_count,
        COALESCE(cx.competing_diabetes_date_count, 0) AS competing_diabetes_date_count,
        COALESCE(lab.abnormal_lab_date_count, 0) AS abnormal_lab_date_count,
        COALESCE(med.medication_date_count, 0) AS medication_date_count
    FROM person AS p
    LEFT JOIN t2dm_diagnosis_summary AS dx
        ON dx.cohort = p.cohort
       AND dx.person_id = p.person_id
    LEFT JOIN competing_diabetes_summary AS cx
        ON cx.cohort = p.cohort
       AND cx.person_id = p.person_id
    LEFT JOIN abnormal_lab_summary AS lab
        ON lab.cohort = p.cohort
       AND lab.person_id = p.person_id
    LEFT JOIN medication_summary AS med
        ON med.cohort = p.cohort
       AND med.person_id = p.person_id
)

/* Return patients satisfying the final type 2 diabetes phenotype. */
SELECT DISTINCT
    person_id
FROM patient_evidence
WHERE
    (
        /* Rule 1: repeated explicit type 2 diabetes diagnoses. */
        t2dm_diagnosis_date_count >= 2

        /* Rule 2: type 2 diagnosis plus diabetes-range laboratory result. */
        OR (
            t2dm_diagnosis_date_count >= 1
            AND abnormal_lab_date_count >= 1
        )

        /* Rule 3: type 2 diagnosis plus non-insulin antihyperglycemic medication. */
        OR (
            t2dm_diagnosis_date_count >= 1
            AND medication_date_count >= 1
        )

        /* Rule 4: repeated abnormal labs plus non-insulin medication. */
        OR (
            abnormal_lab_date_count >= 2
            AND medication_date_count >= 1
        )
    )
    /* Exclude competing diabetes phenotypes unless explicit T2DM evidence exists. */
    AND NOT (
        competing_diabetes_date_count >= 1
        AND t2dm_diagnosis_date_count = 0
    )
ORDER BY person_id;