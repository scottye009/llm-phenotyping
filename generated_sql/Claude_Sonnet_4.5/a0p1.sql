/* ============================================================
   PHENOTYPING ALGORITHM: TYPE 2 DIABETES MELLITUS
   OMOP CDM v5.x
   ============================================================ */

/* -----------------------------------------------------------
   BLOCK A: T2DM DIAGNOSIS CODES
   OMOP Domain: condition_occurrence
   Vocabulary:  ICD9CM | ICD10CM → SNOMED via concept_ancestor
   ----------------------------------------------------------- */

-- ICD-9-CM Codes (T2DM)
-- 250.00  Diabetes mellitus without mention of complication, type II
-- 250.02  Diabetes mellitus without mention of complication, type II, uncontrolled
-- 250.10  Diabetes with ketoacidosis, type II
-- 250.20  Diabetes with hyperosmolarity, type II
-- 250.40  Diabetes with renal manifestations, type II
-- 250.50  Diabetes with ophthalmic manifestations, type II
-- 250.60  Diabetes with neurological manifestations, type II
-- 250.80  Diabetes with other specified manifestations, type II
-- 250.90  Diabetes with unspecified complication, type II

-- ICD-10-CM Codes (T2DM)
-- E11.9   Type 2 diabetes mellitus without complications
-- E11.65  Type 2 diabetes mellitus with hyperglycemia
-- E11.00  Type 2 diabetes mellitus with hyperosmolarity, without NKHHC
-- E11.01  Type 2 diabetes mellitus with hyperosmolarity, with coma
-- E11.21  Type 2 diabetes mellitus with diabetic nephropathy
-- E11.311 Type 2 diabetes mellitus with unspecified diabetic retinopathy
-- E11.40  Type 2 diabetes mellitus with diabetic neuropathy, unspecified
-- E11.51  Type 2 diabetes mellitus with diabetic peripheral angiopathy
-- E11.618 Type 2 diabetes mellitus with other diabetic oral complications
-- E11.8   Type 2 diabetes mellitus with unspecified complications

-- OMOP Standard Concept for T2DM (SNOMED):
-- concept_id = 201826  → 'Type 2 diabetes mellitus'
-- Use concept_ancestor to capture all descendants

WITH t2dm_dx AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date    AS index_date,
        co.condition_concept_id,
        co.condition_source_value  AS icd_code
    FROM condition_occurrence co
    JOIN concept_ancestor ca
        ON co.condition_concept_id = ca.descendant_concept_id
    WHERE ca.ancestor_concept_id = 201826   -- OMOP SNOMED: Type 2 diabetes mellitus
       OR co.condition_source_value IN (
            -- ICD-9-CM
            '250.00','250.02','250.10','250.12','250.20','250.22',
            '250.40','250.42','250.50','250.52','250.60','250.62',
            '250.80','250.82','250.90','250.92',
            -- ICD-10-CM
            'E11.9','E11.65','E11.00','E11.01','E11.21',
            'E11.22','E11.29','E11.311','E11.319','E11.321',
            'E11.40','E11.41','E11.42','E11.43','E11.44',
            'E11.49','E11.51','E11.52','E11.59','E11.618',
            'E11.620','E11.621','E11.8','E11.10','E11.11'
        )
),

/* -----------------------------------------------------------
   BLOCK B: T2DM MEDICATIONS
   OMOP Domain: drug_exposure
   Includes oral antidiabetics and non-insulin injectables
   ----------------------------------------------------------- */

-- Medication Classes & OMOP Ingredient Concept IDs:
--
-- Biguanides:
--   Metformin (generic) | Glucophage, Glumetza, Fortamet (brand)
--   concept_id = 1503297
--
-- Sulfonylureas:
--   Glipizide (generic) | Glucotrol (brand)              concept_id = 1597756
--   Glyburide (generic) | Diabeta, Micronase (brand)     concept_id = 1516766
--   Glimepiride (generic) | Amaryl (brand)               concept_id = 1560171
--   Glibenclamide (generic)                              concept_id = 1516766
--
-- Thiazolidinediones (TZDs):
--   Pioglitazone (generic) | Actos (brand)               concept_id = 1525215
--   Rosiglitazone (generic) | Avandia (brand)            concept_id = 1598003
--
-- DPP-4 Inhibitors:
--   Sitagliptin (generic) | Januvia (brand)              concept_id = 1580747
--   Saxagliptin (generic) | Onglyza (brand)              concept_id = 1583722
--   Linagliptin (generic) | Tradjenta (brand)            concept_id = 40166035
--   Alogliptin (generic) | Nesina (brand)                concept_id = 43013884
--
-- SGLT-2 Inhibitors:
--   Empagliflozin (generic) | Jardiance (brand)          concept_id = 44785829
--   Canagliflozin (generic) | Invokana (brand)           concept_id = 43526465
--   Dapagliflozin (generic) | Farxiga, Forxiga (brand)   concept_id = 44816332
--   Ertugliflozin (generic) | Steglatro (brand)          concept_id = 792484
--
-- GLP-1 Receptor Agonists:
--   Exenatide (generic) | Byetta, Bydureon (brand)       concept_id = 1544838
--   Liraglutide (generic) | Victoza, Saxenda (brand)     concept_id = 40170911
--   Semaglutide (generic) | Ozempic, Rybelsus (brand)    concept_id = 2200644
--   Dulaglutide (generic) | Trulicity (brand)            concept_id = 44507700
--   Albiglutide (generic) | Tanzeum (brand)              concept_id = 45892894
--
-- Meglitinides:
--   Repaglinide (generic) | Prandin (brand)              concept_id = 1549686
--   Nateglinide (generic) | Starlix (brand)              concept_id = 1550557
--
-- Alpha-glucosidase Inhibitors:
--   Acarbose (generic) | Precose (brand)                 concept_id = 1510202
--   Miglitol (generic) | Glyset (brand)                  concept_id = 1547504
--
-- NOTE: Insulin is excluded from inclusion criteria (shared with T1DM)
--       but can be used as supportive evidence in conjunction with T2DM Dx

