/*============================================================
  TYPE 2 DIABETES MELLITUS — PHENOTYPING ALGORITHM
  Standard: OMOP CDM v5.x
  Logic: ≥2 independent evidence signals AND NOT exclusions
============================================================*/

WITH

-- -------------------------------------------------------
-- COMPONENT 1: T2DM Diagnosis (≥2 distinct dates)
-- -------------------------------------------------------
dx_t2dm AS (
    SELECT
        person_id,
        COUNT(DISTINCT condition_start_date) AS dx_count
    FROM condition_occurrence
    WHERE
        -- OMOP Standard Concept (T2DM + all descendants)
        condition_concept_id IN (
            SELECT descendant_concept_id
            FROM concept_ancestor
            WHERE ancestor_concept_id = 201826  -- Type 2 diabetes mellitus
        )
        OR
        -- ICD-9-CM direct codes
        condition_source_value IN (
            '250.00','250.02','250.10','250.12','250.20','250.22',
            '250.30','250.32','250.40','250.42','250.50','250.52',
            '250.60','250.62','250.70','250.72','250.80','250.82',
            '250.90','250.92'
        )
        OR
        -- ICD-10-CM direct codes
        condition_source_value LIKE 'E11%'
    GROUP BY person_id
    HAVING COUNT(DISTINCT condition_start_date) >= 2
),

-- -------------------------------------------------------
-- COMPONENT 2: Antidiabetic Medication Exposure
-- -------------------------------------------------------
med_t2dm AS (
    SELECT DISTINCT person_id
    FROM drug_exposure
    WHERE drug_concept_id IN (
        SELECT descendant_concept_id
        FROM concept_ancestor
        WHERE ancestor_concept_id IN (
            -- Biguanides
            1503297,  -- Metformin (Glucophage, Glumetza, Fortamet, Riomet)
            -- Sulfonylureas
            1597756,  -- Glipizide (Glucotrol)
            1516766,  -- Glyburide (DiaBeta, Micronase, Glynase)
            1560171,  -- Glimepiride (Amaryl)
            -- DPP-4 Inhibitors
            1580747,  -- Sitagliptin (Januvia)
            1583722,  -- Saxagliptin (Onglyza)
            40166035, -- Alogliptin (Nesina)
            1589505,  -- Linagliptin (Tradjenta)
            -- GLP-1 Receptor Agonists
            40170911, -- Semaglutide (Ozempic, Wegovy)
            1544838,  -- Liraglutide (Victoza)
            1551099,  -- Dulaglutide (Trulicity)
            1311276,  -- Exenatide (Byetta, Bydureon)
            -- SGLT-2 Inhibitors
            45774751, -- Empagliflozin (Jardiance)
            43526465, -- Canagliflozin (Invokana)
            44785829, -- Dapagliflozin (Farxiga)
            -- Thiazolidinediones
            1525215,  -- Pioglitazone (Actos)
            1516976,  -- Rosiglitazone (Avandia)
            -- Meglitinides
            1351461,  -- Repaglinide (Prandin)
            1364005,  -- Nateglinide (Starlix)
            -- Alpha-glucosidase Inhibitors
            1317640,  -- Acarbose (Precose)
            1326481   -- Miglitol (Glyset)
        )
    )
    -- Exclude insulin-only (allowed only when paired with T2DM Dx or oral agent)
    AND person_id NOT IN (
        SELECT person_id FROM drug_exposure
        WHERE drug_concept_id IN (
            SELECT descendant_concept_id FROM concept_ancestor
            WHERE ancestor_concept_id = 21600713  -- Insulin class
        )
        AND person_id NOT IN (
            SELECT DISTINCT de2.person_id FROM drug_exposure de2
            WHERE de2.drug_concept_id NOT IN (
                SELECT descendant_concept_id FROM concept_ancestor
                WHERE ancestor_concept_id = 21600713
            )
        )
    )
),

