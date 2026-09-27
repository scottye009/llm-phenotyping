WITH
/* ICD9CM/ICD10CM source concepts for type 2 diabetes, then mapped to standard condition concepts */
t2d_icd_source AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (c.invalid_reason IS NULL OR c.invalid_reason = '')
      AND (
            /* ICD10CM E11.* = type 2 diabetes mellitus */
            (c.vocabulary_id = 'ICD10CM' AND c.concept_code ~* '^E11')
            OR
            /* ICD9CM 250.x0 or 250.x2 = type 2 or unspecified type, not uncontrolled/controlled variants */
            (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~* '^250(\.[0-9][02]|[0-9][02])$')
          )
),
t2d_standard_condition AS (
    SELECT DISTINCT cr.concept_id_2 AS condition_concept_id
    FROM t2d_icd_source s
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = s.concept_id
     AND cr.relationship_id = 'Maps to'
     AND (cr.invalid_reason IS NULL OR cr.invalid_reason = '')
),

/* Exclusion ICD concepts: type 1, gestational, and secondary diabetes */
exclusion_icd_source AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (c.invalid_reason IS NULL OR c.invalid_reason = '')
      AND (
            /* Type 1 diabetes */
            (c.vocabulary_id = 'ICD10CM' AND c.concept_code ~* '^E10')
            OR
            (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~* '^250(\.[0-9][13]|[0-9][13])$')

            /* Gestational diabetes */
            OR
            (c.vocabulary_id = 'ICD10CM' AND c.concept_code ~* '^O24\.4')
            OR
            (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~* '^648\.8')

            /* Secondary or other specified diabetes */
            OR
            (c.vocabulary_id = 'ICD10CM' AND c.concept_code ~* '^(E08|E09|E13)')
            OR
            (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~* '^249')
          )
),
exclusion_standard_condition AS (
    SELECT DISTINCT cr.concept_id_2 AS condition_concept_id
    FROM exclusion_icd_source s
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = s.concept_id
     AND cr.relationship_id = 'Maps to'
     AND (cr.invalid_reason IS NULL OR cr.invalid_reason = '')
),

/* T2DM diagnosis evidence */
t2d_dx AS (
    SELECT DISTINCT
           co.person_id,
           co.condition_start_date AS evidence_date
    FROM public.condition_occurrence co
    JOIN t2d_standard_condition t
      ON t.condition_concept_id = co.condition_concept_id
    WHERE co.condition_start_date IS NOT NULL
),

/* Exclusion diagnosis evidence */
exclusion_dx AS (
    SELECT DISTINCT
           co.person_id,
           co.condition_start_date AS evidence_date
    FROM public.condition_occurrence co
    JOIN exclusion_standard_condition e
      ON e.condition_concept_id = co.condition_concept_id
    WHERE co.condition_start_date IS NOT NULL
),

/* Non-insulin antidiabetic medication concepts using generic and brand names */
non_insulin_antidiabetic_ancestors AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Drug'
      AND (c.invalid_reason IS NULL OR c.invalid_reason = '')
      AND c.concept_name ~* (
            'metformin|glucophage|fortamet|glumetza|riomet|' ||
            'sitagliptin|januvia|janumet|linagliptin|tradjenta|saxagliptin|onglyza|alogliptin|nesina|' ||
            'canagliflozin|invokana|dapagliflozin|farxiga|empagliflozin|jardiance|ertugliflozin|steglatro|' ||
            'glipizide|glucotrol|glyburide|micronase|diabeta|glynase|glimepiride|amaryl|' ||
            'repaglinide|prandin|nateglinide|starlix|' ||
            'pioglitazone|actos|rosiglitazone|avandia|' ||
            'exenatide|byetta|bydureon|liraglutide|victoza|dulaglutide|trulicity|' ||
            'semaglutide|ozempic|rybelsus|tirzepatide|mounjaro|' ||
            'acarbose|precose|miglitol|glyset|pramlintide|symlin'
          )
      AND c.concept_name !~* 'insulin'
),
non_insulin_antidiabetic_concepts AS (
    SELECT DISTINCT ca.descendant_concept_id AS drug_concept_id
    FROM public.concept_ancestor ca
    JOIN non_insulin_antidiabetic_ancestors a
      ON a.concept_id = ca.ancestor_concept_id

    UNION

    SELECT DISTINCT concept_id AS drug_concept_id
    FROM non_insulin_antidiabetic_ancestors
),

