WITH t2dm_icd_source AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD9CM'
      AND REPLACE(concept_code, '.', '') IN (
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

    UNION

    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD10CM'
      AND concept_code LIKE 'E11%'
),

t2dm_standard_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM t2dm_icd_source s
    JOIN public.concept_relationship cr
      ON s.concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'

    UNION

    SELECT concept_id
    FROM t2dm_icd_source
),

t1dm_icd_source AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD9CM'
      AND REPLACE(concept_code, '.', '') IN (
          '25001','25003',
          '25011','25013',
          '25021','25023',
          '25031','25033',
          '25041','25043',
          '25051','25053',
          '25061','25063',
          '25071','25073',
          '25081','25083',
          '25091','25093'
      )

    UNION

    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD10CM'
      AND concept_code LIKE 'E10%'
),

t1dm_standard_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM t1dm_icd_source s
    JOIN public.concept_relationship cr
      ON s.concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'

    UNION

    SELECT concept_id
    FROM t1dm_icd_source
),

exclusion_icd_source AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD10CM'
      AND (
          concept_code LIKE 'O24.4%'
          OR concept_code LIKE 'O24.9%'
          OR concept_code LIKE 'E08%'
          OR concept_code LIKE 'E09%'
          OR concept_code LIKE 'E13%'
      )

    UNION

    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD9CM'
      AND (
          REPLACE(concept_code, '.', '') LIKE '249%'
          OR REPLACE(concept_code, '.', '') LIKE '6488%'
      )
),

exclusion_standard_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM exclusion_icd_source s
    JOIN public.concept_relationship cr
      ON s.concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'

    UNION

    SELECT concept_id
    FROM exclusion_icd_source
),

t2dm_diagnosis AS (
    SELECT
        co.person_id,
        COUNT(DISTINCT co.condition_occurrence_id) AS t2dm_dx_count,
        MIN(co.condition_start_date) AS first_t2dm_dx_date
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (
        SELECT concept_id FROM t2dm_standard_concepts
    )
    GROUP BY co.person_id
),

t1dm_diagnosis AS (
    SELECT
        co.person_id,
        COUNT(DISTINCT co.condition_occurrence_id) AS t1dm_dx_count
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (
        SELECT concept_id FROM t1dm_standard_concepts
    )
    GROUP BY co.person_id
),

excluded_conditions AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (
        SELECT concept_id FROM exclusion_standard_concepts
    )
),

diabetes_medication_concepts AS (
    SELECT DISTINCT c.concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Drug'
      AND (
          LOWER(c.concept_name) LIKE '%metformin%'
          OR LOWER(c.concept_name) LIKE '%glucophage%'
          OR LOWER(c.concept_name) LIKE '%glumetza%'
          OR LOWER(c.concept_name) LIKE '%fortamet%'

          OR LOWER(c.concept_name) LIKE '%sitagliptin%'
          OR LOWER(c.concept_name) LIKE '%januvia%'
          OR LOWER(c.concept_name) LIKE '%janumet%'

          OR LOWER(c.concept_name) LIKE '%linagliptin%'
          OR LOWER(c.concept_name) LIKE '%tradjenta%'
          OR LOWER(c.concept_name) LIKE '%jentadueto%'

          OR LOWER(c.concept_name) LIKE '%saxagliptin%'
          OR LOWER(c.concept_name) LIKE '%onglyza%'
          OR LOWER(c.concept_name) LIKE '%kombiglyze%'

          OR LOWER(c.concept_name) LIKE '%alogliptin%'
          OR LOWER(c.concept_name) LIKE '%nesina%'

          OR LOWER(c.concept_name) LIKE '%glipizide%'
          OR LOWER(c.concept_name) LIKE '%glucotrol%'

          OR LOWER(c.concept_name) LIKE '%glyburide%'
          OR LOWER(c.concept_name) LIKE '%diaBeta%'
          OR LOWER(c.concept_name) LIKE '%glynase%'

          OR LOWER(c.concept_name) LIKE '%glimepiride%'
          OR LOWER(c.concept_name) LIKE '%amaryl%'

          OR LOWER(c.concept_name) LIKE '%pioglitazone%'
          OR LOWER(c.concept_name) LIKE '%actos%'

          OR LOWER(c.concept_name) LIKE '%rosiglitazone%'
          OR LOWER(c.concept_name) LIKE '%avandia%'

          OR LOWER(c.concept_name) LIKE '%empagliflozin%'
          OR LOWER(c.concept_name) LIKE '%jardiance%'

          OR LOWER(c.concept_name) LIKE '%dapagliflozin%'
          OR LOWER(c.concept_name) LIKE '%farxiga%'

          OR LOWER(c.concept_name) LIKE '%canagliflozin%'
          OR LOWER(c.concept_name) LIKE '%invokana%'

          OR LOWER(c.concept_name) LIKE '%ertugliflozin%'
          OR LOWER(c.concept_name) LIKE '%steglatro%'

          OR LOWER(c.concept_name) LIKE '%semaglutide%'
          OR LOWER(c.concept_name) LIKE '%ozempic%'
          OR LOWER(c.concept_name) LIKE '%rybelsus%'

          OR LOWER(c.concept_name) LIKE '%liraglutide%'
          OR LOWER(c.concept_name) LIKE '%victoza%'

          OR LOWER(c.concept_name) LIKE '%dulaglutide%'
          OR LOWER(c.concept_name) LIKE '%trulicity%'

          OR LOWER(c.concept_name) LIKE '%exenatide%'
          OR LOWER(c.concept_name) LIKE '%byetta%'
          OR LOWER(c.concept_name) LIKE '%bydureon%'

          OR LOWER(c.concept_name) LIKE '%tirzepatide%'
          OR LOWER(c.concept_name) LIKE '%mounjaro%'

          OR LOWER(c.concept_name) LIKE '%acarbose%'
          OR LOWER(c.concept_name) LIKE '%precose%'

          OR LOWER(c.concept_name) LIKE '%miglitol%'
          OR LOWER(c.concept_name) LIKE '%glyset%'

          OR LOWER(c.concept_name) LIKE '%repaglinide%'
          OR LOWER(c.concept_name) LIKE '%prandin%'

          OR LOWER(c.concept_name) LIKE '%nateglinide%'
          OR LOWER(c.concept_name) LIKE '%starlix%'
      )
),

