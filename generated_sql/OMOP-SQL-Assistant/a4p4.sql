WITH
/* 1) ICD9CM / ICD10CM source diagnosis concepts for Type 2 diabetes */
t2_icd_source AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND c.invalid_reason IS NULL
      AND (
            /* ICD10CM E11.* = Type 2 diabetes mellitus */
            (c.vocabulary_id = 'ICD10CM' AND c.concept_code ~* '^E11(\.|$)')
            OR
            /* ICD9CM 250.x0 or 250.x2 = Type II or unspecified type diabetes */
            (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~* '^250\.?[0-9][0-9][02]$')
          )
),

/* 2) Map ICD source concepts to standard OMOP condition concepts */
t2_dx_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS condition_concept_id
    FROM t2_icd_source s
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = s.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL

    UNION

    /* Also capture standard condition concepts by OMOP concept name */
    SELECT DISTINCT ca.descendant_concept_id AS condition_concept_id
    FROM public.concept c
    JOIN public.concept_ancestor ca
      ON ca.ancestor_concept_id = c.concept_id
    WHERE c.domain_id = 'Condition'
      AND c.standard_concept = 'S'
      AND c.invalid_reason IS NULL
      AND c.concept_name ~* '(type 2|type ii|non-insulin).*(diabetes)'
),

/* 3) Exclusion diagnosis concepts: Type 1, gestational, secondary diabetes */
exclusion_icd_source AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND c.invalid_reason IS NULL
      AND (
            /* Type 1 diabetes */
            (c.vocabulary_id = 'ICD10CM' AND c.concept_code ~* '^E10(\.|$)')
            OR
            (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~* '^250\.?[0-9][0-9][13]$')

            /* Secondary diabetes */
            OR (c.vocabulary_id = 'ICD10CM' AND c.concept_code ~* '^E0[89](\.|$)')
            OR (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~* '^249\.?')

            /* Gestational diabetes */
            OR (c.vocabulary_id = 'ICD10CM' AND c.concept_code ~* '^O24\.4')
            OR (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~* '^648\.8')
          )
),

exclusion_dx_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS condition_concept_id
    FROM exclusion_icd_source s
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = s.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL

    UNION

    SELECT DISTINCT ca.descendant_concept_id AS condition_concept_id
    FROM public.concept c
    JOIN public.concept_ancestor ca
      ON ca.ancestor_concept_id = c.concept_id
    WHERE c.domain_id = 'Condition'
      AND c.standard_concept = 'S'
      AND c.invalid_reason IS NULL
      AND c.concept_name ~* '(type 1 diabetes|type i diabetes|gestational diabetes|secondary diabetes)'
),

/* 4) Type 2 diabetes diagnosis evidence */
t2_dx_events AS (
    SELECT
        co.person_id,
        co.condition_start_date AS event_date
    FROM public.condition_occurrence co
    JOIN t2_dx_concepts d
      ON d.condition_concept_id = co.condition_concept_id
    WHERE co.condition_start_date IS NOT NULL
),

/* 5) Non-insulin antihyperglycemic medication concepts, generic and brand names */
t2_med_anchors AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Drug'
      AND c.invalid_reason IS NULL
      AND c.concept_name ~* (
          'metformin|glucophage|fortamet|glumetza|' ||
          'glipizide|glucotrol|glyburide|diabeta|glynase|micronase|' ||
          'glimepiride|amaryl|' ||
          'pioglitazone|actos|rosiglitazone|avandia|' ||
          'sitagliptin|januvia|janumet|saxagliptin|onglyza|' ||
          'linagliptin|tradjenta|alogliptin|nesina|' ||
          'empagliflozin|jardiance|canagliflozin|invokana|' ||
          'dapagliflozin|farxiga|ertugliflozin|' ||
          'liraglutide|victoza|semaglutide|ozempic|rybelsus|' ||
          'dulaglutide|trulicity|exenatide|byetta|bydureon|' ||
          'lixisenatide|tirzepatide|mounjaro|' ||
          'acarbose|precose|miglitol|glyset|' ||
          'repaglinide|prandin|nateglinide|starlix'
      )
      AND c.concept_name !~* 'insulin'
),

t2_med_concepts AS (
    SELECT DISTINCT concept_id AS drug_concept_id
    FROM t2_med_anchors

    UNION

    SELECT DISTINCT ca.descendant_concept_id AS drug_concept_id
    FROM t2_med_anchors a
    JOIN public.concept_ancestor ca
      ON ca.ancestor_concept_id = a.concept_id
),

