WITH
/* ICD9CM/ICD10CM source concepts for type 2 diabetes */
t2dm_icd_source AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND c.invalid_reason IS NULL
      AND (
            /* ICD10CM type 2 diabetes mellitus */
            (c.vocabulary_id = 'ICD10CM' AND c.concept_code ~* '^E11')
            OR
            /* ICD9CM diabetes mellitus type II or unspecified type, not stated as uncontrolled/controlled */
            (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~* '^250\.[0-9][02]$')
          )
),

/* Map ICD source concepts to standard condition concepts */
t2dm_standard_condition AS (
    SELECT DISTINCT cr.concept_id_2 AS condition_concept_id
    FROM t2dm_icd_source s
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = s.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
),

/* T2DM diagnosis events */
t2dm_dx AS (
    SELECT
        co.person_id,
        co.condition_start_date AS event_date
    FROM public.condition_occurrence co
    JOIN t2dm_standard_condition t
      ON t.condition_concept_id = co.condition_concept_id
    WHERE co.condition_start_date IS NOT NULL
),

/* Exclusion ICD concepts: type 1, gestational, and secondary diabetes */
exclusion_icd_source AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND c.invalid_reason IS NULL
      AND (
            /* ICD10CM type 1 diabetes */
            c.concept_code ~* '^E10'
            OR
            /* ICD10CM gestational diabetes */
            c.concept_code ~* '^O24\.4'
            OR
            /* ICD10CM secondary diabetes */
            c.concept_code ~* '^E08|^E09|^E13'
            OR
            /* ICD9CM type 1 diabetes: 250.x1 or 250.x3 */
            c.concept_code ~* '^250\.[0-9][13]$'
            OR
            /* ICD9CM secondary diabetes */
            c.concept_code ~* '^249'
            OR
            /* ICD9CM gestational diabetes */
            c.concept_code ~* '^648\.8'
          )
),

/* Map exclusion ICD concepts to standard condition concepts */
exclusion_standard_condition AS (
    SELECT DISTINCT cr.concept_id_2 AS condition_concept_id
    FROM exclusion_icd_source s
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = s.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
),

/* Patients with exclusion diagnoses */
excluded_persons AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN exclusion_standard_condition e
      ON e.condition_concept_id = co.condition_concept_id
),

/* Diabetes medication ingredients, classes, and major brand names */
diabetes_drug_seed AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Drug'
      AND c.invalid_reason IS NULL
      AND (
            c.concept_name ~* '\mmetformin\M'
         OR c.concept_name ~* '\minsulin\M'
         OR c.concept_name ~* '\mglipizide\M'
         OR c.concept_name ~* '\mglyburide\M'
         OR c.concept_name ~* '\mglimepiride\M'
         OR c.concept_name ~* '\mpioglitazone\M'
         OR c.concept_name ~* '\mrosiglitazone\M'
         OR c.concept_name ~* '\msitagliptin\M'
         OR c.concept_name ~* '\msaxagliptin\M'
         OR c.concept_name ~* '\mlinagliptin\M'
         OR c.concept_name ~* '\malogliptin\M'
         OR c.concept_name ~* '\msemaglutide\M'
         OR c.concept_name ~* '\mliraglutide\M'
         OR c.concept_name ~* '\mdulaglutide\M'
         OR c.concept_name ~* '\mexenatide\M'
         OR c.concept_name ~* '\mlixisenatide\M'
         OR c.concept_name ~* '\mtirzepatide\M'
         OR c.concept_name ~* '\mcanagliflozin\M'
         OR c.concept_name ~* '\mdapagliflozin\M'
         OR c.concept_name ~* '\mempagliflozin\M'
         OR c.concept_name ~* '\mertugliflozin\M'
         OR c.concept_name ~* '\macarbose\M'
         OR c.concept_name ~* '\mmiglitol\M'
         OR c.concept_name ~* '\mrepaglinide\M'
         OR c.concept_name ~* '\mnateglinide\M'

         /* Common brand names */
         OR c.concept_name ~* '\mGlucophage\M'
         OR c.concept_name ~* '\mFortamet\M'
         OR c.concept_name ~* '\mGlumetza\M'
         OR c.concept_name ~* '\mAmaryl\M'
         OR c.concept_name ~* '\mGlucotrol\M'
         OR c.concept_name ~* '\mMicronase\M'
         OR c.concept_name ~* '\mDiabeta\M'
         OR c.concept_name ~* '\mActos\M'
         OR c.concept_name ~* '\mAvandia\M'
         OR c.concept_name ~* '\mJanuvia\M'
         OR c.concept_name ~* '\mOnglyza\M'
         OR c.concept_name ~* '\mTradjenta\M'
         OR c.concept_name ~* '\mNesina\M'
         OR c.concept_name ~* '\mOzempic\M'
         OR c.concept_name ~* '\mRybelsus\M'
         OR c.concept_name ~* '\mVictoza\M'
         OR c.concept_name ~* '\mTrulicity\M'
         OR c.concept_name ~* '\mByetta\M'
         OR c.concept_name ~* '\mBydureon\M'
         OR c.concept_name ~* '\mMounjaro\M'
         OR c.concept_name ~* '\mInvokana\M'
         OR c.concept_name ~* '\mFarxiga\M'
         OR c.concept_name ~* '\mJardiance\M'
         OR c.concept_name ~* '\mSteglatro\M'
          )
),

