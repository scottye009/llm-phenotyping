-- ============================================
-- 1. CONCEPT SETS
-- ============================================

-- Type 2 diabetes diagnosis concepts (ICD9CM 250.x0/250.x2, ICD10CM E11.*)
WITH t2dm_dx_concepts AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (
            (c.vocabulary_id = 'ICD9CM'
             AND c.concept_code LIKE '250.%'
             AND RIGHT(c.concept_code, 1) IN ('0','2'))  -- 250.x0, 250.x2
         OR (c.vocabulary_id = 'ICD10CM'
             AND c.concept_code LIKE 'E11%')
      )
),

-- Type 1 diabetes diagnosis concepts
t1dm_dx_concepts AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (
            (c.vocabulary_id = 'ICD9CM'
             AND c.concept_code LIKE '250.%'
             AND RIGHT(c.concept_code, 1) IN ('1','3'))  -- 250.x1, 250.x3
         OR (c.vocabulary_id = 'ICD10CM'
             AND c.concept_code LIKE 'E10%')
      )
),

-- Gestational diabetes diagnosis concepts
gestational_dm_dx_concepts AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (
            (c.vocabulary_id = 'ICD9CM'
             AND c.concept_code LIKE '648.8%')
         OR (c.vocabulary_id = 'ICD10CM'
             AND c.concept_code LIKE 'O24.4%')
      )
),

-- Secondary diabetes diagnosis concepts
secondary_dm_dx_concepts AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (
            (c.vocabulary_id = 'ICD9CM'
             AND c.concept_code LIKE '249.%')
         OR (c.vocabulary_id = 'ICD10CM'
             AND (c.concept_code LIKE 'E08%' 
                  OR c.concept_code LIKE 'E09%' 
                  OR c.concept_code LIKE 'E13%'))
      )
),

-- Diabetes medication concepts (RxNorm) - oral and injectable
-- Here we use concept_name patterns for illustration; in practice, use curated concept sets.
diabetes_med_concepts AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id = 'RxNorm'
      AND (
            -- Biguanides
            LOWER(c.concept_name) LIKE '%metformin%'
         OR LOWER(c.concept_name) LIKE '%glucophage%'
         OR LOWER(c.concept_name) LIKE '%glumetza%'
         OR LOWER(c.concept_name) LIKE '%fortamet%'
         OR LOWER(c.concept_name) LIKE '%riomet%'

            -- Sulfonylureas
         OR LOWER(c.concept_name) LIKE '%glipizide%'
         OR LOWER(c.concept_name) LIKE '%glucotrol%'
         OR LOWER(c.concept_name) LIKE '%glyburide%'
         OR LOWER(c.concept_name) LIKE '%diabeta%'
         OR LOWER(c.concept_name) LIKE '%micronase%'
         OR LOWER(c.concept_name) LIKE '%glynase%'
         OR LOWER(c.concept_name) LIKE '%glimepiride%'
         OR LOWER(c.concept_name) LIKE '%amaryl%'

            -- Thiazolidinediones
         OR LOWER(c.concept_name) LIKE '%pioglitazone%'
         OR LOWER(c.concept_name) LIKE '%actos%'
         OR LOWER(c.concept_name) LIKE '%rosiglitazone%'
         OR LOWER(c.concept_name) LIKE '%avandia%'

            -- DPP-4 inhibitors
         OR LOWER(c.concept_name) LIKE '%sitagliptin%'
         OR LOWER(c.concept_name) LIKE '%januvia%'
         OR LOWER(c.concept_name) LIKE '%saxagliptin%'
         OR LOWER(c.concept_name) LIKE '%onglyza%'
         OR LOWER(c.concept_name) LIKE '%linagliptin%'
         OR LOWER(c.concept_name) LIKE '%tradjenta%'

            -- GLP-1 agonists
         OR LOWER(c.concept_name) LIKE '%exenatide%'
         OR LOWER(c.concept_name) LIKE '%byetta%'
         OR LOWER(c.concept_name) LIKE '%bydureon%'
         OR LOWER(c.concept_name) LIKE '%liraglutide%'
         OR LOWER(c.concept_name) LIKE '%victoza%'
         OR LOWER(c.concept_name) LIKE '%dulaglutide%'
         OR LOWER(c.concept_name) LIKE '%trulicity%'
         OR LOWER(c.concept_name) LIKE '%semaglutide%'
         OR LOWER(c.concept_name) LIKE '%ozempic%'
         OR LOWER(c.concept_name) LIKE '%rybelsus%'

            -- SGLT2 inhibitors
         OR LOWER(c.concept_name) LIKE '%canagliflozin%'
         OR LOWER(c.concept_name) LIKE '%invokana%'
         OR LOWER(c.concept_name) LIKE '%dapagliflozin%'
         OR LOWER(c.concept_name) LIKE '%farxiga%'
         OR LOWER(c.concept_name) LIKE '%empagliflozin%'
         OR LOWER(c.concept_name) LIKE '%jardiance%'

            -- Insulins (optional: you may separate insulin-only users)
         OR LOWER(c.concept_name) LIKE '%insulin%'
         OR LOWER(c.concept_name) LIKE '%lantus%'
         OR LOWER(c.concept_name) LIKE '%levemir%'
         OR LOWER(c.concept_name) LIKE '%tresiba%'
         OR LOWER(c.concept_name) LIKE '%humalog%'
         OR LOWER(c.concept_name) LIKE '%novolog%'
      )
),

