WITH
/* ICD9CM/ICD10CM source diagnosis concepts for type 2 diabetes */
t2dm_icd_source AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (c.invalid_reason IS NULL OR c.invalid_reason = '')
      AND (
            /* ICD10CM E11.* */
            (
                c.vocabulary_id = 'ICD10CM'
                AND regexp_replace(upper(c.concept_code), '\.', '', 'g') ~ '^E11'
            )

            OR

            /* ICD9CM 250.x0 or 250.x2 */
            (
                c.vocabulary_id = 'ICD9CM'
                AND regexp_replace(c.concept_code, '\.', '', 'g') ~ '^250[0-9][02]$'
            )
          )
),

/* Map ICD source concepts to standard OMOP condition concepts */
t2dm_mapped_condition AS (
    SELECT DISTINCT cr.concept_id_2 AS condition_concept_id
    FROM t2dm_icd_source s
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = s.concept_id
     AND cr.relationship_id = 'Maps to'
     AND (cr.invalid_reason IS NULL OR cr.invalid_reason = '')
),

/* Standard OMOP condition-name backup for populated synthetic OMOP data */
t2dm_named_condition AS (
    SELECT DISTINCT c.concept_id AS condition_concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Condition'
      AND c.standard_concept = 'S'
      AND (c.invalid_reason IS NULL OR c.invalid_reason = '')
      AND c.concept_name ~* '(type 2.*diabetes|diabetes mellitus type 2|non[- ]insulin[- ]dependent diabetes)'

    UNION

    SELECT DISTINCT ca.descendant_concept_id AS condition_concept_id
    FROM public.concept c
    JOIN public.concept_ancestor ca
      ON ca.ancestor_concept_id = c.concept_id
    WHERE c.domain_id = 'Condition'
      AND c.standard_concept = 'S'
      AND (c.invalid_reason IS NULL OR c.invalid_reason = '')
      AND c.concept_name ~* '(type 2.*diabetes|diabetes mellitus type 2|non[- ]insulin[- ]dependent diabetes)'
),

t2dm_condition_concepts AS (
    SELECT condition_concept_id FROM t2dm_mapped_condition
    UNION
    SELECT condition_concept_id FROM t2dm_named_condition
),

/* ICD9CM/ICD10CM source concepts for competing diabetes phenotypes */
exclusion_icd_source AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (c.invalid_reason IS NULL OR c.invalid_reason = '')
      AND (
            /* ICD10CM type 1 diabetes */
            (
                c.vocabulary_id = 'ICD10CM'
                AND regexp_replace(upper(c.concept_code), '\.', '', 'g') ~ '^E10'
            )

            OR

            /* ICD10CM secondary or other specified diabetes */
            (
                c.vocabulary_id = 'ICD10CM'
                AND regexp_replace(upper(c.concept_code), '\.', '', 'g') ~ '^(E08|E09|E13)'
            )

            OR

            /* ICD10CM gestational diabetes */
            (
                c.vocabulary_id = 'ICD10CM'
                AND regexp_replace(upper(c.concept_code), '\.', '', 'g') ~ '^O244'
            )

            OR

            /* ICD9CM type 1 diabetes: 250.x1 or 250.x3 */
            (
                c.vocabulary_id = 'ICD9CM'
                AND regexp_replace(c.concept_code, '\.', '', 'g') ~ '^250[0-9][13]$'
            )

            OR

            /* ICD9CM secondary diabetes */
            (
                c.vocabulary_id = 'ICD9CM'
                AND regexp_replace(c.concept_code, '\.', '', 'g') ~ '^249'
            )

            OR

            /* ICD9CM gestational diabetes */
            (
                c.vocabulary_id = 'ICD9CM'
                AND regexp_replace(c.concept_code, '\.', '', 'g') ~ '^6488'
            )
          )
),

/* Map exclusion ICD concepts to standard OMOP condition concepts */
exclusion_mapped_condition AS (
    SELECT DISTINCT cr.concept_id_2 AS condition_concept_id
    FROM exclusion_icd_source s
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = s.concept_id
     AND cr.relationship_id = 'Maps to'
     AND (cr.invalid_reason IS NULL OR cr.invalid_reason = '')
),