/* Include descendant clinical drug concepts */
diabetes_drug_concepts AS (
    SELECT DISTINCT concept_id AS drug_concept_id
    FROM diabetes_drug_seed

    UNION

    SELECT DISTINCT ca.descendant_concept_id AS drug_concept_id
    FROM diabetes_drug_seed s
    JOIN public.concept_ancestor ca
      ON ca.ancestor_concept_id = s.concept_id
),

/* Diabetes medication exposure */
diabetes_med AS (
    SELECT DISTINCT
        de.person_id,
        de.drug_exposure_start_date AS event_date
    FROM public.drug_exposure de
    JOIN diabetes_drug_concepts d
      ON d.drug_concept_id = de.drug_concept_id
    WHERE de.drug_exposure_start_date IS NOT NULL
),

/* Diabetes-related laboratory concepts using OMOP concept names and LOINC-like codes */
diabetes_lab_concepts AS (
    SELECT
        c.concept_id AS measurement_concept_id,
        CASE
            WHEN c.concept_name ~* 'A1c|HbA1c|Hemoglobin A1c|Glycohemoglobin'
              OR c.concept_code IN ('4548-4', '4549-2', '17856-6', '59261-8')
                THEN 'a1c'
            WHEN c.concept_name ~* 'glucose'
              OR c.concept_code IN ('2345-7', '1558-6', '14749-6', '2339-0')
                THEN 'glucose'
        END AS lab_type
    FROM public.concept c
    WHERE c.domain_id = 'Measurement'
      AND c.invalid_reason IS NULL
      AND (
            c.concept_name ~* 'A1c|HbA1c|Hemoglobin A1c|Glycohemoglobin'
         OR c.concept_code IN ('4548-4', '4549-2', '17856-6', '59261-8')
         OR c.concept_name ~* 'glucose'
         OR c.concept_code IN ('2345-7', '1558-6', '14749-6', '2339-0')
          )
),

/* Abnormal diabetes labs */
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
            /* HbA1c percentage threshold */
            (lc.lab_type = 'a1c' AND m.value_as_number >= 6.5)

            OR

            /* Glucose threshold in mg/dL */
            (lc.lab_type = 'glucose' AND m.value_as_number >= 200)

            OR

            /* Fasting plasma glucose threshold when fasting/random detail is unavailable */
            (
                lc.lab_type = 'glucose'
                AND m.value_as_number >= 126
                AND (
                       m.measurement_source_value IN ('1558-6', '14749-6')
                    OR m.value_source_value ~* 'fasting'
                    OR m.measurement_source_value ~* 'fasting'
                    OR m.measurement_source_value ~* 'fast'
                )
            )
          )
),

/* Summarize diagnosis evidence */
dx_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS t2dm_dx_dates,
        MIN(event_date) AS first_dx_date
    FROM t2dm_dx
    GROUP BY person_id
),

/* Summarize medication evidence */
med_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS diabetes_med_dates,
        MIN(event_date) AS first_med_date
    FROM diabetes_med
    GROUP BY person_id
),

/* Summarize laboratory evidence */
lab_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS abnormal_lab_dates,
        MIN(event_date) AS first_lab_date
    FROM abnormal_labs
    GROUP BY person_id
),

/* Combine phenotype evidence */
candidate_t2dm AS (
    SELECT
        p.person_id
    FROM public.person p
    LEFT JOIN dx_summary dx
      ON dx.person_id = p.person_id
    LEFT JOIN med_summary med
      ON med.person_id = p.person_id
    LEFT JOIN lab_summary lab
      ON lab.person_id = p.person_id
    WHERE
          COALESCE(dx.t2dm_dx_dates, 0) >= 2
       OR (
              COALESCE(dx.t2dm_dx_dates, 0) >= 1
          AND COALESCE(med.diabetes_med_dates, 0) >= 1
          )
       OR COALESCE(lab.abnormal_lab_dates, 0) >= 2
)

/* Final T2DM phenotype cohort */
SELECT DISTINCT c.person_id
FROM candidate_t2dm c
WHERE NOT EXISTS (
    SELECT 1
    FROM excluded_persons e
    WHERE e.person_id = c.person_id
)
ORDER BY c.person_id;