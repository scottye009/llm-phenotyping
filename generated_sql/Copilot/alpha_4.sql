
-- Phenotyping algorithm for Type 2 Diabetes Mellitus (T2DM)
-- Schema: public

WITH

-- 1. Concept sets
t2dm_dx_concepts AS (
    SELECT DISTINCT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    JOIN public.concept c_anc
      ON c_anc.concept_id = ca.ancestor_concept_id
    WHERE c_anc.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (
            -- ICD9CM: 250.x0 or 250.x2
            (c_anc.vocabulary_id = 'ICD9CM'
             AND c_anc.concept_code LIKE '250.%'
             AND RIGHT(c_anc.concept_code, 1) IN ('0','2'))
         OR -- ICD10CM: E11%
            (c_anc.vocabulary_id = 'ICD10CM'
             AND c_anc.concept_code LIKE 'E11%')
      )
),

t1dm_dx_concepts AS (
    SELECT DISTINCT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    JOIN public.concept c_anc
      ON c_anc.concept_id = ca.ancestor_concept_id
    WHERE c_anc.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (
            -- ICD9CM: 250.x1 or 250.x3
            (c_anc.vocabulary_id = 'ICD9CM'
             AND c_anc.concept_code LIKE '250.%'
             AND RIGHT(c_anc.concept_code, 1) IN ('1','3'))
         OR -- ICD10CM: E10%
            (c_anc.vocabulary_id = 'ICD10CM'
             AND c_anc.concept_code LIKE 'E10%')
      )
),

gestational_dm_dx_concepts AS (
    SELECT DISTINCT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    JOIN public.concept c_anc
      ON c_anc.concept_id = ca.ancestor_concept_id
    WHERE c_anc.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (
            (c_anc.vocabulary_id = 'ICD9CM'
             AND c_anc.concept_code LIKE '648.8%')
         OR (c_anc.vocabulary_id = 'ICD10CM'
             AND c_anc.concept_code LIKE 'O24.4%')
         OR (c_anc.vocabulary_id = 'ICD10CM'
             AND c_anc.concept_code LIKE 'O24.9%')
      )
),

secondary_dm_dx_concepts AS (
    SELECT DISTINCT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    JOIN public.concept c_anc
      ON c_anc.concept_id = ca.ancestor_concept_id
    WHERE c_anc.vocabulary_id = 'ICD10CM'
      AND c_anc.concept_code LIKE 'E0_%'  -- e.g., E08%, E09%, E13% (adjust as needed)
),

-- Non-insulin antihyperglycemic drugs (RxNorm ingredients and descendants)
t2dm_drug_concepts AS (
    SELECT DISTINCT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    JOIN public.concept c_anc
      ON c_anc.concept_id = ca.ancestor_concept_id
    WHERE c_anc.vocabulary_id = 'RxNorm'
      AND c_anc.concept_class_id = 'Ingredient'
      AND UPPER(c_anc.concept_name) IN (
            'METFORMIN',
            'GLIPIZIDE',
            'GLYBURIDE',
            'GLIMEPIRIDE',
            'PIOGLITAZONE',
            'ROSIGLITAZONE',
            'SITAGLIPTIN',
            'SAXAGLIPTIN',
            'LINAGLIPTIN',
            'ALOGLIPTIN',
            'EXENATIDE',
            'LIRAGLUTIDE',
            'DULAGLUTIDE',
            'SEMAGLUTIDE',
            'CANAGLIFLOZIN',
            'DAPAGLIFLOZIN',
            'EMPAGLIFLOZIN',
            'ERTUGLIFLOZIN',
            'ACARBOSE',
            'MIGLITOL',
            'NATEGLINIDE',
            'REPAGLINIDE'
      )
),

insulin_drug_concepts AS (
    SELECT DISTINCT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    JOIN public.concept c_anc
      ON c_anc.concept_id = ca.ancestor_concept_id
    WHERE c_anc.vocabulary_id = 'RxNorm'
      AND c_anc.concept_class_id = 'Ingredient'
      AND UPPER(c_anc.concept_name) LIKE 'INSULIN%'  -- crude but effective starting point
),

