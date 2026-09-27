/* ============================================================
   PHENOTYPING ALGORITHM: TYPE 2 DIABETES MELLITUS
   Standard  : OMOP CDM v5.x
   Diagnosis : ICD9CM + ICD10CM source codes + SNOMED via concept_ancestor
   Inclusion : (≥2 T2DM Dx on separate dates)
            OR (≥1 T2DM Dx AND ≥1 T2DM-specific medication)
            OR (≥1 T2DM Dx AND ≥1 confirmatory lab)
            OR (≥1 T2DM-specific medication AND ≥1 confirmatory lab)
   Exclusion : T1DM, gestational DM, secondary DM, neonatal DM, age <18
   ============================================================ */


/* ============================================================
   BLOCK A: T2DM DIAGNOSIS CANDIDATES
   ICD-9-CM even 5th digit = Type 2; ICD-10-CM E11.x = Type 2
   OMOP SNOMED ancestor 201826 = Type 2 diabetes mellitus
   ============================================================ */
SELECT
    p.person_id,
    MIN(dx.first_dx_date)                        AS cohort_start_date,
    CASE
        WHEN dx.person_id IS NOT NULL
         AND dx.dx_count  >= 2                   THEN 1 ELSE 0
    END                                          AS has_dx2,
    CASE
        WHEN dx.person_id IS NOT NULL            THEN 1 ELSE 0
    END                                          AS has_dx,
    CASE
        WHEN lab.person_id IS NOT NULL           THEN 1 ELSE 0
    END                                          AS has_lab,
    CASE
        WHEN med.person_id IS NOT NULL           THEN 1 ELSE 0
    END                                          AS has_med
FROM person p

/* ── JOIN: T2DM diagnosis (≥1 occurrence) ── */
LEFT JOIN (
    SELECT
        person_id,
        MIN(condition_start_date)                AS first_dx_date,
        COUNT(DISTINCT condition_start_date)     AS dx_count
    FROM condition_occurrence
    WHERE
        /* OMOP Standard Concepts via concept_ancestor */
        condition_concept_id IN (
            SELECT descendant_concept_id
            FROM concept_ancestor
            WHERE ancestor_concept_id = 201826   -- Type 2 diabetes mellitus (SNOMED)
        )
        OR
        /* ICD-9-CM: even 5th digit = Type 2 DM */
        condition_source_value IN (
            '250.00','250.02',  -- DM type II without complication
            '250.10','250.12',  -- DM type II with ketoacidosis
            '250.20','250.22',  -- DM type II with hyperosmolarity
            '250.30','250.32',  -- DM type II with other coma
            '250.40','250.42',  -- DM type II with renal manifestations
            '250.50','250.52',  -- DM type II with ophthalmic manifestations
            '250.60','250.62',  -- DM type II with neurological manifestations
            '250.70','250.72',  -- DM type II with peripheral circulatory disorders
            '250.80','250.82',  -- DM type II with other specified manifestations
            '250.90','250.92'   -- DM type II with unspecified complications
        )
        OR
        /* ICD-10-CM: all E11 subtypes */
        condition_source_value LIKE 'E11%'
    GROUP BY person_id
) dx ON p.person_id = dx.person_id

/* ── JOIN: Confirmatory laboratory values ── */
LEFT JOIN (
    SELECT DISTINCT person_id
    FROM measurement
    WHERE
        /* HbA1c >= 6.5%
           LOINC 4548-4  → OMOP concept_id 3004410
           LOINC 17856-6 → OMOP concept_id 3034639
           LOINC 4549-2  → OMOP concept_id 3007263  */
        ( measurement_concept_id IN (3004410, 3034639, 3007263)
          AND value_as_number >= 6.5 )

        OR
        /* Fasting plasma glucose >= 126 mg/dL
           LOINC 1558-6  → OMOP concept_id 3037110
           LOINC 14771-0 → OMOP concept_id 3000483  */
        ( measurement_concept_id IN (3037110, 3000483)
          AND value_as_number >= 126
          AND unit_concept_id = 8753 )   -- mg/dL

        OR
        /* Random plasma glucose >= 200 mg/dL
           LOINC 2345-7  → OMOP concept_id 3000963
           LOINC 2339-0  → OMOP concept_id 3004501  */
        ( measurement_concept_id IN (3000963, 3004501)
          AND value_as_number >= 200
          AND unit_concept_id = 8753 )   -- mg/dL

        OR
        /* 2-hour OGTT glucose >= 200 mg/dL
           LOINC 20436-2 → OMOP concept_id 3016562
           LOINC 1504-0  → OMOP concept_id 3016047  */
        ( measurement_concept_id IN (3016562, 3016047)
          AND value_as_number >= 200
          AND unit_concept_id = 8753 )   -- mg/dL
) lab ON p.person_id = lab.person_id

