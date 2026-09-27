/* ============================================================
   TYPE 2 DIABETES MELLITUS — OMOP PHENOTYPING ALGORITHM
   Standard: OMOP CDM v5.x
   Diagnosis: ICD9CM + ICD10CM codes mapped to OMOP concept_ids
   ============================================================ */

-- ----------------------------------------------------------------
-- BLOCK A: DIAGNOSIS CODES (condition_occurrence)
-- ----------------------------------------------------------------
-- ICD10CM: E11.x  (Type 2 diabetes mellitus and subtypes)
-- ICD9CM:  250.x0, 250.x2  (Diabetes mellitus, type II / unspecified,
--                            not stated as uncontrolled / uncontrolled)

WITH dx_t2dm AS (
    SELECT DISTINCT co.person_id,
                    co.condition_start_date AS index_date,
                    co.condition_concept_id,
                    co.condition_source_value
    FROM condition_occurrence co
    JOIN concept c
      ON co.condition_concept_id = c.concept_id
    WHERE
      /* --- OMOP Standard Concepts (SNOMED mapped) --- */
      co.condition_concept_id IN (
          201826,   -- Type 2 diabetes mellitus
          442793,   -- Type 2 diabetes mellitus without complications
          443729,   -- Type 2 diabetes mellitus with unspecified complications
          4193704,  -- Type 2 diabetes mellitus with diabetic nephropathy
          4230254,  -- Type 2 diabetes mellitus with diabetic retinopathy
          4299544,  -- Type 2 diabetes mellitus with diabetic neuropathy
          443732,   -- Type 2 diabetes mellitus with peripheral angiopathy
          200687    -- Diabetes mellitus (NOS, used with source code filter)
      )
      OR
      /* --- Source codes (ICD10CM) retained in source_value --- */
      co.condition_source_value LIKE 'E11%'    -- T2DM all subtypes
      OR
      /* --- Source codes (ICD9CM) --- */
      co.condition_source_value IN (
          '250.00','250.02',   -- DM type II, not stated uncontrolled
          '250.10','250.12',   -- DM with ketoacidosis
          '250.20','250.22',   -- DM with hyperosmolarity
          '250.30','250.32',   -- DM with other coma
          '250.40','250.42',   -- DM with renal manifestations
          '250.50','250.52',   -- DM with ophthalmic manifestations
          '250.60','250.62',   -- DM with neurological manifestations
          '250.70','250.72',   -- DM with peripheral circulatory disorders
          '250.80','250.82',   -- DM with other specified manifestations
          '250.90','250.92'    -- DM with unspecified complications
      )
),

-- Require ≥2 diagnosis encounters on DIFFERENT dates for specificity
dx_t2dm_qualified AS (
    SELECT   person_id,
             MIN(index_date) AS first_dx_date,
             COUNT(DISTINCT index_date) AS dx_count
    FROM     dx_t2dm
    GROUP BY person_id
    HAVING   COUNT(DISTINCT index_date) >= 2
),


-- ----------------------------------------------------------------
-- BLOCK B: LABORATORY EVIDENCE (measurement)
-- ----------------------------------------------------------------
-- Thresholds (ADA diagnostic criteria):
--   HbA1c          >= 6.5%   (concept: 3004410)
--   Fasting glucose >= 126 mg/dL (concept: 3004501, 3005131)
--   Random glucose  >= 200 mg/dL (concept: 3000483)

lab_evidence AS (
    SELECT DISTINCT m.person_id,
                    m.measurement_date AS index_date
    FROM measurement m
    WHERE
      (
        /* HbA1c >= 6.5% */
        m.measurement_concept_id IN (
            3004410,  -- Hemoglobin A1c/Hemoglobin.total in Blood
            3007263,  -- Hemoglobin A1c [Mass/volume] in Blood
            40789263  -- HbA1c % (LOINC 4548-4, 17856-6)
        )
        AND m.value_as_number >= 6.5
      )
      OR
      (
        /* Fasting plasma glucose >= 126 mg/dL */
        m.measurement_concept_id IN (
            3004501,  -- Glucose [Mass/volume] in Serum or Plasma --Fasting
            3005131,  -- Fasting glucose (LOINC 1558-6)
            40795800  -- Glucose [Moles/volume] fasting
        )
        AND m.value_as_number >= 126
        AND m.unit_concept_id = 8753  -- mg/dL
      )
      OR
      (
        /* Random plasma glucose >= 200 mg/dL */
        m.measurement_concept_id IN (
            3000483,  -- Glucose [Mass/volume] in Serum or Plasma
            3004249,  -- Glucose (LOINC 2345-7)
            40758583
        )
        AND m.value_as_number >= 200
        AND m.unit_concept_id = 8753  -- mg/dL
      )
),


