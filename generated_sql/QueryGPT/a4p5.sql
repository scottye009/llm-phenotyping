WITH
/* ICD9CM/ICD10CM source concepts for Type 2 diabetes */
t2dm_icd_source AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND c.invalid_reason IS NULL
      AND (
            /* ICD10CM E11.* */
            (c.vocabulary_id = 'ICD10CM'
             AND regexp_replace(upper(c.concept_code), '\.', '', 'g') ~ '^E11')

            OR

            /* ICD9CM 250.x0 or 250.x2 */
            (c.vocabulary_id = 'ICD9CM'
             AND regexp_replace(c.concept_code, '\.', '', 'g') ~ '^250[0-9][02]$')
          )
),

/* Map ICD source concepts to standard OMOP condition concepts */
t2dm_mapped_condition AS (
    SELECT DISTINCT cr.concept_id_2 AS condition_concept_id
    FROM public.concept_relationship cr
    JOIN t2dm_icd_source s
      ON s.concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'
      AND cr.invalid_reason IS NULL
),

/* Standard OMOP Type 2 diabetes condition concepts and descendants */
t2dm_standard_condition AS (
    SELECT DISTINCT c.concept_id AS condition_concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Condition'
      AND c.standard_concept = 'S'
      AND c.invalid_reason IS NULL
      AND c.concept_name ~* 'type 2.*diabetes|diabetes mellitus type 2'

    UNION

    SELECT DISTINCT ca.descendant_concept_id AS condition_concept_id
    FROM public.concept c
    JOIN public.concept_ancestor ca
      ON ca.ancestor_concept_id = c.concept_id
    WHERE c.domain_id = 'Condition'
      AND c.standard_concept = 'S'
      AND c.invalid_reason IS NULL
      AND c.concept_name ~* 'type 2.*diabetes|diabetes mellitus type 2'
),

t2dm_condition_concepts AS (
    SELECT condition_concept_id FROM t2dm_mapped_condition
    UNION
    SELECT condition_concept_id FROM t2dm_standard_condition
),

/* Type 2 diabetes diagnosis evidence */
t2dm_dx AS (
    SELECT
        co.person_id,
        MIN(co.condition_start_date) AS first_t2dm_dx_date,
        COUNT(*) AS t2dm_dx_count
    FROM public.condition_occurrence co
    JOIN t2dm_condition_concepts tc
      ON tc.condition_concept_id = co.condition_concept_id
    GROUP BY co.person_id
),

/* Exclusion ICD source concepts: Type 1, gestational, secondary/other specified diabetes */
exclusion_icd_source AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND c.invalid_reason IS NULL
      AND (
            /* ICD10CM Type 1 diabetes */
            regexp_replace(upper(c.concept_code), '\.', '', 'g') ~ '^E10'

            OR

            /* ICD10CM secondary/other specified diabetes */
            regexp_replace(upper(c.concept_code), '\.', '', 'g') ~ '^E0[893]'

            OR

            /* ICD10CM gestational diabetes */
            regexp_replace(upper(c.concept_code), '\.', '', 'g') ~ '^O244'

            OR

            /* ICD9CM Type 1 diabetes: 250.x1 or 250.x3 */
            regexp_replace(c.concept_code, '\.', '', 'g') ~ '^250[0-9][13]$'

            OR

            /* ICD9CM secondary diabetes */
            regexp_replace(c.concept_code, '\.', '', 'g') ~ '^249'
          )
),

exclusion_mapped_condition AS (
    SELECT DISTINCT cr.concept_id_2 AS condition_concept_id
    FROM public.concept_relationship cr
    JOIN exclusion_icd_source s
      ON s.concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'
      AND cr.invalid_reason IS NULL
),

/* Standard exclusion concepts by name, plus descendants */
exclusion_standard_condition AS (
    SELECT DISTINCT c.concept_id AS condition_concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Condition'
      AND c.standard_concept = 'S'
      AND c.invalid_reason IS NULL
      AND c.concept_name ~* 'type 1.*diabetes|diabetes mellitus type 1|gestational diabetes|secondary diabetes|drug.*induced diabetes|steroid.*diabetes'

    UNION

    SELECT DISTINCT ca.descendant_concept_id AS condition_concept_id
    FROM public.concept c
    JOIN public.concept_ancestor ca
      ON ca.ancestor_concept_id = c.concept_id
    WHERE c.domain_id = 'Condition'
      AND c.standard_concept = 'S'
      AND c.invalid_reason IS NULL
      AND c.concept_name ~* 'type 1.*diabetes|diabetes mellitus type 1|gestational diabetes|secondary diabetes|drug.*induced diabetes|steroid.*diabetes'
),

exclusion_condition_concepts AS (
    SELECT condition_concept_id FROM exclusion_mapped_condition
    UNION
    SELECT condition_concept_id FROM exclusion_standard_condition
),

exclusion_dx AS (
    SELECT
        co.person_id,
        COUNT(*) AS exclusion_dx_count
    FROM public.condition_occurrence co
    JOIN exclusion_condition_concepts ec
      ON ec.condition_concept_id = co.condition_concept_id
    GROUP BY co.person_id
),