/* Standard OMOP exclusion-name backup */
exclusion_named_condition AS (
    SELECT DISTINCT c.concept_id AS condition_concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Condition'
      AND c.standard_concept = 'S'
      AND (c.invalid_reason IS NULL OR c.invalid_reason = '')
      AND c.concept_name ~* '(type 1.*diabetes|diabetes mellitus type 1|gestational diabetes|secondary diabetes|drug[- ]induced diabetes|steroid[- ]induced diabetes|diabetes mellitus due to underlying condition)'

    UNION

    SELECT DISTINCT ca.descendant_concept_id AS condition_concept_id
    FROM public.concept c
    JOIN public.concept_ancestor ca
      ON ca.ancestor_concept_id = c.concept_id
    WHERE c.domain_id = 'Condition'
      AND c.standard_concept = 'S'
      AND (c.invalid_reason IS NULL OR c.invalid_reason = '')
      AND c.concept_name ~* '(type 1.*diabetes|diabetes mellitus type 1|gestational diabetes|secondary diabetes|drug[- ]induced diabetes|steroid[- ]induced diabetes|diabetes mellitus due to underlying condition)'
),

exclusion_condition_concepts AS (
    SELECT condition_concept_id FROM exclusion_mapped_condition
    UNION
    SELECT condition_concept_id FROM exclusion_named_condition
),

/* T2DM diagnosis evidence */
t2dm_dx AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date AS evidence_date
    FROM public.condition_occurrence co
    JOIN t2dm_condition_concepts tc
      ON tc.condition_concept_id = co.condition_concept_id
    WHERE co.condition_start_date IS NOT NULL
),

/* Exclusion diagnosis evidence */
exclusion_dx AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date AS evidence_date
    FROM public.condition_occurrence co
    JOIN exclusion_condition_concepts ec
      ON ec.condition_concept_id = co.condition_concept_id
    WHERE co.condition_start_date IS NOT NULL
),

/* Non-insulin antidiabetic medication seed concepts: generic and brand names */
antidiabetic_drug_seed AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Drug'
      AND (c.invalid_reason IS NULL OR c.invalid_reason = '')
      AND c.concept_name ~* (
            'metformin|glucophage|fortamet|glumetza|riomet|'
         || 'glyburide|glibenclamide|glipizide|glimepiride|tolbutamide|chlorpropamide|'
         || 'diabeta|glynase|micronase|glucotrol|amaryl|'
         || 'pioglitazone|rosiglitazone|actos|avandia|'
         || 'sitagliptin|saxagliptin|linagliptin|alogliptin|'
         || 'januvia|onglyza|tradjenta|nesina|janumet|'
         || 'exenatide|liraglutide|dulaglutide|semaglutide|lixisenatide|tirzepatide|'
         || 'byetta|bydureon|victoza|trulicity|ozempic|rybelsus|mounjaro|adlyxin|'
         || 'canagliflozin|dapagliflozin|empagliflozin|ertugliflozin|'
         || 'invokana|farxiga|jardiance|steglatro|'
         || 'acarbose|miglitol|precose|glyset|'
         || 'repaglinide|nateglinide|prandin|starlix|'
         || 'colesevelam|welchol|bromocriptine|cycloset|pramlintide|symlin'
          )
      AND c.concept_name !~* 'insulin'
),

/* Include descendant drug concepts */
antidiabetic_drug_concepts AS (
    SELECT DISTINCT concept_id AS drug_concept_id
    FROM antidiabetic_drug_seed

    UNION

    SELECT DISTINCT ca.descendant_concept_id AS drug_concept_id
    FROM antidiabetic_drug_seed s
    JOIN public.concept_ancestor ca
      ON ca.ancestor_concept_id = s.concept_id
),

/* Medication evidence */
t2dm_med AS (
    SELECT DISTINCT
        de.person_id,
        de.drug_exposure_start_date AS evidence_date
    FROM public.drug_exposure de
    JOIN antidiabetic_drug_concepts dc
      ON dc.drug_concept_id = de.drug_concept_id
    WHERE de.drug_exposure_start_date IS NOT NULL
),

