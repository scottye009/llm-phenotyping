WITH

-- =========================
-- DIAGNOSIS CONCEPT SETS
-- =========================

t2dm_dx_concepts AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
      AND (
            -- ICD9CM: 250.x0, 250.x2
            (c.vocabulary_id = 'ICD9CM'
             AND c.concept_code LIKE '250.%'
             AND SUBSTRING(c.concept_code FROM 6 FOR 1) IN ('0','2'))
         OR -- ICD10CM: E11%
            (c.vocabulary_id = 'ICD10CM'
             AND c.concept_code LIKE 'E11%')
      )
),

t1dm_dx_concepts AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
      AND (
            -- ICD9CM: 250.x1, 250.x3
            (c.vocabulary_id = 'ICD9CM'
             AND c.concept_code LIKE '250.%'
             AND SUBSTRING(c.concept_code FROM 6 FOR 1) IN ('1','3'))
         OR -- ICD10CM: E10%
            (c.vocabulary_id = 'ICD10CM'
             AND c.concept_code LIKE 'E10%')
      )
),

gest_secondary_dm_concepts AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id = 'ICD10CM'
      AND (
            c.concept_code LIKE 'O24.4%'  -- gestational
         OR c.concept_code LIKE 'O24.9%'  -- other pregnancy-related DM
         OR c.concept_code LIKE 'E08%'    -- due to underlying condition
         OR c.concept_code LIKE 'E09%'    -- drug/chemical induced
         OR c.concept_code LIKE 'E13%'    -- other specified DM
      )
),

-- =========================
-- MEDICATION CONCEPT SETS
-- =========================

t2dm_med_concepts AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id = 'RxNorm'
      AND (
            -- Biguanides
            c.concept_name ILIKE '%metformin%'
         OR c.concept_name ILIKE '%Glucophage%'
            -- Sulfonylureas
         OR c.concept_name ILIKE '%glipizide%'
         OR c.concept_name ILIKE '%Glucotrol%'
         OR c.concept_name ILIKE '%glyburide%'
         OR c.concept_name ILIKE '%Diabeta%'
         OR c.concept_name ILIKE '%glimepiride%'
         OR c.concept_name ILIKE '%Amaryl%'
            -- TZDs
         OR c.concept_name ILIKE '%pioglitazone%'
         OR c.concept_name ILIKE '%Actos%'
         OR c.concept_name ILIKE '%rosiglitazone%'
         OR c.concept_name ILIKE '%Avandia%'
            -- DPP-4 inhibitors
         OR c.concept_name ILIKE '%sitagliptin%'
         OR c.concept_name ILIKE '%Januvia%'
         OR c.concept_name ILIKE '%saxagliptin%'
         OR c.concept_name ILIKE '%Onglyza%'
         OR c.concept_name ILIKE '%linagliptin%'
         OR c.concept_name ILIKE '%Tradjenta%'
            -- GLP-1 RAs
         OR c.concept_name ILIKE '%exenatide%'
         OR c.concept_name ILIKE '%Byetta%'
         OR c.concept_name ILIKE '%liraglutide%'
         OR c.concept_name ILIKE '%Victoza%'
         OR c.concept_name ILIKE '%semaglutide%'
         OR c.concept_name ILIKE '%Ozempic%'
         OR c.concept_name ILIKE '%dulaglutide%'
         OR c.concept_name ILIKE '%Trulicity%'
            -- SGLT2 inhibitors
         OR c.concept_name ILIKE '%canagliflozin%'
         OR c.concept_name ILIKE '%Invokana%'
         OR c.concept_name ILIKE '%dapagliflozin%'
         OR c.concept_name ILIKE '%Farxiga%'
         OR c.concept_name ILIKE '%empagliflozin%'
         OR c.concept_name ILIKE '%Jardiance%'
      )
),

insulin_concepts AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id = 'RxNorm'
      AND (
            c.concept_name ILIKE '%insulin%'
         OR c.concept_name ILIKE '%Lantus%'
         OR c.concept_name ILIKE '%Levemir%'
         OR c.concept_name ILIKE '%Tresiba%'
         OR c.concept_name ILIKE '%Humalog%'
         OR c.concept_name ILIKE '%Novolog%'
      )
),

-- =========================
-- LAB CONCEPT SETS
-- =========================

t2dm_lab_concepts AS (
    SELECT c.concept_id, c.concept_name, c.concept_code
    FROM public.concept c
    WHERE c.vocabulary_id = 'LOINC'
      AND (
            c.concept_code IN ('4548-4','17856-6','41995-2') -- HbA1c examples
         OR c.concept_name ILIKE '%glucose%'
      )
),

-- =========================
-- EVENT-LEVEL CTEs
-- =========================

t2dm_dx AS (
    SELECT
        co.person_id,
        co.condition_start_date AS event_date
    FROM public.condition_occurrence co
    JOIN t2dm_dx_concepts t2
      ON co.condition_concept_id = t2.concept_id
),

t1dm_dx AS (
    SELECT
        co.person_id,
        co.condition_start_date AS event_date
    FROM public.condition_occurrence co
    JOIN t1dm_dx_concepts t1
      ON co.condition_concept_id = t1.concept_id
),

gest_secondary_dm_dx AS (
    SELECT
        co.person_id,
        co.condition_start_date AS event_date
    FROM public.condition_occurrence co
    JOIN gest_secondary_dm_concepts g
      ON co.condition_concept_id = g.concept_id
),

t2dm_meds AS (
    SELECT
        de.person_id,
        de.drug_exposure_start_date AS event_date
    FROM public.drug_exposure de
    JOIN t2dm_med_concepts m
      ON de.drug_concept_id = m.concept_id
),

