/*=============================================================
  TYPE 2 DIABETES PHENOTYPING ALGORITHM
  Standard : OMOP CDM v5.x
  Diagnosis : ICD9CM + ICD10CM
  Confidence: HIGH (≥2 domains) | MEDIUM (1 domain)
=============================================================*/

/* ── DOMAIN 1: DIAGNOSIS ──────────────────────────────────────
   OMOP Domain  : CONDITION_OCCURRENCE
   Vocabulary   : ICD9CM, ICD10CM, SNOMED
   Minimum count: ≥ 2 qualifying diagnosis codes
   (reduces miscoding noise)
──────────────────────────────────────────────────────────────*/
WITH dx_criteria AS (
    SELECT
        person_id,
        COUNT(DISTINCT condition_start_date) AS dx_count
    FROM condition_occurrence
    WHERE condition_concept_id IN (
        -- ── ICD10CM ─────────────────────────────────────
        -- E11     Type 2 diabetes mellitus (parent)
        -- E11.0   T2DM with hyperosmolarity
        -- E11.00  T2DM with hyperosmolarity without NKHHC
        -- E11.01  T2DM with hyperosmolarity with coma
        -- E11.1   T2DM with ketoacidosis (atypical T2)
        -- E11.2x  T2DM with kidney complications
        -- E11.3x  T2DM with ophthalmic complications
        -- E11.4x  T2DM with neurological complications
        -- E11.5x  T2DM with circulatory complications
        -- E11.6x  T2DM with other complications
        -- E11.8   T2DM with unspecified complications
        -- E11.9   T2DM without complications
        SELECT concept_id FROM concept
        WHERE vocabulary_id = 'ICD10CM'
          AND concept_code LIKE 'E11%'
          AND invalid_reason IS NULL

        UNION

        -- ── ICD9CM ──────────────────────────────────────
        -- 250.x0  Diabetes mellitus, type 2, not stated uncontrolled
        -- 250.x2  Diabetes mellitus, type 2, uncontrolled
        SELECT concept_id FROM concept
        WHERE vocabulary_id = 'ICD9CM'
          AND concept_code IN (
              '250.00','250.02','250.10','250.12',
              '250.20','250.22','250.30','250.32',
              '250.40','250.42','250.50','250.52',
              '250.60','250.62','250.70','250.72',
              '250.80','250.82','250.90','250.92'
          )
          AND invalid_reason IS NULL

        UNION

        -- ── SNOMED (OMOP Standard) ───────────────────────
        -- 44054006  Diabetes mellitus type 2
        -- 359642000 T2DM in nonobese
        -- 237599002 T2DM in obese
        -- 190331003 T2DM with hyperosmolar coma
        SELECT concept_id FROM concept
        WHERE vocabulary_id = 'SNOMED'
          AND concept_code IN (
              '44054006','359642000','237599002','190331003',
              '313436004','314903002','314904008'
          )
          AND invalid_reason IS NULL
    )
    GROUP BY person_id
    HAVING COUNT(DISTINCT condition_start_date) >= 2
),

/* ── DOMAIN 2: LABORATORY TESTS ───────────────────────────────
   OMOP Domain  : MEASUREMENT
   Qualifying if ANY of the following thresholds are met:
     · HbA1c              ≥ 6.5%        (LOINC 4548-4, 17856-6)
     · Fasting glucose    ≥ 126 mg/dL   (LOINC 1558-6, 1493-6)
     · Random glucose     ≥ 200 mg/dL   (LOINC 2345-7, 2339-0)
     · OGTT 2-hr glucose  ≥ 200 mg/dL   (LOINC 1504-0, 20438-8)
──────────────────────────────────────────────────────────────*/
lab_criteria AS (
    SELECT DISTINCT person_id
    FROM measurement
    WHERE (
        -- HbA1c ≥ 6.5%
        ( measurement_concept_id IN (
              SELECT concept_id FROM concept
              WHERE vocabulary_id = 'LOINC'
                AND concept_code IN ('4548-4','17856-6','59261-8')
          )
          AND value_as_number >= 6.5
        )
        OR
        -- Fasting plasma glucose ≥ 126 mg/dL
        ( measurement_concept_id IN (
              SELECT concept_id FROM concept
              WHERE vocabulary_id = 'LOINC'
                AND concept_code IN ('1558-6','1493-6','14771-0','77145-1')
          )
          AND value_as_number >= 126
          AND unit_concept_id IN (
              SELECT concept_id FROM concept
              WHERE concept_code = 'mg/dL'
          )
        )
        OR
        -- Random plasma glucose ≥ 200 mg/dL
        ( measurement_concept_id IN (
              SELECT concept_id FROM concept
              WHERE vocabulary_id = 'LOINC'
                AND concept_code IN ('2345-7','2339-0','15074-8')
          )
          AND value_as_number >= 200
          AND unit_concept_id IN (
              SELECT concept_id FROM concept
              WHERE concept_code = 'mg/dL'
          )
        )
        OR
        -- OGTT 2-hour glucose ≥ 200 mg/dL
        ( measurement_concept_id IN (
              SELECT concept_id FROM concept
              WHERE vocabulary_id = 'LOINC'
                AND concept_code IN ('1504-0','20438-8','1518-0')
          )
          AND value_as_number >= 200
          AND unit_concept_id IN (
              SELECT concept_id FROM concept
              WHERE concept_code = 'mg/dL'
          )
        )
    )
),

