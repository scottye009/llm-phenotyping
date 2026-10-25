-- Type 2 diabetes mellitus phenotype (synthetic OMOP CDM, PostgreSQL)

WITH t2dm_source_codes AS (
    -- ICD10CM / ICD9CM type 2 diabetes source codes resolved to standard concepts
    SELECT DISTINCT c_std.concept_id AS condition_concept_id
    FROM public.concept c_src
    JOIN public.concept_relationship cr
         ON cr.concept_id_1 = c_src.concept_id
        AND cr.relationship_id = 'Maps to'
        AND cr.invalid_reason IS NULL
    JOIN public.concept c_std
         ON c_std.concept_id = cr.concept_id_2
        AND c_std.standard_concept = 'S'
    WHERE c_src.vocabulary_id IN ('ICD10CM', 'ICD9CM')
      AND (
            (c_src.vocabulary_id = 'ICD10CM' AND c_src.concept_code ~ '^E11(\.|$)')
         OR (c_src.vocabulary_id = 'ICD9CM'  AND c_src.concept_code ~ '^250\.[0-9]2$')
          )
),
t2dm_expanded AS (
    -- Expand to descendants where hierarchy is populated
    SELECT DISTINCT ca.descendant_concept_id AS condition_concept_id
    FROM public.concept_ancestor ca
    JOIN t2dm_source_codes s
         ON s.condition_concept_id = ca.ancestor_concept_id
    UNION
    SELECT condition_concept_id FROM t2dm_source_codes
),
t1dm_source_codes AS (
    -- Type 1 diabetes exclusion codes
    SELECT DISTINCT c_std.concept_id AS condition_concept_id
    FROM public.concept c_src
    JOIN public.concept_relationship cr
         ON cr.concept_id_1 = c_src.concept_id
        AND cr.relationship_id = 'Maps to'
        AND cr.invalid_reason IS NULL
    JOIN public.concept c_std
         ON c_std.concept_id = cr.concept_id_2
        AND c_std.standard_concept = 'S'
    WHERE c_src.vocabulary_id IN ('ICD10CM', 'ICD9CM')
      AND (
            (c_src.vocabulary_id = 'ICD10CM' AND c_src.concept_code ~ '^E10(\.|$)')
         OR (c_src.vocabulary_id = 'ICD9CM'  AND c_src.concept_code ~ '^250\.[0-9][13]$')
          )
),
t2dm_dx AS (
    -- Qualifying T2DM diagnosis records
    SELECT co.person_id,
           co.condition_start_date::date AS dx_date
    FROM public.condition_occurrence co
    JOIN t2dm_expanded t
         ON t.condition_concept_id = co.condition_concept_id
),
t2dm_dx_summary AS (
    SELECT person_id,
           COUNT(DISTINCT dx_date) AS n_dx_dates
    FROM t2dm_dx
    GROUP BY person_id
),
t1dm_persons AS (
    -- Persons with any type 1 diabetes diagnosis
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN t1dm_source_codes t
         ON t.condition_concept_id = co.condition_concept_id
),
hba1c_pos AS (
    -- HbA1c >= 6.5 % (LOINC 4548-4, 17856-6, 59261-8)
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    WHERE m.measurement_source_value IN ('4548-4', '17856-6', '59261-8')
      AND m.value_as_number IS NOT NULL
      AND m.value_as_number > 0
      AND (
            (m.unit_source_value ILIKE '%\%%' AND m.value_as_number >= 6.5)
         OR (m.unit_source_value ILIKE '%mmol/mol%' AND m.value_as_number >= 48)
         OR (m.unit_source_value IS NULL AND m.value_as_number >= 6.5 AND m.value_as_number < 20)
          )
),
fpg_pos AS (
    -- Fasting plasma glucose >= 126 mg/dL (LOINC 1558-6)
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    WHERE m.measurement_source_value = '1558-6'
      AND m.value_as_number IS NOT NULL
      AND m.value_as_number >= 126
      AND (m.unit_source_value ILIKE '%mg/dL%' OR m.unit_source_value IS NULL)
),
oral_antidiabetic_drugs AS (
    -- Non-insulin antidiabetic agents, generic and brand names
    SELECT DISTINCT de.person_id, de.drug_exposure_start_date::date AS drug_date
    FROM public.drug_exposure de
    JOIN public.concept c
         ON c.concept_id = de.drug_concept_id
    WHERE c.concept_name ILIKE ANY (ARRAY[
            '%metformin%', '%glipizide%', '%glyburide%', '%glimepiride%',
            '%sitagliptin%', '%Januvia%', '%linagliptin%', '%Tradjenta%',
            '%saxagliptin%', '%Onglyza%', '%alogliptin%', '%Nesina%',
            '%empagliflozin%', '%Jardiance%', '%dapagliflozin%', '%Farxiga%',
            '%canagliflozin%', '%Invokana%', '%pioglitazone%', '%Actos%',
            '%semaglutide%', '%Ozempic%', '%Rybelsus%', '%liraglutide%', '%Victoza%',
            '%dulaglutide%', '%Trulicity%', '%repaglinide%', '%nateglinide%'
          ])
),
oral_med_persons AS (
    SELECT DISTINCT person_id FROM oral_antidiabetic_drugs
),
dx_with_biomarker_or_med AS (
    -- Persons meeting case definition
    SELECT s.person_id
    FROM t2dm_dx_summary s
    WHERE s.n_dx_dates >= 2
    UNION
    SELECT s.person_id
    FROM t2dm_dx_summary s
    WHERE s.n_dx_dates >= 1
      AND (
            s.person_id IN (SELECT person_id FROM hba1c_pos)
         OR s.person_id IN (SELECT person_id FROM fpg_pos)
         OR s.person_id IN (SELECT person_id FROM oral_med_persons)
          )
)
-- Final cohort: distinct person_id, excluding type 1 diabetes
SELECT DISTINCT d.person_id
FROM dx_with_biomarker_or_med d
WHERE d.person_id NOT IN (SELECT person_id FROM t1dm_persons)
ORDER BY d.person_id;