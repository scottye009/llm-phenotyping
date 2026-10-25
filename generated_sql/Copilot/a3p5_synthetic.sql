/* Type 2 Diabetes Mellitus phenotype:
   Include persons meeting ANY of:
   1) >=2 T2DM diagnoses (ICD9CM/ICD10CM mapped to standard concepts) on different dates
   2) >=1 T2DM diagnosis + >=1 antihyperglycemic drug exposure
   3) Diabetes laboratory evidence:
      - HbA1c >= 6.5 %
      - Fasting plasma glucose >= 126 mg/dL
      - Random plasma glucose >= 200 mg/dL
      - Oral glucose tolerance test (2 hr) >= 200 mg/dL
      on at least two measurement dates
*/

WITH t2dm_icd_source AS (
    /* ICD9CM 250.x0/250.x2 and ICD10CM E11* */
    SELECT DISTINCT cr.concept_id_2 AS standard_concept_id
    FROM public.concept c
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = c.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
    WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
      AND (
            (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~ '^250')
         OR (c.vocabulary_id = 'ICD10CM' AND c.concept_code ~ '^E11')
      )
),

t2dm_condition_concepts AS (
    /* Expand mapped standard concepts through hierarchy */
    SELECT DISTINCT ca.descendant_concept_id AS concept_id
    FROM t2dm_icd_source s
    JOIN public.concept_ancestor ca
      ON ca.ancestor_concept_id = s.standard_concept_id

    UNION

    SELECT DISTINCT standard_concept_id
    FROM t2dm_icd_source
),

t2dm_dx AS (
    SELECT
        co.person_id,
        co.condition_start_date::date AS dx_date
    FROM public.condition_occurrence co
    JOIN t2dm_condition_concepts t
      ON co.condition_concept_id = t.concept_id
),

dx_2plus AS (
    SELECT person_id
    FROM t2dm_dx
    GROUP BY person_id
    HAVING COUNT(DISTINCT dx_date) >= 2
),

antidiabetic_ingredients AS (
    /* RxNorm ingredients and common branded/generic antihyperglycemics */
    SELECT DISTINCT ca.descendant_concept_id AS concept_id
    FROM public.concept c
    JOIN public.concept_ancestor ca
      ON ca.ancestor_concept_id = c.concept_id
    WHERE c.vocabulary_id = 'RxNorm'
      AND (
           c.concept_name ILIKE 'metformin%'
        OR c.concept_name ILIKE 'glipizide%'
        OR c.concept_name ILIKE 'glyburide%'
        OR c.concept_name ILIKE 'glimepiride%'
        OR c.concept_name ILIKE 'pioglitazone%'
        OR c.concept_name ILIKE 'rosiglitazone%'
        OR c.concept_name ILIKE 'sitagliptin%'
        OR c.concept_name ILIKE 'saxagliptin%'
        OR c.concept_name ILIKE 'linagliptin%'
        OR c.concept_name ILIKE 'alogliptin%'
        OR c.concept_name ILIKE 'exenatide%'
        OR c.concept_name ILIKE 'liraglutide%'
        OR c.concept_name ILIKE 'dulaglutide%'
        OR c.concept_name ILIKE 'semaglutide%'
        OR c.concept_name ILIKE 'lixisenatide%'
        OR c.concept_name ILIKE 'empagliflozin%'
        OR c.concept_name ILIKE 'dapagliflozin%'
        OR c.concept_name ILIKE 'canagliflozin%'
        OR c.concept_name ILIKE 'ertugliflozin%'
        OR c.concept_name ILIKE 'acarbose%'
        OR c.concept_name ILIKE 'miglitol%'
        OR c.concept_name ILIKE 'repaglinide%'
        OR c.concept_name ILIKE 'nateglinide%'
        OR c.concept_name ILIKE 'insulin%'
        OR c.concept_name ILIKE 'glucophage%'
        OR c.concept_name ILIKE 'januvia%'
        OR c.concept_name ILIKE 'onglyza%'
        OR c.concept_name ILIKE 'tradjenta%'
        OR c.concept_name ILIKE 'victoza%'
        OR c.concept_name ILIKE 'ozempic%'
        OR c.concept_name ILIKE 'trulicity%'
        OR c.concept_name ILIKE 'byetta%'
        OR c.concept_name ILIKE 'farxiga%'
        OR c.concept_name ILIKE 'jardiance%'
        OR c.concept_name ILIKE 'invokana%'
      )
),

antidiabetic_rx AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN antidiabetic_ingredients a
      ON de.drug_concept_id = a.concept_id
),

dx_plus_rx AS (
    SELECT DISTINCT d.person_id
    FROM t2dm_dx d
    JOIN antidiabetic_rx r
      ON d.person_id = r.person_id
),

diabetes_labs AS (
    SELECT
        m.person_id,
        m.measurement_date::date AS lab_date
    FROM public.measurement m
    JOIN public.concept mc
      ON mc.concept_id = m.measurement_concept_id
    WHERE m.value_as_number IS NOT NULL
      AND (
            /* HbA1c >= 6.5 % */
            (
              (
                   mc.concept_name ILIKE '%hemoglobin a1c%'
                OR mc.concept_name ILIKE '%hba1c%'
                OR m.measurement_source_value ILIKE '%4548-4%'
                OR m.measurement_source_value ILIKE '%17856-6%'
              )
              AND m.value_as_number >= 6.5
            )

         OR /* Fasting glucose >=126 mg/dL */
            (
              (
                   mc.concept_name ILIKE '%fasting%glucose%'
                OR m.measurement_source_value ILIKE '%1558-6%'
              )
              AND m.value_as_number >= 126
            )

         OR /* Random glucose >=200 mg/dL */
            (
              (
                   mc.concept_name ILIKE '%glucose%'
                OR m.measurement_source_value ILIKE '%2345-7%'
              )
              AND m.value_as_number >= 200
            )

         OR /* 2-hour OGTT glucose >=200 mg/dL */
            (
              (
                   mc.concept_name ILIKE '%oral glucose tolerance%'
                OR mc.concept_name ILIKE '%2 hour%glucose%'
                OR m.measurement_source_value ILIKE '%1557-8%'
              )
              AND m.value_as_number >= 200
            )
      )
),

lab_positive AS (
    SELECT person_id
    FROM diabetes_labs
    GROUP BY person_id
    HAVING COUNT(DISTINCT lab_date) >= 2
)

SELECT DISTINCT person_id
FROM (
    SELECT person_id FROM dx_2plus
    UNION
    SELECT person_id FROM dx_plus_rx
    UNION
    SELECT person_id FROM lab_positive
) t
ORDER BY person_id;