-- HbA1c measurement concepts (LOINC)
hba1c_concepts AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id = 'LOINC'
      AND c.concept_code IN ('4548-4','17856-6','41995-2')  -- example set
),

-- Glucose measurement concepts (LOINC) - fasting, random, OGTT
glucose_concepts AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id = 'LOINC'
      AND c.concept_code IN (
            '1558-6',   -- Glucose [Moles/volume] in Serum or Plasma
            '2345-7',   -- Glucose [Mass/volume] in Serum or Plasma
            '14771-0',  -- Glucose [Mass/volume] in Serum or Plasma -- fasting
            '20436-2'   -- Glucose [Mass/volume] in Serum or Plasma -- 2h post 75g glucose
      )
),

-- ============================================
-- 2. SIGNALS: DIAGNOSES, MEDS, LABS
-- ============================================

t2dm_dx AS (
    SELECT
        co.person_id,
        co.condition_start_date AS dx_date
    FROM public.condition_occurrence co
    JOIN t2dm_dx_concepts t2 ON co.condition_concept_id = t2.concept_id
),

t1dm_dx AS (
    SELECT
        co.person_id,
        co.condition_start_date AS dx_date
    FROM public.condition_occurrence co
    JOIN t1dm_dx_concepts t1 ON co.condition_concept_id = t1.concept_id
),

gestational_dm_dx AS (
    SELECT
        co.person_id,
        co.condition_start_date AS dx_date
    FROM public.condition_occurrence co
    JOIN gestational_dm_dx_concepts g ON co.condition_concept_id = g.concept_id
),

secondary_dm_dx AS (
    SELECT
        co.person_id,
        co.condition_start_date AS dx_date
    FROM public.condition_occurrence co
    JOIN secondary_dm_dx_concepts s ON co.condition_concept_id = s.concept_id
),

diabetes_meds AS (
    SELECT
        de.person_id,
        de.drug_exposure_start_date AS med_date
    FROM public.drug_exposure de
    JOIN diabetes_med_concepts dmc ON de.drug_concept_id = dmc.concept_id
),

hba1c_abnormal AS (
    SELECT
        m.person_id,
        m.measurement_date AS lab_date
    FROM public.measurement m
    JOIN hba1c_concepts h ON m.measurement_concept_id = h.concept_id
    WHERE m.value_as_number >= 6.5
),

glucose_abnormal AS (
    SELECT
        m.person_id,
        m.measurement_date AS lab_date
    FROM public.measurement m
    JOIN glucose_concepts g ON m.measurement_concept_id = g.concept_id
    WHERE m.value_as_number >= 126  -- fasting threshold; you may refine by measurement_type or additional metadata
),

abnormal_labs AS (
    SELECT person_id, lab_date
    FROM hba1c_abnormal
    UNION ALL
    SELECT person_id, lab_date
    FROM glucose_abnormal
),

