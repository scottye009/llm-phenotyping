WITH
/* ICD9CM / ICD10CM source diagnosis concepts for type 2 diabetes.
   ICD concepts are mapped to standard condition concepts before comparison. */
t2d_icd_source AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id = 'ICD10CM'
      AND c.concept_code ~* '^E11'
      AND COALESCE(c.invalid_reason, '') = ''

    UNION

    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id = 'ICD9CM'
      AND (
            c.concept_code ~* '^250\.[0-9][02]$'
         OR c.concept_code ~* '^250[0-9][02]$'
      )
      AND COALESCE(c.invalid_reason, '') = ''
),

t2d_condition_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS condition_concept_id
    FROM t2d_icd_source s
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = s.concept_id
     AND cr.relationship_id = 'Maps to'
     AND COALESCE(cr.invalid_reason, '') = ''

    UNION

    /* Safety net for synthetic OMOP data where standard SNOMED names are populated. */
    SELECT c.concept_id AS condition_concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Condition'
      AND c.standard_concept = 'S'
      AND c.concept_name ~* 'type 2 diabetes|type ii diabetes|non[- ]insulin dependent diabetes'
      AND COALESCE(c.invalid_reason, '') = ''
),

/* Exclusion diagnosis concepts: type 1, gestational, secondary, drug-induced, or underlying-condition diabetes. */
exclusion_icd_source AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id = 'ICD10CM'
      AND (
            c.concept_code ~* '^E10'
         OR c.concept_code ~* '^O24\.4'
         OR c.concept_code ~* '^E08'
         OR c.concept_code ~* '^E09'
         OR c.concept_code ~* '^E13'
      )
      AND COALESCE(c.invalid_reason, '') = ''

    UNION

    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id = 'ICD9CM'
      AND (
            c.concept_code ~* '^250\.[0-9][13]$'
         OR c.concept_code ~* '^250[0-9][13]$'
         OR c.concept_name ~* 'gestational diabetes|secondary diabetes'
      )
      AND COALESCE(c.invalid_reason, '') = ''
),

exclusion_condition_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS condition_concept_id
    FROM exclusion_icd_source s
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = s.concept_id
     AND cr.relationship_id = 'Maps to'
     AND COALESCE(cr.invalid_reason, '') = ''

    UNION

    SELECT c.concept_id AS condition_concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Condition'
      AND c.standard_concept = 'S'
      AND c.concept_name ~* 'type 1 diabetes|type i diabetes|gestational diabetes|secondary diabetes|drug-induced diabetes|diabetes mellitus due to underlying condition'
      AND COALESCE(c.invalid_reason, '') = ''
),

/* Type 2 diabetes diagnosis evidence. */
t2d_dx AS (
    SELECT
        co.person_id,
        co.condition_start_date AS event_date
    FROM public.condition_occurrence co
    JOIN t2d_condition_concepts tc
      ON tc.condition_concept_id = co.condition_concept_id
    WHERE co.condition_start_date IS NOT NULL
),

/* Exclusion diagnosis evidence. */
exclusion_dx AS (
    SELECT
        co.person_id,
        COUNT(DISTINCT co.condition_start_date) AS exclusion_dx_dates
    FROM public.condition_occurrence co
    JOIN exclusion_condition_concepts ec
      ON ec.condition_concept_id = co.condition_concept_id
    WHERE co.condition_start_date IS NOT NULL
    GROUP BY co.person_id
),

/* Antidiabetic medication concepts.
   Includes generic and common brand names, then expands to descendant drug concepts. */
diabetes_drug_seed AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Drug'
      AND COALESCE(c.invalid_reason, '') = ''
      AND c.concept_name ~* (
            'metformin|glucophage|glumetza|fortamet|riomet'
         || '|glyburide|glibenclamide|diabeta|glynase|micronase'
         || '|glipizide|glucotrol'
         || '|glimepiride|amaryl'
         || '|pioglitazone|actos'
         || '|rosiglitazone|avandia'
         || '|sitagliptin|januvia'
         || '|saxagliptin|onglyza'
         || '|linagliptin|tradjenta'
         || '|alogliptin|nesina'
         || '|empagliflozin|jardiance'
         || '|canagliflozin|invokana'
         || '|dapagliflozin|farxiga'
         || '|ertugliflozin|steglatro'
         || '|liraglutide|victoza'
         || '|semaglutide|ozempic|rybelsus'
         || '|dulaglutide|trulicity'
         || '|exenatide|byetta|bydureon'
         || '|lixisenatide|adlyxin'
         || '|tirzepatide|mounjaro'
         || '|repaglinide|prandin'
         || '|nateglinide|starlix'
         || '|acarbose|precose'
         || '|miglitol|glyset'
         || '|colesevelam|welchol'
         || '|bromocriptine|cycloset'
      )
),

