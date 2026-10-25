/* Type 2 Diabetes Mellitus (T2DM) phenotype for synthetic OMOP CDM

Inclusion:
1) >= 2 T2DM diagnoses on different dates
OR
2) >= 1 T2DM diagnosis + >= 1 non-insulin antihyperglycemic drug exposure
OR
3) >= 1 qualifying diabetes laboratory result + >= 1 T2DM diagnosis

Uses:
- ICD9CM/ICD10CM -> standard concept mapping through concept_relationship
- concept_ancestor hierarchy expansion
- Standard OMOP condition_concept_id, drug_concept_id, measurement_concept_id
*/

WITH

/* ICD10CM E11* (Type 2 diabetes mellitus) */
t2dm_icd_source AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
      AND (
            c.concept_code LIKE 'E11%'
            OR (
                 c.vocabulary_id = 'ICD9CM'
                 AND c.concept_name ILIKE '%type 2 diabetes%'
               )
          )
      AND c.invalid_reason IS NULL
),

/* Source ICD -> standard concepts */
t2dm_standard AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM t2dm_icd_source s
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = s.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
),

/* Expand diagnosis hierarchy */
t2dm_condition_concepts AS (
    SELECT DISTINCT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    JOIN t2dm_standard ts
      ON ca.ancestor_concept_id = ts.concept_id

    UNION

    SELECT concept_id
    FROM t2dm_standard
),

/* Diagnosis events */
t2dm_dx AS (
    SELECT
        co.person_id,
        co.condition_start_date::date AS dx_date
    FROM public.condition_occurrence co
    JOIN t2dm_condition_concepts t
      ON t.concept_id = co.condition_concept_id
),

/* >=2 diagnosis dates */
dx_two_dates AS (
    SELECT person_id
    FROM t2dm_dx
    GROUP BY person_id
    HAVING COUNT(DISTINCT dx_date) >= 2
),

/* Non-insulin antihyperglycemic ingredients */
antidiabetic_ingredients AS (
    SELECT DISTINCT c.concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Drug'
      AND c.standard_concept = 'S'
      AND (
            c.concept_name ILIKE '%metformin%'
         OR c.concept_name ILIKE '%glipizide%'
         OR c.concept_name ILIKE '%glyburide%'
         OR c.concept_name ILIKE '%glimepiride%'
         OR c.concept_name ILIKE '%acarbose%'
         OR c.concept_name ILIKE '%miglitol%'
         OR c.concept_name ILIKE '%pioglitazone%'
         OR c.concept_name ILIKE '%rosiglitazone%'
         OR c.concept_name ILIKE '%repaglinide%'
         OR c.concept_name ILIKE '%nateglinide%'
         OR c.concept_name ILIKE '%sitagliptin%'
         OR c.concept_name ILIKE '%saxagliptin%'
         OR c.concept_name ILIKE '%linagliptin%'
         OR c.concept_name ILIKE '%alogliptin%'
         OR c.concept_name ILIKE '%exenatide%'
         OR c.concept_name ILIKE '%liraglutide%'
         OR c.concept_name ILIKE '%dulaglutide%'
         OR c.concept_name ILIKE '%semaglutide%'
         OR c.concept_name ILIKE '%lixisenatide%'
         OR c.concept_name ILIKE '%tirzepatide%'
         OR c.concept_name ILIKE '%empagliflozin%'
         OR c.concept_name ILIKE '%dapagliflozin%'
         OR c.concept_name ILIKE '%canagliflozin%'
         OR c.concept_name ILIKE '%ertugliflozin%'
      )
),

/* Expand ingredient descendants */
antidiabetic_drug_concepts AS (
    SELECT DISTINCT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    JOIN antidiabetic_ingredients ai
      ON ca.ancestor_concept_id = ai.concept_id

    UNION

    SELECT concept_id
    FROM antidiabetic_ingredients
),

drug_evidence AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN antidiabetic_drug_concepts d
      ON d.concept_id = de.drug_concept_id
),

/* Relevant LOINC laboratory source concepts */
lab_loinc_source AS (
    SELECT concept_id,
           concept_code
    FROM public.concept
    WHERE vocabulary_id = 'LOINC'
      AND concept_code IN (
            '4548-4',   /* HbA1c */
            '17856-6',  /* HbA1c */
            '1558-6',   /* fasting glucose */
            '14771-0',  /* fasting glucose */
            '2339-0',   /* glucose */
            '2345-7'    /* glucose */
      )
),

/* LOINC -> standard measurement concepts */
lab_standard AS (
    SELECT DISTINCT
           cr.concept_id_2 AS concept_id,
           ls.concept_code
    FROM lab_loinc_source ls
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = ls.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
),

lab_evidence AS (
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN lab_standard l
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
                    OR m.unit_source_value ILIKE '%mg/dL%'
                  )
            )
         OR (
              l.concept_code IN ('2339-0','2345-7')
              AND m.value_as_number >= 200
              AND (
                    m.unit_source_value ILIKE '%mg/dl%'
                    OR m.unit_source_value ILIKE '%mg/dL%'
                  )
            )
          )
),

dx_plus_drug AS (
    SELECT DISTINCT d.person_id
    FROM t2dm_dx d
    JOIN drug_evidence r
      ON r.person_id = d.person_id
),

dx_plus_lab AS (
    SELECT DISTINCT d.person_id
    FROM t2dm_dx d
    JOIN lab_evidence l
      ON l.person_id = d.person_id
)

SELECT DISTINCT person_id
FROM (
    SELECT person_id FROM dx_two_dates
    UNION
    SELECT person_id FROM dx_plus_drug
    UNION
    SELECT person_id FROM dx_plus_lab
) phenotype
ORDER BY person_id;