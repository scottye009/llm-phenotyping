WITH
/* ICD9CM / ICD10CM source diagnosis concepts for type 2 diabetes.
   These are mapped to standard OMOP condition concepts before matching
   condition_occurrence.condition_concept_id. */
t2dm_icd_source AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND c.invalid_reason IS NULL
      AND (
          /* ICD10CM E11.* = Type 2 diabetes mellitus */
          (c.vocabulary_id = 'ICD10CM'
           AND replace(c.concept_code, '.', '') LIKE 'E11%')

          OR

          /* ICD9CM 250.x0 or 250.x2 = diabetes mellitus, type II or unspecified type,
             not stated as uncontrolled / uncontrolled */
          (c.vocabulary_id = 'ICD9CM'
           AND replace(c.concept_code, '.', '') ~ '^250[0-9][02]$')
      )
),

/* Standard condition concepts reached from ICD9CM / ICD10CM T2DM codes. */
t2dm_condition_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS condition_concept_id
    FROM t2dm_icd_source s
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = s.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL

    UNION

    /* Fallback for already-standard clinical condition concepts in synthetic OMOP. */
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Condition'
      AND c.standard_concept = 'S'
      AND c.invalid_reason IS NULL
      AND c.concept_name ~* 'type 2 diabetes|diabetes mellitus type 2|non.?insulin.?dependent diabetes'
),

/* Exclusion diagnosis concepts: type 1, gestational, secondary/other specified diabetes. */
exclusion_icd_source AS (
    SELECT
        c.concept_id,
        CASE
            WHEN c.vocabulary_id = 'ICD10CM'
             AND replace(c.concept_code, '.', '') LIKE 'E10%' THEN 'T1DM'

            WHEN c.vocabulary_id = 'ICD9CM'
             AND replace(c.concept_code, '.', '') ~ '^250[0-9][13]$' THEN 'T1DM'

            WHEN c.vocabulary_id = 'ICD10CM'
             AND replace(c.concept_code, '.', '') LIKE 'O244%' THEN 'GESTATIONAL'

            WHEN c.vocabulary_id = 'ICD9CM'
             AND replace(c.concept_code, '.', '') LIKE '6488%' THEN 'GESTATIONAL'

            WHEN c.vocabulary_id = 'ICD10CM'
             AND (
                 replace(c.concept_code, '.', '') LIKE 'E08%'
              OR replace(c.concept_code, '.', '') LIKE 'E09%'
              OR replace(c.concept_code, '.', '') LIKE 'E13%'
             ) THEN 'SECONDARY_OTHER'
        END AS exclusion_type
    FROM public.concept c
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND c.invalid_reason IS NULL
),

exclusion_condition_concepts AS (
    SELECT DISTINCT
        cr.concept_id_2 AS condition_concept_id,
        s.exclusion_type
    FROM exclusion_icd_source s
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = s.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
    WHERE s.exclusion_type IS NOT NULL

    UNION

    /* Fallback for standard exclusion concepts already present in condition_occurrence. */
    SELECT
        c.concept_id,
        CASE
            WHEN c.concept_name ~* 'type 1 diabetes|diabetes mellitus type 1' THEN 'T1DM'
            WHEN c.concept_name ~* 'gestational diabetes|diabetes.*pregnancy' THEN 'GESTATIONAL'
            WHEN c.concept_name ~* 'secondary diabetes|drug induced diabetes|other specified diabetes' THEN 'SECONDARY_OTHER'
        END AS exclusion_type
    FROM public.concept c
    WHERE c.domain_id = 'Condition'
      AND c.standard_concept = 'S'
      AND c.invalid_reason IS NULL
      AND c.concept_name ~* 'type 1 diabetes|diabetes mellitus type 1|gestational diabetes|diabetes.*pregnancy|secondary diabetes|drug induced diabetes|other specified diabetes'
),

/* Non-insulin antidiabetic medications.
   Uses generic ingredient/class names plus common brand names. */
antidiabetic_seed_concepts AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Drug'
      AND c.invalid_reason IS NULL
      AND c.concept_name ~* (
          'metformin|glucophage|fortamet|glumetza|riomet|' ||
          'glyburide|glibenclamide|glipizide|glimepiride|tolbutamide|chlorpropamide|diabeta|glynase|glucotrol|amaryl|' ||
          'pioglitazone|rosiglitazone|actos|avandia|' ||
          'sitagliptin|saxagliptin|linagliptin|alogliptin|januvia|janumet|onglyza|tradjenta|nesina|' ||
          'canagliflozin|dapagliflozin|empagliflozin|ertugliflozin|invokana|farxiga|jardiance|steglatro|' ||
          'liraglutide|semaglutide|dulaglutide|exenatide|lixisenatide|victoza|ozempic|rybelsus|trulicity|byetta|bydureon|adlyxin|' ||
          'repaglinide|nateglinide|prandin|starlix|' ||
          'acarbose|miglitol|precose|glyset'
      )
      AND c.concept_name !~* 'insulin'
),

antidiabetic_drug_concepts AS (
    SELECT concept_id AS drug_concept_id
    FROM antidiabetic_seed_concepts

    UNION

    /* Include descendant RxNorm clinical/branded drugs where ancestry exists. */
    SELECT ca.descendant_concept_id AS drug_concept_id
    FROM antidiabetic_seed_concepts s
    JOIN public.concept_ancestor ca
      ON ca.ancestor_concept_id = s.concept_id
),

