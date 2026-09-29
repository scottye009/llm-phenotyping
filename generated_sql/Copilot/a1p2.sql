
-- ============================================
-- TYPE 2 DIABETES PHENOTYPE (OMOP CDM, PUBLIC)
-- ============================================

-- 1. CONCEPT SETS
WITH

-- T2DM diagnosis concepts (ICD9CM + ICD10CM)
t2dm_dx_concepts AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Condition'
      AND c.standard_concept = 'S'
      AND (
            (c.vocabulary_id = 'ICD9CM'  AND c.concept_code LIKE '250.%'
                 AND SUBSTRING(c.concept_code FROM 6 FOR 1) IN ('0','2')) -- 250.x0, 250.x2
         OR (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E11%')
      )
),

-- Type 1 diabetes diagnosis concepts (for exclusion)
t1dm_dx_concepts AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Condition'
      AND c.standard_concept = 'S'
      AND (
            (c.vocabulary_id = 'ICD9CM'  AND c.concept_code LIKE '250.%'
                 AND SUBSTRING(c.concept_code FROM 6 FOR 1) IN ('1','3')) -- 250.x1, 250.x3
         OR (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E10%')
      )
),

-- Gestational / secondary diabetes concepts (for exclusion)
gest_dm_dx_concepts AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Condition'
      AND c.standard_concept = 'S'
      AND (
            (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'O24%')
         OR (c.vocabulary_id = 'IC10CM' AND c.concept_code = 'P70.2')
         OR (c.vocabulary_id = 'ICD9CM'  AND (
                 c.concept_code LIKE '648.8%' OR c.concept_code IN ('775.1')
             ))
      )
),

-- Diabetes medications (RxNorm; generic + brand)
dm_med_concepts AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Drug'
      AND c.vocabulary_id = 'RxNorm'
      AND (
            -- Biguanides
            c.concept_name ILIKE '%metformin%'
         OR c.concept_name ILIKE '%Glucophage%'
         OR c.concept_name ILIKE '%Glumetza%'
         OR c.concept_name ILIKE '%Fortamet%'
         OR c.concept_name ILIKE '%Riomet%'

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

            -- GLP-1 agonists
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

            -- Insulins (keep broad; you can refine)
         OR c.concept_name ILIKE '%insulin%'
      )
),

-- Diabetes lab concepts (HbA1c, fasting glucose, random glucose)
dm_lab_concepts AS (
    SELECT c.concept_id, c.concept_code
    FROM public.concept c
    WHERE c.domain_id = 'Measurement'
      AND c.vocabulary_id = 'LOINC'
      AND c.concept_code IN (
          -- HbA1c
          '4548-4','17856-6','41995-2','59261-8',
          -- Fasting plasma glucose
          '1558-6','1557-8',
          -- Random plasma glucose
          '2345-7'
      )
),

-- 2. PATIENT-LEVEL EVIDENCE

-- T2DM diagnosis events
t2dm_dx AS (
    SELECT
        co.person_id,
        co.condition_start_date::date AS dx_date
    FROM public.condition_occurrence co
    JOIN t2dm_dx_concepts c
      ON co.condition_concept_id = c.concept_id
),

-- Type 1 diagnosis events
t1dm_dx AS (
    SELECT DISTINCT
        co.person_id
    FROM public.condition_occurrence co
    JOIN t1dm_dx_concepts c
      ON co.condition_concept_id = c.concept_id
),

-- Gestational / secondary diabetes diagnosis events
gest_dm_dx AS (
    SELECT DISTINCT
        co.person_id
    FROM public.condition_occurrence co
    JOIN gest_dm_dx_concepts c
      ON co.condition_concept_id = c.concept_id
),

-- Diabetes medication exposure
dm_meds AS (
    SELECT DISTINCT
        de.person_id,
        de.drug_exposure_start_date::date AS med_date
    FROM public.drug_exposure de
    JOIN dm_med_concepts c
      ON de.drug_concept_id = c.concept_id
),

