/* Type 2 Diabetes Mellitus phenotype:
   Include patients meeting ANY of:
   1) >= 2 T2DM diagnoses on different dates
   2) 1 T2DM diagnosis + exposure to a non-insulin antihyperglycemic medication
   3) Diabetes laboratory evidence:
        - HbA1c >= 6.5 %
        - Fasting glucose >= 126 mg/dL
        - Random/plasma glucose >= 200 mg/dL
   Exclude patients with evidence of Type 1 diabetes and no supporting T2DM evidence.
*/

WITH t2dm_icd_source AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
      AND (
            c.concept_code LIKE '250%'      /* ICD9DM */
         OR c.concept_code LIKE 'E11%'      /* ICD10 T2DM */
      )
),
t2dm_standard AS (
    SELECT DISTINCT
           COALESCE(cr.concept_id_2, c.concept_id) AS standard_concept_id
    FROM public.concept c
    LEFT JOIN public.concept_relationship cr
      ON cr.concept_id_1 = c.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
    WHERE c.concept_id IN (SELECT concept_id FROM t2dm_icd_source)

    UNION

    SELECT DISTINCT ca.descendant_concept_id
    FROM public.concept c
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = c.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
    JOIN public.concept_ancestor ca
      ON ca.ancestor_concept_id = cr.concept_id_2
    WHERE c.concept_id IN (SELECT concept_id FROM t2dm_icd_source)
),
t1dm_standard AS (
    SELECT DISTINCT
           COALESCE(cr.concept_id_2, c.concept_id) AS standard_concept_id
    FROM public.concept c
    LEFT JOIN public.concept_relationship cr
      ON cr.concept_id_1 = c.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
    WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
      AND (
            c.concept_code LIKE '250.x1'
         OR c.concept_code LIKE '250.x3'
         OR c.concept_code LIKE 'E10%'
      )
),
t2dm_dx AS (
    SELECT
        co.person_id,
        COUNT(DISTINCT co.condition_start_date) AS dx_dates
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (
        SELECT standard_concept_id
        FROM t2dm_standard
        WHERE standard_concept_id <> 0
    )
    GROUP BY co.person_id
),
t1dm_dx AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (
        SELECT standard_concept_id
        FROM t1dm_standard
        WHERE standard_concept_id <> 0
    )
),
antidiabetic_drugs AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN public.concept c
      ON c.concept_id = de.drug_concept_id
    WHERE c.domain_id = 'Drug'
      AND (
            c.concept_name ILIKE '%metformin%'
         OR c.concept_name ILIKE '%glipizide%'
         OR c.concept_name ILIKE '%glyburide%'
         OR c.concept_name ILIKE '%glimepiride%'
         OR c.concept_name ILIKE '%pioglitazone%'
         OR c.concept_name ILIKE '%rosiglitazone%'
         OR c.concept_name ILIKE '%acarbose%'
         OR c.concept_name ILIKE '%miglitol%'
         OR c.concept_name ILIKE '%sitagliptin%'
         OR c.concept_name ILIKE '%saxagliptin%'
         OR c.concept_name ILIKE '%linagliptin%'
         OR c.concept_name ILIKE '%alogliptin%'
         OR c.concept_name ILIKE '%exenatide%'
         OR c.concept_name ILIKE '%liraglutide%'
         OR c.concept_name ILIKE '%dulaglutide%'
         OR c.concept_name ILIKE '%semaglutide%'
         OR c.concept_name ILIKE '%lixisenatide%'
         OR c.concept_name ILIKE '%empagliflozin%'
         OR c.concept_name ILIKE '%dapagliflozin%'
         OR c.concept_name ILIKE '%canagliflozin%'
         OR c.concept_name ILIKE '%ertugliflozin%'
         OR c.concept_name ILIKE '%tirzepatide%'
         OR c.concept_name ILIKE '%janumet%'
         OR c.concept_name ILIKE '%januvia%'
         OR c.concept_name ILIKE '%ozempic%'
         OR c.concept_name ILIKE '%rybelsus%'
         OR c.concept_name ILIKE '%trulicity%'
         OR c.concept_name ILIKE '%victoza%'
         OR c.concept_name ILIKE '%farxiga%'
         OR c.concept_name ILIKE '%jardiance%'
         OR c.concept_name ILIKE '%invokana%'
      )
),
dm_labs AS (
    SELECT DISTINCT m.person_id
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
                    OR m.measurement_source_value ILIKE '%4548-4%'
                    OR m.measurement_source_value ILIKE '%17856-6%'
                )
                AND m.value_as_number >= 6.5
            )

            OR

            /* Fasting glucose >=126 mg/dL */
            (
                (
                    c.concept_name ILIKE '%fasting%glucose%'
                    OR m.measurement_source_value ILIKE '%1558-6%'
                )
                AND (
                    (m.unit_source_value ILIKE '%mg/dl%' AND m.value_as_number >= 126)
                    OR m.unit_source_value IS NULL
                    OR m.unit_source_value = ''
                )
            )

            OR

            /* Plasma/random glucose >=200 mg/dL */
            (
                (
                    c.concept_name ILIKE '%glucose%'
                    OR m.measurement_source_value ILIKE '%2345-7%'
                    OR m.measurement_source_value ILIKE '%2339-0%'
                )
                AND (
                    (m.unit_source_value ILIKE '%mg/dl%' AND m.value_as_number >= 200)
                    OR m.unit_source_value IS NULL
                    OR m.unit_source_value = ''
                )
            )
      )
),
eligible AS (
    SELECT person_id
    FROM t2dm_dx
    WHERE dx_dates >= 2

    UNION

    SELECT d.person_id
    FROM t2dm_dx d
    JOIN antidiabetic_drugs a
      ON a.person_id = d.person_id
    WHERE d.dx_dates >= 1

    UNION

    SELECT person_id
    FROM dm_labs
)
SELECT DISTINCT e.person_id
FROM eligible e
LEFT JOIN t1dm_dx t1
  ON t1.person_id = e.person_id
LEFT JOIN t2dm_dx t2
  ON t2.person_id = e.person_id
WHERE t1.person_id IS NULL
   OR COALESCE(t2.dx_dates,0) >= 1
ORDER BY e.person_id;