t2dm_meds AS (
    SELECT DISTINCT
        de.person_id,
        de.drug_exposure_start_date AS index_date,
        de.drug_concept_id,
        c.concept_name               AS drug_name
    FROM drug_exposure de
    JOIN concept_ancestor ca
        ON de.drug_concept_id = ca.descendant_concept_id
    JOIN concept c
        ON de.drug_concept_id = c.concept_id
    WHERE ca.ancestor_concept_id IN (
        -- Biguanides
        1503297,                               -- Metformin
        -- Sulfonylureas
        1597756, 1516766, 1560171,             -- Glipizide, Glyburide, Glimepiride
        -- TZDs
        1525215, 1598003,                      -- Pioglitazone, Rosiglitazone
        -- DPP-4 Inhibitors
        1580747, 1583722, 40166035, 43013884,  -- Sitagliptin, Saxagliptin, Linagliptin, Alogliptin
        -- SGLT-2 Inhibitors
        44785829, 43526465, 44816332, 792484,  -- Empagliflozin, Canagliflozin, Dapagliflozin, Ertugliflozin
        -- GLP-1 Agonists
        1544838, 40170911, 2200644, 44507700,  -- Exenatide, Liraglutide, Semaglutide, Dulaglutide
        -- Meglitinides
        1549686, 1550557,                      -- Repaglinide, Nateglinide
        -- Alpha-glucosidase Inhibitors
        1510202, 1547504                       -- Acarbose, Miglitol
    )
),

/* -----------------------------------------------------------
   BLOCK C: CONFIRMATORY LABORATORY VALUES
   OMOP Domain: measurement
   ----------------------------------------------------------- */

-- Lab Tests & OMOP Concept IDs (LOINC-mapped):
--
-- HbA1c (≥ 6.5%):
--   LOINC 4548-4  → concept_id = 3004410  (Hemoglobin A1c/Hemoglobin.total in Blood)
--   LOINC 17856-6 → concept_id = 3034639  (Hemoglobin A1c %)
--
-- Fasting Plasma Glucose (≥ 126 mg/dL):
--   LOINC 1558-6  → concept_id = 3037110  (Fasting glucose [Mass/volume] in Serum or Plasma)
--   LOINC 14771-0 → concept_id = 3000483  (Fasting glucose [Moles/volume] in Blood)
--
-- Random / 2-hr OGTT Plasma Glucose (≥ 200 mg/dL):
--   LOINC 2339-0  → concept_id = 3004501  (Glucose [Mass/volume] in Blood)
--   LOINC 20436-2 → concept_id = 3016562  (2h glucose [Mass/volume] in Serum/Plasma)

t2dm_labs AS (
    SELECT DISTINCT
        m.person_id,
        m.measurement_date  AS index_date,
        m.measurement_concept_id,
        m.value_as_number,
        m.unit_concept_id
    FROM measurement m
    WHERE (
        -- HbA1c >= 6.5%
        (
            m.measurement_concept_id IN (3004410, 3034639)
            AND m.value_as_number >= 6.5
        )
        OR
        -- Fasting Plasma Glucose >= 126 mg/dL
        (
            m.measurement_concept_id IN (3037110, 3000483)
            AND m.value_as_number >= 126
        )
        OR
        -- Random Glucose or 2-hr OGTT >= 200 mg/dL
        (
            m.measurement_concept_id IN (3004501, 3016562)
            AND m.value_as_number >= 200
        )
    )
),

/* -----------------------------------------------------------
   BLOCK D: EXCLUSION CRITERIA
   Exclude T1DM, Gestational DM, Secondary DM
   ----------------------------------------------------------- */