diabetes_medication AS (
    SELECT
        de.person_id,
        COUNT(DISTINCT de.drug_exposure_id) AS diabetes_med_count,
        MIN(de.drug_exposure_start_date) AS first_diabetes_med_date
    FROM public.drug_exposure de
    WHERE de.drug_concept_id IN (
        SELECT concept_id FROM diabetes_medication_concepts
    )
    GROUP BY de.person_id
),

diabetes_lab AS (
    SELECT
        m.person_id,
        COUNT(DISTINCT m.measurement_id) AS abnormal_lab_count,
        MIN(m.measurement_date) AS first_abnormal_lab_date
    FROM public.measurement m
    JOIN public.concept c
      ON m.measurement_concept_id = c.concept_id
    WHERE m.value_as_number IS NOT NULL
      AND (
          (
              LOWER(c.concept_name) LIKE '%hemoglobin a1c%'
              AND m.value_as_number >= 6.5
          )
          OR (
              LOWER(c.concept_name) LIKE '%hba1c%'
              AND m.value_as_number >= 6.5
          )
          OR (
              LOWER(c.concept_name) LIKE '%fasting glucose%'
              AND m.value_as_number >= 126
          )
          OR (
              LOWER(c.concept_name) LIKE '%glucose%'
              AND LOWER(c.concept_name) LIKE '%fasting%'
              AND m.value_as_number >= 126
          )
          OR (
              LOWER(c.concept_name) LIKE '%glucose%'
              AND LOWER(c.concept_name) LIKE '%random%'
              AND m.value_as_number >= 200
          )
          OR (
              LOWER(c.concept_name) LIKE '%oral glucose tolerance%'
              AND m.value_as_number >= 200
          )
      )
    GROUP BY m.person_id
),

candidate_t2dm AS (
    SELECT
        p.person_id,
        COALESCE(dx.t2dm_dx_count, 0) AS t2dm_dx_count,
        COALESCE(med.diabetes_med_count, 0) AS diabetes_med_count,
        COALESCE(lab.abnormal_lab_count, 0) AS abnormal_lab_count,
        COALESCE(t1.t1dm_dx_count, 0) AS t1dm_dx_count
    FROM public.person p
    LEFT JOIN t2dm_diagnosis dx
      ON p.person_id = dx.person_id
    LEFT JOIN diabetes_medication med
      ON p.person_id = med.person_id
    LEFT JOIN diabetes_lab lab
      ON p.person_id = lab.person_id
    LEFT JOIN t1dm_diagnosis t1
      ON p.person_id = t1.person_id
),

final_t2dm_phenotype AS (
    SELECT person_id
    FROM candidate_t2dm c
    WHERE (
            c.t2dm_dx_count >= 2
            OR (
                c.t2dm_dx_count >= 1
                AND (
                    c.diabetes_med_count >= 1
                    OR c.abnormal_lab_count >= 1
                )
            )
            OR (
                c.diabetes_med_count >= 1
                AND c.abnormal_lab_count >= 1
            )
          )
      AND NOT (
            c.t1dm_dx_count > c.t2dm_dx_count
          )
      AND NOT EXISTS (
            SELECT 1
            FROM excluded_conditions e
            WHERE e.person_id = c.person_id
          )
)

SELECT DISTINCT person_id
FROM final_t2dm_phenotype
ORDER BY person_id;