/* Medication evidence */
diabetes_med AS (
    SELECT DISTINCT
           de.person_id,
           de.drug_exposure_start_date AS evidence_date
    FROM public.drug_exposure de
    JOIN non_insulin_antidiabetic_concepts d
      ON d.drug_concept_id = de.drug_concept_id
    WHERE de.drug_exposure_start_date IS NOT NULL
),

/* Lab concepts identified by OMOP concept names, LOINC-style concept codes, or populated source values */
lab_measurements AS (
    SELECT
        m.person_id,
        m.measurement_date AS evidence_date,
        m.value_as_number,
        c.concept_name,
        c.concept_code,
        m.measurement_source_value,
        CASE
            WHEN c.concept_name ~* '(hemoglobin a1c|hba1c|glycated hemoglobin)'
              OR c.concept_code IN ('4548-4', '17856-6', '4549-2')
              OR m.measurement_source_value IN ('4548-4', '17856-6', '4549-2')
                THEN 'A1C'

            WHEN c.concept_name ~* 'glucose'
              AND c.concept_name ~* 'fasting'
              AND c.concept_name !~* 'urine'
                THEN 'FASTING_GLUCOSE'

            WHEN c.concept_code IN ('1558-6', '1556-0')
              OR m.measurement_source_value IN ('1558-6', '1556-0')
                THEN 'FASTING_GLUCOSE'

            WHEN c.concept_name ~* 'glucose'
              AND c.concept_name !~* 'urine'
                THEN 'GLUCOSE'
        END AS lab_type
    FROM public.measurement m
    JOIN public.concept c
      ON c.concept_id = m.measurement_concept_id
    WHERE m.measurement_date IS NOT NULL
      AND m.value_as_number IS NOT NULL
),

/* Abnormal lab evidence: A1c >= 6.5%, fasting glucose >= 126 mg/dL, or other blood glucose >= 200 mg/dL */
abnormal_lab AS (
    SELECT DISTINCT
           person_id,
           evidence_date
    FROM lab_measurements
    WHERE
        (lab_type = 'A1C' AND value_as_number >= 6.5)
        OR
        (lab_type = 'FASTING_GLUCOSE' AND value_as_number >= 126)
        OR
        (lab_type = 'GLUCOSE' AND value_as_number >= 200)
),

/* Person-level evidence counts */
person_evidence AS (
    SELECT
        p.person_id,
        MIN(e.evidence_date) AS index_date,
        COUNT(DISTINCT CASE WHEN e.evidence_type = 'DX'  THEN e.evidence_date END) AS t2d_dx_dates,
        COUNT(DISTINCT CASE WHEN e.evidence_type = 'MED' THEN e.evidence_date END) AS med_dates,
        COUNT(DISTINCT CASE WHEN e.evidence_type = 'LAB' THEN e.evidence_date END) AS abnormal_lab_dates
    FROM public.person p
    JOIN (
        SELECT person_id, evidence_date, 'DX' AS evidence_type FROM t2d_dx
        UNION ALL
        SELECT person_id, evidence_date, 'MED' AS evidence_type FROM diabetes_med
        UNION ALL
        SELECT person_id, evidence_date, 'LAB' AS evidence_type FROM abnormal_lab
    ) e
      ON e.person_id = p.person_id
    GROUP BY p.person_id
),

/* Exclusions on or before the person's first qualifying evidence date */
excluded_persons AS (
    SELECT DISTINCT pe.person_id
    FROM person_evidence pe
    JOIN exclusion_dx ex
      ON ex.person_id = pe.person_id
     AND ex.evidence_date <= pe.index_date
)

/* Final T2DM phenotype cohort */
SELECT pe.person_id
FROM person_evidence pe
JOIN public.person p
  ON p.person_id = pe.person_id
LEFT JOIN excluded_persons ex
  ON ex.person_id = pe.person_id
WHERE ex.person_id IS NULL
  AND pe.index_date >= (p.birth_datetime::date + INTERVAL '18 years')
  AND (
        pe.t2d_dx_dates >= 2
        OR (pe.t2d_dx_dates >= 1 AND pe.med_dates >= 1)
        OR (pe.t2d_dx_dates >= 1 AND pe.abnormal_lab_dates >= 1)
        OR (pe.med_dates >= 1 AND pe.abnormal_lab_dates >= 1)
        OR pe.abnormal_lab_dates >= 2
      )
ORDER BY pe.person_id;