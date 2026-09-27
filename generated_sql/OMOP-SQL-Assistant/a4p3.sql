WITH
/* ICD-9-CM / ICD-10-CM source concepts for type 2 diabetes. */
icd_t2dm_source AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.invalid_reason IS NULL
      AND (
            /* ICD-10-CM E11.* = Type 2 diabetes mellitus */
            (c.vocabulary_id = 'ICD10CM' AND c.concept_code ~* '^E11(\.|$)')

            OR

            /* ICD-9-CM 250.x0 or 250.x2 = type II / unspecified type, not stated or uncontrolled */
            (
                c.vocabulary_id = 'ICD9CM'
                AND replace(c.concept_code, '.', '') ~ '^250[0-9][02]$'
            )
      )
),

/* Map ICD source diagnosis concepts to standard OMOP condition concepts. */
t2dm_condition_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS condition_concept_id
    FROM icd_t2dm_source s
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = s.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
),

/* ICD concepts for exclusion diagnoses: type 1, secondary, gestational, and pregnancy-related diabetes. */
icd_exclusion_source AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.invalid_reason IS NULL
      AND (
            /* ICD-10-CM exclusions */
            (
                c.vocabulary_id = 'ICD10CM'
                AND (
                       c.concept_code ~* '^E10(\.|$)'  -- Type 1 diabetes
                    OR c.concept_code ~* '^E08(\.|$)'  -- Diabetes due to underlying condition
                    OR c.concept_code ~* '^E09(\.|$)'  -- Drug/chemical induced diabetes
                    OR c.concept_code ~* '^E13(\.|$)'  -- Other specified diabetes
                    OR c.concept_code ~* '^O24(\.|$)'  -- Diabetes in pregnancy
                )
            )

            OR

            /* ICD-9-CM exclusions */
            (
                c.vocabulary_id = 'ICD9CM'
                AND (
                       replace(c.concept_code, '.', '') ~ '^250[0-9][13]$'  -- Type 1 diabetes
                    OR replace(c.concept_code, '.', '') ~ '^249[0-9][0-9]$'  -- Secondary diabetes
                    OR replace(c.concept_code, '.', '') ~ '^6488[0-9]$'      -- Diabetes in pregnancy
                )
            )
      )
),

/* Map exclusion ICD concepts to standard OMOP condition concepts. */
exclusion_condition_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS condition_concept_id
    FROM icd_exclusion_source s
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = s.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
),

/* T2DM diagnosis evidence from mapped standard condition_concept_id values. */
t2dm_dx AS (
    SELECT
        co.person_id,
        co.condition_start_date
    FROM public.condition_occurrence co
    JOIN t2dm_condition_concepts tc
      ON tc.condition_concept_id = co.condition_concept_id
    WHERE co.condition_start_date IS NOT NULL
),

/* Person-level diagnosis summary. */
t2dm_dx_summary AS (
    SELECT
        person_id,
        MIN(condition_start_date) AS first_t2dm_dx_date,
        COUNT(DISTINCT condition_start_date) AS distinct_t2dm_dx_dates
    FROM t2dm_dx
    GROUP BY person_id
),

/* Non-insulin diabetes medication concepts using generic and common brand names. */
t2dm_med_concepts AS (
    SELECT c.concept_id AS drug_concept_id
    FROM public.concept c
    WHERE c.invalid_reason IS NULL
      AND c.domain_id = 'Drug'
      AND c.concept_name ~* (
            'metformin|glucophage|fortamet|glumetza|riomet|' ||
            'glipizide|glucotrol|glyburide|diabeta|glynase|glycron|' ||
            'glimepiride|amaryl|' ||
            'pioglitazone|actos|rosiglitazone|avandia|' ||
            'sitagliptin|januvia|saxagliptin|onglyza|linagliptin|tradjenta|alogliptin|nesina|' ||
            'empagliflozin|jardiance|canagliflozin|invokana|dapagliflozin|farxiga|ertugliflozin|steglatro|' ||
            'liraglutide|victoza|semaglutide|ozempic|rybelsus|dulaglutide|trulicity|' ||
            'exenatide|byetta|bydureon|lixisenatide|adlyxin|tirzepatide|mounjaro|' ||
            'acarbose|precose|miglitol|glyset|repaglinide|prandin|nateglinide|starlix|pramlintide|symlin'
      )
      AND c.concept_name !~* 'insulin'
),