-- Diabetes-related lab concepts (HbA1c + glucose)
dm_lab_concepts AS (
    SELECT DISTINCT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    JOIN public.concept c_anc
      ON c_anc.concept_id = ca.ancestor_concept_id
    WHERE c_anc.vocabulary_id = 'LOINC'
      AND (
            UPPER(c_anc.concept_name) LIKE '%HBA1C%'
         OR UPPER(c_anc.concept_name) LIKE '%GLUCOSE%'
      )
),

-- 2. Base events

t2dm_dx_events AS (
    SELECT
        co.person_id,
        co.condition_start_date,
        co.condition_concept_id,
        vo.visit_concept_id
    FROM public.condition_occurrence co
    JOIN public.observation_period op
      ON op.person_id = co.person_id
     AND co.condition_start_date BETWEEN op.observation_period_start_date
                                     AND op.observation_period_end_date
    LEFT JOIN public.visit_occurrence vo
      ON vo.visit_occurrence_id = co.visit_occurrence_id
    WHERE co.condition_concept_id IN (SELECT concept_id FROM t2dm_dx_concepts)
),

t1dm_dx_events AS (
    SELECT DISTINCT person_id
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (SELECT concept_id FROM t1dm_dx_concepts)
),

gestational_dm_dx_events AS (
    SELECT DISTINCT person_id
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (SELECT concept_id FROM gestational_dm_dx_concepts)
),

secondary_dm_dx_events AS (
    SELECT DISTINCT person_id
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (SELECT concept_id FROM secondary_dm_dx_concepts)
),

t2dm_drug_events AS (
    SELECT
        de.person_id,
        de.drug_exposure_start_date,
        de.drug_concept_id
    FROM public.drug_exposure de
    JOIN public.observation_period op
      ON op.person_id = de.person_id
     AND de.drug_exposure_start_date BETWEEN op.observation_period_start_date
                                         AND op.observation_period_end_date
    WHERE de.drug_concept_id IN (SELECT concept_id FROM t2dm_drug_concepts)
),

insulin_drug_events AS (
    SELECT DISTINCT
        de.person_id,
        de.drug_exposure_start_date,
        de.drug_concept_id
    FROM public.drug_exposure de
    JOIN public.observation_period op
      ON op.person_id = de.person_id
     AND de.drug_exposure_start_date BETWEEN op.observation_period_start_date
                                         AND op.observation_period_end_date
    WHERE de.drug_concept_id IN (SELECT concept_id FROM insulin_drug_concepts)
),

dm_lab_events AS (
    SELECT
        m.person_id,
        m.measurement_date,
        m.measurement_concept_id,
        m.value_as_number,
        m.unit_concept_id
    FROM public.measurement m
    JOIN public.observation_period op
      ON op.person_id = m.person_id
     AND m.measurement_date BETWEEN op.observation_period_start_date
                               AND op.observation_period_end_date
    WHERE m.measurement_concept_id IN (SELECT concept_id FROM dm_lab_concepts)
),

-- 3. Derived criteria

-- A1: >= 2 T2DM diagnoses on different dates (any setting)
criterion_A1 AS (
    SELECT
        person_id
    FROM t2dm_dx_events
    GROUP BY person_id
    HAVING COUNT(DISTINCT condition_start_date) >= 2
),

-- A2: >= 1 inpatient T2DM diagnosis
-- (assuming visit_concept_id for inpatient is standard inpatient concept; adjust IDs)
criterion_A2 AS (
    SELECT DISTINCT
        person_id
    FROM t2dm_dx_events
    WHERE visit_concept_id IN (
        -- put your standard inpatient visit_concept_ids here, e.g. 9201, 9203
        9201, 9203
    )
),

-- B: >= 1 T2DM diagnosis AND >= 1 non-insulin antihyperglycemic exposure
criterion_B AS (
    SELECT DISTINCT
        dx.person_id
    FROM t2dm_dx_events dx
    JOIN t2dm_drug_events dr
      ON dx.person_id = dr.person_id
),