diabetes_drug_concepts AS (
    SELECT DISTINCT concept_id AS drug_concept_id
    FROM diabetes_drug_seed

    UNION

    SELECT DISTINCT ca.descendant_concept_id AS drug_concept_id
    FROM diabetes_drug_seed s
    JOIN public.concept_ancestor ca
      ON ca.ancestor_concept_id = s.concept_id
),

med_evidence AS (
    SELECT
        de.person_id,
        MIN(de.drug_exposure_start_date) AS first_med_date,
        COUNT(*) AS diabetes_med_count
    FROM public.drug_exposure de
    JOIN diabetes_drug_concepts dc
      ON dc.drug_concept_id = de.drug_concept_id
    WHERE de.drug_exposure_start_date IS NOT NULL
    GROUP BY de.person_id
),

/* Diabetes-range lab evidence using OMOP concepts, LOINC/source codes, and concept names. */
lab_evidence AS (
    SELECT
        m.person_id,
        MIN(m.measurement_date) AS first_lab_date,
        COUNT(*) AS abnormal_lab_count
    FROM public.measurement m
    LEFT JOIN public.concept c
      ON c.concept_id = m.measurement_concept_id
    WHERE m.measurement_date IS NOT NULL
      AND m.value_as_number IS NOT NULL
      AND (
            /* HbA1c >= 6.5%. Common LOINC examples included. */
            (
                (
                    c.concept_name ~* 'hemoglobin a1c|hba1c|glycated hemoglobin'
                    OR c.concept_code IN ('4548-4', '17856-6', '59261-8')
                    OR m.measurement_source_value IN ('4548-4', '17856-6', '59261-8')
                )
                AND m.value_as_number >= 6.5
            )

            OR

            /* Fasting glucose >= 126 mg/dL. Common LOINC examples included. */
            (
                (
                    c.concept_name ~* 'fasting.*glucose|glucose.*fasting'
                    OR c.concept_code IN ('1558-6', '1556-0')
                    OR m.measurement_source_value IN ('1558-6', '1556-0')
                )
                AND m.value_as_number >= 126
            )

            OR

            /* Random/plasma/serum glucose >= 200 mg/dL. */
            (
                (
                    c.concept_name ~* 'glucose.*(serum|plasma|blood)|glucose'
                    OR c.concept_code IN ('2345-7', '2339-0', '41653-7')
                    OR m.measurement_source_value IN ('2345-7', '2339-0', '41653-7')
                )
                AND COALESCE(m.unit_source_value, '') ~* 'mg/dL|mg per dL|milligram'
                AND m.value_as_number >= 200
            )
      )
    GROUP BY m.person_id
),

dx_summary AS (
    SELECT
        person_id,
        MIN(event_date) AS first_t2d_dx_date,
        COUNT(DISTINCT event_date) AS t2d_dx_dates
    FROM t2d_dx
    GROUP BY person_id
),

candidate_patients AS (
    SELECT
        p.person_id,
        COALESCE(dx.t2d_dx_dates, 0) AS t2d_dx_dates,
        COALESCE(me.diabetes_med_count, 0) AS diabetes_med_count,
        COALESCE(le.abnormal_lab_count, 0) AS abnormal_lab_count,
        COALESCE(ex.exclusion_dx_dates, 0) AS exclusion_dx_dates
    FROM public.person p
    LEFT JOIN dx_summary dx
      ON dx.person_id = p.person_id
    LEFT JOIN med_evidence me
      ON me.person_id = p.person_id
    LEFT JOIN lab_evidence le
      ON le.person_id = p.person_id
    LEFT JOIN exclusion_dx ex
      ON ex.person_id = p.person_id
)

SELECT DISTINCT person_id
FROM candidate_patients
WHERE
    (
        t2d_dx_dates >= 2
        OR (t2d_dx_dates >= 1 AND diabetes_med_count >= 1)
        OR (t2d_dx_dates >= 1 AND abnormal_lab_count >= 1)
        OR (diabetes_med_count >= 1 AND abnormal_lab_count >= 1)
    )
    /* Exclude competing diabetes phenotypes unless type 2 diagnosis evidence is stronger. */
    AND (
        exclusion_dx_dates = 0
        OR t2d_dx_dates > exclusion_dx_dates
    )
ORDER BY person_id;