-- ----------------------------------------------------------------
-- BLOCK C: ANTIDIABETIC MEDICATIONS (drug_exposure)
-- ----------------------------------------------------------------
-- T2DM-specific oral agents and non-insulin injectables
-- Excludes insulin (which is used in both T1DM and T2DM)

medication_t2dm AS (
    SELECT DISTINCT de.person_id,
                    de.drug_exposure_start_date AS index_date
    FROM drug_exposure de
    JOIN concept_ancestor ca
      ON de.drug_concept_id = ca.descendant_concept_id
    WHERE ca.ancestor_concept_id IN (

        /* --- BIGUANIDES --- */
        1503297,  -- Metformin (generic)
                  -- Brand: Glucophage, Glucophage XR, Glumetza, Fortamet, Riomet

        /* --- SULFONYLUREAS --- */
        1597756,  -- Glipizide (Glucotrol, Glucotrol XL)
        1580747,  -- Glyburide (DiaBeta, Glynase, Micronase)
        1516766,  -- Glimepiride (Amaryl)
        1502855,  -- Chlorpropamide (Diabinese)
        1502905,  -- Tolazamide (Tolinase)
        1519880,  -- Tolbutamide (Orinase)

        /* --- THIAZOLIDINEDIONES (TZDs) --- */
        1525215,  -- Pioglitazone (Actos)
        1530014,  -- Rosiglitazone (Avandia)

        /* --- DPP-4 INHIBITORS --- */
        1580747,  -- Sitagliptin (Januvia)
        40166035, -- Saxagliptin (Onglyza)
        40239216, -- Linagliptin (Tradjenta)
        44818489, -- Alogliptin (Nesina)
        44507700, -- Trelagliptin (Zafatek)

        /* --- GLP-1 RECEPTOR AGONISTS --- */
        40170911, -- Exenatide (Byetta, Bydureon)
        44816332, -- Liraglutide (Victoza — diabetes; Saxenda — obesity)
        45774435, -- Dulaglutide (Trulicity)
        45892894, -- Semaglutide (Ozempic [inject], Rybelsus [oral])
        46221285, -- Albiglutide (Tanzeum)
        35603563, -- Lixisenatide (Adlyxin)
        37003518, -- Tirzepatide (Mounjaro) -- GIP/GLP-1 dual agonist

        /* --- SGLT-2 INHIBITORS --- */
        44816189, -- Canagliflozin (Invokana)
        44818518, -- Dapagliflozin (Farxiga)
        45774103, -- Empagliflozin (Jardiance)
        46234869, -- Ertugliflozin (Steglatro)

        /* --- ALPHA-GLUCOSIDASE INHIBITORS --- */
        1510202,  -- Acarbose (Precose)
        1502809,  -- Miglitol (Glyset)

        /* --- MEGLITINIDES --- */
        1502826,  -- Repaglinide (Prandin)
        1547504,  -- Nateglinide (Starlix)

        /* --- AMYLIN ANALOGUE --- */
        40170920  -- Pramlintide (Symlin)
    )
),


-- ----------------------------------------------------------------
-- BLOCK D: EXCLUSION CRITERIA
-- ----------------------------------------------------------------

