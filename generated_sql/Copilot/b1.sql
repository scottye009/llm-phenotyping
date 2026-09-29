Prompt 1 result:


SELECT DISTINCT
    p.person_id,
    index_events.index_date,
    (EXTRACT(YEAR FROM index_events.index_date) - p.year_of_birth) AS age_at_index
FROM public.person p

/* -----------------------------
   1. T2DM DIAGNOSES (ICD9CM + ICD10CM)
   ----------------------------- */
LEFT JOIN (
    SELECT
        co.person_id,
        MIN(co.condition_start_date) AS index_date,
        COUNT(DISTINCT co.condition_start_date) AS dx_dates
    FROM public.condition_occurrence co
    JOIN public.concept c
        ON co.condition_concept_id = c.concept_id
    WHERE c.domain_id = 'Condition'
      AND c.standard_concept = 'S'
      AND (
            /* ICD9CM 250.x0 or 250.x2 */
            (c.vocabulary_id = 'ICD9CM'
             AND c.concept_code LIKE '250.%'
             AND RIGHT(c.concept_code, 1) IN ('0','2'))
            OR
            /* ICD10CM E11% */
            (c.vocabulary_id = 'ICD10CM'
             AND c.concept_code LIKE 'E11%')
          )
    GROUP BY co.person_id
) t2dx
ON p.person_id = t2dx.person_id

/* -----------------------------
   2. TYPE 1 DIABETES EXCLUSION
   ----------------------------- */
LEFT JOIN (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN public.concept c
        ON co.condition_concept_id = c.concept_id
    WHERE c.domain_id = 'Condition'
      AND c.standard_concept = 'S'
      AND (
            /* ICD9CM 250.x1 or 250.x3 */
            (c.vocabulary_id = 'ICD9CM'
             AND c.concept_code LIKE '250.%'
             AND RIGHT(c.concept_code, 1) IN ('1','3'))
            OR
            /* ICD10CM E10% */
            (c.vocabulary_id = 'ICD10CM'
             AND c.concept_code LIKE 'E10%')
          )
) t1dx
ON p.person_id = t1dx.person_id

/* -----------------------------
   3. GESTATIONAL DIABETES EXCLUSION
   ----------------------------- */
LEFT JOIN (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN public.concept c
        ON co.condition_concept_id = c.concept_id
    WHERE c.domain_id = 'Condition'
      AND c.standard_concept = 'S'
      AND (
            (c.vocabulary_id = 'ICD9CM' AND c.concept_code LIKE '648.8%')
            OR
            (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'O24.4%')
            OR
            (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'O24.9%')
          )
) gestdx
ON p.person_id = gestdx.person_id

/* -----------------------------
   4. SECONDARY DIABETES EXCLUSION
   ----------------------------- */
LEFT JOIN (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN public.concept c
        ON co.condition_concept_id = c.concept_id
    WHERE c.domain_id = 'Condition'
      AND c.standard_concept = 'S'
      AND c.vocabulary_id = 'ICD10CM'
      AND (
            c.concept_code LIKE 'E08%'
            OR c.concept_code LIKE 'E09%'
            OR c.concept_code LIKE 'E13%'
          )
) secdx
ON p.person_id = secdx.person_id

/* -----------------------------
   5. NON‑INSULIN ANTIHYPERGLYCEMIC MEDICATIONS
   ----------------------------- */
