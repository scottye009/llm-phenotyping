-- ============================================
-- TYPE 2 DIABETES PHENOTYPE (OMOP CDM, public)
-- ============================================

WITH

-- -------------------------
-- 1. Concept sets (diagnoses)
-- -------------------------

t2dm_dx AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date
    FROM public.condition_occurrence co
    JOIN public.concept c
        ON co.condition_concept_id = c.concept_id
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (
            -- ICD9CM: 250.x0 or 250.x2
            (c.vocabulary_id = 'ICD9CM'
             AND c.concept_code LIKE '250.%'
             AND RIGHT(c.concept_code, 1) IN ('0', '2'))
         OR
            -- ICD10CM: E11%
            (c.vocabulary_id = 'ICD10CM'
             AND c.concept_code LIKE 'E11%')
      )
),

t1dm_dx AS (
    SELECT DISTINCT
        co.person_id
    FROM public.condition_occurrence co
    JOIN public.concept c
        ON co.condition_concept_id = c.concept_id
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (
            -- ICD9CM: 250.x1 or 250.x3
            (c.vocabulary_id = 'ICD9CM'
             AND c.concept_code LIKE '250.%'
             AND RIGHT(c.concept_code, 1) IN ('1', '3'))
         OR
            -- ICD10CM: E10%
            (c.vocabulary_id = 'ICD10CM'
             AND c.concept_code LIKE 'E10%')
      )
),

gest_dm_dx AS (
    SELECT DISTINCT
        co.person_id
    FROM public.condition_occurrence co
    JOIN public.concept c
        ON co.condition_concept_id = c.concept_id
    WHERE c.vocabulary_id = 'ICD10CM'
      AND c.concept_code LIKE 'O24.4%'
),

secondary_dm_dx AS (
    SELECT DISTINCT
        co.person_id
    FROM public.condition_occurrence co
    JOIN public.concept c
        ON co.condition_concept_id = c.concept_id
    WHERE c.vocabulary_id = 'ICD10CM'
      AND (
            c.concept_code LIKE 'E08%'
         OR c.concept_code LIKE 'E09%'
         OR c.concept_code LIKE 'E13%'
      )
),

-- -------------------------
-- 2. Concept sets (medications)
--    Use ingredient/brand names via concept_name or concept_ancestor
-- -------------------------

t2dm_meds AS (
    SELECT DISTINCT
        de.person_id,
        de.drug_exposure_start_date
    FROM public.drug_exposure de
    JOIN public.concept c
        ON de.drug_concept_id = c.concept_id
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
         OR c.concept_name ILIKE '%Micronase%'
         OR c.concept_name ILIKE '%glimepiride%'
         OR c.concept_name ILIKE '%Amaryl%'
            -- DPP-4 inhibitors
         OR c.concept_name ILIKE '%sitagliptin%'
         OR c.concept_name ILIKE '%Januvia%'
         OR c.concept_name ILIKE '%saxagliptin%'
         OR c.concept_name ILIKE '%Onglyza%'
         OR c.concept_name ILIKE '%linagliptin%'
         OR c.concept_name ILIKE '%Tradjenta%'
         OR c.concept_name ILIKE '%alogliptin%'
         OR c.concept_name ILIKE '%Nesina%'
            -- GLP-1 receptor agonists
         OR c.concept_name ILIKE '%exenatide%'
         OR c.concept_name ILIKE '%Byetta%'
         OR c.concept_name ILIKE '%Bydureon%'
         OR c.concept_name ILIKE '%liraglutide%'
         OR c.concept_name ILIKE '%Victoza%'
         OR c.concept_name ILIKE '%dulaglutide%'
         OR c.concept_name ILIKE '%Trulicity%'
         OR c.concept_name ILIKE '%semaglutide%'
         OR c.concept_name ILIKE '%Ozempic%'
         OR c.concept_name ILIKE '%Rybelsus%'
            -- SGLT2 inhibitors
         OR c.concept_name ILIKE '%canagliflozin%'
         OR c.concept_name ILIKE '%Invokana%'
         OR c.concept_name ILIKE '%dapagliflozin%'
         OR c.concept_name ILIKE '%Farxiga%'
         OR c.concept_name ILIKE '%empagliflozin%'
         OR c.concept_name ILIKE '%Jardiance%'
         OR c.concept_name ILIKE '%ertugliflozin%'
         OR c.concept_name ILIKE '%Steglatro%'
            -- Thiazolidinediones
         OR c.concept_name ILIKE '%pioglitazone%'
         OR c.concept_name ILIKE '%Actos%'
         OR c.concept_name ILIKE '%rosiglitazone%'
         OR c.concept_name ILIKE '%Avandia%'
      )
),