/* Lab concepts for HbA1c and glucose using LOINC codes and concept names. */
diabetes_lab_concepts AS (
    SELECT
        c.concept_id AS measurement_concept_id,
        CASE
            WHEN c.concept_code IN ('4548-4', '4549-2', '17856-6')
              OR c.concept_name ~* 'hemoglobin a1c|hba1c|glycohemoglobin'
            THEN 'A1C'

            WHEN c.concept_code IN ('1558-6', '2345-7')
              OR c.concept_name ~* 'glucose.*fasting|fasting.*glucose'
            THEN 'FASTING_GLUCOSE'

            WHEN c.concept_code IN ('2339-0', '2340-8')
              OR c.concept_name ~* 'glucose.*serum|glucose.*plasma|random.*glucose'
            THEN 'RANDOM_GLUCOSE'
        END AS lab_type
    FROM public.concept c
    WHERE c.domain_id = 'Measurement'
      AND c.invalid_reason IS NULL
      AND (
          c.concept_code IN ('4548-4', '4549-2', '17856-6', '1558-6', '2345-7', '2339-0', '2340-8')
          OR c.concept_name ~* 'hemoglobin a1c|hba1c|glycohemoglobin|glucose.*fasting|fasting.*glucose|glucose.*serum|glucose.*plasma|random.*glucose'
      )
),

/* T2DM diagnosis evidence. */
t2dm_dx AS (
    SELECT
        co.person_id,
        co.condition_start_date AS event_date
    FROM public.condition_occurrence co
    JOIN t2dm_condition_concepts t2
      ON t2.condition_concept_id = co.condition_concept_id
    WHERE co.condition_start_date IS NOT NULL
),

/* Exclusion diagnosis evidence. */
exclusion_dx AS (
    SELECT
        co.person_id,
        ex.exclusion_type,
        co.condition_start_date AS event_date
    FROM public.condition_occurrence co
    JOIN exclusion_condition_concepts ex
      ON ex.condition_concept_id = co.condition_concept_id
    WHERE co.condition_start_date IS NOT NULL
),

/* Medication evidence supporting treated T2DM. */
antidiabetic_rx AS (
    SELECT
        de.person_id,
        de.drug_exposure_start_date AS event_date
    FROM public.drug_exposure de
    JOIN antidiabetic_drug_concepts adc
      ON adc.drug_concept_id = de.drug_concept_id
    WHERE de.drug_exposure_start_date IS NOT NULL
),

/* Abnormal diabetes-range laboratory evidence.
   Thresholds:
   - HbA1c >= 6.5 percent
   - fasting glucose >= 126 mg/dL
   - random glucose >= 200 mg/dL */
abnormal_labs AS (
    SELECT
        m.person_id,
        m.measurement_date AS event_date
    FROM public.measurement m
    JOIN diabetes_lab_concepts lc
      ON lc.measurement_concept_id = m.measurement_concept_id
    WHERE m.measurement_date IS NOT NULL
      AND m.value_as_number IS NOT NULL
      AND (
          (lc.lab_type = 'A1C'
           AND m.value_as_number >= 6.5
           AND coalesce(m.unit_source_value, '') ~* '%|percent')

          OR

          (lc.lab_type = 'FASTING_GLUCOSE'
           AND m.value_as_number >= 126
           AND coalesce(m.unit_source_value, 'mg/dL') ~* 'mg/dl')

          OR

          (lc.lab_type = 'RANDOM_GLUCOSE'
           AND m.value_as_number >= 200
           AND coalesce(m.unit_source_value, 'mg/dL') ~* 'mg/dl')
      )
),

/* Aggregate evidence by person. */
person_evidence AS (
    SELECT
        p.person_id,

        count(DISTINCT td.event_date) AS t2dm_dx_dates,
        min(td.event_date) AS first_t2dm_dx_date,

        count(DISTINCT rx.event_date) AS antidiabetic_rx_dates,
        min(rx.event_date) AS first_rx_date,

        count(DISTINCT lab.event_date) AS abnormal_lab_dates,
        min(lab.event_date) AS first_abnormal_lab_date,

        count(DISTINCT CASE WHEN ex.exclusion_type = 'T1DM' THEN ex.event_date END) AS t1dm_dx_dates,
        count(DISTINCT CASE WHEN ex.exclusion_type = 'GESTATIONAL' THEN ex.event_date END) AS gestational_dx_dates,
        count(DISTINCT CASE WHEN ex.exclusion_type = 'SECONDARY_OTHER' THEN ex.event_date END) AS secondary_other_dx_dates
    FROM public.person p
    LEFT JOIN t2dm_dx td
      ON td.person_id = p.person_id
    LEFT JOIN antidiabetic_rx rx
      ON rx.person_id = p.person_id
    LEFT JOIN abnormal_labs lab
      ON lab.person_id = p.person_id
    LEFT JOIN exclusion_dx ex
      ON ex.person_id = p.person_id
    GROUP BY p.person_id
)

/* Final phenotype:
   Include persons with repeated T2DM diagnosis, or diagnosis plus treatment/lab evidence,
   or treatment plus repeated abnormal labs. Exclude likely type 1 diabetes and diabetes
   explained only by gestational or secondary/other specified diabetes. */
SELECT pe.person_id
FROM person_evidence pe
WHERE (
        pe.t2dm_dx_dates >= 2
     OR (pe.t2dm_dx_dates >= 1 AND (pe.antidiabetic_rx_dates >= 1 OR pe.abnormal_lab_dates >= 1))
     OR (pe.antidiabetic_rx_dates >= 1 AND pe.abnormal_lab_dates >= 2)
)
AND NOT (
        pe.t1dm_dx_dates >= 2
    AND pe.t1dm_dx_dates > pe.t2dm_dx_dates
)
AND NOT (
        pe.gestational_dx_dates >= 1
    AND pe.t2dm_dx_dates = 0
)
AND NOT (
        pe.secondary_other_dx_dates >= 1
    AND pe.t2dm_dx_dates = 0
)
ORDER BY pe.person_id;