LEFT JOIN (
    SELECT
        de.person_id,
        MIN(de.drug_exposure_start_date) AS med_date,
        COUNT(DISTINCT de.drug_exposure_start_date) AS med_count
    FROM public.drug_exposure de
    JOIN public.concept c
        ON de.drug_concept_id = c.concept_id
    WHERE c.domain_id = 'Drug'
      AND c.vocabulary_id = 'RxNorm'
      AND c.standard_concept = 'S'
      AND (
            /* Biguanides */
            LOWER(c.concept_name) LIKE '%metformin%' OR
            LOWER(c.concept_name) LIKE '%glucophage%' OR
            LOWER(c.concept_name) LIKE '%glumetza%' OR
            LOWER(c.concept_name) LIKE '%fortamet%' OR
            LOWER(c.concept_name) LIKE '%riomet%' OR

            /* Sulfonylureas */
            LOWER(c.concept_name) LIKE '%glipizide%' OR
            LOWER(c.concept_name) LIKE '%glucotrol%' OR
            LOWER(c.concept_name) LIKE '%glyburide%' OR
            LOWER(c.concept_name) LIKE '%diabeta%' OR
            LOWER(c.concept_name) LIKE '%micronase%' OR
            LOWER(c.concept_name) LIKE '%glimepiride%' OR
            LOWER(c.concept_name) LIKE '%amaryl%' OR

            /* TZDs */
            LOWER(c.concept_name) LIKE '%pioglitazone%' OR
            LOWER(c.concept_name) LIKE '%actos%' OR
            LOWER(c.concept_name) LIKE '%rosiglitazone%' OR
            LOWER(c.concept_name) LIKE '%avandia%' OR

            /* DPP‑4 inhibitors */
            LOWER(c.concept_name) LIKE '%sitagliptin%' OR
            LOWER(c.concept_name) LIKE '%januvia%' OR
            LOWER(c.concept_name) LIKE '%saxagliptin%' OR
            LOWER(c.concept_name) LIKE '%onglyza%' OR
            LOWER(c.concept_name) LIKE '%linagliptin%' OR
            LOWER(c.concept_name) LIKE '%tradjenta%' OR
            LOWER(c.concept_name) LIKE '%alogliptin%' OR
            LOWER(c.concept_name) LIKE '%nesina%' OR

            /* GLP‑1 agonists */
            LOWER(c.concept_name) LIKE '%exenatide%' OR
            LOWER(c.concept_name) LIKE '%byetta%' OR
            LOWER(c.concept_name) LIKE '%bydureon%' OR
            LOWER(c.concept_name) LIKE '%liraglutide%' OR
            LOWER(c.concept_name) LIKE '%victoza%' OR
            LOWER(c.concept_name) LIKE '%dulaglutide%' OR
            LOWER(c.concept_name) LIKE '%trulicity%' OR
            LOWER(c.concept_name) LIKE '%semaglutide%' OR
            LOWER(c.concept_name) LIKE '%ozempic%' OR
            LOWER(c.concept_name) LIKE '%rybelsus%' OR

            /* SGLT2 inhibitors */
            LOWER(c.concept_name) LIKE '%canagliflozin%' OR
            LOWER(c.concept_name) LIKE '%invokana%' OR
            LOWER(c.concept_name) LIKE '%dapagliflozin%' OR
            LOWER(c.concept_name) LIKE '%farxiga%' OR
            LOWER(c.concept_name) LIKE '%empagliflozin%' OR
            LOWER(c.concept_name) LIKE '%jardiance%' OR
            LOWER(c.concept_name) LIKE '%ertugliflozin%' OR
            LOWER(c.concept_name) LIKE '%steglatro%' OR

            /* Meglitinides */
            LOWER(c.concept_name) LIKE '%nateglinide%' OR
            LOWER(c.concept_name) LIKE '%repaglinide%' OR

            /* Alpha‑glucosidase inhibitors */
            LOWER(c.concept_name) LIKE '%acarbose%' OR
            LOWER(c.concept_name) LIKE '%miglitol%'
          )
    GROUP BY de.person_id
) meds
ON p.person_id = meds.person_id

/* -----------------------------
   6. ABNORMAL LABS (LOINC)
   ----------------------------- */
LEFT JOIN (
    SELECT
        m.person_id,
        COUNT(DISTINCT m.measurement_date) AS abnormal_lab_dates,
        MIN(m.measurement_date) AS first_abnormal_date
    FROM public.measurement m
    JOIN public.concept c
        ON m.measurement_concept_id = c.concept_id
    WHERE c.domain_id = 'Measurement'
      AND c.vocabulary_id = 'LOINC'
      AND (
            /* HbA1c ≥ 6.5% */
            (c.concept_code IN ('4548-4','17856-6','41995-2','59261-8')
             AND m.value_as_number >= 6.5)
            OR
            /* Fasting glucose ≥ 126 mg/dL */
            (c.concept_code IN ('1558-6','1557-8')
             AND m.value_as_number >= 126)
            OR
            /* OGTT ≥ 200 mg/dL */
            (c.concept_code IN ('20436-2','14749-6')
             AND m.value_as_number >= 200)
            OR
            /* Random glucose ≥ 200 mg/dL */
            (c.concept_code IN ('2345-7','2339-0')
             AND m.value_as_number >= 200)
          )
    GROUP BY m.person_id
) labs
ON p.person_id = labs.person_id

/* -----------------------------
   7. OBSERVATION PERIOD COVERAGE
   ----------------------------- */
JOIN public.observation_period op
ON p.person_id = op.person_id