/* Diabetes-range laboratory evidence */
abnormal_lab AS (
    SELECT DISTINCT
        m.person_id,
        m.measurement_date AS evidence_date
    FROM public.measurement m
    JOIN public.concept c
      ON c.concept_id = m.measurement_concept_id
    WHERE m.measurement_date IS NOT NULL
      AND m.value_as_number IS NOT NULL
      AND c.domain_id = 'Measurement'
      AND (c.invalid_reason IS NULL OR c.invalid_reason = '')
      AND (
            /* HbA1c >= 6.5% */
            (
                (
                    c.concept_name ~* '(hemoglobin a1c|hba1c|glycated hemoglobin|glycohemoglobin)'
                    OR c.concept_code IN ('4548-4', '4549-2', '17856-6', '59261-8')
                    OR m.measurement_source_value IN ('4548-4', '4549-2', '17856-6', '59261-8')
                )
                AND m.value_as_number >= 6.5
            )

            OR

            /* Fasting glucose >= 126 mg/dL or >= 7.0 mmol/L */
            (
                (
                    c.concept_name ~* '(fasting.*glucose|glucose.*fasting)'
                    OR c.concept_code IN ('1558-6', '1556-0', '14771-0')
                    OR m.measurement_source_value IN ('1558-6', '1556-0', '14771-0')
                    OR m.value_source_value ~* 'fasting'
                )
                AND (
                    (
                        COALESCE(m.unit_source_value, '') ~* 'mmol'
                        AND m.value_as_number >= 7.0
                    )
                    OR
                    (
                        COALESCE(m.unit_source_value, '') !~* 'mmol'
                        AND m.value_as_number >= 126
                    )
                )
            )

            OR

            /* Blood/plasma/serum/random glucose >= 200 mg/dL or >= 11.1 mmol/L */
            (
                (
                    c.concept_name ~* 'glucose'
                    OR c.concept_code IN ('2345-7', '2339-0', '14749-6', '15074-8', '41653-7')
                    OR m.measurement_source_value IN ('2345-7', '2339-0', '14749-6', '15074-8', '41653-7')
                )
                AND COALESCE(c.concept_name, '') !~* '(urine|csf|cerebrospinal)'
                AND COALESCE(m.measurement_source_value, '') !~* '(urine|csf|cerebrospinal)'
                AND (
                    (
                        COALESCE(m.unit_source_value, '') ~* 'mmol'
                        AND m.value_as_number >= 11.1
                    )
                    OR
                    (
                        COALESCE(m.unit_source_value, '') !~* 'mmol'
                        AND m.value_as_number >= 200
                    )
                )
            )
          )
),

/* Person-level evidence counts and index date */
person_evidence AS (
    SELECT
        p.person_id,
        MIN(e.evidence_date) AS index_date,
        COUNT(DISTINCT CASE WHEN e.evidence_type = 'DX'  THEN e.evidence_date END) AS t2dm_dx_dates,
        COUNT(DISTINCT CASE WHEN e.evidence_type = 'MED' THEN e.evidence_date END) AS med_dates,
        COUNT(DISTINCT CASE WHEN e.evidence_type = 'LAB' THEN e.evidence_date END) AS abnormal_lab_dates
    FROM public.person p
    JOIN (
        SELECT person_id, evidence_date, 'DX' AS evidence_type FROM t2dm_dx
        UNION ALL
        SELECT person_id, evidence_date, 'MED' AS evidence_type FROM t2dm_med
        UNION ALL
        SELECT person_id, evidence_date, 'LAB' AS evidence_type FROM abnormal_lab
    ) e
      ON e.person_id = p.person_id
    GROUP BY p.person_id
),

/* Apply inclusion criteria */
included AS (
    SELECT
        pe.person_id,
        pe.index_date,
        pe.t2dm_dx_dates,
        pe.med_dates,
        pe.abnormal_lab_dates
    FROM person_evidence pe
    WHERE
           pe.t2dm_dx_dates >= 2
        OR (pe.t2dm_dx_dates >= 1 AND pe.med_dates >= 1)
        OR (pe.t2dm_dx_dates >= 1 AND pe.abnormal_lab_dates >= 1)
        OR (pe.med_dates >= 1 AND pe.abnormal_lab_dates >= 1)
        OR pe.abnormal_lab_dates >= 2
),

/* Exclude competing diabetes phenotypes unless T2DM evidence is stronger */
exclusion_summary AS (
    SELECT
        i.person_id,
        COUNT(DISTINCT ex.evidence_date) AS exclusion_dates
    FROM included i
    JOIN exclusion_dx ex
      ON ex.person_id = i.person_id
     AND ex.evidence_date <= i.index_date
    GROUP BY i.person_id
)

/* Final T2DM cohort */
SELECT DISTINCT i.person_id
FROM included i
LEFT JOIN exclusion_summary ex
  ON ex.person_id = i.person_id
WHERE COALESCE(ex.exclusion_dates, 0) = 0
   OR i.t2dm_dx_dates > COALESCE(ex.exclusion_dates, 0)
ORDER BY i.person_id;