-- ============================================
-- 3. BUILD LOGIC COMPONENTS
-- ============================================

-- A. ≥2 T2DM diagnoses on distinct dates
t2dm_dx_multi AS (
    SELECT person_id,
           MIN(dx_date) AS first_t2dm_dx_date
    FROM (
        SELECT DISTINCT person_id, dx_date
        FROM t2dm_dx
    ) d
    GROUP BY person_id
    HAVING COUNT(*) >= 2
),

-- B. ≥1 T2DM diagnosis AND ≥1 diabetes medication
t2dm_dx_plus_med AS (
    SELECT DISTINCT d.person_id,
           MIN(d.dx_date) AS first_t2dm_dx_date
    FROM t2dm_dx d
    JOIN diabetes_meds m
      ON d.person_id = m.person_id
    GROUP BY d.person_id
),

-- C. ≥2 abnormal labs on distinct dates AND (≥1 T2DM diagnosis OR ≥1 diabetes medication)
abnormal_labs_multi AS (
    SELECT person_id,
           MIN(lab_date) AS first_abnormal_lab_date
    FROM (
        SELECT DISTINCT person_id, lab_date
        FROM abnormal_labs
    ) l
    GROUP BY person_id
    HAVING COUNT(*) >= 2
),

labs_plus_dx_or_med AS (
    SELECT DISTINCT l.person_id,
           l.first_abnormal_lab_date AS index_date
    FROM abnormal_labs_multi l
    LEFT JOIN t2dm_dx d
      ON l.person_id = d.person_id
    LEFT JOIN diabetes_meds m
      ON l.person_id = m.person_id
    WHERE d.person_id IS NOT NULL
       OR m.person_id IS NOT NULL
),

-- UNION of inclusion signals
t2dm_inclusion_raw AS (
    SELECT person_id, first_t2dm_dx_date AS index_date, 'DX_MULTI' AS source
    FROM t2dm_dx_multi

    UNION

    SELECT person_id, first_t2dm_dx_date AS index_date, 'DX_PLUS_MED' AS source
    FROM t2dm_dx_plus_med

    UNION

    SELECT person_id, index_date, 'LABS_PLUS_DX_OR_MED' AS source
    FROM labs_plus_dx_or_med
),

-- D. Exclusion patterns
any_t1dm AS (
    SELECT DISTINCT person_id
    FROM t1dm_dx
),

any_gestational_dm AS (
    SELECT DISTINCT person_id
    FROM gestational_dm_dx
),

any_secondary_dm AS (
    SELECT DISTINCT person_id
    FROM secondary_dm_dx
),

-- ============================================
-- 4. AGE FILTER (≥18 at index date)
-- ============================================

t2dm_inclusion_with_age AS (
    SELECT
        i.person_id,
        i.index_date,
        i.source,
        p.year_of_birth,
        (EXTRACT(YEAR FROM i.index_date) - p.year_of_birth) AS age_at_index
    FROM t2dm_inclusion_raw i
    JOIN public.person p
      ON i.person_id = p.person_id
    WHERE (EXTRACT(YEAR FROM i.index_date) - p.year_of_birth) >= 18
),

-- ============================================
-- 5. APPLY EXCLUSIONS
-- ============================================

t2dm_final AS (
    SELECT DISTINCT i.person_id,
           i.index_date,
           i.source
    FROM t2dm_inclusion_with_age i
    LEFT JOIN any_gestational_dm g
      ON i.person_id = g.person_id
    LEFT JOIN any_secondary_dm s
      ON i.person_id = s.person_id
    LEFT JOIN any_t1dm t1
      ON i.person_id = t1.person_id
    WHERE g.person_id IS NULL   -- NOT gestational
      AND s.person_id IS NULL   -- NOT secondary

      -- Type 1 handling:
      -- Here we allow patients with any T2DM signal even if they also have T1DM codes.
      -- If you want to exclude those with ONLY T1DM and no T2DM, this is already handled
      -- because inclusion requires T2DM signals.
)

-- ============================================
-- 6. FINAL COHORT OUTPUT
-- ============================================

SELECT
    f.person_id,
    f.index_date,
    f.source AS inclusion_rule
FROM t2dm_final f;
