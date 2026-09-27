WITH
/* ICD9CM / ICD10CM source diagnosis concepts for T2DM */
t2d_icd_source AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE COALESCE(c.invalid_reason, '') = ''
      AND c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (
            /* ICD10CM: Type 2 diabetes mellitus */
            (c.vocabulary_id = 'ICD10CM' AND c.concept_code ~* '^E11')
            OR
            /* ICD9CM: Diabetes mellitus, type 2 or unspecified type, not stated uncontrolled/controlled */
            (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~* '^250\.[0-9][02]$')
          )
),

/* Map ICD source concepts to standard OMOP condition concepts */
t2d_mapped_condition AS (
    SELECT DISTINCT cr.concept_id_2 AS condition_concept_id
    FROM t2d_icd_source s
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = s.concept_id
     AND cr.relationship_id = 'Maps to'
     AND COALESCE(cr.invalid_reason, '') = ''
),

/* Standard named T2DM concepts and descendants, used as OMOP standard backup */
t2d_named_condition AS (
    SELECT DISTINCT ca.descendant_concept_id AS condition_concept_id
    FROM public.concept c
    JOIN public.concept_ancestor ca
      ON ca.ancestor_concept_id = c.concept_id
    WHERE COALESCE(c.invalid_reason, '') = ''
      AND c.domain_id = 'Condition'
      AND c.standard_concept = 'S'
      AND c.concept_name ~* '(type 2 diabetes|diabetes mellitus type 2|non[- ]insulin[- ]dependent diabetes)'
),

/* Final T2DM diagnosis concept set */
t2d_condition_concepts AS (
    SELECT condition_concept_id FROM t2d_mapped_condition
    UNION
    SELECT condition_concept_id FROM t2d_named_condition
),

/* Exclusion ICD concepts: type 1, gestational, and secondary diabetes */
exclusion_icd_source AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE COALESCE(c.invalid_reason, '') = ''
      AND c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (
            /* Type 1 diabetes */
            (c.vocabulary_id = 'ICD10CM' AND c.concept_code ~* '^E10')
            OR
            (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~* '^250\.[0-9][13]$')

            /* Secondary diabetes */
            OR (c.vocabulary_id = 'ICD10CM' AND c.concept_code ~* '^(E08|E09|E13)')
            OR (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~* '^249')

            /* Gestational diabetes */
            OR (c.vocabulary_id = 'ICD10CM' AND c.concept_code ~* '^O24\.4')
            OR (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~* '^648\.8')
          )
),

/* Map exclusion ICD concepts to standard OMOP condition concepts */
exclusion_mapped_condition AS (
    SELECT DISTINCT cr.concept_id_2 AS condition_concept_id
    FROM exclusion_icd_source s
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = s.concept_id
     AND cr.relationship_id = 'Maps to'
     AND COALESCE(cr.invalid_reason, '') = ''
),

/* Standard named exclusion concepts and descendants */
exclusion_named_condition AS (
    SELECT DISTINCT ca.descendant_concept_id AS condition_concept_id
    FROM public.concept c
    JOIN public.concept_ancestor ca
      ON ca.ancestor_concept_id = c.concept_id
    WHERE COALESCE(c.invalid_reason, '') = ''
      AND c.domain_id = 'Condition'
      AND c.standard_concept = 'S'
      AND c.concept_name ~* '(type 1 diabetes|gestational diabetes|secondary diabetes|drug induced diabetes|steroid induced diabetes)'
),

/* Final exclusion concept set */
exclusion_condition_concepts AS (
    SELECT condition_concept_id FROM exclusion_mapped_condition
    UNION
    SELECT condition_concept_id FROM exclusion_named_condition
),

/* Diagnosis evidence */
dx_evidence AS (
    SELECT
        co.person_id,
        co.condition_start_date AS evidence_date
    FROM public.condition_occurrence co
    JOIN t2d_condition_concepts tc
      ON tc.condition_concept_id = co.condition_concept_id
    WHERE co.condition_start_date IS NOT NULL
),

/* Non-insulin antidiabetic medication seed concepts */
diabetes_drug_seed AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE COALESCE(c.invalid_reason, '') = ''
      AND c.domain_id = 'Drug'
      AND c.concept_name ~* (
          'metformin|glucophage|fortamet|glumetza|riomet|' ||
          'glipizide|glucotrol|glyburide|glibenclamide|glimepiride|amaryl|' ||
          'chlorpropamide|tolazamide|tolbutamide|' ||
          'pioglitazone|actos|rosiglitazone|avandia|' ||
          'sitagliptin|januvia|saxagliptin|onglyza|linagliptin|tradjenta|alogliptin|nesina|' ||
          'semaglutide|ozempic|rybelsus|liraglutide|victoza|dulaglutide|trulicity|' ||
          'exenatide|byetta|bydureon|tirzepatide|mounjaro|' ||
          'empagliflozin|jardiance|dapagliflozin|farxiga|canagliflozin|invokana|ertugliflozin|steglatro|' ||
          'acarbose|precose|miglitol|glyset|' ||
          'repaglinide|prandin|nateglinide|starlix|' ||
          'pramlintide|symlin|' ||
          'janumet|synjardy|xigduo|kombiglyze|glyxambi|invokamet|kazano|oseni|' ||
          'actoplus|duetact|avandamet|avandaryl|jentadueto|segluromet|steglujan|trijardy'
      )
      AND c.concept_name !~* 'insulin'
),