exclusions AS (
    SELECT DISTINCT co.person_id
    FROM condition_occurrence co
    WHERE

      /* --- Type 1 Diabetes --- */
      co.condition_concept_id IN (
          201254,   -- Type 1 diabetes mellitus
          435216,   -- Type 1 diabetes mellitus without complications
          4058243   -- Insulin-dependent diabetes mellitus
      )
      OR co.condition_source_value LIKE 'E10%'    -- ICD10CM T1DM
      OR co.condition_source_value IN (
          '250.01','250.03','250.11','250.13',     -- ICD9CM T1DM (odd 3rd digit)
          '250.21','250.23','250.31','250.33',
          '250.41','250.43','250.51','250.53',
          '250.61','250.63','250.71','250.73',
          '250.81','250.83','250.91','250.93'
      )

      OR

      /* --- Secondary / Other Specific Diabetes --- */
      co.condition_concept_id IN (
          195771,   -- Secondary diabetes mellitus
          4063043   -- Diabetes mellitus due to underlying condition
      )
      OR co.condition_source_value LIKE 'E08%'    -- DM due to underlying condition
      OR co.condition_source_value LIKE 'E09%'    -- Drug/chemical-induced DM
      OR co.condition_source_value LIKE 'E13%'    -- Other specified DM

      OR

      /* --- Gestational Diabetes --- */
      co.condition_concept_id IN (
          4024659,  -- Gestational diabetes mellitus
          40484648
      )
      OR co.condition_source_value LIKE 'O24.4%'  -- ICD10CM gestational DM
      OR co.condition_source_value IN (
          '648.00','648.01','648.02','648.03','648.04'  -- ICD9CM gestational DM
      )
),


-- ----------------------------------------------------------------
-- FINAL ALGORITHM: COMBINE BLOCKS
-- ----------------------------------------------------------------

t2dm_candidates AS (

    /* CASE DEFINITION:
       (≥2 T2DM diagnoses)
         OR (≥1 T2DM diagnosis AND ≥1 qualifying lab)
         OR (≥1 T2DM diagnosis AND ≥1 T2DM medication)
         OR (≥1 qualifying lab AND ≥1 T2DM medication)
       AND NOT any exclusion criterion
    */

    SELECT   p.person_id,
             COALESCE(d.first_dx_date,
                      l.index_date,
                      m.index_date)        AS index_date,
             CASE
               WHEN d.person_id  IS NOT NULL
                AND l.person_id  IS NOT NULL THEN 'Dx+Lab'
               WHEN d.person_id  IS NOT NULL
                AND m.person_id  IS NOT NULL THEN 'Dx+Med'
               WHEN d.person_id  IS NOT NULL
                AND d.dx_count  >= 2        THEN 'Dx>=2'
               WHEN l.person_id  IS NOT NULL
                AND m.person_id  IS NOT NULL THEN 'Lab+Med'
               ELSE 'Single_Signal'
             END                           AS phenotype_category,

             CASE
               WHEN d.person_id IS NOT NULL THEN 1 ELSE 0
             END AS has_dx,
             CASE
               WHEN l.person_id IS NOT NULL THEN 1 ELSE 0
             END AS has_lab,
             CASE
               WHEN m.person_id IS NOT NULL THEN 1 ELSE 0
             END AS has_med

    FROM person p

    /* JOIN positive signals */
    LEFT JOIN dx_t2dm_qualified  d ON p.person_id = d.person_id
    LEFT JOIN lab_evidence       l ON p.person_id = l.person_id
    LEFT JOIN medication_t2dm    m ON p.person_id = m.person_id

    /* EXCLUDE non-T2DM patients */
    LEFT JOIN exclusions         e ON p.person_id = e.person_id

    WHERE e.person_id IS NULL   -- NOT in exclusion list

      AND (
            /* At least 2 corroborating signals, or ≥2 dx visits */
            (d.person_id IS NOT NULL AND d.dx_count >= 2)
            OR (d.person_id IS NOT NULL AND l.person_id IS NOT NULL)
            OR (d.person_id IS NOT NULL AND m.person_id IS NOT NULL)
            OR (l.person_id IS NOT NULL AND m.person_id IS NOT NULL)
          )
)

-- ----------------------------------------------------------------
-- FINAL OUTPUT
-- ----------------------------------------------------------------
SELECT   person_id,
         index_date,
         phenotype_category,
         has_dx,
         has_lab,
         has_med,
         (has_dx + has_lab + has_med) AS signal_count
FROM     t2dm_candidates
ORDER BY signal_count DESC, person_id;