/* Diabetes medication evidence: generic and brand names from OMOP concept names */
t2dm_med_concepts AS (
    SELECT DISTINCT c.concept_id AS drug_concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Drug'
      AND c.invalid_reason IS NULL
      AND (
            c.concept_name ~* 'metformin|glucophage|fortamet|glumetza|riomet'
         OR c.concept_name ~* 'glyburide|glibenclamide|glipizide|glimepiride|tolbutamide|chlorpropamide|diabeta|glynase|glucotrol|amaryl'
         OR c.concept_name ~* 'pioglitazone|rosiglitazone|actos|avandia'
         OR c.concept_name ~* 'sitagliptin|saxagliptin|linagliptin|alogliptin|januvia|onglyza|tradjenta|nesina'
         OR c.concept_name ~* 'exenatide|liraglutide|dulaglutide|semaglutide|lixisenatide|byetta|bydureon|victoza|trulicity|ozempic|rybelsus|mounjaro|tirzepatide'
         OR c.concept_name ~* 'canagliflozin|dapagliflozin|empagliflozin|ertugliflozin|invokana|farxiga|jardiance|steglatro'
         OR c.concept_name ~* 'acarbose|miglitol|precose|glyset'
         OR c.concept_name ~* 'repaglinide|nateglinide|prandin|starlix'
          )
),

t2dm_med AS (
    SELECT
        de.person_id,
        MIN(de.drug_exposure_start_date) AS first_t2dm_med_date,
        COUNT(*) AS t2dm_med_count
    FROM public.drug_exposure de
    JOIN t2dm_med_concepts mc
      ON mc.drug_concept_id = de.drug_concept_id
    GROUP BY de.person_id
),

/* Lab concepts identified by OMOP concept name or LOINC-like concept code */
lab_measurements AS (
    SELECT
        m.person_id,
        m.measurement_date,
        c.concept_name,
        c.concept_code,
        m.value_as_number,
        CASE
            WHEN (
                    c.concept_name ~* 'hemoglobin a1c|hba1c|glycated hemoglobin'
                 OR c.concept_code IN ('4548-4', '17856-6', '4549-2')
                 )
                 AND m.value_as_number >= 6.5
            THEN 1

            WHEN (
                    c.concept_name ~* 'glucose.*fasting|fasting.*glucose'
                 OR c.concept_code IN ('1558-6', '14771-0')
                 )
                 AND m.value_as_number >= 126
            THEN 1

            WHEN (
                    c.concept_name ~* 'glucose'
                 OR c.concept_code IN ('2345-7', '14749-6', '15074-8')
                 )
                 AND m.value_as_number >= 200
            THEN 1

            ELSE 0
        END AS abnormal_diabetes_lab
    FROM public.measurement m
    JOIN public.concept c
      ON c.concept_id = m.measurement_concept_id
    WHERE m.value_as_number IS NOT NULL
      AND c.domain_id = 'Measurement'
      AND c.invalid_reason IS NULL
),

t2dm_lab AS (
    SELECT
        person_id,
        MIN(measurement_date) FILTER (WHERE abnormal_diabetes_lab = 1) AS first_abnormal_lab_date,
        COUNT(*) FILTER (WHERE abnormal_diabetes_lab = 1) AS abnormal_lab_count
    FROM lab_measurements
    WHERE abnormal_diabetes_lab = 1
    GROUP BY person_id
),

/* Combine diagnosis, medication, and laboratory evidence */
candidate_persons AS (
    SELECT
        p.person_id,
        COALESCE(dx.t2dm_dx_count, 0) AS t2dm_dx_count,
        COALESCE(med.t2dm_med_count, 0) AS t2dm_med_count,
        COALESCE(lab.abnormal_lab_count, 0) AS abnormal_lab_count,
        COALESCE(excl.exclusion_dx_count, 0) AS exclusion_dx_count
    FROM public.person p
    LEFT JOIN t2dm_dx dx
      ON dx.person_id = p.person_id
    LEFT JOIN t2dm_med med
      ON med.person_id = p.person_id
    LEFT JOIN t2dm_lab lab
      ON lab.person_id = p.person_id
    LEFT JOIN exclusion_dx excl
      ON excl.person_id = p.person_id
)

SELECT DISTINCT person_id
FROM candidate_persons
WHERE
    (
        /* Strong evidence: Type 2 diabetes diagnosis */
        t2dm_dx_count >= 1

        OR

        /* Supportive evidence: medication plus abnormal diabetes lab */
        (t2dm_med_count >= 1 AND abnormal_lab_count >= 1)

        OR

        /* Repeated abnormal diabetes labs */
        abnormal_lab_count >= 2
    )

    /* Exclude likely non-Type-2 diabetes unless Type 2 diagnosis is present */
    AND NOT (
        exclusion_dx_count > 0
        AND t2dm_dx_count = 0
    )
ORDER BY person_id;