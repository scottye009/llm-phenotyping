-- Type 2 Diabetes Mellitus Phenotyping Algorithm
-- Inclusion: >=2 T2DM dx on different dates, OR 1 dx + T2DM med, OR 1 dx + HbA1c >= 6.5%
-- Exclusion: patients with more T1DM diagnoses than T2DM diagnoses

WITH t2dm_concepts AS (
    -- Standard concepts from ICD9CM (250.x0, 250.x2) and ICD10CM (E11.x)
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM public.concept c
    JOIN public.concept_relationship cr
        ON c.concept_id = cr.concept_id_1
        AND cr.relationship_id = 'Maps to'
        AND cr.invalid_reason IS NULL
    WHERE (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~ '^250\.[0-9][02]$')
       OR (c.vocabulary_id = 'ICD10CM' AND c.concept_code ~ '^E11')
    UNION
    -- Include all descendant concepts of T2DM (SNOMED 44054006)
    SELECT DISTINCT ca.descendant_concept_id
    FROM public.concept_ancestor ca
    WHERE ca.ancestor_concept_id = 201826
),

t1dm_concepts AS (
    -- Standard concepts from ICD9CM (250.x1, 250.x3) and ICD10CM (E10.x)
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM public.concept c
    JOIN public.concept_relationship cr
        ON c.concept_id = cr.concept_id_1
        AND cr.relationship_id = 'Maps to'
        AND cr.invalid_reason IS NULL
    WHERE (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~ '^250\.[0-9][13]$')
       OR (c.vocabulary_id = 'ICD10CM' AND c.concept_code ~ '^E10')
    UNION
    SELECT DISTINCT ca.descendant_concept_id
    FROM public.concept_ancestor ca
    WHERE ca.ancestor_concept_id = 201254
),

t2dm_dx AS (
    -- All T2DM condition occurrences
    SELECT co.person_id, co.condition_start_date
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (SELECT concept_id FROM t2dm_concepts)
),

t1dm_dx AS (
    -- All T1DM condition occurrences
    SELECT co.person_id, co.condition_start_date
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (SELECT concept_id FROM t1dm_concepts)
),

t2dm_meds AS (
    -- T2DM-specific medications (oral hypoglycemics, GLP-1 RAs, SGLT2i)
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN public.concept c ON de.drug_concept_id = c.concept_id
    WHERE c.concept_name ~* '(metformin|glipizide|glyburide|glimepiride|pioglitazone|rosiglitazone|sitagliptin|saxagliptin|linagliptin|alogliptin|canagliflozin|dapagliflozin|empagliflozin|ertugliflozin|exenatide|liraglutide|dulaglutide|semaglutide|repaglinide|nateglinide|acarbose|miglitol)'
),

hba1c_elevated AS (
    -- HbA1c >= 6.5%
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN public.concept c ON m.measurement_concept_id = c.concept_id
    WHERE (c.concept_code IN ('4548-4', '17856-6', '4549-2')
           OR c.concept_name ~* 'hemoglobin a1c|glycated hemoglobin|hba1c')
      AND m.value_as_number >= 6.5
),

dx_twice AS (
    -- >=2 T2DM diagnoses on different dates
    SELECT person_id
    FROM t2dm_dx
    GROUP BY person_id
    HAVING COUNT(DISTINCT condition_start_date) >= 2
),

dx_once AS (
    -- >=1 T2DM diagnosis
    SELECT DISTINCT person_id
    FROM t2dm_dx
),

t1dm_predominant AS (
    -- Patients with more T1DM than T2DM diagnoses
    SELECT t1.person_id
    FROM (SELECT person_id, COUNT(*) AS cnt FROM t1dm_dx GROUP BY person_id) t1
    LEFT JOIN (SELECT person_id, COUNT(*) AS cnt FROM t2dm_dx GROUP BY person_id) t2
        ON t1.person_id = t2.person_id
    WHERE t1.cnt > COALESCE(t2.cnt, 0)
)

SELECT DISTINCT person_id
FROM (
    SELECT person_id FROM dx_twice
    UNION
    SELECT person_id FROM dx_once
        WHERE person_id IN (SELECT person_id FROM t2dm_meds)
    UNION
    SELECT person_id FROM dx_once
        WHERE person_id IN (SELECT person_id FROM hba1c_elevated)
) qualified
WHERE person_id NOT IN (SELECT person_id FROM t1dm_predominant)
ORDER BY person_id;
