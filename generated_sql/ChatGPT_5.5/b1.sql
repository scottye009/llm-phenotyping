WITH t2dm_icd_source AS (
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
      AND REPLACE(concept_code, '.', '') LIKE 'E11%'
),

t2dm_standard_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM t2dm_icd_source s
    JOIN public.concept_relationship cr
      ON s.concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'
),

t2dm_dx AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date AS event_date
    FROM public.condition_occurrence co
    JOIN t2dm_standard_concepts t
      ON co.condition_concept_id = t.concept_id
    WHERE co.condition_start_date IS NOT NULL
),

t2dm_dx_counts AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS t2dm_dx_dates
    FROM t2dm_dx
    GROUP BY person_id
),

exclusion_icd_source AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD9CM'
      AND (
             REPLACE(concept_code, '.', '') LIKE '249%'
          OR REPLACE(concept_code, '.', '') IN (
              '25001','25003','25011','25013','25021','25023',
              '25031','25033','25041','25043','25051','25053',
              '25061','25063','25071','25073','25081','25083',
              '25091','25093',
              '64800','64801','64802','64803','64804',
              '64880','64881','64882','64883','64884'
          )
      )

    UNION

    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD10CM'
      AND (
             REPLACE(concept_code, '.', '') LIKE 'E10%'
          OR REPLACE(concept_code, '.', '') LIKE 'E08%'
          OR REPLACE(concept_code, '.', '') LIKE 'E09%'
          OR REPLACE(concept_code, '.', '') LIKE 'E13%'
          OR REPLACE(concept_code, '.', '') LIKE 'O244%'
      )
),

exclusion_standard_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM exclusion_icd_source s
    JOIN public.concept_relationship cr
      ON s.concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'
),

exclusion_dx AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN exclusion_standard_concepts e
      ON co.condition_concept_id = e.concept_id
),

abnormal_diabetes_labs AS (
    SELECT
        m.person_id,
        COUNT(DISTINCT m.measurement_date) AS abnormal_lab_dates
    FROM public.measurement m
    JOIN public.concept c
      ON m.measurement_concept_id = c.concept_id
    WHERE m.value_as_number IS NOT NULL
      AND m.measurement_date IS NOT NULL
      AND (
            (
                (
                    LOWER(c.concept_name) LIKE '%hemoglobin a1c%'
                    OR LOWER(c.concept_name) LIKE '%hba1c%'
                    OR LOWER(c.concept_name) LIKE '%glycated hemoglobin%'
                )
                AND m.value_as_number >= 6.5
            )
            OR
            (
                LOWER(c.concept_name) LIKE '%glucose%'
                AND (
                    LOWER(c.concept_name) LIKE '%fasting%'
                    OR LOWER(c.concept_name) LIKE '%fasted%'
                )
                AND m.value_as_number >= 126
            )
            OR
            (
                LOWER(c.concept_name) LIKE '%glucose%'
                AND (
                    LOWER(c.concept_name) LIKE '%random%'
                    OR LOWER(c.concept_name) LIKE '%casual%'
                )
                AND m.value_as_number >= 200
            )
            OR
            (
                (
                    LOWER(c.concept_name) LIKE '%oral glucose tolerance%'
                    OR LOWER(c.concept_name) LIKE '%glucose tolerance%'
                    OR LOWER(c.concept_name) LIKE '%2 hour glucose%'
                    OR LOWER(c.concept_name) LIKE '%two hour glucose%'
                )
                AND m.value_as_number >= 200
            )
      )
    GROUP BY m.person_id
),

lab_evidence AS (
    SELECT person_id
    FROM abnormal_diabetes_labs
    WHERE abnormal_lab_dates >= 1
),

