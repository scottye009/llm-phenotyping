/* ============================================================
   PHENOTYPING ALGORITHM: TYPE 2 DIABETES MELLITUS
   OMOP CDM v5.x
   ============================================================ */

-- ----------------------------------------------------------------
-- COMPONENT A: T2DM Diagnosis Codes
-- ICD9CM: 250.x0, 250.x2 (even 5th digit = T2DM)
-- ICD10CM: E11.x (Type 2 diabetes mellitus)
-- OMOP concept_id examples included as reference
-- ----------------------------------------------------------------
WITH dx_T2DM AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date AS event_date,
        co.condition_concept_id,
        co.condition_source_value
    FROM condition_occurrence co
    WHERE
        -- OMOP Standard Concept
        co.condition_concept_id IN (
            201826,   -- Type 2 diabetes mellitus
            443238,   -- Diabetes mellitus (non-T1, non-gestational)
            4193704,  -- T2DM without complications
            443729,   -- T2DM with complications
            40482801  -- Maturity onset diabetes
        )
        OR
        -- ICD9CM source codes (even 5th digit = Type 2)
        co.condition_source_value IN (
            '250.00','250.02','250.10','250.12',
            '250.20','250.22','250.30','250.32',
            '250.40','250.42','250.50','250.52',
            '250.60','250.62','250.70','250.72',
            '250.80','250.82','250.90','250.92'
        )
        OR
        -- ICD10CM source codes
        co.condition_source_value LIKE 'E11%'   -- E11.0 through E11.9
),

-- ----------------------------------------------------------------
-- COMPONENT B: Antidiabetic Medications (NON-Insulin)
-- Includes generic and brand names
-- ----------------------------------------------------------------
rx_antidiabetic AS (
    SELECT DISTINCT
        de.person_id,
        de.drug_exposure_start_date AS event_date,
        de.drug_concept_id,
        de.drug_source_value
    FROM drug_exposure de
    WHERE de.drug_concept_id IN (

        -- BIGUANIDES
        -- Metformin (generic) / Glucophage, Glumetza, Fortamet, Riomet (brand)
        1503297, 1503298, 40166035,

        -- SULFONYLUREAS
        -- Glipizide / Glucotrol | Glyburide / Diabeta, Micronase, Glynase
        -- Glimepiride / Amaryl
        1597756, 1502826, 1502855,

        -- DPP-4 INHIBITORS
        -- Sitagliptin / Januvia | Saxagliptin / Onglyza
        -- Alogliptin / Nesina | Linagliptin / Tradjenta
        40166035, 1580747, 1583722, 45774751,

        -- SGLT-2 INHIBITORS
        -- Canagliflozin / Invokana | Dapagliflozin / Farxiga
        -- Empagliflozin / Jardiance | Ertugliflozin / Steglatro
        44816332, 44785829, 45774751, 792484,

        -- GLP-1 RECEPTOR AGONISTS
        -- Semaglutide / Ozempic, Rybelsus | Liraglutide / Victoza
        -- Dulaglutide / Trulicity | Exenatide / Byetta, Bydureon
        -- Tirzepatide / Mounjaro
        40239216, 1580747, 1583722, 45774751, 792484,

        -- THIAZOLIDINEDIONES (TZDs)
        -- Pioglitazone / Actos | Rosiglitazone / Avandia
        1525215, 1516976,

        -- MEGLITINIDES
        -- Repaglinide / Prandin | Nateglinide / Starlix
        1502809, 1502905,

        -- ALPHA-GLUCOSIDASE INHIBITORS
        -- Acarbose / Precose | Miglitol / Glyset
        1503297, 1510202
    )
    AND de.drug_concept_id NOT IN (
        -- Exclude pure insulin products (may indicate T1DM)
        1516976, 19122137, 19029532  -- long/short/rapid-acting insulins
    )
),

-- ----------------------------------------------------------------
-- COMPONENT C: Abnormal Laboratory Values
-- ----------------------------------------------------------------
lab_abnormal AS (
    SELECT DISTINCT
        m.person_id,
        m.measurement_date AS event_date,
        m.measurement_concept_id,
        m.value_as_number
    FROM measurement m
    WHERE
        (
            -- HbA1c >= 6.5%
            -- OMOP concept: LOINC 4548-4 / 17856-6
            m.measurement_concept_id IN (3004410, 3005673, 40762352)
            AND m.value_as_number >= 6.5
        )
        OR
        (
            -- Fasting Plasma Glucose >= 126 mg/dL
            -- OMOP concept: LOINC 1558-6 / 2339-0
            m.measurement_concept_id IN (3037110, 3000483, 3034639)
            AND m.value_as_number >= 126
        )
        OR
        (
            -- Random Plasma Glucose >= 200 mg/dL
            -- OMOP concept: LOINC 2345-7
            m.measurement_concept_id IN (3004501, 3000845, 3034639)
            AND m.value_as_number >= 200
        )
        OR
        (
            -- 2-hr OGTT Glucose >= 200 mg/dL
            -- OMOP concept: LOINC 20436-2
            m.measurement_concept_id IN (3034639, 3007332)
            AND m.value_as_number >= 200
        )
),

