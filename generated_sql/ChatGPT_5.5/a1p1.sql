WITH t2dm_diagnosis_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM public.concept c
    JOIN public.concept_relationship cr
        ON c.concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'
      AND (
            (
                c.vocabulary_id = 'ICD9CM'
                AND REPLACE(c.concept_code, '.', '') IN (
                    '25000','25002',
                    '25010','25012',
                    '25020','25022',
                    '25030','25032',
                    '25040','25042',
                    '25050','25052',
                    '25060','25062',
                    '25070','25072',
                    '25080','25082',
                    '25090','25092'
                )
            )
            OR (
                c.vocabulary_id = 'ICD10CM'
                AND c.concept_code LIKE 'E11%'
            )
      )
),

exclude_diabetes_diagnosis_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM public.concept c
    JOIN public.concept_relationship cr
        ON c.concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'
      AND (
            (
                c.vocabulary_id = 'ICD10CM'
                AND (
                    c.concept_code LIKE 'E10%' OR
                    c.concept_code LIKE 'E08%' OR
                    c.concept_code LIKE 'E09%' OR
                    c.concept_code LIKE 'E13%' OR
                    c.concept_code LIKE 'O24.4%'
                )
            )
            OR (
                c.vocabulary_id = 'ICD9CM'
                AND (
                    REPLACE(c.concept_code, '.', '') LIKE '249%' OR
                    REPLACE(c.concept_code, '.', '') IN (
                        '64800','64801','64802','64803','64804',
                        '64880','64881','64882','64883','64884'
                    )
                )
            )
      )
),

t2dm_diagnosis_evidence AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN t2dm_diagnosis_concepts dx
        ON co.condition_concept_id = dx.concept_id
),

exclude_diagnosis_evidence AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN exclude_diabetes_diagnosis_concepts dx
        ON co.condition_concept_id = dx.concept_id
),

abnormal_lab_evidence AS (
    SELECT
        m.person_id,
        COUNT(*) AS abnormal_lab_count
    FROM public.measurement m
    JOIN public.concept c
        ON m.measurement_concept_id = c.concept_id
    WHERE m.value_as_number IS NOT NULL
      AND (
            (
                c.concept_name ILIKE '%hemoglobin a1c%'
                AND m.value_as_number >= 6.5
            )
            OR (
                (
                    c.concept_name ILIKE '%glucose%'
                    OR c.concept_name ILIKE '%fasting glucose%'
                    OR c.concept_name ILIKE '%glucose fasting%'
                )
                AND m.value_as_number >= 126
            )
            OR (
                (
                    c.concept_name ILIKE '%random glucose%'
                    OR c.concept_name ILIKE '%glucose random%'
                )
                AND m.value_as_number >= 200
            )
            OR (
                (
                    c.concept_name ILIKE '%oral glucose tolerance%'
                    OR c.concept_name ILIKE '%glucose tolerance%'
                    OR c.concept_name ILIKE '%2 hour glucose%'
                )
                AND m.value_as_number >= 200
            )
      )
    GROUP BY m.person_id
),

t2dm_medication_evidence AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN public.concept c
        ON de.drug_concept_id = c.concept_id
    WHERE
        c.concept_name ILIKE ANY (ARRAY[
            '%metformin%',
            '%glucophage%',
            '%glumetza%',
            '%fortamet%',

            '%sitagliptin%',
            '%januvia%',
            '%janumet%',
            '%linagliptin%',
            '%tradjenta%',
            '%saxagliptin%',
            '%onglyza%',
            '%alogliptin%',
            '%nesina%',

            '%empagliflozin%',
            '%jardiance%',
            '%dapagliflozin%',
            '%farxiga%',
            '%canagliflozin%',
            '%invokana%',
            '%ertugliflozin%',
            '%steglatro%',

            '%semaglutide%',
            '%ozempic%',
            '%rybelsus%',
            '%liraglutide%',
            '%victoza%',
            '%dulaglutide%',
            '%trulicity%',
            '%exenatide%',
            '%byetta%',
            '%bydureon%',
            '%tirzepatide%',
            '%mounjaro%',

            '%pioglitazone%',
            '%actos%',
            '%rosiglitazone%',
            '%avandia%',

            '%glipizide%',
            '%glucotrol%',
            '%glyburide%',
            '%diabeta%',
            '%glynase%',
            '%glimepiride%',
            '%amaryl%',

            '%repaglinide%',
            '%prandin%',
            '%nateglinide%',
            '%starlix%',

            '%acarbose%',
            '%precose%',
            '%miglitol%',
            '%glyset%'
        ])
),

phenotype_flags AS (
    SELECT
        p.person_id,

        CASE
            WHEN dx.person_id IS NOT NULL THEN 1
            ELSE 0
        END AS has_t2dm_diagnosis,

        CASE
            WHEN lab.abnormal_lab_count >= 2 THEN 1
            ELSE 0
        END AS has_repeated_abnormal_labs,

        CASE
            WHEN med.person_id IS NOT NULL THEN 1
            ELSE 0
        END AS has_t2dm_medication,

        CASE
            WHEN ex.person_id IS NOT NULL THEN 1
            ELSE 0
        END AS has_exclusion_diagnosis

    FROM public.person p
    LEFT JOIN t2dm_diagnosis_evidence dx
        ON p.person_id = dx.person_id
    LEFT JOIN abnormal_lab_evidence lab
        ON p.person_id = lab.person_id
    LEFT JOIN t2dm_medication_evidence med
        ON p.person_id = med.person_id
    LEFT JOIN exclude_diagnosis_evidence ex
        ON p.person_id = ex.person_id
)

SELECT DISTINCT person_id
FROM phenotype_flags
WHERE
    (
        has_t2dm_diagnosis = 1
        OR has_repeated_abnormal_labs = 1
        OR (
            has_t2dm_medication = 1
            AND (
                has_t2dm_diagnosis = 1
                OR has_repeated_abnormal_labs = 1
            )
        )
    )
    AND NOT has_exclusion_diagnosis = 1;