t2dm_med_concepts AS (
    SELECT DISTINCT concept_id
    FROM public.concept
    WHERE domain_id = 'Drug'
      AND (
             LOWER(concept_name) LIKE '%metformin%'
          OR LOWER(concept_name) LIKE '%glucophage%'
          OR LOWER(concept_name) LIKE '%glumetza%'
          OR LOWER(concept_name) LIKE '%fortamet%'
          OR LOWER(concept_name) LIKE '%riomet%'

          OR LOWER(concept_name) LIKE '%glipizide%'
          OR LOWER(concept_name) LIKE '%glucotrol%'
          OR LOWER(concept_name) LIKE '%glyburide%'
          OR LOWER(concept_name) LIKE '%diabeta%'
          OR LOWER(concept_name) LIKE '%glynase%'
          OR LOWER(concept_name) LIKE '%micronase%'
          OR LOWER(concept_name) LIKE '%glimepiride%'
          OR LOWER(concept_name) LIKE '%amaryl%'

          OR LOWER(concept_name) LIKE '%pioglitazone%'
          OR LOWER(concept_name) LIKE '%actos%'
          OR LOWER(concept_name) LIKE '%rosiglitazone%'
          OR LOWER(concept_name) LIKE '%avandia%'

          OR LOWER(concept_name) LIKE '%sitagliptin%'
          OR LOWER(concept_name) LIKE '%januvia%'
          OR LOWER(concept_name) LIKE '%saxagliptin%'
          OR LOWER(concept_name) LIKE '%onglyza%'
          OR LOWER(concept_name) LIKE '%linagliptin%'
          OR LOWER(concept_name) LIKE '%tradjenta%'
          OR LOWER(concept_name) LIKE '%alogliptin%'
          OR LOWER(concept_name) LIKE '%nesina%'

          OR LOWER(concept_name) LIKE '%empagliflozin%'
          OR LOWER(concept_name) LIKE '%jardiance%'
          OR LOWER(concept_name) LIKE '%dapagliflozin%'
          OR LOWER(concept_name) LIKE '%farxiga%'
          OR LOWER(concept_name) LIKE '%canagliflozin%'
          OR LOWER(concept_name) LIKE '%invokana%'
          OR LOWER(concept_name) LIKE '%ertugliflozin%'
          OR LOWER(concept_name) LIKE '%steglatro%'

          OR LOWER(concept_name) LIKE '%semaglutide%'
          OR LOWER(concept_name) LIKE '%ozempic%'
          OR LOWER(concept_name) LIKE '%rybelsus%'
          OR LOWER(concept_name) LIKE '%liraglutide%'
          OR LOWER(concept_name) LIKE '%victoza%'
          OR LOWER(concept_name) LIKE '%dulaglutide%'
          OR LOWER(concept_name) LIKE '%trulicity%'
          OR LOWER(concept_name) LIKE '%exenatide%'
          OR LOWER(concept_name) LIKE '%byetta%'
          OR LOWER(concept_name) LIKE '%bydureon%'
          OR LOWER(concept_name) LIKE '%tirzepatide%'
          OR LOWER(concept_name) LIKE '%mounjaro%'

          OR LOWER(concept_name) LIKE '%repaglinide%'
          OR LOWER(concept_name) LIKE '%prandin%'
          OR LOWER(concept_name) LIKE '%nateglinide%'
          OR LOWER(concept_name) LIKE '%starlix%'

          OR LOWER(concept_name) LIKE '%acarbose%'
          OR LOWER(concept_name) LIKE '%precose%'
          OR LOWER(concept_name) LIKE '%miglitol%'
          OR LOWER(concept_name) LIKE '%glyset%'
      )
),

t2dm_med_evidence AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN public.concept_ancestor ca
      ON de.drug_concept_id = ca.descendant_concept_id
    JOIN t2dm_med_concepts mc
      ON ca.ancestor_concept_id = mc.concept_id

    UNION

    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN t2dm_med_concepts mc
      ON de.drug_concept_id = mc.concept_id
),

phenotype_candidates AS (
    SELECT DISTINCT person_id
    FROM t2dm_dx_counts
    WHERE t2dm_dx_dates >= 2

    UNION

    SELECT DISTINCT dx.person_id
    FROM t2dm_dx dx
    JOIN lab_evidence lab
      ON dx.person_id = lab.person_id

    UNION

    SELECT DISTINCT dx.person_id
    FROM t2dm_dx dx
    JOIN t2dm_med_evidence med
      ON dx.person_id = med.person_id

    UNION

    SELECT DISTINCT lab.person_id
    FROM lab_evidence lab
    JOIN t2dm_med_evidence med
      ON lab.person_id = med.person_id
)

SELECT DISTINCT p.person_id
FROM public.person p
JOIN phenotype_candidates pc
  ON p.person_id = pc.person_id
WHERE NOT EXISTS (
    SELECT 1
    FROM exclusion_dx ex
    WHERE ex.person_id = p.person_id
)
ORDER BY p.person_id;