/* 6) Medication evidence */
t2_med_events AS (
    SELECT
        de.person_id,
        de.drug_exposure_start_date AS event_date
    FROM public.drug_exposure de
    JOIN t2_med_concepts m
      ON m.drug_concept_id = de.drug_concept_id
    WHERE de.drug_exposure_start_date IS NOT NULL
),

/* 7) Abnormal diabetes lab evidence using OMOP measurement concepts or LOINC source codes */
t2_lab_events AS (
    SELECT
        m.person_id,
        m.measurement_date AS event_date
    FROM public.measurement m
    LEFT JOIN public.concept c
      ON c.concept_id = m.measurement_concept_id
    WHERE m.measurement_date IS NOT NULL
      AND m.value_as_number IS NOT NULL
      AND (
            /* HbA1c >= 6.5% or >= 48 mmol/mol */
            (
                (
                    m.measurement_source_value IN ('4548-4', '4549-2', '17856-6', '59261-8')
                    OR c.concept_name ~* '(hemoglobin A1c|HbA1c|glycated hemoglobin)'
                )
                AND (
                    m.value_as_number >= 6.5
                    OR (
                        COALESCE(m.unit_source_value, '') ~* 'mmol/mol'
                        AND m.value_as_number >= 48
                    )
                )
            )

            OR

            /* Fasting glucose >=126 mg/dL or >=7.0 mmol/L */
            (
                (
                    m.measurement_source_value IN ('1558-6', '14771-0')
                    OR c.concept_name ~* '(fasting).*glucose'
                )
                AND (
                    (
                        (COALESCE(m.unit_source_value, '') ~* 'mg/dL' OR m.unit_concept_id = 8840)
                        AND m.value_as_number >= 126
                    )
                    OR (
                        COALESCE(m.unit_source_value, '') ~* 'mmol/L'
                        AND m.value_as_number >= 7.0
                    )
                )
            )

            OR

            /* Random/non-fasting blood glucose >=200 mg/dL or >=11.1 mmol/L */
            (
                (
                    m.measurement_source_value IN ('2345-7', '2339-0')
                    OR c.concept_name ~* 'glucose'
                )
                AND COALESCE(c.concept_name, '') !~* 'urine'
                AND COALESCE(m.measurement_source_value, '') NOT IN ('5792-7', '5797-6', '5804-0')
                AND (
                    (
                        (COALESCE(m.unit_source_value, '') ~* 'mg/dL' OR m.unit_concept_id = 8840)
                        AND m.value_as_number >= 200
                    )
                    OR (
                        COALESCE(m.unit_source_value, '') ~* 'mmol/L'
                        AND m.value_as_number >= 11.1
                    )
                )
            )
          )
),

/* 8) Exclusion evidence */
exclusion_events AS (
    SELECT
        co.person_id,
        co.condition_start_date AS event_date
    FROM public.condition_occurrence co
    JOIN exclusion_dx_concepts e
      ON e.condition_concept_id = co.condition_concept_id
    WHERE co.condition_start_date IS NOT NULL
),

/* 9) Combine evidence at the person level */
person_evidence AS (
    SELECT
        p.person_id,
        COUNT(DISTINCT dx.event_date) AS t2_dx_dates,
        COUNT(DISTINCT med.event_date) AS t2_med_dates,
        COUNT(DISTINCT lab.event_date) AS t2_lab_dates,
        MIN(
            LEAST(
                COALESCE(dx.event_date, DATE '9999-12-31'),
                COALESCE(med.event_date, DATE '9999-12-31'),
                COALESCE(lab.event_date, DATE '9999-12-31')
            )
        ) AS index_date
    FROM public.person p
    LEFT JOIN t2_dx_events dx
      ON dx.person_id = p.person_id
    LEFT JOIN t2_med_events med
      ON med.person_id = p.person_id
    LEFT JOIN t2_lab_events lab
      ON lab.person_id = p.person_id
    GROUP BY p.person_id
)

/* Final Type 2 diabetes phenotype */
SELECT DISTINCT pe.person_id
FROM person_evidence pe
WHERE
    /* Require diagnosis evidence plus either repeated diagnosis or supportive med/lab evidence */
    pe.t2_dx_dates >= 1
    AND (
        pe.t2_dx_dates >= 2
        OR pe.t2_med_dates >= 1
        OR pe.t2_lab_dates >= 1
    )

    /* Exclude likely non-Type 2 diabetes when exclusion evidence occurs on/before phenotype index */
    AND NOT EXISTS (
        SELECT 1
        FROM exclusion_events ex
        WHERE ex.person_id = pe.person_id
          AND ex.event_date <= pe.index_date
    )
ORDER BY pe.person_id;