/* ── DOMAIN 3: MEDICATIONS ────────────────────────────────────
   OMOP Domain : DRUG_EXPOSURE
   Vocabularies: RxNorm, RxNorm Extension
   Classes     : Biguanides, Sulfonylureas, DPP-4i, GLP-1 RA,
                 SGLT-2i, Thiazolidinediones, Meglitinides,
                 Alpha-glucosidase inhibitors, combinations

   NOTE: Insulin alone is NOT sufficient (T1/T2 overlap)
         Must appear with at least one NON-insulin agent
         OR with a qualifying diagnosis/lab
──────────────────────────────────────────────────────────────*/
med_criteria AS (
    SELECT DISTINCT person_id
    FROM drug_exposure
    WHERE drug_concept_id IN (
        SELECT c.concept_id
        FROM concept c
        JOIN concept_ancestor ca
          ON c.concept_id = ca.descendant_concept_id
        WHERE ca.ancestor_concept_id IN (

            -- ── BIGUANIDES ──────────────────────────────
            -- Metformin (generic) | Glucophage, Glumetza,
            --   Fortamet, Riomet (brand)
            1503297,   -- Metformin [RxNorm ingredient]

            -- ── SULFONYLUREAS ───────────────────────────
            -- Glipizide    | Glucotrol, Glucotrol XL
            -- Glyburide    | DiaBeta, Micronase, Glynase
            -- Glimepiride  | Amaryl
            -- Chlorpropamide | Diabinese
            -- Tolbutamide  | Orinase
            -- Tolazamide   | Tolinase
            1597756,   -- Glipizide
            1516766,   -- Glyburide
            1560171,   -- Glimepiride
            1594973,   -- Chlorpropamide
            1595799,   -- Tolbutamide
            1596977,   -- Tolazamide

            -- ── DPP-4 INHIBITORS ────────────────────────
            -- Sitagliptin  | Januvia
            -- Saxagliptin  | Onglyza
            -- Linagliptin  | Tradjenta
            -- Alogliptin   | Nesina
            -- Vildagliptin | Galvus (ex-US)
            1580747,   -- Sitagliptin
            40166035,  -- Saxagliptin
            40239216,  -- Linagliptin
            40241331,  -- Alogliptin
            1512515,   -- Vildagliptin

            -- ── GLP-1 RECEPTOR AGONISTS ─────────────────
            -- Exenatide    | Byetta, Bydureon
            -- Liraglutide  | Victoza (T2DM), Saxenda (obesity)
            -- Dulaglutide  | Trulicity
            -- Semaglutide  | Ozempic (T2DM), Wegovy (obesity)
            --               | Rybelsus (oral)
            -- Albiglutide  | Tanzeum (discontinued)
            -- Lixisenatide | Adlyxin
            -- Tirzepatide  | Mounjaro (GIP/GLP-1)
            40170911,  -- Exenatide
            45774751,  -- Liraglutide
            44507700,  -- Dulaglutide
            793143,    -- Semaglutide
            45892867,  -- Lixisenatide
            702776,    -- Tirzepatide

            -- ── SGLT-2 INHIBITORS ───────────────────────
            -- Canagliflozin  | Invokana
            -- Dapagliflozin  | Farxiga, Forxiga
            -- Empagliflozin  | Jardiance
            -- Ertugliflozin  | Steglatro
            44816332,  -- Canagliflozin
            44507705,  -- Dapagliflozin
            44507706,  -- Empagliflozin
            792484,    -- Ertugliflozin

            -- ── THIAZOLIDINEDIONES (TZDs) ────────────────
            -- Pioglitazone | Actos
            -- Rosiglitazone| Avandia
            1529331,   -- Pioglitazone
            1516976,   -- Rosiglitazone

            -- ── MEGLITINIDES ────────────────────────────
            -- Repaglinide  | Prandin
            -- Nateglinide  | Starlix
            1525215,   -- Repaglinide
            1547504,   -- Nateglinide

            -- ── ALPHA-GLUCOSIDASE INHIBITORS ────────────
            -- Acarbose     | Precose
            -- Miglitol     | Glyset
            1515249,   -- Acarbose
            1515480    -- Miglitol
        )
        AND c.invalid_reason IS NULL
    )
),

