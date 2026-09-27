-- ============================================================================
-- minimal changes made to make the query work / show results
-- ============================================================================
-- 1. kept the phenotype logic the same:
--      diagnosis OR medication OR abnormal lab OR symptoms
--      minus type 1 / gestational / secondary diabetes
--
-- 2. changed ICD diagnosis matching to check both:
--      condition_concept_id
--      condition_source_concept_id
--    because in standard OMOP, ICD codes are often stored as source concepts,
--    while condition_concept_id may map to SNOMED.
--
-- 3. changed exact concept_name IN matches to case-insensitive LIKE matches.
--    This keeps the same clinical criteria but avoids missing standard OMOP names
--    such as longer RxNorm/LOINC labels.
--
-- 4. changed the lab threshold CASE logic to direct OR conditions.
--    This avoids NULL or multi-row scalar subquery issues from concept lookup.
--
-- 5. changed exclusion matching to use both concept_code and concept_name,
--    because ICD vocabularies usually do not have concept names like
--    'Type 1 diabetes mellitus' exactly.
-- ============================================================================

SELECT DISTINCT person_id
FROM (
    SELECT co.person_id
    FROM public.condition_occurrence co
    JOIN public.concept c
        ON co.condition_concept_id = c.concept_id
        OR co.condition_source_concept_id = c.concept_id
    WHERE (
        c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
        AND c.concept_code IN (
            '250.00', '250.02',
            'E11', 'E11.0', 'E11.1', 'E11.2', 'E11.3', 'E11.4',
            'E11.5', 'E11.6', 'E11.7', 'E11.8', 'E11.9'
        )
    )

    UNION

    SELECT de.person_id
    FROM public.drug_exposure de
    JOIN public.concept c
        ON de.drug_concept_id = c.concept_id
    WHERE c.vocabulary_id = 'RxNorm'
      AND (
          LOWER(c.concept_name) LIKE '%metformin%'
          OR LOWER(c.concept_name) LIKE '%glipizide%'
          OR LOWER(c.concept_name) LIKE '%glyburide%'
          OR LOWER(c.concept_name) LIKE '%repaglinide%'
          OR LOWER(c.concept_name) LIKE '%nateglinide%'
          OR LOWER(c.concept_name) LIKE '%pioglitazone%'
          OR LOWER(c.concept_name) LIKE '%rosiglitazone%'
          OR LOWER(c.concept_name) LIKE '%sitagliptin%'
          OR LOWER(c.concept_name) LIKE '%saxagliptin%'
          OR LOWER(c.concept_name) LIKE '%exenatide%'
          OR LOWER(c.concept_name) LIKE '%liraglutide%'
          OR LOWER(c.concept_name) LIKE '%canagliflozin%'
          OR LOWER(c.concept_name) LIKE '%empagliflozin%'
          OR LOWER(c.concept_name) LIKE '%glucophage%'
          OR LOWER(c.concept_name) LIKE '%glucotrol%'
          OR LOWER(c.concept_name) LIKE '%micronase%'
      )

    UNION

    SELECT m.person_id
    FROM public.measurement m
    JOIN public.concept c
        ON m.measurement_concept_id = c.concept_id
    WHERE c.vocabulary_id = 'LOINC'
      AND m.value_as_number IS NOT NULL
      AND (
          (
              LOWER(c.concept_name) LIKE '%hemoglobin a1c%'
              AND m.value_as_number > 6.5
          )
          OR (
              LOWER(c.concept_name) LIKE '%fasting%glucose%'
              AND m.value_as_number > 126
          )
          OR (
              (
                  LOWER(c.concept_name) LIKE '%2-hour%glucose%'
                  OR LOWER(c.concept_name) LIKE '%2 hour%glucose%'
              )
              AND m.value_as_number > 200
          )
      )

    UNION

    SELECT co.person_id
    FROM public.condition_occurrence co
    JOIN public.concept c
        ON co.condition_concept_id = c.concept_id
        OR co.condition_source_concept_id = c.concept_id
    WHERE c.vocabulary_id = 'SNOMED'
      AND (
          LOWER(c.concept_name) LIKE '%polyuria%'
          OR LOWER(c.concept_name) LIKE '%polydipsia%'
          OR LOWER(c.concept_name) LIKE '%polyphagia%'
          OR LOWER(c.concept_name) LIKE '%unexplained weight loss%'
      )
) AS combined
WHERE person_id NOT IN (
    SELECT co.person_id
    FROM public.condition_occurrence co
    JOIN public.concept c
        ON co.condition_concept_id = c.concept_id
        OR co.condition_source_concept_id = c.concept_id
    WHERE (
        (
            c.vocabulary_id = 'ICD10CM'
            AND (
                c.concept_code = 'E10'
                OR c.concept_code LIKE 'E10.%'
                OR c.concept_code LIKE 'O24.4%'
                OR c.concept_code LIKE 'E08.%'
                OR c.concept_code LIKE 'E09.%'
                OR c.concept_code LIKE 'E13.%'
            )
        )
        OR (
            c.vocabulary_id = 'ICD9CM'
            AND (
                c.concept_code IN (
                    '250.01', '250.03', '250.11', '250.13',
                    '250.21', '250.23', '250.31', '250.33',
                    '250.41', '250.43', '250.51', '250.53',
                    '250.61', '250.63', '250.71', '250.73',
                    '250.81', '250.83', '250.91', '250.93',
                    '648.80', '648.81', '648.82', '648.83', '648.84'
                )
            )
        )
        OR (
            LOWER(c.concept_name) LIKE '%type 1 diabetes%'
            OR LOWER(c.concept_name) LIKE '%diabetes mellitus type 1%'
            OR LOWER(c.concept_name) LIKE '%gestational diabetes%'
            OR LOWER(c.concept_name) LIKE '%secondary diabetes%'
        )
    )
);