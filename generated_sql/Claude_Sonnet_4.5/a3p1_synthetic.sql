-- T2DM phenotype: OMOP synthetic database (PostgreSQL / pgAdmin 4)

WITH
-- Standard T2DM concepts (SNOMED 201826 and descendants)
t2dm_std AS (
    SELECT descendant_concept_id AS concept_id
    FROM concept_ancestor
    WHERE ancestor_concept_id = 201826
),
-- Standard T1DM concepts (SNOMED 201820 and descendants), used for exclusion
t1dm_std AS (
    SELECT descendant_concept_id AS concept_id
    FROM concept_ancestor
    WHERE ancestor_concept_id = 201820
),
-- Source ICD-10-CM / ICD-9-CM T2DM codes
t2dm_src AS (
    SELECT c.concept_id
    FROM concept c
    WHERE (c.vocabulary_id = 'ICD10CM' AND c.concept_code ILIKE 'E11%')
       OR (c.vocabulary_id = 'ICD9CM'  AND c.concept_code ~ '^250\.[0-9][02]$')
),
-- Source ICD-10-CM / ICD-9-CM T1DM codes, used for exclusion
t1dm_src AS (
    SELECT c.concept_id
    FROM concept c
    WHERE (c.vocabulary_id = 'ICD10CM' AND c.concept_code ILIKE 'E10%')
       OR (c.vocabulary_id = 'ICD9CM'  AND c.concept_code ~ '^250\.[0-9][13]$')
),
-- Map ICD source codes to standard concepts ('Maps to', currently valid)
t2dm_mapped AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM concept_relationship cr
    JOIN t2dm_src s ON s.concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'
      AND cr.invalid_reason IS NULL
),
t1dm_mapped AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM concept_relationship cr
    JOIN t1dm_src s ON s.concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'
      AND cr.invalid_reason IS NULL
),
-- T2DM diagnosis events (standard concept or ICD source concept)
dx AS (
    SELECT co.person_id, co.condition_start_date AS dx_date
    FROM condition_occurrence co
    WHERE co.condition_concept_id IN (
              SELECT concept_id FROM t2dm_std
              UNION
              SELECT concept_id FROM t2dm_mapped)
       OR co.condition_source_concept_id IN (SELECT concept_id FROM t2dm_src)
),
-- T1DM diagnosis events (for exclusion)
t1dm_dx AS (
    SELECT DISTINCT co.person_id
    FROM condition_occurrence co
    WHERE co.condition_concept_id IN (
              SELECT concept_id FROM t1dm_std
              UNION
              SELECT concept_id FROM t1dm_mapped)
       OR co.condition_source_concept_id IN (SELECT concept_id FROM t1dm_src)
),
-- Persons with >=2 T2DM diagnoses on distinct dates
dx_multi AS (
    SELECT person_id
    FROM dx
    GROUP BY person_id
    HAVING COUNT(DISTINCT dx_date) >= 2
),
-- Persons with >=1 T2DM diagnosis
dx_any AS (
    SELECT DISTINCT person_id FROM dx
),
-- Glucose-lowering drug exposure (generic and brand names; insulin as class)
glucose_lowering_rx AS (
    SELECT DISTINCT de.person_id
    FROM drug_exposure de
    JOIN concept c ON c.concept_id = de.drug_concept_id
    WHERE c.concept_name ILIKE ANY (ARRAY[
        '%metformin%',  '%glucophage%',
        '%sitagliptin%', '%januvia%',
        '%empagliflozin%', '%jardiance%',
        '%dapagliflozin%', '%farxiga%',
        '%canagliflozin%', '%invokana%',
        '%liraglutide%', '%victoza%',
        '%semaglutide%', '%ozempic%',
        '%glipizide%', '%glucotrol%',
        '%glimepiride%', '%amaryl%',
        '%glyburide%', '%pioglitazone%', '%actos%',
        '%insulin%'
    ])
),
-- Diabetic-range labs (HbA1c >= 6.5% or >= 48 mmol/mol; glucose >= 126 mg/dL)
diabetic_lab AS (
    SELECT DISTINCT m.person_id
    FROM measurement m
    WHERE (
        -- HbA1c in percent (LOINC 4548-4, 17856-6, 4549-2)
        (m.measurement_source_value IN ('4548-4', '17856-6', '4549-2')
         AND m.value_as_number >= 6.5
         AND m.unit_source_value ILIKE '%\%%')
        OR
        -- HbA1c in mmol/mol (LOINC 59261-8)
        (m.measurement_source_value = '59261-8'
         AND m.value_as_number >= 48
         AND m.unit_source_value ILIKE '%mmol%')
        OR
        -- Fasting/serum glucose in mg/dL (LOINC 2339-0, 1558-6)
        (m.measurement_source_value IN ('2339-0', '1558-6')
         AND m.value_as_number >= 126
         AND m.unit_source_value ILIKE '%mg/dL%')
    )
    AND m.value_as_number IS NOT NULL
    AND m.value_as_number > 0
),
-- Cohort: T2DM by repeated diagnosis, or diagnosis plus treatment/lab evidence
t2dm_cohort AS (
    SELECT person_id FROM dx_multi
    UNION
    SELECT d.person_id
    FROM dx_any d
    WHERE d.person_id IN (SELECT person_id FROM glucose_lowering_rx)
       OR d.person_id IN (SELECT person_id FROM diabetic_lab)
)
-- Final: distinct persons, excluding type 1 DM evidence
SELECT DISTINCT p.person_id
FROM person p
WHERE p.person_id IN (SELECT person_id FROM t2dm_cohort)
  AND p.person_id NOT IN (SELECT person_id FROM t1dm_dx);