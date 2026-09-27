WITH icd_t2dm_source AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (
            (
                vocabulary_id = 'ICD9CM'
                AND REPLACE(concept_code, '.', '') ~ '^250[0-9][02]$'
            )
            OR
            (
                vocabulary_id = 'ICD10CM'
                AND REPLACE(concept_code, '.', '') LIKE 'E11%'
            )
      )
),

icd_t2dm_standard AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM public.concept_relationship cr
    JOIN icd_t2dm_source s
      ON cr.concept_id_1 = s.concept_id
    WHERE cr.relationship_id = 'Maps to'
),

t2dm_diagnosis AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (
        SELECT concept_id FROM icd_t2dm_standard
    )
),

icd_t1dm_source AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (
            (
                vocabulary_id = 'ICD9CM'
                AND REPLACE(concept_code, '.', '') ~ '^250[0-9][13]$'
            )
            OR
            (
                vocabulary_id = 'ICD10CM'
                AND REPLACE(concept_code, '.', '') LIKE 'E10%'
            )
      )
),

icd_t1dm_standard AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM public.concept_relationship cr
    JOIN icd_t1dm_source s
      ON cr.concept_id_1 = s.concept_id
    WHERE cr.relationship_id = 'Maps to'
),

t1dm_diagnosis AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (
        SELECT concept_id FROM icd_t1dm_standard
    )
),

t2dm_medications AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN public.concept c
      ON de.drug_concept_id = c.concept_id
    WHERE
        c.concept_name ILIKE ANY (ARRAY[
            '%metformin%', '%glucophage%', '%fortamet%', '%glumetza%', '%riomet%',
            '%glipizide%', '%glucotrol%',
            '%glyburide%', '%diabeta%', '%glynase%', '%micronase%',
            '%glimepiride%', '%amaryl%',
            '%pioglitazone%', '%actos%',
            '%rosiglitazone%', '%avandia%',
            '%sitagliptin%', '%januvia%',
            '%saxagliptin%', '%onglyza%',
            '%linagliptin%', '%tradjenta%',
            '%alogliptin%', '%nesina%',
            '%empagliflozin%', '%jardiance%',
            '%dapagliflozin%', '%farxiga%',
            '%canagliflozin%', '%invokana%',
            '%ertugliflozin%', '%steglatro%',
            '%semaglutide%', '%ozempic%', '%rybelsus%',
            '%liraglutide%', '%victoza%',
            '%dulaglutide%', '%trulicity%',
            '%exenatide%', '%byetta%', '%bydureon%',
            '%tirzepatide%', '%mounjaro%'
        ])
),

insulin_medications AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN public.concept c
      ON de.drug_concept_id = c.concept_id
    WHERE
        c.concept_name ILIKE ANY (ARRAY[
            '%insulin%',
            '%lantus%', '%basaglar%', '%levemir%', '%toujeo%', '%tresiba%',
            '%humalog%', '%novolog%', '%apidra%', '%fiasp%',
            '%humulin%', '%novolin%'
        ])
),

abnormal_diabetes_labs AS (
    SELECT
        m.person_id,
        COUNT(DISTINCT m.measurement_date) AS abnormal_lab_dates
    FROM public.measurement m
    JOIN public.concept c
      ON m.measurement_concept_id = c.concept_id
    WHERE
        m.value_as_number IS NOT NULL
        AND (
            (
                c.concept_name ILIKE ANY (ARRAY[
                    '%hemoglobin a1c%',
                    '%hba1c%',
                    '%glycated hemoglobin%'
                ])
                AND m.value_as_number >= 6.5
            )
            OR
            (
                c.concept_name ILIKE '%glucose%'
                AND c.concept_name ILIKE '%fasting%'
                AND m.value_as_number >= 126
            )
            OR
            (
                c.concept_name ILIKE '%glucose%'
                AND m.value_as_number >= 200
            )
        )
    GROUP BY m.person_id
),

t2dm_lab_evidence AS (
    SELECT person_id
    FROM abnormal_diabetes_labs
    WHERE abnormal_lab_dates >= 2
),

candidate_t2dm AS (
    SELECT person_id FROM t2dm_diagnosis

    UNION

    SELECT person_id FROM t2dm_medications

    UNION

    SELECT person_id FROM t2dm_lab_evidence

    UNION

    SELECT i.person_id
    FROM insulin_medications i
    WHERE i.person_id IN (
        SELECT person_id FROM t2dm_diagnosis
        UNION
        SELECT person_id FROM t2dm_lab_evidence
    )
)

SELECT DISTINCT
    p.person_id
FROM public.person p
JOIN candidate_t2dm c
  ON p.person_id = c.person_id
WHERE
    (
        p.person_id IN (SELECT person_id FROM t2dm_diagnosis)
        OR p.person_id IN (SELECT person_id FROM t2dm_medications)
        OR p.person_id IN (SELECT person_id FROM t2dm_lab_evidence)
        OR (
            p.person_id IN (SELECT person_id FROM insulin_medications)
            AND (
                p.person_id IN (SELECT person_id FROM t2dm_diagnosis)
                OR p.person_id IN (SELECT person_id FROM t2dm_lab_evidence)
            )
        )
    )
    AND NOT (
        p.person_id IN (SELECT person_id FROM t1dm_diagnosis)
        AND p.person_id NOT IN (SELECT person_id FROM t2dm_diagnosis)
        AND p.person_id NOT IN (SELECT person_id FROM t2dm_medications)
    );