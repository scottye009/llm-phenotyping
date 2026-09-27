--too long to run
WITH t2dm_source_codes AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD9CM'
      AND REPLACE(concept_code, '.', '') IN (
          '25000','25002','25010','25012','25020','25022',
          '25030','25032','25040','25042','25050','25052',
          '25060','25062','25070','25072','25080','25082',
          '25090','25092'
      )

    UNION

    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD10CM'
      AND concept_code LIKE 'E11%'
),

t1dm_source_codes AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD9CM'
      AND REPLACE(concept_code, '.', '') IN (
          '25001','25003','25011','25013','25021','25023',
          '25031','25033','25041','25043','25051','25053',
          '25061','25063','25071','25073','25081','25083',
          '25091','25093'
      )

    UNION

    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD10CM'
      AND concept_code LIKE 'E10%'
),

exclude_diabetes_source_codes AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD10CM'
      AND (
          concept_code LIKE 'O24.4%' OR
          concept_code LIKE 'O24.9%' OR
          concept_code LIKE 'E08%' OR
          concept_code LIKE 'E09%' OR
          concept_code LIKE 'E13%'
      )

    UNION

    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD9CM'
      AND REPLACE(concept_code, '.', '') IN (
          '64880','64881','64882','64883','64884'
      )
),

t2dm_standard_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM public.concept_relationship cr
    JOIN t2dm_source_codes s
      ON cr.concept_id_1 = s.concept_id
    WHERE cr.relationship_id = 'Maps to'

    UNION

    SELECT concept_id
    FROM t2dm_source_codes
),

t1dm_standard_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM public.concept_relationship cr
    JOIN t1dm_source_codes s
      ON cr.concept_id_1 = s.concept_id
    WHERE cr.relationship_id = 'Maps to'

    UNION

    SELECT concept_id
    FROM t1dm_source_codes
),

exclude_standard_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM public.concept_relationship cr
    JOIN exclude_diabetes_source_codes s
      ON cr.concept_id_1 = s.concept_id
    WHERE cr.relationship_id = 'Maps to'

    UNION

    SELECT concept_id
    FROM exclude_diabetes_source_codes
),

t2dm_diagnosis AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN t2dm_standard_concepts t2
      ON co.condition_concept_id = t2.concept_id
),

t1dm_diagnosis AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN t1dm_standard_concepts t1
      ON co.condition_concept_id = t1.concept_id
),

excluded_diabetes_diagnosis AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN exclude_standard_concepts ex
      ON co.condition_concept_id = ex.concept_id
),

abnormal_diabetes_labs AS (
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN public.concept c
      ON m.measurement_concept_id = c.concept_id
    WHERE m.value_as_number IS NOT NULL
      AND (
          (
              c.concept_name ILIKE '%hemoglobin a1c%'
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
              AND c.concept_name ILIKE '%random%'
              AND m.value_as_number >= 200
          )
          OR
          (
              c.concept_name ILIKE '%glucose%'
              AND (
                  c.concept_name ILIKE '%oral glucose tolerance%' OR
                  c.concept_name ILIKE '%2 hour%'
              )
              AND m.value_as_number >= 200
          )
      )
),

non_insulin_diabetes_medications AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN public.concept dc
      ON de.drug_concept_id = dc.concept_id
    LEFT JOIN public.concept_ancestor ca
      ON de.drug_concept_id = ca.descendant_concept_id
    LEFT JOIN public.concept ac
      ON ca.ancestor_concept_id = ac.concept_id
    WHERE
        dc.concept_name ILIKE ANY (ARRAY[
            '%metformin%', '%glucophage%', '%fortamet%', '%glumetza%', '%riomet%',
            '%glyburide%', '%diabeta%', '%glynase%', '%glibenclamide%',
            '%glipizide%', '%glucotrol%',
            '%glimepiride%', '%amaryl%',
            '%pioglitazone%', '%actos%',
            '%rosiglitazone%', '%avandia%',
            '%sitagliptin%', '%januvia%',
            '%saxagliptin%', '%onglyza%',
            '%linagliptin%', '%tradjenta%',
            '%alogliptin%', '%nesina%',
            '%liraglutide%', '%victoza%',
            '%semaglutide%', '%ozempic%', '%rybelsus%',
            '%dulaglutide%', '%trulicity%',
            '%exenatide%', '%byetta%', '%bydureon%',
            '%tirzepatide%', '%mounjaro%',
            '%canagliflozin%', '%invokana%',
            '%dapagliflozin%', '%farxiga%',
            '%empagliflozin%', '%jardiance%',
            '%ertugliflozin%', '%steglatro%',
            '%repaglinide%', '%prandin%',
            '%nateglinide%', '%starlix%',
            '%acarbose%', '%precose%',
            '%miglitol%', '%glyset%'
        ])
        OR
        ac.concept_name ILIKE ANY (ARRAY[
            '%metformin%', '%glyburide%', '%glipizide%', '%glimepiride%',
            '%pioglitazone%', '%rosiglitazone%',
            '%sitagliptin%', '%saxagliptin%', '%linagliptin%', '%alogliptin%',
            '%liraglutide%', '%semaglutide%', '%dulaglutide%', '%exenatide%',
            '%tirzepatide%',
            '%canagliflozin%', '%dapagliflozin%', '%empagliflozin%', '%ertugliflozin%',
            '%repaglinide%', '%nateglinide%', '%acarbose%', '%miglitol%'
        ])
),

insulin_medications AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN public.concept dc
      ON de.drug_concept_id = dc.concept_id
    LEFT JOIN public.concept_ancestor ca
      ON de.drug_concept_id = ca.descendant_concept_id
    LEFT JOIN public.concept ac
      ON ca.ancestor_concept_id = ac.concept_id
    WHERE
        dc.concept_name ILIKE ANY (ARRAY[
            '%insulin%', '%lantus%', '%basaglar%', '%levemir%', '%toujeo%',
            '%tresiba%', '%humalog%', '%novolog%', '%novorapid%', '%apidra%',
            '%humulin%', '%novolin%', '%fiasp%'
        ])
        OR
        ac.concept_name ILIKE '%insulin%'
),

candidate_t2dm AS (
    SELECT person_id
    FROM t2dm_diagnosis

    UNION

    SELECT l.person_id
    FROM abnormal_diabetes_labs l
    JOIN non_insulin_diabetes_medications d
      ON l.person_id = d.person_id
),

final_t2dm_phenotype AS (
    SELECT DISTINCT p.person_id
    FROM public.person p
    JOIN candidate_t2dm c
      ON p.person_id = c.person_id
    LEFT JOIN t1dm_diagnosis t1
      ON p.person_id = t1.person_id
    LEFT JOIN t2dm_diagnosis t2
      ON p.person_id = t2.person_id
    LEFT JOIN non_insulin_diabetes_medications noninsulin
      ON p.person_id = noninsulin.person_id
    LEFT JOIN excluded_diabetes_diagnosis ex
      ON p.person_id = ex.person_id
    WHERE
        (
            t2.person_id IS NOT NULL
            OR (
                p.person_id IN (SELECT person_id FROM abnormal_diabetes_labs)
                AND p.person_id IN (SELECT person_id FROM non_insulin_diabetes_medications)
            )
        )
        AND NOT (
            ex.person_id IS NOT NULL
        )
        AND NOT (
            t1.person_id IS NOT NULL
            AND t2.person_id IS NULL
            AND noninsulin.person_id IS NULL
        )
)

SELECT person_id
FROM final_t2dm_phenotype
ORDER BY person_id;