insulin_meds AS (
    SELECT
        de.person_id,
        de.drug_exposure_start_date AS event_date
    FROM public.drug_exposure de
    JOIN insulin_concepts i
      ON de.drug_concept_id = i.concept_id
),

t2dm_labs AS (
    SELECT
        m.person_id,
        m.measurement_date AS event_date,
        m.value_as_number,
        m.unit_concept_id
    FROM public.measurement m
    JOIN t2dm_lab_concepts l
      ON m.measurement_concept_id = l.concept_id
),

qual_labs AS (
    SELECT DISTINCT person_id, event_date
    FROM t2dm_labs
    WHERE value_as_number IS NOT NULL
      AND (
            value_as_number >= 6.5   -- assume HbA1c %
         OR value_as_number >= 126   -- assume mg/dL glucose
      )
),

-- =========================
-- PERSON-LEVEL AGGREGATES
-- =========================

person_t2dm_dx AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS t2dm_dx_dates,
        MIN(event_date) AS first_t2dm_dx_date
    FROM t2dm_dx
    GROUP BY person_id
),

person_t1dm_dx AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS t1dm_dx_dates,
        MIN(event_date) AS first_t1dm_dx_date
    FROM t1dm_dx
    GROUP BY person_id
),

person_gest_secondary_dm AS (
    SELECT
        person_id,
        MIN(event_date) AS first_gest_secondary_date
    FROM gest_secondary_dm_dx
    GROUP BY person_id
),

person_t2dm_meds AS (
    SELECT
        person_id,
        COUNT(*) AS t2dm_med_count,
        MIN(event_date) AS first_t2dm_med_date
    FROM t2dm_meds
    GROUP BY person_id
),

person_insulin_meds AS (
    SELECT
        person_id,
        COUNT(*) AS insulin_med_count,
        MIN(event_date) AS first_insulin_date
    FROM insulin_meds
    GROUP BY person_id
),

person_qual_labs AS (
    SELECT
        person_id,
        COUNT(*) AS qual_lab_count,
        MIN(event_date) AS first_qual_lab_date
    FROM qual_labs
    GROUP BY person_id
),

-- =========================
-- CANDIDATE CASES + INDEX
-- =========================

candidate_cases AS (
    SELECT
        p.person_id,

        t2dx.t2dm_dx_dates,
        t2dx.first_t2dm_dx_date,
        t1dx.t1dm_dx_dates,
        t1dx.first_t1dm_dx_date,
        gsdm.first_gest_secondary_date,
        t2m.t2dm_med_count,
        t2m.first_t2dm_med_date,
        im.insulin_med_count,
        im.first_insulin_date,
        ql.qual_lab_count,
        ql.first_qual_lab_date,

        LEAST(
            COALESCE(t2dx.first_t2dm_dx_date, DATE '9999-12-31'),
            COALESCE(t2m.first_t2dm_med_date, DATE '9999-12-31'),
            COALESCE(ql.first_qual_lab_date, DATE '9999-12-31')
        ) AS index_date
    FROM public.person p
    LEFT JOIN person_t2dm_dx t2dx
        ON p.person_id = t2dx.person_id
    LEFT JOIN person_t1dm_dx t1dx
        ON p.person_id = t1dx.person_id
    LEFT JOIN person_gest_secondary_dm gsdm
        ON p.person_id = gsdm.person_id
    LEFT JOIN person_t2dm_meds t2m
        ON p.person_id = t2m.person_id
    LEFT JOIN person_insulin_meds im
        ON p.person_id = im.person_id
    LEFT JOIN person_qual_labs ql
        ON p.person_id = ql.person_id
),

candidate_with_age_obs AS (
    SELECT
        c.*,
        op.observation_period_start_date,
        op.observation_period_end_date,
        DATE_PART('year', c.index_date) - DATE_PART('year', p.birth_datetime)
          - CASE WHEN TO_CHAR(c.index_date, 'MMDD') < TO_CHAR(p.birth_datetime, 'MMDD') THEN 1 ELSE 0 END
          AS age_at_index
    FROM candidate_cases c
    JOIN public.person p
      ON c.person_id = p.person_id
    JOIN public.observation_period op
      ON c.person_id = op.person_id
     AND c.index_date BETWEEN op.observation_period_start_date AND op.observation_period_end_date
)

-- =========================
-- FINAL T2DM COHORT
-- =========================

SELECT
    person_id,
    index_date,
    age_at_index
FROM candidate_with_age_obs
WHERE
    index_date IS NOT NULL
    AND age_at_index >= 18

    AND (
            -- Path 1: >= 2 T2DM diagnosis dates
            (t2dm_dx_dates IS NOT NULL AND t2dm_dx_dates >= 2)

         OR -- Path 2: >= 1 T2DM diagnosis AND >= 1 T2DM med
            (t2dm_dx_dates IS NOT NULL AND t2dm_dx_dates >= 1
             AND t2dm_med_count IS NOT NULL AND t2dm_med_count >= 1)

         OR -- Path 3: >= 1 T2DM med AND >= 1 qualifying lab
            (t2dm_med_count IS NOT NULL AND t2dm_med_count >= 1
             AND qual_lab_count IS NOT NULL AND qual_lab_count >= 1)
        )

    AND NOT (
            -- Strong T1DM pattern
            t1dm_dx_dates IS NOT NULL AND t1dm_dx_dates >= 2
        AND (t2dm_dx_dates IS NULL OR t2dm_dx_dates = 0)
        AND (t2dm_med_count IS NULL OR t2dm_med_count = 0)
        AND insulin_med_count IS NOT NULL AND insulin_med_count >= 1
    )

    AND first_gest_secondary_date IS NULL;