/* -----------------------------
   8. INDEX DATE SELECTION
   ----------------------------- */
LEFT JOIN (
    SELECT
        person_id,
        MIN(event_date) AS index_date
    FROM (
        SELECT person_id, condition_start_date AS event_date
        FROM public.condition_occurrence co
        JOIN public.concept c
            ON co.condition_concept_id = c.concept_id
        WHERE c.standard_concept = 'S'
          AND (
                (c.vocabulary_id = 'ICD9CM'
                 AND c.concept_code LIKE '250.%'
                 AND RIGHT(c.concept_code,1) IN ('0','2'))
                OR
                (c.vocabulary_id = 'ICD10CM'
                 AND c.concept_code LIKE 'E11%')
              )

        UNION ALL
        SELECT person_id, drug_exposure_start_date
        FROM public.drug_exposure de
        JOIN public.concept c
            ON de.drug_concept_id = c.concept_id
        WHERE c.standard_concept = 'S'
          AND c.vocabulary_id = 'RxNorm'
          AND (
                LOWER(c.concept_name) LIKE '%metformin%' OR
                LOWER(c.concept_name) LIKE '%glipizide%' OR
                LOWER(c.concept_name) LIKE '%glyburide%' OR
                LOWER(c.concept_name) LIKE '%glimepiride%' OR
                LOWER(c.concept_name) LIKE '%pioglitazone%' OR
                LOWER(c.concept_name) LIKE '%rosiglitazone%' OR
                LOWER(c.concept_name) LIKE '%sitagliptin%' OR
                LOWER(c.concept_name) LIKE '%saxagliptin%' OR
                LOWER(c.concept_name) LIKE '%linagliptin%' OR
                LOWER(c.concept_name) LIKE '%alogliptin%' OR
                LOWER(c.concept_name) LIKE '%exenatide%' OR
                LOWER(c.concept_name) LIKE '%liraglutide%' OR
                LOWER(c.concept_name) LIKE '%dulaglutide%' OR
                LOWER(c.concept_name) LIKE '%semaglutide%' OR
                LOWER(c.concept_name) LIKE '%canagliflozin%' OR
                LOWER(c.concept_name) LIKE '%dapagliflozin%' OR
                LOWER(c.concept_name) LIKE '%empagliflozin%' OR
                LOWER(c.concept_name) LIKE '%ertugliflozin%' OR
                LOWER(c.concept_name) LIKE '%acarbose%' OR
                LOWER(c.concept_name) LIKE '%miglitol%' OR
                LOWER(c.concept_name) LIKE '%nateglinide%' OR
                LOWER(c.concept_name) LIKE '%repaglinide%'
              )

        UNION ALL
        SELECT person_id, measurement_date
        FROM public.measurement m
        JOIN public.concept c
            ON m.measurement_concept_id = c.concept_id
        WHERE c.vocabulary_id = 'LOINC'
          AND (
                (c.concept_code IN ('4548-4','17856-6','41995-2','59261-8')
                 AND m.value_as_number >= 6.5)
                OR
                (c.concept_code IN ('1558-6','1557-8')
                 AND m.value_as_number >= 126)
                OR
                (c.concept_code IN ('20436-2','14749-6')
                 AND m.value_as_number >= 200)
                OR
                (c.concept_code IN ('2345-7','2339-0')
                 AND m.value_as_number >= 200)
              )
    ) e
    GROUP BY person_id
) index_events
ON p.person_id = index_events.person_id

/* -----------------------------
   9. FINAL COHORT LOGIC (OPTION B)
   ----------------------------- */
WHERE
    /* Age ≥ 18 */
    (EXTRACT(YEAR FROM index_events.index_date) - p.year_of_birth) >= 18

    /* Observation period covers index date */
    AND index_events.index_date BETWEEN op.observation_period_start_date
                                    AND op.observation_period_end_date

    /* Exclusions */
    AND t1dx.person_id IS NULL
    AND gestdx.person_id IS NULL
    AND secdx.person_id IS NULL

    /* Inclusion logic (Option B) */
    AND (
            /* ≥2 T2DM dx dates */
            (t2dx.dx_dates >= 2)

            OR

            /* ≥1 T2DM dx AND ≥1 non‑insulin medication */
            (t2dx.dx_dates >= 1 AND meds.med_count >= 1)

            OR

            /* ≥2 abnormal labs AND ≥1 non‑insulin medication */
            (labs.abnormal_lab_dates >= 2 AND meds.med_count >= 1)
        )

ORDER BY p.person_id;


