/* Type 2 Diabetes Mellitus phenotype:
   Include persons meeting ANY of:
   1) >=2 T2DM diagnoses on different dates (ICD9CM/ICD10CM mapped to standard concepts), OR
   2) >=1 T2DM diagnosis + >=1 non-insulin antihyperglycemic drug exposure, OR
   3) >=2 abnormal diabetes laboratory results:
        - HbA1c >= 6.5 %
        - Fasting plasma glucose >= 126 mg/dL
        - Random plasma glucose >= 200 mg/dL
*/

WITH t2dm_icd_source AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
      AND (
            c.concept_name ILIKE '%type 2 diabetes%'
         OR c.concept_name ILIKE '%type ii diabetes%'
         OR c.concept_name ILIKE '%non-insulin-dependent diabetes%'
      )
),
t2dm_standard AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM t2dm_icd_source s
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = s.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL

    UNION

    SELECT DISTINCT ca.descendant_concept_id
    FROM (
        SELECT DISTINCT cr.concept_id_2 AS concept_id
        FROM t2dm_icd_source s
        JOIN public.concept_relationship cr
          ON cr.concept_id_1 = s.concept_id
         AND cr.relationship_id = 'Maps to'
         AND cr.invalid_reason IS NULL
    ) std
    JOIN public.concept_ancestor ca
      ON ca.ancestor_concept_id = std.concept_id
),
t2dm_dx AS (
    SELECT
        co.person_id,
        COUNT(DISTINCT co.condition_start_date) AS dx_dates
    FROM public.condition_occurrence co
    JOIN t2dm_standard t
      ON co.condition_concept_id = t.concept_id
    GROUP BY co.person_id
),
antidiabetic_ingredients AS (
    SELECT DISTINCT ca.descendant_concept_id AS concept_id
    FROM public.concept c
    JOIN public.concept_ancestor ca
      ON ca.ancestor_concept_id = c.concept_id
    WHERE c.vocabulary_id = 'RxNorm'
      AND c.standard_concept = 'S'
      AND (
            c.concept_name ILIKE 'metformin%'
         OR c.concept_name ILIKE 'glipizide%'
         OR c.concept_name ILIKE 'glyburide%'
         OR c.concept_name ILIKE 'glimepiride%'
         OR c.concept_name ILIKE 'pioglitazone%'
         OR c.concept_name ILIKE 'rosiglitazone%'
         OR c.concept_name ILIKE 'acarbose%'
         OR c.concept_name ILIKE 'miglitol%'
         OR c.concept_name ILIKE 'sitagliptin%'
         OR c.concept_name ILIKE 'saxagliptin%'
         OR c.concept_name ILIKE 'linagliptin%'
         OR c.concept_name ILIKE 'alogliptin%'
         OR c.concept_name ILIKE 'empagliflozin%'
         OR c.concept_name ILIKE 'dapagliflozin%'
         OR c.concept_name ILIKE 'canagliflozin%'
         OR c.concept_name ILIKE 'ertugliflozin%'
         OR c.concept_name ILIKE 'exenatide%'
         OR c.concept_name ILIKE 'liraglutide%'
         OR c.concept_name ILIKE 'dulaglutide%'
         OR c.concept_name ILIKE 'semaglutide%'
         OR c.concept_name ILIKE 'lixisenatide%'
         OR c.concept_name ILIKE 'tirzepatide%'
         OR c.concept_name ILIKE 'repaglinide%'
         OR c.concept_name ILIKE 'nateglinide%'
      )
),
antidiabetic_rx AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN antidiabetic_ingredients ai
      ON de.drug_concept_id = ai.concept_id
),
abnormal_dm_labs AS (
    SELECT
        m.person_id,
        COUNT(DISTINCT m.measurement_date) AS abnormal_lab_dates
    FROM public.measurement m
    JOIN public.concept c
      ON c.concept_id = m.measurement_concept_id
    WHERE m.value_as_number IS NOT NULL
      AND (
            /* HbA1c >= 6.5% */
            (
                (
                    c.concept_name ILIKE '%hemoglobin a1c%'
                 OR c.concept_name ILIKE '%glycated hemoglobin%'
                 OR m.measurement_source_value IN ('4548-4','17856-6')
                )
                AND m.value_as_number >= 6.5
            )

            OR

            /* Fasting glucose >=126 mg/dL */
            (
                (
                    c.concept_name ILIKE '%fasting%glucose%'
                 OR m.measurement_source_value IN ('1558-6','14771-0')
                )
                AND (
                     m.unit_source_value ILIKE '%mg/dl%'
                     OR m.unit_source_value IS NULL
                     OR m.unit_source_value = ''
                )
                AND m.value_as_number >= 126
            )

            OR

            /* Random glucose >=200 mg/dL */
            (
                (
                    c.concept_name ILIKE '%glucose%'
                    AND c.concept_name NOT ILIKE '%fasting%'
                )
                AND (
                     m.unit_source_value ILIKE '%mg/dl%'
                     OR m.unit_source_value IS NULL
                     OR m.unit_source_value = ''
                )
                AND m.value_as_number >= 200
            )
      )
    GROUP BY m.person_id
)

SELECT DISTINCT person_id
FROM (
    /* Criterion 1: repeated T2DM diagnoses */
    SELECT dx.person_id
    FROM t2dm_dx dx
    WHERE dx.dx_dates >= 2

    UNION

    /* Criterion 2: diagnosis plus antidiabetic medication */
    SELECT dx.person_id
    FROM t2dm_dx dx
    JOIN antidiabetic_rx rx
      ON dx.person_id = rx.person_id
    WHERE dx.dx_dates >= 1

    UNION

    /* Criterion 3: repeated abnormal diabetes labs */
    SELECT l.person_id
    FROM abnormal_dm_labs l
    WHERE l.abnormal_lab_dates >= 2
) phenotype;