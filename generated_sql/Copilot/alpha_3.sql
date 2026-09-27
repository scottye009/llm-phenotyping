
WITH

-- 1. Concept sets -------------------------------------------------------

t2dm_dx_concepts AS (
    SELECT DISTINCT c.concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Condition'
      AND c.standard_concept = 'S'
      AND (
            -- ICD-9-CM 250.x0, 250.x2
            (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~ '^250..[02]$')
         OR -- ICD-10-CM E11.*
            (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E11%')
      )
),

t1dm_dx_concepts AS (
    SELECT DISTINCT c.concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Condition'
      AND c.standard_concept = 'S'
      AND (
            (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~ '^250..[13]$')
         OR (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E10%')
      )
),

gestational_dm_dx_concepts AS (
    SELECT DISTINCT c.concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Condition'
      AND c.standard_concept = 'S'
      AND c.vocabulary_id = 'ICD10CM'
      AND c.concept_code LIKE 'O24.4%'  -- gestational
),

-- T2DM medication concepts (RxNorm) – example using ingredient/brand names
t2dm_drug_concepts AS (
    SELECT DISTINCT c.concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Drug'
      AND c.standard_concept = 'S'
      AND c.vocabulary_id = 'RxNorm'
      AND (
            LOWER(c.concept_name) LIKE '%metformin%'      -- Glucophage, etc.
         OR LOWER(c.concept_name) LIKE '%glipizide%'      -- Glucotrol
         OR LOWER(c.concept_name) LIKE '%glyburide%'      -- Diabeta, Micronase
         OR LOWER(c.concept_name) LIKE '%glimepiride%'    -- Amaryl
         OR LOWER(c.concept_name) LIKE '%pioglitazone%'   -- Actos
         OR LOWER(c.concept_name) LIKE '%rosiglitazone%'  -- Avandia
         OR LOWER(c.concept_name) LIKE '%sitagliptin%'    -- Januvia
         OR LOWER(c.concept_name) LIKE '%saxagliptin%'    -- Onglyza
         OR LOWER(c.concept_name) LIKE '%linagliptin%'    -- Tradjenta
         OR LOWER(c.concept_name) LIKE '%alogliptin%'     -- Nesina
         OR LOWER(c.concept_name) LIKE '%exenatide%'      -- Byetta, Bydureon
         OR LOWER(c.concept_name) LIKE '%liraglutide%'    -- Victoza
         OR LOWER(c.concept_name) LIKE '%dulaglutide%'    -- Trulicity
         OR LOWER(c.concept_name) LIKE '%semaglutide%'    -- Ozempic, Rybelsus
         OR LOWER(c.concept_name) LIKE '%canagliflozin%'  -- Invokana
         OR LOWER(c.concept_name) LIKE '%dapagliflozin%'  -- Farxiga
         OR LOWER(c.concept_name) LIKE '%empagliflozin%'  -- Jardiance
         OR LOWER(c.concept_name) LIKE '%ertugliflozin%'  -- Steglatro
         OR LOWER(c.concept_name) LIKE '%insulin%'        -- insulin products
      )
),

-- Diabetes lab concepts (HbA1c, glucose, OGTT)
t2dm_lab_concepts AS (
    SELECT DISTINCT
        c.concept_id,
        c.concept_code
    FROM public.concept c
    WHERE c.domain_id = 'Measurement'
      AND c.standard_concept = 'S'
      AND c.vocabulary_id = 'LOINC'
      AND c.concept_code IN (
            -- HbA1c
            '4548-4','17856-6','41995-2',
            -- fasting glucose
            '1558-6','14771-0',
            -- OGTT
            '20436-2','14749-6',
            -- random glucose
            '2339-0'
      )
),

-- 2. Evidence tables ----------------------------------------------------

t2dm_dx AS (
    SELECT
        co.person_id,
        co.condition_start_date::date AS dx_date
    FROM public.condition_occurrence co
    JOIN t2dm_dx_concepts t2
      ON co.condition_concept_id = t2.concept_id
),

t1_or_gestational_dx AS (
    SELECT
        co.person_id,
        co.condition_start_date::date AS dx_date,
        CASE
            WHEN co.condition_concept_id IN (SELECT concept_id FROM t1dm_dx_concepts)
                THEN 'T1DM'
            WHEN co.condition_concept_id IN (SELECT concept_id FROM gestational_dm_dx_concepts)
                THEN 'GESTATIONAL'
        END AS dx_type
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (
        SELECT concept_id FROM t1dm_dx_concepts
        UNION
        SELECT concept_id FROM gestational_dm_dx_concepts
    )
),

t2dm_drug AS (
    SELECT
        de.person_id,
        de.drug_exposure_start_date::date AS drug_date
    FROM public.drug_exposure de
    JOIN t2dm_drug_concepts tdr
      ON de.drug_concept_id = tdr.concept_id
),

t2dm_abnormal_labs AS (
    SELECT
        m.person_id,
        m.measurement_date::date AS lab_date
    FROM public.measurement m
    JOIN t2dm_lab_concepts tl
      ON m.measurement_concept_id = tl.concept_id
    WHERE
        (
            -- HbA1c >= 6.5%
            tl.concept_code IN ('4548-4','17856-6','41995-2')
            AND m.value_as_number >= 6.5
        )
        OR
        (
            -- fasting glucose >= 126 mg/dL
            tl.concept_code IN ('1558-6','14771-0')
            AND m.value_as_number >= 126
        )
        OR
        (
            -- OGTT >= 200 mg/dL
            tl.concept_code IN ('20436-2','14749-6')
            AND m.value_as_number >= 200
        )
        OR
        (
            -- random glucose >= 200 mg/dL
            tl.concept_code IN ('2339-0')
            AND m.value_as_number >= 200
        )
),

-- 3. Aggregate evidence per person -------------------------------------

dx_counts AS (
    SELECT
        person_id,
        COUNT(DISTINCT dx_date) AS t2dm_dx_dates
    FROM t2dm_dx
    GROUP BY person_id
),

lab_counts AS (
    SELECT
        person_id,
        COUNT(DISTINCT lab_date) AS abnormal_lab_dates
    FROM t2dm_abnormal_labs
    GROUP BY person_id
),

drug_counts AS (
    SELECT
        person_id,
        COUNT(DISTINCT drug_date) AS t2dm_drug_dates
    FROM t2dm_drug
    GROUP BY person_id
),

t1_or_gestational_flags AS (
    SELECT
        person_id,
        MAX(CASE WHEN dx_type = 'T1DM' THEN 1 ELSE 0 END) AS has_t1dm_dx,
        MAX(CASE WHEN dx_type = 'GESTATIONAL' THEN 1 ELSE 0 END) AS has_gestational_dx
    FROM t1_or_gestational_dx
    GROUP BY person_id
),

-- 4. Combine logic into phenotype --------------------------------------

t2dm_candidates AS (
    SELECT
        p.person_id,

        COALESCE(dx_counts.t2dm_dx_dates, 0) AS t2dm_dx_dates,
        COALESCE(drug_counts.t2dm_drug_dates, 0) AS t2dm_drug_dates,
        COALESCE(lab_counts.abnormal_lab_dates, 0) AS abnormal_lab_dates,
        COALESCE(t1_or_gestational_flags.has_t1dm_dx, 0) AS has_t1dm_dx,
        COALESCE(t1_or_gestational_flags.has_gestational_dx, 0) AS has_gestational_dx

    FROM public.person p
    LEFT JOIN dx_counts
        ON p.person_id = dx_counts.person_id
    LEFT JOIN drug_counts
        ON p.person_id = drug_counts.person_id
    LEFT JOIN lab_counts
        ON p.person_id = lab_counts.person_id
    LEFT JOIN t1_or_gestational_flags
        ON p.person_id = t1_or_gestational_flags.person_id
)

SELECT *
FROM t2dm_candidates
WHERE
    (
        -- ( ≥2 T2DM diagnoses )
        t2dm_dx_dates >= 2

        OR

        -- ( ≥1 T2DM diagnosis AND ≥1 T2DM medication )
        (t2dm_dx_dates >= 1 AND t2dm_drug_dates >= 1)

        OR

        -- ( ≥2 abnormal diabetes labs )
        abnormal_lab_dates >= 2
    )
    AND
    -- Exclusion: NOT only type 1 or gestational
    NOT (
        t2dm_dx_dates = 0
        AND t2dm_drug_dates = 0
        AND abnormal_lab_dates = 0
        AND (has_t1dm_dx = 1 OR has_gestational_dx = 1)
    );