/* ── JOIN: T2DM-specific medications (non-insulin) ── */
LEFT JOIN (
    SELECT DISTINCT de.person_id
    FROM drug_exposure de
    JOIN concept_ancestor ca
      ON de.drug_concept_id = ca.descendant_concept_id
    WHERE ca.ancestor_concept_id IN (

        /* BIGUANIDES
           Metformin (generic) | Glucophage, Glucophage XR, Glumetza,
                                  Fortamet, Riomet (brand) */
        1503297,   -- Metformin

        /* SULFONYLUREAS
           Glipizide    | Glucotrol, Glucotrol XL
           Glyburide    | DiaBeta, Glynase, Micronase
           Glimepiride  | Amaryl
           Chlorpropamide | Diabinese
           Tolbutamide  | Orinase
           Tolazamide   | Tolinase */
        1597756,   -- Glipizide
        1516766,   -- Glyburide
        1560171,   -- Glimepiride
        1594973,   -- Chlorpropamide
        1595799,   -- Tolbutamide
        1596977,   -- Tolazamide

        /* THIAZOLIDINEDIONES (TZDs)
           Pioglitazone  | Actos
           Rosiglitazone | Avandia */
        1525215,   -- Pioglitazone
        1598003,   -- Rosiglitazone

        /* DPP-4 INHIBITORS
           Sitagliptin  | Januvia
           Saxagliptin  | Onglyza
           Linagliptin  | Tradjenta
           Alogliptin   | Nesina
           Vildagliptin | Galvus (approved outside US) */
        1580747,   -- Sitagliptin
        1583722,   -- Saxagliptin
        40166035,  -- Linagliptin
        43013884,  -- Alogliptin
        1512515,   -- Vildagliptin

        /* SGLT-2 INHIBITORS
           Canagliflozin  | Invokana
           Dapagliflozin  | Farxiga, Forxiga
           Empagliflozin  | Jardiance
           Ertugliflozin  | Steglatro */
        43526465,  -- Canagliflozin
        44816332,  -- Dapagliflozin
        44785829,  -- Empagliflozin
        792484,    -- Ertugliflozin

        /* GLP-1 RECEPTOR AGONISTS
           Exenatide    | Byetta, Bydureon
           Liraglutide  | Victoza (T2DM), Saxenda (obesity)
           Dulaglutide  | Trulicity
           Semaglutide  | Ozempic (inject), Rybelsus (oral), Wegovy (obesity)
           Albiglutide  | Tanzeum (discontinued)
           Lixisenatide | Adlyxin
           Tirzepatide  | Mounjaro (GIP/GLP-1 dual agonist) */
        1544838,   -- Exenatide
        40170911,  -- Liraglutide
        44507700,  -- Dulaglutide
        2200644,   -- Semaglutide
        45892894,  -- Albiglutide
        45892867,  -- Lixisenatide
        702776,    -- Tirzepatide

        /* MEGLITINIDES
           Repaglinide | Prandin
           Nateglinide | Starlix */
        1549686,   -- Repaglinide
        1550557,   -- Nateglinide

        /* ALPHA-GLUCOSIDASE INHIBITORS
           Acarbose | Precose
           Miglitol | Glyset */
        1510202,   -- Acarbose
        1547504,   -- Miglitol

        /* AMYLIN ANALOGUE
           Pramlintide | Symlin */
        40170920   -- Pramlintide

        /* NOTE: Insulin is intentionally excluded from the inclusion list.
                 Insulin is used in both T1DM and T2DM and by itself does
                 not distinguish between the two. It is permissible as
                 supportive evidence only when co-occurring with a T2DM
                 diagnosis or one of the above T2DM-specific agents. */
    )
) med ON p.person_id = med.person_id