-- Optional: insulin exposures (used only when combined with T2DM dx)
insulin_meds AS (
    SELECT DISTINCT
        de.person_id,
        de.drug_exposure_start_date
    FROM public.drug_exposure de
    JOIN public.concept c
        ON de.drug_concept_id = c.concept_id
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

-- -------------------------
-- 3. Concept sets (labs)
-- -------------------------

t2dm_labs AS (
    SELECT DISTINCT
        m.person_id,
        m.measurement_date,
        m.value_as_number
    FROM public.measurement m
    JOIN public.concept c
        ON m.measurement_concept_id = c.concept_id
    WHERE
        (
            -- HbA1c >= 6.5%
            c.concept_name ILIKE '%hemoglobin A1c%'
            AND m.value_as_number >= 6.5
        )
        OR
        (
            -- Fasting plasma glucose >= 126 mg/dL
            c.concept_name ILIKE '%fasting glucose%'
            AND m.value_as_number >= 126
        )
        OR
        (
            -- Random plasma glucose >= 200 mg/dL
            c.concept_name ILIKE '%glucose%'
            AND m.value_as_number >= 200
        )
),

-- -------------------------
-- 4. Aggregate logic per person
-- -------------------------

t2dm_dx_agg AS (
    SELECT
        person_id,
        COUNT(DISTINCT condition_start_date) AS dx_dates
    FROM t2dm_dx
    GROUP BY person_id
),

t2dm_med_flag AS (
    SELECT DISTINCT person_id
    FROM t2dm_meds
),

insulin_med_flag AS (
    SELECT DISTINCT person_id
    FROM insulin_meds
),

t2dm_lab_flag AS (
    SELECT DISTINCT person_id
    FROM t2dm_labs
),

-- -------------------------
-- 5. Final cohort: apply AND / OR / NOT logic
-- -------------------------

eligible_persons AS (
    SELECT
        p.person_id,
        p.year_of_birth,
        MIN(op.observation_period_start_date) AS first_obs_date
    FROM public.person p
    JOIN public.observation_period op
        ON p.person_id = op.person_id
    GROUP BY p.person_id, p.year_of_birth
),

t2dm_cohort AS (
    SELECT DISTINCT
        e.person_id
    FROM eligible_persons e

    LEFT JOIN t2dm_dx_agg dx
        ON e.person_id = dx.person_id
    LEFT JOIN t2dm_med_flag med
        ON e.person_id = med.person_id
    LEFT JOIN insulin_med_flag ins
        ON e.person_id = ins.person_id
    LEFT JOIN t2dm_lab_flag lab
        ON e.person_id = lab.person_id
    LEFT JOIN t1dm_dx t1
        ON e.person_id = t1.person_id
    LEFT JOIN gest_dm_dx gdm
        ON e.person_id = gdm.person_id
    LEFT JOIN secondary_dm_dx sdm
        ON e.person_id = sdm.person_id

    WHERE
        -- Age >= 18 at first observation (approximate)
        (EXTRACT(YEAR FROM first_obs_date) - e.year_of_birth) >= 18

        AND
        (
            -- T2DM_DX: >= 2 T2DM dx dates
            (dx.dx_dates >= 2)

            OR

            -- 1 T2DM dx + T2DM medication
            ((dx.dx_dates >= 1) AND (med.person_id IS NOT NULL))

            OR

            -- T2DM_MED AND T2DM_LAB
            ((med.person_id IS NOT NULL) AND (lab.person_id IS NOT NULL))

            OR

            -- Insulin + T2DM dx (optional)
            ((ins.person_id IS NOT NULL) AND (dx.dx_dates >= 1))
        )

        -- EXCLUSIONS
        AND t1.person_id IS NULL      -- NOT Type 1 diabetes
        AND gdm.person_id IS NULL     -- NOT gestational diabetes
        AND sdm.person_id IS NULL     -- NOT secondary diabetes
)

SELECT *
FROM t2dm_cohort;