/* Include descendants so ingredient, clinical drug, branded drug, and combination concepts are captured */
diabetes_drug_concepts AS (
    SELECT DISTINCT concept_id AS drug_concept_id
    FROM diabetes_drug_seed

    UNION

    SELECT DISTINCT ca.descendant_concept_id AS drug_concept_id
    FROM diabetes_drug_seed s
    JOIN public.concept_ancestor ca
      ON ca.ancestor_concept_id = s.concept_id
),

/* Medication evidence */
med_evidence AS (
    SELECT
        de.person_id,
        de.drug_exposure_start_date AS evidence_date
    FROM public.drug_exposure de
    JOIN diabetes_drug_concepts dc
      ON dc.drug_concept_id = de.drug_concept_id
    WHERE de.drug_exposure_start_date IS NOT NULL
),

/* Lab evidence using OMOP measurement concepts, concept names, and LOINC-like source/code fields */
lab_evidence AS (
    SELECT
        m.person_id,
        m.measurement_date AS evidence_date
    FROM public.measurement m
    LEFT JOIN public.concept c
      ON c.concept_id = m.measurement_concept_id
    WHERE m.measurement_date IS NOT NULL
      AND m.value_as_number IS NOT NULL
      AND COALESCE(c.concept_name, '') !~* 'urine'
      AND COALESCE(m.measurement_source_value, '') !~* 'urine'
      AND (
            /* HbA1c >= 6.5% */
            (
                (
                    COALESCE(c.concept_name, '') ~* '(hemoglobin a1c|hba1c|glycated hemoglobin|glycohemoglobin)'
                    OR COALESCE(c.concept_code, '') IN ('4548-4', '4549-2', '17856-6', '59261-8', '41995-2')
                    OR COALESCE(m.measurement_source_value, '') IN ('4548-4', '4549-2', '17856-6', '59261-8', '41995-2')
                )
                AND m.value_as_number >= 6.5
            )

            OR

            /* Fasting glucose >= 126 mg/dL or >= 7.0 mmol/L */
            (
                (
                    COALESCE(c.concept_name, '') ~* '(fasting.*glucose|glucose.*fasting)'
                    OR COALESCE(c.concept_code, '') IN ('1558-6', '1556-0')
                    OR COALESCE(m.measurement_source_value, '') IN ('1558-6', '1556-0')
                )
                AND (
                    (COALESCE(m.unit_source_value, '') ~* 'mmol' AND m.value_as_number >= 7.0)
                    OR
                    (COALESCE(m.unit_source_value, '') !~* 'mmol' AND m.value_as_number >= 126)
                )
            )

            OR

            /* Random, serum, plasma, blood, or OGTT glucose >= 200 mg/dL or >= 11.1 mmol/L */
            (
                (
                    COALESCE(c.concept_name, '') ~* '(glucose|oral glucose tolerance|ogtt)'
                    OR COALESCE(c.concept_code, '') IN ('2345-7', '14749-6', '14743-9', '2339-0', '20436-2')
                    OR COALESCE(m.measurement_source_value, '') IN ('2345-7', '14749-6', '14743-9', '2339-0', '20436-2')
                )
                AND COALESCE(c.concept_name, '') !~* '(urine|csf|cerebrospinal)'
                AND (
                    (COALESCE(m.unit_source_value, '') ~* 'mmol' AND m.value_as_number >= 11.1)
                    OR
                    (COALESCE(m.unit_source_value, '') !~* 'mmol' AND m.value_as_number >= 200)
                )
            )
          )
),

/* Per-person evidence counts */
person_evidence AS (
    SELECT
        p.person_id,
        COUNT(DISTINCT dx.evidence_date)  AS dx_dates,
        COUNT(DISTINCT med.evidence_date) AS med_dates,
        COUNT(DISTINCT lab.evidence_date) AS lab_dates,
        LEAST(
            COALESCE(MIN(dx.evidence_date),  DATE '9999-12-31'),
            COALESCE(MIN(med.evidence_date), DATE '9999-12-31'),
            COALESCE(MIN(lab.evidence_date), DATE '9999-12-31')
        ) AS index_date
    FROM public.person p
    LEFT JOIN dx_evidence dx
      ON dx.person_id = p.person_id
    LEFT JOIN med_evidence med
      ON med.person_id = p.person_id
    LEFT JOIN lab_evidence lab
      ON lab.person_id = p.person_id
    GROUP BY p.person_id
),

/* Apply phenotype inclusion logic */
included AS (
    SELECT pe.person_id, pe.index_date
    FROM person_evidence pe
    WHERE
        pe.dx_dates >= 2
        OR (pe.dx_dates >= 1 AND pe.med_dates >= 1)
        OR (pe.dx_dates >= 1 AND pe.lab_dates >= 1)
        OR pe.lab_dates >= 2
        OR (pe.med_dates >= 1 AND pe.lab_dates >= 1)
),

/* Exclusion evidence up to phenotype index date */
excluded AS (
    SELECT DISTINCT i.person_id
    FROM included i
    JOIN public.condition_occurrence co
      ON co.person_id = i.person_id
     AND co.condition_start_date <= i.index_date
    JOIN exclusion_condition_concepts ec
      ON ec.condition_concept_id = co.condition_concept_id
)

/* Final phenotype cohort */
SELECT DISTINCT i.person_id
FROM included i
WHERE NOT EXISTS (
    SELECT 1
    FROM excluded e
    WHERE e.person_id = i.person_id
)
ORDER BY i.person_id;