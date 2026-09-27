WITH t2dm_icd_source AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD9CM'
      AND REPLACE(concept_code, '.', '') ~ '^250[0-9][0-9][02]$'

    UNION

    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD10CM'
      AND REPLACE(concept_code, '.', '') LIKE 'E11%'
),

t2dm_condition_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS condition_concept_id
    FROM t2dm_icd_source s
    JOIN public.concept_relationship cr
      ON s.concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'

    UNION

    SELECT concept_id AS condition_concept_id
    FROM t2dm_icd_source
),

t2dm_diagnosis AS (
    SELECT
        co.person_id,
        COUNT(DISTINCT co.condition_occurrence_id) AS t2dm_dx_count,
        MIN(co.condition_start_date) AS first_t2dm_dx_date
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (
        SELECT condition_concept_id
        FROM t2dm_condition_concepts
    )
    GROUP BY co.person_id
),

t1dm_icd_source AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD9CM'
      AND REPLACE(concept_code, '.', '') ~ '^250[0-9][0-9][13]$'

    UNION

    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD10CM'
      AND REPLACE(concept_code, '.', '') LIKE 'E10%'
),

t1dm_condition_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS condition_concept_id
    FROM t1dm_icd_source s
    JOIN public.concept_relationship cr
      ON s.concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'

    UNION

    SELECT concept_id AS condition_concept_id
    FROM t1dm_icd_source
),

t1dm_diagnosis AS (
    SELECT
        co.person_id,
        COUNT(DISTINCT co.condition_occurrence_id) AS t1dm_dx_count
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (
        SELECT condition_concept_id
        FROM t1dm_condition_concepts
    )
    GROUP BY co.person_id
),

other_diabetes_exclusion_icd_source AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD9CM'
      AND (
          REPLACE(concept_code, '.', '') LIKE '249%'
          OR REPLACE(concept_code, '.', '') LIKE '6488%'
      )

    UNION

    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD10CM'
      AND (
          REPLACE(concept_code, '.', '') LIKE 'E08%'
          OR REPLACE(concept_code, '.', '') LIKE 'E09%'
          OR REPLACE(concept_code, '.', '') LIKE 'E13%'
          OR REPLACE(concept_code, '.', '') LIKE 'O244%'
      )
),

other_diabetes_exclusion_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS condition_concept_id
    FROM other_diabetes_exclusion_icd_source s
    JOIN public.concept_relationship cr
      ON s.concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'

    UNION

    SELECT concept_id AS condition_concept_id
    FROM other_diabetes_exclusion_icd_source
),

other_diabetes_exclusion AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (
        SELECT condition_concept_id
        FROM other_diabetes_exclusion_concepts
    )
),

antidiabetic_seed_drugs AS (
    SELECT concept_id
    FROM public.concept
    WHERE domain_id = 'Drug'
      AND vocabulary_id IN ('RxNorm', 'RxNorm Extension')
      AND LOWER(concept_name) ~ (
          'metformin|glucophage|glumetza|fortamet|riomet|' ||
          'glipizide|glucotrol|glyburide|glibenclamide|diabeta|glynase|micronase|glimepiride|amaryl|' ||
          'pioglitazone|actos|rosiglitazone|avandia|' ||
          'sitagliptin|januvia|saxagliptin|onglyza|linagliptin|tradjenta|alogliptin|nesina|' ||
          'empagliflozin|jardiance|canagliflozin|invokana|dapagliflozin|farxiga|ertugliflozin|steglatro|' ||
          'liraglutide|victoza|semaglutide|ozempic|rybelsus|dulaglutide|trulicity|exenatide|byetta|bydureon|tirzepatide|mounjaro|' ||
          'acarbose|precose|miglitol|glyset|repaglinide|prandin|nateglinide|starlix'
      )
),

antidiabetic_drug_concepts AS (
    SELECT concept_id AS drug_concept_id
    FROM antidiabetic_seed_drugs

    UNION

    SELECT ca.descendant_concept_id AS drug_concept_id
    FROM public.concept_ancestor ca
    JOIN antidiabetic_seed_drugs s
      ON ca.ancestor_concept_id = s.concept_id
),

antidiabetic_medication AS (
    SELECT
        de.person_id,
        COUNT(DISTINCT de.drug_exposure_id) AS diabetes_med_count,
        MIN(de.drug_exposure_start_date) AS first_diabetes_med_date
    FROM public.drug_exposure de
    WHERE de.drug_concept_id IN (
        SELECT drug_concept_id
        FROM antidiabetic_drug_concepts
    )
    GROUP BY de.person_id
),

abnormal_diabetes_labs AS (
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
              (
                  LOWER(c.concept_name) LIKE '%hemoglobin a1c%'
                  OR LOWER(c.concept_name) LIKE '%hba1c%'
              )
              AND m.value_as_number >= 6.5
          )
          OR (
              (
                  LOWER(c.concept_name) LIKE '%fasting glucose%'
                  OR (
                      LOWER(c.concept_name) LIKE '%glucose%'
                      AND LOWER(c.concept_name) LIKE '%fasting%'
                  )
              )
              AND m.value_as_number >= 126
          )
          OR (
              (
                  LOWER(c.concept_name) LIKE '%oral glucose tolerance%'
                  OR LOWER(c.concept_name) LIKE '%glucose tolerance%'
                  OR (
                      LOWER(c.concept_name) LIKE '%glucose%'
                      AND LOWER(c.concept_name) LIKE '%2 hour%'
                  )
                  OR (
                      LOWER(c.concept_name) LIKE '%glucose%'
                      AND LOWER(c.concept_name) LIKE '%random%'
                  )
              )
              AND m.value_as_number >= 200
          )
      )
    GROUP BY m.person_id
),

candidate_t2dm AS (
    SELECT
        p.person_id,
        COALESCE(dx.t2dm_dx_count, 0) AS t2dm_dx_count,
        COALESCE(t1.t1dm_dx_count, 0) AS t1dm_dx_count,
        COALESCE(med.diabetes_med_count, 0) AS diabetes_med_count,
        COALESCE(lab.abnormal_lab_count, 0) AS abnormal_lab_count,
        dx.first_t2dm_dx_date,
        med.first_diabetes_med_date,
        lab.first_abnormal_lab_date
    FROM public.person p
    LEFT JOIN t2dm_diagnosis dx
      ON p.person_id = dx.person_id
    LEFT JOIN t1dm_diagnosis t1
      ON p.person_id = t1.person_id
    LEFT JOIN antidiabetic_medication med
      ON p.person_id = med.person_id
    LEFT JOIN abnormal_diabetes_labs lab
      ON p.person_id = lab.person_id
),

final_t2dm_phenotype AS (
    SELECT
        c.person_id,
        LEAST(
            COALESCE(c.first_t2dm_dx_date, DATE '9999-12-31'),
            COALESCE(c.first_diabetes_med_date, DATE '9999-12-31'),
            COALESCE(c.first_abnormal_lab_date, DATE '9999-12-31')
        ) AS index_date,
        c.t2dm_dx_count,
        c.t1dm_dx_count,
        c.diabetes_med_count,
        c.abnormal_lab_count
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
            FROM other_diabetes_exclusion ex
            WHERE ex.person_id = c.person_id
          )
)

SELECT DISTINCT
    person_id,
    index_date,
    t2dm_dx_count,
    t1dm_dx_count,
    diabetes_med_count,
    abnormal_lab_count
FROM final_t2dm_phenotype
ORDER BY person_id;