/* Type 2 Diabetes Mellitus phenotype (synthetic OMOP CDM)
   Logic:
   1) T2DM diagnosis:
      - ICD9CM 250.x0, 250.x2
      - ICD10CM E11*
      - Map source ICD concepts to standard concepts via 'Maps to'
      - Expand descendants using concept_ancestor
   2) T2DM medication evidence:
      - RxNorm/RxNorm Extension concepts matching common T2DM drugs
        (metformin, sulfonylureas, DPP4 inhibitors, GLP1 agonists,
         SGLT2 inhibitors, thiazolidinediones, meglitinides)
      - Ingredient and descendant expansion through concept_ancestor
   3) Diabetes laboratory evidence:
      - HbA1c >= 6.5%
      - Fasting plasma glucose >= 126 mg/dL
      - Random plasma glucose >= 200 mg/dL
      - Uses LOINC source concepts mapped to standard measurement concepts
   4) Final phenotype:
      - (>=2 T2DM diagnoses)
        OR
      - (>=1 T2DM diagnosis AND >=1 T2DM medication)
        OR
      - (>=1 T2DM diagnosis AND >=1 qualifying diabetes lab)
*/

WITH t2dm_icd_source AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
      AND (
            (c.vocabulary_id = 'ICD9CM'
             AND (c.concept_code ~ '^250.*0$'
                  OR c.concept_code ~ '^250.*2$'))
         OR (c.vocabulary_id = 'ICD10CM'
             AND c.concept_code LIKE 'E11%')
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

    SELECT DISTINCT concept_id
    FROM t2dm_icd_source
),
t2dm_condition_concepts AS (
    SELECT DISTINCT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    JOIN t2dm_standard t
      ON ca.ancestor_concept_id = t.concept_id

    UNION

    SELECT concept_id
    FROM t2dm_standard
),
dx_patients AS (
    SELECT
        co.person_id,
        COUNT(*) AS dx_count
    FROM public.condition_occurrence co
    JOIN t2dm_condition_concepts d
      ON co.condition_concept_id = d.concept_id
    GROUP BY co.person_id
),

/* Common T2DM ingredients and brands represented through RxNorm naming */
t2dm_drug_ingredients AS (
    SELECT DISTINCT c.concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Drug'
      AND c.vocabulary_id IN ('RxNorm','RxNorm Extension')
      AND (
            c.concept_name ILIKE 'metformin%'
         OR c.concept_name ILIKE 'glipizide%'
         OR c.concept_name ILIKE 'glyburide%'
         OR c.concept_name ILIKE 'glimepiride%'
         OR c.concept_name ILIKE 'tolazamide%'
         OR c.concept_name ILIKE 'tolbutamide%'
         OR c.concept_name ILIKE 'chlorpropamide%'
         OR c.concept_name ILIKE 'pioglitazone%'
         OR c.concept_name ILIKE 'rosiglitazone%'
         OR c.concept_name ILIKE 'repaglinide%'
         OR c.concept_name ILIKE 'nateglinide%'
         OR c.concept_name ILIKE 'sitagliptin%'
         OR c.concept_name ILIKE 'saxagliptin%'
         OR c.concept_name ILIKE 'linagliptin%'
         OR c.concept_name ILIKE 'alogliptin%'
         OR c.concept_name ILIKE 'exenatide%'
         OR c.concept_name ILIKE 'liraglutide%'
         OR c.concept_name ILIKE 'dulaglutide%'
         OR c.concept_name ILIKE 'semaglutide%'
         OR c.concept_name ILIKE 'lixisenatide%'
         OR c.concept_name ILIKE 'tirzepatide%'
         OR c.concept_name ILIKE 'canagliflozin%'
         OR c.concept_name ILIKE 'dapagliflozin%'
         OR c.concept_name ILIKE 'empagliflozin%'
         OR c.concept_name ILIKE 'ertugliflozin%'
         OR c.concept_name ILIKE 'janumet%'
         OR c.concept_name ILIKE 'januvia%'
         OR c.concept_name ILIKE 'onglyza%'
         OR c.concept_name ILIKE 'tradjenta%'
         OR c.concept_name ILIKE 'nesina%'
         OR c.concept_name ILIKE 'victoza%'
         OR c.concept_name ILIKE 'ozempic%'
         OR c.concept_name ILIKE 'rybelsus%'
         OR c.concept_name ILIKE 'trulicity%'
         OR c.concept_name ILIKE 'byetta%'
         OR c.concept_name ILIKE 'bydureon%'
         OR c.concept_name ILIKE 'farxiga%'
         OR c.concept_name ILIKE 'jardiance%'
         OR c.concept_name ILIKE 'invokana%'
         OR c.concept_name ILIKE 'steglatro%'
         OR c.concept_name ILIKE 'actos%'
         OR c.concept_name ILIKE 'avandia%'
      )
),
t2dm_drug_concepts AS (
    SELECT DISTINCT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    JOIN t2dm_drug_ingredients i
      ON ca.ancestor_concept_id = i.concept_id

    UNION

    SELECT concept_id
    FROM t2dm_drug_ingredients
),
drug_patients AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN t2dm_drug_concepts dc
      ON de.drug_concept_id = dc.concept_id
),

/* HbA1c, fasting glucose, random glucose via LOINC -> standard mapping */
lab_source_concepts AS (
    SELECT DISTINCT c.concept_id,
           c.concept_code
    FROM public.concept c
    WHERE c.vocabulary_id = 'LOINC'
      AND c.concept_code IN (
            '4548-4',  /* HbA1c */
            '17856-6', /* HbA1c */
            '1558-6',  /* fasting glucose */
            '14771-0', /* fasting glucose */
            '2339-0'   /* glucose */
      )
),
lab_standard_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id,
           ls.concept_code
    FROM lab_source_concepts ls
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = ls.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
),
lab_patients AS (
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN lab_standard_concepts l
      ON m.measurement_concept_id = l.concept_id
    WHERE m.value_as_number IS NOT NULL
      AND (
            (
              l.concept_code IN ('4548-4','17856-6')
              AND m.value_as_number >= 6.5
            )
         OR (
              l.concept_code IN ('1558-6','14771-0')
              AND m.value_as_number >= 126
              AND (
                    m.unit_source_value ILIKE '%mg/dl%'
                    OR m.unit_source_value IS NULL
                    OR m.unit_source_value = ''
                  )
            )
         OR (
              l.concept_code = '2339-0'
              AND m.value_as_number >= 200
              AND (
                    m.unit_source_value ILIKE '%mg/dl%'
                    OR m.unit_source_value IS NULL
                    OR m.unit_source_value = ''
                  )
            )
          )
)

SELECT DISTINCT p.person_id
FROM public.person p
LEFT JOIN dx_patients dx
       ON p.person_id = dx.person_id
LEFT JOIN drug_patients rx
       ON p.person_id = rx.person_id
LEFT JOIN lab_patients lab
       ON p.person_id = lab.person_id
WHERE
      COALESCE(dx.dx_count,0) >= 2
   OR (
        COALESCE(dx.dx_count,0) >= 1
        AND rx.person_id IS NOT NULL
      )
   OR (
        COALESCE(dx.dx_count,0) >= 1
        AND lab.person_id IS NOT NULL
      );