/* Medication evidence from populated drug_concept_id. */
t2dm_med AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN t2dm_med_concepts mc
      ON mc.drug_concept_id = de.drug_concept_id
    WHERE de.drug_exposure_start_date IS NOT NULL
),

/* Diabetes lab concepts by OMOP concept code/name: HbA1c and plasma/serum glucose. */
diabetes_lab_concepts AS (
    SELECT
        c.concept_id AS measurement_concept_id,
        CASE
            WHEN c.concept_code IN ('4548-4', '17856-6', '59261-8')
              OR c.concept_name ~* 'hemoglobin a1c|hba1c|glycated hemoglobin'
                THEN 'A1C'
            WHEN c.concept_code IN ('2345-7', '2339-0', '1558-6', '14749-6', '15074-8', '14995-5', '41653-7', '1557-8')
              OR c.concept_name ~* 'glucose'
                THEN 'GLUCOSE'
        END AS lab_type,
        c.concept_name
    FROM public.concept c
    WHERE c.invalid_reason IS NULL
      AND c.domain_id = 'Measurement'
      AND (
            c.concept_code IN (
                '4548-4', '17856-6', '59261-8',
                '2345-7', '2339-0', '1558-6', '14749-6', '15074-8', '14995-5', '41653-7', '1557-8'
            )
            OR c.concept_name ~* 'hemoglobin a1c|hba1c|glycated hemoglobin|glucose'
      )
),

/* Abnormal lab evidence consistent with diabetes. */
abnormal_diabetes_lab AS (
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN diabetes_lab_concepts lc
      ON lc.measurement_concept_id = m.measurement_concept_id
    WHERE m.value_as_number IS NOT NULL
      AND (
            /* HbA1c diagnostic threshold: >= 6.5% */
            (lc.lab_type = 'A1C' AND m.value_as_number >= 6.5)

            OR

            /* Fasting glucose diagnostic threshold: >= 126 mg/dL */
            (
                lc.lab_type = 'GLUCOSE'
                AND lc.concept_name ~* 'fasting'
                AND m.value_as_number >= 126
            )

            OR

            /* Random / unspecified glucose threshold: >= 200 mg/dL */
            (
                lc.lab_type = 'GLUCOSE'
                AND m.value_as_number >= 200
            )
      )
),

/* Exclusion diagnosis evidence. */
exclusion_dx AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN exclusion_condition_concepts ec
      ON ec.condition_concept_id = co.condition_concept_id
    JOIN t2dm_dx_summary ds
      ON ds.person_id = co.person_id
    WHERE co.condition_start_date IS NOT NULL
      AND co.condition_start_date <= ds.first_t2dm_dx_date
)

/* Final T2DM cohort: diagnosis-based phenotype with medication or lab support when only one diagnosis date exists. */
SELECT DISTINCT ds.person_id
FROM t2dm_dx_summary ds
WHERE (
        ds.distinct_t2dm_dx_dates >= 2
        OR (
            ds.distinct_t2dm_dx_dates >= 1
            AND (
                EXISTS (
                    SELECT 1
                    FROM t2dm_med med
                    WHERE med.person_id = ds.person_id
                )
                OR EXISTS (
                    SELECT 1
                    FROM abnormal_diabetes_lab lab
                    WHERE lab.person_id = ds.person_id
                )
            )
        )
      )
  AND NOT EXISTS (
        SELECT 1
        FROM exclusion_dx ex
        WHERE ex.person_id = ds.person_id
  )
ORDER BY ds.person_id;