-- ----------------------------------------------------------------
-- COMPONENT D: EXCLUSION — Type 1 DM
-- ICD9CM: 250.x1, 250.x3 (odd 5th digit = T1DM)
-- ICD10CM: E10.x
-- ----------------------------------------------------------------
excl_T1DM AS (
    SELECT DISTINCT co.person_id
    FROM condition_occurrence co
    WHERE
        co.condition_concept_id IN (
            201254,   -- Type 1 diabetes mellitus
            4058243   -- T1DM with complications
        )
        OR co.condition_source_value IN (
            '250.01','250.03','250.11','250.13',
            '250.21','250.23','250.31','250.33',
            '250.41','250.43','250.51','250.53',
            '250.61','250.63','250.71','250.73',
            '250.81','250.83','250.91','250.93'
        )
        OR co.condition_source_value LIKE 'E10%'
),

-- ----------------------------------------------------------------
-- COMPONENT E: EXCLUSION — Gestational Diabetes
-- ICD9CM: 648.0x | ICD10CM: O24.4x
-- ----------------------------------------------------------------
excl_gestational AS (
    SELECT DISTINCT co.person_id
    FROM condition_occurrence co
    WHERE
        co.condition_concept_id IN (4024659, 40487583)
        OR co.condition_source_value IN ('648.00','648.01','648.02','648.03','648.04')
        OR co.condition_source_value LIKE 'O24.4%'
),

-- ----------------------------------------------------------------
-- COMPONENT F: EXCLUSION — Secondary Diabetes
-- (Drug-induced, post-pancreatectomy, Cushing's-related, etc.)
-- ICD9CM: 249.xx | ICD10CM: E08.x, E09.x, E13.x
-- ----------------------------------------------------------------
excl_secondary AS (
    SELECT DISTINCT co.person_id
    FROM condition_occurrence co
    WHERE
        co.condition_source_value LIKE '249%'
        OR co.condition_source_value LIKE 'E08%'
        OR co.condition_source_value LIKE 'E09%'
        OR co.condition_source_value LIKE 'E13%'
),

-- ----------------------------------------------------------------
-- CANDIDATE PATIENTS: Must meet >= 1 inclusion rule
-- Rule 1: >= 2 T2DM diagnoses on SEPARATE dates
-- Rule 2: >= 1 T2DM diagnosis AND >= 1 antidiabetic medication
-- Rule 3: >= 1 T2DM diagnosis AND >= 1 abnormal lab value
-- ----------------------------------------------------------------
candidates AS (

    -- Rule 1: >= 2 T2DM Dx on separate dates
    SELECT person_id FROM dx_T2DM
    GROUP BY person_id
    HAVING COUNT(DISTINCT event_date) >= 2

    UNION

    -- Rule 2: >= 1 T2DM Dx AND >= 1 antidiabetic Rx
    SELECT dx.person_id
    FROM dx_T2DM dx
    INNER JOIN rx_antidiabetic rx
        ON dx.person_id = rx.person_id

    UNION

    -- Rule 3: >= 1 T2DM Dx AND >= 1 abnormal lab
    SELECT dx.person_id
    FROM dx_T2DM dx
    INNER JOIN lab_abnormal lab
        ON dx.person_id = lab.person_id
),

-- ----------------------------------------------------------------
-- FINAL COHORT: Candidates MINUS exclusions
-- ----------------------------------------------------------------
final_cohort AS (
    SELECT DISTINCT c.person_id
    FROM candidates c
    WHERE c.person_id NOT IN (SELECT person_id FROM excl_T1DM)
      AND c.person_id NOT IN (SELECT person_id FROM excl_gestational)
      AND c.person_id NOT IN (SELECT person_id FROM excl_secondary)
)

-- ================================================================
-- OUTPUT: Final T2DM Phenotype Cohort
-- ================================================================
SELECT
    p.person_id,
    p.year_of_birth,
    p.gender_concept_id,
    p.race_concept_id
FROM person p
INNER JOIN final_cohort fc
    ON p.person_id = fc.person_id
ORDER BY p.person_id;