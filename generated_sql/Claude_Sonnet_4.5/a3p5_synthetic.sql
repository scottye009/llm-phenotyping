-- Type 2 diabetes mellitus phenotype (synthetic OMOP CDM, PostgreSQL)

WITH icd_t2 AS (
    -- ICD10CM E11.x and ICD9CM 250.x0 / 250.x2 source codes
    SELECT c.concept_id
    FROM public.concept c
    WHERE (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E11%')
       OR (c.vocabulary_id = 'ICD9CM'  AND c.concept_code ~ '^250\.?[0-9][02]')
),
icd_t1 AS (
    -- ICD10CM E10.x and ICD9CM 250.x1 / 250.x3 source codes
    SELECT c.concept_id
    FROM public.concept c
    WHERE (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E10%')
       OR (c.vocabulary_id = 'ICD9CM'  AND c.concept_code ~ '^250\.?[0-9][13]')
),
t2_concepts AS (
    -- SNOMED T2DM hierarchy, ICD source codes, and their 'Maps to' standard targets
    SELECT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    WHERE ca.ancestor_concept_id = 201826
    UNION
    SELECT concept_id FROM icd_t2
    UNION
    SELECT cr.concept_id_2
    FROM public.concept_relationship cr
    JOIN icd_t2 i ON i.concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'
      AND cr.invalid_reason IS NULL
),
t1_concepts AS (
    -- SNOMED T1DM hierarchy, ICD source codes, and their 'Maps to' standard targets
    SELECT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    WHERE ca.ancestor_concept_id = 201254
    UNION
    SELECT concept_id FROM icd_t1
    UNION
    SELECT cr.concept_id_2
    FROM public.concept_relationship cr
    JOIN icd_t1 i ON i.concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'
      AND cr.invalid_reason IS NULL
),
dx_t2 AS (
    -- Persons with at least one T2DM diagnosis
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (SELECT concept_id FROM t2_concepts)
       OR co.condition_source_concept_id IN (SELECT concept_id FROM t2_concepts)
),
dx_t1 AS (
    -- Persons with at least one T1DM diagnosis (exclusion)
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (SELECT concept_id FROM t1_concepts)
       OR co.condition_source_concept_id IN (SELECT concept_id FROM t1_concepts)
),
med_t2 AS (
    -- Antidiabetic drug exposure by generic or brand name
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN public.concept c ON c.concept_id = de.drug_concept_id
    WHERE c.domain_id = 'Drug'
      AND c.concept_name ILIKE ANY (ARRAY[
            '%metformin%', '%glucophage%',
            '%glipizide%', '%glucotrol%',
            '%glyburide%', '%glynase%', '%diabeta%',
            '%glimepiride%', '%amaryl%',
            '%sitagliptin%', '%januvia%',
            '%saxagliptin%', '%onglyza%',
            '%linagliptin%', '%tradjenta%',
            '%pioglitazone%', '%actos%',
            '%empagliflozin%', '%jardiance%',
            '%dapagliflozin%', '%farxiga%',
            '%canagliflozin%', '%invokana%',
            '%semaglutide%', '%ozempic%', '%rybelsus%',
            '%liraglutide%', '%victoza%',
            '%dulaglutide%', '%trulicity%',
            '%insulin%', '%lantus%', '%humalog%', '%novolog%'
          ])
),
lab_t2 AS (
    -- HbA1c >= 6.5 %
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    WHERE m.measurement_source_value IN ('4548-4', '17856-6', '41995-2')
      AND m.value_as_number >= 6.5
      AND (m.unit_concept_id IN (8554, 0)
           OR m.unit_source_value IS NULL
           OR m.unit_source_value ILIKE '%\%%')
    UNION
    -- Fasting glucose >= 126 mg/dL (mmol/L converted)
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    WHERE m.measurement_source_value = '1558-6'
      AND (CASE WHEN m.unit_concept_id = 8753 OR m.unit_source_value ILIKE '%mmol%'
                THEN m.value_as_number * 18.016
                ELSE m.value_as_number END) >= 126
    UNION
    -- Random glucose >= 200 mg/dL (mmol/L converted)
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    WHERE m.measurement_source_value = '2345-7'
      AND (CASE WHEN m.unit_concept_id = 8753 OR m.unit_source_value ILIKE '%mmol%'
                THEN m.value_as_number * 18.016
                ELSE m.value_as_number END) >= 200
)
-- Final cohort: (T2DM diagnosis OR antidiabetic drug + elevated glycemic lab), excluding T1DM
SELECT DISTINCT p.person_id
FROM public.person p
WHERE (
        p.person_id IN (SELECT person_id FROM dx_t2)
     OR (p.person_id IN (SELECT person_id FROM med_t2)
         AND p.person_id IN (SELECT person_id FROM lab_t2))
      )
  AND p.person_id NOT IN (SELECT person_id FROM dx_t1);