-- Abnormal diabetes labs
dm_labs_abnormal AS (
    SELECT
        m.person_id,
        m.measurement_date::date AS lab_date,
        c.concept_code,
        m.value_as_number
    FROM public.measurement m
    JOIN dm_lab_concepts c
      ON m.measurement_concept_id = c.concept_id
    WHERE
        (
            -- HbA1c >= 6.5%
            c.concept_code IN ('4548-4','17856-6','41995-2','59261-8')
            AND m.value_as_number >= 6.5
        )
        OR
        (
            -- Fasting plasma glucose >= 126 mg/dL
            c.concept_code IN ('1558-6','1557-8')
            AND m.value_as_number >= 126
        )
        OR
        (
            -- Random plasma glucose >= 200 mg/dL
            c.concept_code IN ('2345-7')
            AND m.value_as_number >= 200
        )
),

-- Aggregate evidence per patient
patient_evidence AS (
    SELECT
        p.person_id,

        -- Diagnosis evidence
        COUNT(DISTINCT t2.dx_date) AS n_t2dm_dx_dates,

        -- Medication evidence
        CASE WHEN COUNT(DISTINCT dm.med_date) > 0 THEN 1 ELSE 0 END AS has_dm_med,

        -- Lab evidence
        COUNT(DISTINCT dl.lab_date) AS n_abnormal_dm_labs,

        -- Exclusion flags
        CASE WHEN EXISTS (SELECT 1 FROM t1dm_dx t1 WHERE t1.person_id = p.person_id) THEN 1 ELSE 0 END AS has_type1_dx,
        CASE WHEN EXISTS (SELECT 1 FROM gest_dm_dx g  WHERE g.person_id  = p.person_id) THEN 1 ELSE 0 END AS has_gest_dm_dx
    FROM public.person p
    LEFT JOIN t2dm_dx t2
      ON p.person_id = t2.person_id
    LEFT JOIN dm_meds dm
      ON p.person_id = dm.person_id
    LEFT JOIN dm_labs_abnormal dl
      ON p.person_id = dl.person_id
    GROUP BY p.person_id
),

-- 3. APPLY LOGIC (AND / OR / NOT)

phenotype_logic AS (
    SELECT
        pe.*,

        -- DX_T2DM: (>=2 T2DM dx dates) OR (>=1 T2DM dx date AND has DM med)
        CASE
            WHEN pe.n_t2dm_dx_dates >= 2 THEN 1
            WHEN pe.n_t2dm_dx_dates >= 1 AND pe.has_dm_med = 1 THEN 1
            ELSE 0
        END AS dx_t2dm_flag,

        -- DM_LAB: >=2 abnormal labs
        CASE
            WHEN pe.n_abnormal_dm_labs >= 2 THEN 1
            ELSE 0
        END AS dm_lab_flag,

        -- INCLUDE_T2DM: DX_T2DM OR (DM_LAB AND has DM med)
        CASE
            WHEN
                ( (pe.n_t2dm_dx_dates >= 2)
                  OR (pe.n_t2dm_dx_dates >= 1 AND pe.has_dm_med = 1)
                )
                OR
                (pe.n_abnormal_dm_labs >= 2 AND pe.has_dm_med = 1)
            THEN 1
            ELSE 0
        END AS include_t2dm_flag,

        -- EXCLUDE_NON_T2DM: (type1 OR gestational) AND NO T2DM dx
        CASE
            WHEN ( (pe.has_type1_dx = 1 OR pe.has_gest_dm_dx = 1)
                   AND pe.n_t2dm_dx_dates = 0 )
            THEN 1
            ELSE 0
        END AS exclude_non_t2dm_flag
    FROM patient_evidence pe
),

final_t2dm_cohort AS (
    SELECT
        person_id
    FROM phenotype_logic
    WHERE
        include_t2dm_flag = 1
        AND exclude_non_t2dm_flag = 0
)

-- 4. FINAL OUTPUT
SELECT *
FROM final_t2dm_cohort;
