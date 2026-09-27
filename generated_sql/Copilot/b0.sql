SELECT
    final.person_id,
    final.index_date
FROM (
    SELECT
        p.person_id,
        MIN(evidence.earliest_event_date) AS index_date
    FROM person p

    JOIN (
        ----------------------------------------------------------------------
        -- 1. T2DM DIAGNOSES
        ----------------------------------------------------------------------
        SELECT
            co.person_id,
            co.condition_start_date AS earliest_event_date
        FROM condition_occurrence co
        JOIN concept c ON co.condition_concept_id = c.concept_id
        WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
          AND (
                (c.vocabulary_id='ICD9CM'
                 AND c.concept_code LIKE '250%'
                 AND SUBSTRING(c.concept_code,5,1) IN ('0','2'))
             OR (c.vocabulary_id='ICD10CM'
                 AND c.concept_code LIKE 'E11%')
          )

        UNION ALL

        ----------------------------------------------------------------------
        -- 2. NON‑INSULIN DIABETES MEDICATIONS
        ----------------------------------------------------------------------
        SELECT
            de.person_id,
            de.drug_exposure_start_date AS earliest_event_date
        FROM drug_exposure de
        JOIN concept c ON de.drug_concept_id = c.concept_id
        WHERE c.vocabulary_id='RxNorm'
          AND c.standard_concept='S'
          AND (
                c.concept_name ILIKE '%metformin%' OR c.concept_name ILIKE '%Glucophage%' OR
                c.concept_name ILIKE '%Fortamet%' OR c.concept_name ILIKE '%Glumetza%' OR
                c.concept_name ILIKE '%Riomet%' OR

                c.concept_name ILIKE '%glipizide%' OR c.concept_name ILIKE '%glyburide%' OR
                c.concept_name ILIKE '%glimepiride%' OR

                c.concept_name ILIKE '%pioglitazone%' OR c.concept_name ILIKE '%rosiglitazone%' OR

                c.concept_name ILIKE '%sitagliptin%' OR c.concept_name ILIKE '%saxagliptin%' OR
                c.concept_name ILIKE '%linagliptin%' OR c.concept_name ILIKE '%alogliptin%' OR

                c.concept_name ILIKE '%exenatide%' OR c.concept_name ILIKE '%liraglutide%' OR
                c.concept_name ILIKE '%dulaglutide%' OR c.concept_name ILIKE '%semaglutide%' OR
                c.concept_name ILIKE '%lixisenatide%' OR

                c.concept_name ILIKE '%canagliflozin%' OR c.concept_name ILIKE '%dapagliflozin%' OR
                c.concept_name ILIKE '%empagliflozin%' OR c.concept_name ILIKE '%ertugliflozin%' OR

                c.concept_name ILIKE '%repaglinide%' OR c.concept_name ILIKE '%nateglinide%' OR

                c.concept_name ILIKE '%acarbose%' OR c.concept_name ILIKE '%miglitol%'
          )

        UNION ALL

        ----------------------------------------------------------------------
        -- 3. ABNORMAL DIABETES LABS
        ----------------------------------------------------------------------
        SELECT
            m.person_id,
            m.measurement_date AS earliest_event_date
        FROM measurement m
        JOIN concept c ON m.measurement_concept_id = c.concept_id
        WHERE c.vocabulary_id='LOINC'
          AND (
                (c.concept_code IN ('4548-4','17856-6','41995-2','59261-8')
                 AND m.value_as_number >= 6.5)
             OR (c.concept_code IN ('1558-6','14771-0')
                 AND m.value_as_number >= 126)
             OR (c.concept_code IN ('20436-2','14779-1')
                 AND m.value_as_number >= 200)
             OR (c.concept_code IN ('2339-0','2345-7')
                 AND m.value_as_number >= 200)
          )
    ) AS evidence
        ON p.person_id = evidence.person_id

    ----------------------------------------------------------------------
    -- EXCLUSIONS
    ----------------------------------------------------------------------
    LEFT JOIN (
        SELECT DISTINCT co.person_id
        FROM condition_occurrence co
        JOIN concept c ON co.condition_concept_id = c.concept_id
        WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
          AND (
                (c.vocabulary_id='ICD9CM'
                 AND SUBSTRING(c.concept_code,5,1) IN ('1','3'))
             OR (c.vocabulary_id='ICD10CM'
                 AND c.concept_code LIKE 'E10%')
             OR (c.vocabulary_id='ICD9CM'
                 AND c.concept_code LIKE '6488%')
             OR (c.vocabulary_id='ICD10CM'
                 AND c.concept_code LIKE 'O24.4%')
             OR (c.vocabulary_id='ICD10CM'
                 AND c.concept_code LIKE 'E08%')
             OR (c.vocabulary_id='ICD10CM'
                 AND c.concept_code LIKE 'E09%')
             OR (c.vocabulary_id='ICD10CM'
                 AND c.concept_code LIKE 'E13%')
          )
    ) AS excl ON excl.person_id = p.person_id

    WHERE excl.person_id IS NULL
    GROUP BY p.person_id
) AS final

JOIN person p2 ON p2.person_id = final.person_id

----------------------------------------------------------------------
-- AGE FILTER (valid because index_date is now available)
----------------------------------------------------------------------
WHERE DATE_PART('year', AGE(final.index_date, p2.birth_datetime)) >= 18;
