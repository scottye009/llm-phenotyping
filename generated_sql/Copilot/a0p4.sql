WITH

-- 1. Adult patients
adult_person AS (
    SELECT p.person_id
    FROM person p
),

-- 2. T2DM diagnosis concepts (ICD9/10 mapped to standard OMOP)
t2dm_dx AS (
    SELECT DISTINCT
        c.person_id,
        DATE(c.condition_start_date) AS dx_date
    FROM condition_occurrence c
    WHERE c.condition_concept_id IN (
        -- OMOP standard concepts for Type 2 diabetes mellitus
        -- (mapped from ICD-9 250.x0, 250.x2 and ICD-10 E11.*)
        -- e.g. 201826, 201820, ... (placeholder)
    )
),

-- 3. Type 1 / gestational / secondary diabetes (exclusions)
exclusion_dx AS (
    SELECT DISTINCT
        c.person_id
    FROM condition_occurrence c
    WHERE c.condition_concept_id IN (
        -- OMOP standard concepts for:
        -- Type 1 diabetes (E10.*, 250.x1, 250.x3)
        -- Gestational diabetes (O24.4x, 648.0x, 648.8x)
        -- Secondary diabetes (E08.*, E09.*, E13.*, 249.*)
    )
),

-- 4. Diabetes medications (drug_exposure)
dm_meds AS (
    SELECT DISTINCT
        d.person_id,
        DATE(d.drug_exposure_start_date) AS med_date
    FROM drug_exposure d
    WHERE d.drug_concept_id IN (
        -- OMOP standard RxNorm concepts for:
        -- metformin (Glucophage, Glumetza, Fortamet, Riomet),
        -- sulfonylureas (glipizide/Glucotrol, glyburide/DiaBeta/Micronase/Glynase, glimepiride/Amaryl, etc.),
        -- TZDs (pioglitazone/Actos, rosiglitazone/Avandia),
        -- DPP-4 inhibitors (sitagliptin/Januvia, saxagliptin/Onglyza, linagliptin/Tradjenta, alogliptin/Nesina),
        -- GLP-1 agonists (exenatide/Byetta/Bydureon, liraglutide/Victoza, dulaglutide/Trulicity, semaglutide/Ozempic/Rybelsus, etc.),
        -- SGLT2 inhibitors (canagliflozin/Invokana, dapagliflozin/Farxiga, empagliflozin/Jardiance, ertugliflozin/Steglatro),
        -- meglitinides (repaglinide/Prandin, nateglinide/Starlix),
        -- other T2DM agents (acarbose/Precose, miglitol/Glyset, colesevelam/Welchol, bromocriptine/Cycloset),
        -- insulin products (Lantus, Levemir, Tresiba, Humalog, Novolog, Humulin, Novolin, etc.)
    )
),

-- 5. Diabetes-related labs (HbA1c, fasting glucose)
dm_labs AS (
    SELECT
        m.person_id,
        DATE(m.measurement_date) AS lab_date,
        m.value_as_number,
        m.measurement_concept_id
    FROM measurement m
    WHERE m.measurement_concept_id IN (
        -- OMOP standard concepts for HbA1c and plasma glucose
        -- (e.g., HbA1c LOINC 4548-4, 17856-6, etc.; fasting glucose LOINC 1558-6, etc.)
    )
),

-- 6. Abnormal diabetes labs (meeting diagnostic thresholds)
abnormal_dm_labs AS (
    SELECT
        l.person_id,
        l.lab_date
    FROM dm_labs l
    WHERE
        (
            -- HbA1c >= 6.5%
            l.measurement_concept_id IN ( /* HbA1c concept_ids */ )
            AND l.value_as_number >= 6.5
        )
        OR
        (
            -- Fasting plasma glucose >= 126 mg/dL
            l.measurement_concept_id IN ( /* fasting glucose concept_ids */ )
            AND l.value_as_number >= 126
        )
),

-- 7. Aggregated counts per patient
dx_counts AS (
    SELECT
        person_id,
        COUNT(DISTINCT dx_date) AS dx_dates_count
    FROM t2dm_dx
    GROUP BY person_id
),

lab_counts AS (
    SELECT
        person_id,
        COUNT(DISTINCT lab_date) AS lab_dates_count
    FROM abnormal_dm_labs
    GROUP BY person_id
),

med_counts AS (
    SELECT
        person_id,
        COUNT(DISTINCT med_date) AS med_dates_count
    FROM dm_meds
    GROUP BY person_id
),

-- 8. Strong T2DM evidence (Boolean logic)
strong_t2dm_evidence AS (
    SELECT
        a.person_id
    FROM adult_person a
    LEFT JOIN dx_counts dx   ON a.person_id = dx.person_id
    LEFT JOIN lab_counts lb  ON a.person_id = lb.person_id
    LEFT JOIN med_counts md  ON a.person_id = md.person_id
    WHERE
        (
            -- DX_T2DM_2PLUS
            (dx.dx_dates_count >= 2)
        )
        OR
        (
            -- DX_T2DM_1PLUS AND MED_DM_1PLUS
            (dx.dx_dates_count >= 1 AND md.med_dates_count >= 1)
        )
        OR
        (
            -- DX_T2DM_1PLUS AND LAB_DM_1PLUS
            (dx.dx_dates_count >= 1 AND lb.lab_dates_count >= 1)
        )
        OR
        (
            -- LAB_DM_2PLUS AND MED_DM_1PLUS
            (lb.lab_dates_count >= 2 AND md.med_dates_count >= 1)
        )
),

-- 9. Final T2DM cases: strong evidence AND NOT exclusions
t2dm_cases AS (
    SELECT DISTINCT
        s.person_id
    FROM strong_t2dm_evidence s
    LEFT JOIN exclusion_dx e
        ON s.person_id = e.person_id
    WHERE
        e.person_id IS NULL  -- NOT (Type 1 / gestational / secondary diabetes)
)

SELECT
    c.person_id,
    'TYPE_2_DIABETES' AS phenotype_label
FROM t2dm_cases c;