/* ── EXCLUDE patients with competing diagnoses ── */
WHERE p.person_id NOT IN (

    SELECT DISTINCT co.person_id
    FROM condition_occurrence co
    WHERE

        /* Type 1 Diabetes Mellitus
           OMOP SNOMED ancestor 201254 = Type 1 diabetes mellitus
           ICD-9-CM: odd 5th digit = Type 1 DM
           ICD-10-CM: E10.x */
        co.condition_concept_id IN (
            SELECT descendant_concept_id
            FROM concept_ancestor
            WHERE ancestor_concept_id = 201254   -- Type 1 diabetes mellitus (SNOMED)
        )
        OR co.condition_source_value IN (
            '250.01','250.03',
            '250.11','250.13',
            '250.21','250.23',
            '250.31','250.33',
            '250.41','250.43',
            '250.51','250.53',
            '250.61','250.63',
            '250.71','250.73',
            '250.81','250.83',
            '250.91','250.93'
        )
        OR co.condition_source_value LIKE 'E10%'

        OR

        /* Gestational Diabetes
           OMOP SNOMED 4024659 = Gestational diabetes mellitus
           ICD-9-CM: 648.0x
           ICD-10-CM: O24.4x */
        co.condition_concept_id IN (
            SELECT descendant_concept_id
            FROM concept_ancestor
            WHERE ancestor_concept_id = 4024659   -- Gestational diabetes mellitus (SNOMED)
        )
        OR co.condition_source_value IN (
            '648.00','648.01','648.02','648.03','648.04'
        )
        OR co.condition_source_value LIKE 'O24.4%'

        OR

        /* Secondary / Drug-induced / Other Specified Diabetes
           ICD-9-CM: 249.xx (secondary DM)
           ICD-10-CM: E08.x (DM due to underlying condition)
                      E09.x (drug/chemical-induced DM)
                      E13.x (other specified DM) */
        co.condition_source_value LIKE '249%'
        OR co.condition_source_value LIKE 'E08%'
        OR co.condition_source_value LIKE 'E09%'
        OR co.condition_source_value LIKE 'E13%'

        OR

        /* Neonatal Diabetes Mellitus
           ICD-10-CM: P70.2 */
        co.condition_source_value LIKE 'P70.2%'
)

/* ── EXCLUDE patients under age 18 at time of query
      (pediatric T2DM phenotyping requires separate algorithm;
       early-onset DM in children is more likely T1DM or MODY) ── */
AND (EXTRACT(YEAR FROM CURRENT_DATE) - p.year_of_birth) >= 18

/* ── APPLY INCLUSION CRITERIA ── */
/* Any one of the following four evidence combinations is sufficient:
     1. ≥2 T2DM diagnoses on separate dates
     2. ≥1 T2DM diagnosis AND ≥1 T2DM-specific medication
     3. ≥1 T2DM diagnosis AND ≥1 confirmatory lab result
     4. ≥1 T2DM-specific medication AND ≥1 confirmatory lab result      */
AND (
      (dx.person_id IS NOT NULL AND dx.dx_count >= 2)
   OR (dx.person_id IS NOT NULL AND med.person_id IS NOT NULL)
   OR (dx.person_id IS NOT NULL AND lab.person_id IS NOT NULL)
   OR (med.person_id IS NOT NULL AND lab.person_id IS NOT NULL)
)

GROUP BY
    p.person_id,
    p.year_of_birth,
    p.gender_concept_id,
    p.race_concept_id,
    dx.person_id,
    dx.dx_count,
    lab.person_id,
    med.person_id

ORDER BY p.person_id;