-- C: >= 2 abnormal diabetes labs on different dates AND >= 1 non-insulin antihyperglycemic exposure
abnormal_dm_labs AS (
    SELECT
        l.person_id,
        l.measurement_date,
        l.value_as_number,
        l.measurement_concept_id
    FROM dm_lab_events l
    JOIN public.concept c
      ON c.concept_id = l.measurement_concept_id
    WHERE
        (
            -- crude HbA1c rule: value >= 6.5
            UPPER(c.concept_name) LIKE '%HBA1C%'
            AND l.value_as_number >= 6.5
        )
        OR
        (
            -- crude glucose rule: value >= 126 (fasting) or >= 200 (if not fasting)
            UPPER(c.concept_name) LIKE '%GLUCOSE%'
            AND l.value_as_number >= 126
        )
),

criterion_C_labs AS (
    SELECT
        person_id
    FROM abnormal_dm_labs
    GROUP BY person_id
    HAVING COUNT(DISTINCT measurement_date) >= 2
),

criterion_C AS (
    SELECT DISTINCT
        l.person_id
    FROM criterion_C_labs l
    JOIN t2dm_drug_events dr
      ON l.person_id = dr.person_id
),

-- Age at first evidence (diagnosis, lab, or drug)
first_evidence AS (
    SELECT
        p.person_id,
        MIN(e.event_date) AS first_event_date
    FROM public.person p
    JOIN (
        SELECT person_id, condition_start_date AS event_date
        FROM t2dm_dx_events
        UNION ALL
        SELECT person_id, drug_exposure_start_date AS event_date
        FROM t2dm_drug_events
        UNION ALL
        SELECT person_id, measurement_date AS event_date
        FROM dm_lab_events
    ) e
      ON p.person_id = e.person_id
    GROUP BY p.person_id
),

age_at_first_evidence AS (
    SELECT
        f.person_id,
        DATE_PART('year', f.first_event_date) - p.year_of_birth AS age_at_first
    FROM first_evidence f
    JOIN public.person p
      ON p.person_id = f.person_id
),

age_eligible AS (
    SELECT person_id
    FROM age_at_first_evidence
    WHERE age_at_first >= 18
),

-- Exclusion: gestational / secondary only (no T2DM dx)
gestational_or_secondary_only AS (
    SELECT DISTINCT
        p.person_id
    FROM public.person p
    LEFT JOIN t2dm_dx_events t2
      ON p.person_id = t2.person_id
    LEFT JOIN gestational_dm_dx_events g
      ON p.person_id = g.person_id
    LEFT JOIN secondary_dm_dx_events s
      ON p.person_id = s.person_id
    WHERE t2.person_id IS NULL
      AND (g.person_id IS NOT NULL OR s.person_id IS NOT NULL)
),

-- Optional exclusion: "pure" type 1 pattern
pure_type1_pattern AS (
    SELECT DISTINCT
        p.person_id
    FROM public.person p
    LEFT JOIN t2dm_dx_events t2
      ON p.person_id = t2.person_id
    LEFT JOIN t1dm_dx_events t1
      ON p.person_id = t1.person_id
    LEFT JOIN t2dm_drug_events t2d
      ON p.person_id = t2d.person_id
    LEFT JOIN insulin_drug_events ins
      ON p.person_id = ins.person_id
    WHERE t2.person_id IS NULL              -- no T2DM dx
      AND t1.person_id IS NOT NULL          -- has T1DM dx
      AND t2d.person_id IS NULL             -- no non-insulin antihyperglycemics
      AND ins.person_id IS NOT NULL         -- has insulin
),

-- 4. Combine inclusion criteria (A1 OR A2 OR B OR C)
inclusion_any AS (
    SELECT person_id FROM criterion_A1
    UNION
    SELECT person_id FROM criterion_A2
    UNION
    SELECT person_id FROM criterion_B
    UNION
    SELECT person_id FROM criterion_C
),

-- 5. Apply age and exclusions
t2dm_final AS (
    SELECT DISTINCT
        inc.person_id
    FROM inclusion_any inc
    JOIN age_eligible ae
      ON inc.person_id = ae.person_id
    LEFT JOIN gestational_or_secondary_only gso
      ON inc.person_id = gso.person_id
    LEFT JOIN pure_type1_pattern pt1
      ON inc.person_id = pt1.person_id
    WHERE gso.person_id IS NULL   -- NOT gestational/secondary-only
      AND pt1.person_id IS NULL   -- NOT pure type 1 pattern
)

SELECT *
FROM t2dm_final;