-- ICD-9-CM Exclusions:
--   250.01, 250.03  → Type 1 DM (without / with complication)
--   648.0x          → Gestational diabetes
--   249.xx          → Secondary diabetes mellitus

-- ICD-10-CM Exclusions:
--   E10.x           → Type 1 diabetes mellitus
--   O24.0–O24.3     → Pre-existing diabetes in pregnancy
--   O24.4           → Gestational diabetes mellitus
--   E08.x           → Diabetes due to underlying condition (secondary)
--   E09.x           → Drug or chemical induced diabetes
--   E13.x           → Other specified diabetes

-- OMOP Standard Concept IDs:
--   201254  → Type 1 diabetes mellitus   (SNOMED)
--   4024659 → Gestational diabetes        (SNOMED)
--   4193704 → Secondary diabetes mellitus (SNOMED)

exclusions AS (
    SELECT DISTINCT co.person_id
    FROM condition_occurrence co
    JOIN concept_ancestor ca
        ON co.condition_concept_id = ca.descendant_concept_id
    WHERE ca.ancestor_concept_id IN (
        201254,   -- Type 1 Diabetes Mellitus
        4024659,  -- Gestational Diabetes
        4193704   -- Secondary Diabetes Mellitus
    )
    OR co.condition_source_value LIKE 'E10%'   -- ICD-10 T1DM
    OR co.condition_source_value LIKE 'O24.4%' -- ICD-10 Gestational DM
    OR co.condition_source_value LIKE 'E08%'   -- ICD-10 Secondary DM (underlying condition)
    OR co.condition_source_value LIKE 'E09%'   -- ICD-10 Drug-induced DM
    OR co.condition_source_value LIKE '250.0_' -- ICD-9 T1DM (odd last digit = T1)
    OR co.condition_source_value LIKE '648.0%' -- ICD-9 Gestational DM
    OR co.condition_source_value LIKE '249%'   -- ICD-9 Secondary DM

    -- Additional exclusion: patients coded ONLY as T1DM with no T2DM evidence
    -- (handled in final SELECT via NOT EXISTS / EXCEPT)
),

/* -----------------------------------------------------------
   BLOCK E: INCLUSION LOGIC
   (Any ONE of the following three criteria is sufficient)
   ----------------------------------------------------------- */

-- CRITERION 1: ≥ 2 T2DM diagnosis codes on SEPARATE dates
dx_count AS (
    SELECT
        person_id,
        COUNT(DISTINCT index_date) AS dx_visit_count,
        MIN(index_date)            AS first_dx_date
    FROM t2dm_dx
    GROUP BY person_id
    HAVING COUNT(DISTINCT index_date) >= 2
),

-- CRITERION 2: ≥ 1 T2DM diagnosis AND ≥ 1 T2DM-specific medication
dx_plus_med AS (
    SELECT DISTINCT d.person_id,
        LEAST(d.index_date, m.index_date) AS first_evidence_date
    FROM t2dm_dx  d
    JOIN t2dm_meds m ON d.person_id = m.person_id
),

-- CRITERION 3: ≥ 1 T2DM diagnosis AND ≥ 1 confirmatory lab value
dx_plus_lab AS (
    SELECT DISTINCT d.person_id,
        LEAST(d.index_date, l.index_date) AS first_evidence_date
    FROM t2dm_dx  d
    JOIN t2dm_labs l ON d.person_id = l.person_id
),

/* -----------------------------------------------------------
   BLOCK F: FINAL COHORT
   INCLUSION  : Criterion 1 OR Criterion 2 OR Criterion 3
   EXCLUSION  : NOT in exclusion list (unless they ALSO have
                independent T2DM evidence overriding exclusion)
   ----------------------------------------------------------- */

included_patients AS (
    SELECT person_id, first_dx_date AS index_date, 'Dx x2'          AS qualifying_criterion
    FROM dx_count
    UNION
    SELECT person_id, first_evidence_date,          'Dx + Med'       AS qualifying_criterion
    FROM dx_plus_med
    UNION
    SELECT person_id, first_evidence_date,          'Dx + Lab'       AS qualifying_criterion
    FROM dx_plus_lab
)

/* ============================================================
   FINAL SELECT: T2DM PHENOTYPE COHORT
   ============================================================ */
SELECT DISTINCT
    ip.person_id,
    p.year_of_birth,
    p.gender_concept_id,
    p.race_concept_id,
    MIN(ip.index_date)       AS cohort_start_date,
    ip.qualifying_criterion
FROM included_patients ip
JOIN person p
    ON ip.person_id = p.person_id
WHERE ip.person_id NOT IN (
    SELECT person_id FROM exclusions
)
GROUP BY
    ip.person_id,
    p.year_of_birth,
    p.gender_concept_id,
    p.race_concept_id,
    ip.qualifying_criterion
ORDER BY ip.person_id;