/* ── EXCLUSION 1: TYPE 1 DIABETES ────────────────────────────
   OMOP Domain : CONDITION_OCCURRENCE
   Exclude patients with documented T1DM
──────────────────────────────────────────────────────────────*/
t1dm_exclusion AS (
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE condition_concept_id IN (
        SELECT concept_id FROM concept
        WHERE vocabulary_id = 'ICD10CM'
          AND concept_code LIKE 'E10%'
          AND invalid_reason IS NULL
        UNION
        SELECT concept_id FROM concept
        WHERE vocabulary_id = 'ICD9CM'
          AND concept_code IN (
              '250.01','250.03','250.11','250.13',
              '250.21','250.23','250.31','250.33',
              '250.41','250.43','250.51','250.53',
              '250.61','250.63','250.71','250.73',
              '250.81','250.83','250.91','250.93'
          )
          AND invalid_reason IS NULL
        UNION
        SELECT concept_id FROM concept
        WHERE vocabulary_id = 'SNOMED'
          AND concept_code IN ('46635009','313435000','190330002')
          AND invalid_reason IS NULL
    )
),

/* ── EXCLUSION 2: GESTATIONAL DIABETES ───────────────────────
   ICD10CM: O24.4x (Gestational DM)
   ICD9CM : 648.0x (Diabetes in pregnancy)
──────────────────────────────────────────────────────────────*/
gestational_exclusion AS (
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE condition_concept_id IN (
        SELECT concept_id FROM concept
        WHERE vocabulary_id = 'ICD10CM'
          AND concept_code LIKE 'O24.4%'
          AND invalid_reason IS NULL
        UNION
        SELECT concept_id FROM concept
        WHERE vocabulary_id = 'ICD9CM'
          AND concept_code LIKE '648.0%'
          AND invalid_reason IS NULL
    )
),

/* ── EXCLUSION 3: SECONDARY / OTHER DIABETES ─────────────────
   ICD10CM: E08 (DM due to underlying condition)
            E09 (Drug/chemical-induced DM)
            E13 (Other specified DM)
   ICD9CM : 249.xx (Secondary diabetes)
──────────────────────────────────────────────────────────────*/
secondary_dm_exclusion AS (
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE condition_concept_id IN (
        SELECT concept_id FROM concept
        WHERE vocabulary_id = 'ICD10CM'
          AND (concept_code LIKE 'E08%'
           OR concept_code LIKE 'E09%'
           OR concept_code LIKE 'E13%')
          AND invalid_reason IS NULL
        UNION
        SELECT concept_id FROM concept
        WHERE vocabulary_id = 'ICD9CM'
          AND concept_code LIKE '249%'
          AND invalid_reason IS NULL
    )
),

/* ── EXCLUSION 4: AGE < 18 AT FIRST QUALIFYING EVENT ─────────
   Reduces T1DM misclassification in pediatric patients
   (configurable threshold)
──────────────────────────────────────────────────────────────*/
age_exclusion AS (
    SELECT DISTINCT p.person_id
    FROM person p
    WHERE (YEAR(GETDATE()) - p.year_of_birth) < 18
),

/*=============================================================
  FINAL COHORT ASSEMBLY
  Eligibility = (dx_criteria OR lab_criteria OR med_criteria)
                AND NOT t1dm_exclusion
                AND NOT gestational_exclusion
                AND NOT secondary_dm_exclusion
                AND NOT age_exclusion

  Confidence Tier:
    HIGH   = ≥ 2 domains met
    MEDIUM = exactly 1 domain met
=============================================================*/
qualifying_patients AS (
    SELECT
        person_id,
        MAX(CASE WHEN domain = 'DIAGNOSIS'   THEN 1 ELSE 0 END) AS has_dx,
        MAX(CASE WHEN domain = 'LAB'         THEN 1 ELSE 0 END) AS has_lab,
        MAX(CASE WHEN domain = 'MEDICATION'  THEN 1 ELSE 0 END) AS has_med
    FROM (
        SELECT person_id, 'DIAGNOSIS'  AS domain FROM dx_criteria
        UNION ALL
        SELECT person_id, 'LAB'        AS domain FROM lab_criteria
        UNION ALL
        SELECT person_id, 'MEDICATION' AS domain FROM med_criteria
    ) combined
    GROUP BY person_id
)

SELECT
    qp.person_id,
    qp.has_dx,
    qp.has_lab,
    qp.has_med,
    (qp.has_dx + qp.has_lab + qp.has_med)          AS domain_count,
    CASE
        WHEN (qp.has_dx + qp.has_lab + qp.has_med) >= 2 THEN 'HIGH'
        WHEN (qp.has_dx + qp.has_lab + qp.has_med) = 1  THEN 'MEDIUM'
    END                                              AS confidence_tier
FROM qualifying_patients qp

-- ── APPLY INCLUSION GATE ─────────────────────────────────────
WHERE (qp.has_dx = 1 OR qp.has_lab = 1 OR qp.has_med = 1)

-- ── APPLY ALL EXCLUSIONS ─────────────────────────────────────
AND qp.person_id NOT IN (SELECT person_id FROM t1dm_exclusion)
AND qp.person_id NOT IN (SELECT person_id FROM gestational_exclusion)
AND qp.person_id NOT IN (SELECT person_id FROM secondary_dm_exclusion)
AND qp.person_id NOT IN (SELECT person_id FROM age_exclusion)

ORDER BY confidence_tier, qp.person_id;