-- -------------------------------------------------------
-- COMPONENT 3: Confirmatory Lab Values
-- -------------------------------------------------------
lab_t2dm AS (
    SELECT DISTINCT person_id
    FROM measurement
    WHERE
    (
        -- HbA1c ≥ 6.5%
        (
            measurement_concept_id IN (3004410, 3007263, 3034639)
            -- LOINC 4548-4, 4549-2, 17856-6
            AND value_as_number >= 6.5
        )
        OR
        -- Fasting Plasma Glucose ≥ 126 mg/dL
        (
            measurement_concept_id IN (3037110, 3011363)
            -- LOINC 1558-6, 14771-0
            AND value_as_number >= 126
        )
        OR
        -- Random Plasma Glucose ≥ 200 mg/dL
        (
            measurement_concept_id IN (3000963, 3025232)
            -- LOINC 2345-7
            AND value_as_number >= 200
        )
        OR
        -- 2-hr OGTT ≥ 200 mg/dL
        (
            measurement_concept_id IN (3016047, 3020149)
            -- LOINC 1507-3
            AND value_as_number >= 200
        )
    )
),

-- -------------------------------------------------------
-- EXCLUSION 1: Type 1 Diabetes
-- -------------------------------------------------------
excl_t1dm AS (
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE
        condition_concept_id IN (
            SELECT descendant_concept_id FROM concept_ancestor
            WHERE ancestor_concept_id = 201254  -- Type 1 diabetes mellitus
        )
        OR condition_source_value IN (
            '250.01','250.03','250.11','250.13','250.21','250.23',
            '250.31','250.33','250.41','250.43','250.51','250.53',
            '250.61','250.63','250.71','250.73','250.81','250.83',
            '250.91','250.93'
        )
        OR condition_source_value LIKE 'E10%'
),

-- -------------------------------------------------------
-- EXCLUSION 2: Gestational Diabetes
-- -------------------------------------------------------
excl_gdm AS (
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE
        condition_concept_id IN (
            SELECT descendant_concept_id FROM concept_ancestor
            WHERE ancestor_concept_id = 4058243
        )
        OR condition_source_value IN ('648.0','648.00','648.01','648.02','648.03','648.04')
        OR condition_source_value LIKE 'O24.4%'
),

-- -------------------------------------------------------
-- EXCLUSION 3: Secondary / Drug-induced / Other DM
-- -------------------------------------------------------
excl_other_dm AS (
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE
        condition_source_value LIKE '249%'     -- ICD-9 secondary DM
        OR condition_source_value LIKE 'E08%'  -- ICD-10 DM due to underlying condition
        OR condition_source_value LIKE 'E09%'  -- ICD-10 drug/chemical-induced DM
        OR condition_source_value LIKE 'E13%'  -- ICD-10 other specified DM
        OR condition_source_value LIKE 'P70.2%'-- Neonatal DM
),

-- -------------------------------------------------------
-- FINAL COHORT: Combine signals (≥2 required)
-- -------------------------------------------------------
evidence_signals AS (
    SELECT
        p.person_id,
        CASE WHEN d.person_id IS NOT NULL THEN 1 ELSE 0 END AS has_dx,
        CASE WHEN m.person_id IS NOT NULL THEN 1 ELSE 0 END AS has_med,
        CASE WHEN l.person_id IS NOT NULL THEN 1 ELSE 0 END AS has_lab
    FROM person p
    LEFT JOIN dx_t2dm  d ON p.person_id = d.person_id
    LEFT JOIN med_t2dm m ON p.person_id = m.person_id
    LEFT JOIN lab_t2dm l ON p.person_id = l.person_id
)

-- -------------------------------------------------------
-- OUTPUT: Final T2DM Phenotype
-- -------------------------------------------------------
SELECT DISTINCT es.person_id
FROM evidence_signals es
WHERE
    -- Require ≥2 independent signals
    (
        (has_dx = 1 AND has_med = 1)   -- Dx + Medication
        OR (has_dx = 1 AND has_lab = 1) -- Dx + Lab
        OR (has_med = 1 AND has_lab = 1)-- Medication + Lab
    )

    -- Apply exclusions
    AND es.person_id NOT IN (SELECT person_id FROM excl_t1dm)
    AND es.person_id NOT IN (SELECT person_id FROM excl_gdm)
    AND es.person_id NOT IN (SELECT person_id FROM excl_other_dm)

ORDER BY es.person_id;