-- =========================================
-- Concept set CTEs (simplified placeholders)
-- =========================================

WITH

t2dm_dx_concepts AS (
    SELECT concept_id
    FROM concept
    WHERE vocabulary_id IN ('ICD9CM','ICD10CM')
      AND (
            -- ICD9CM T2DM
            concept_code IN (
                '25000','25002','25010','25012','25020','25022','25030','25032',
                '25040','25042','25050','25052','25060','25062','25070','25072',
                '25080','25082','25090','25092'
            )
            OR
            -- ICD10CM T2DM
            concept_code LIKE 'E11%'
          )
),

t1dm_dx_concepts AS (
    SELECT concept_id
    FROM concept
    WHERE vocabulary_id IN ('ICD9CM','ICD10CM')
      AND (
            -- ICD9CM Type 1
            concept_code LIKE '250%1'
            OR concept_code LIKE '250%3'
            OR
            -- ICD10CM Type 1
            concept_code LIKE 'E10%'
          )
),

gest_dm_dx_concepts AS (
    SELECT concept_id
    FROM concept
    WHERE vocabulary_id IN ('ICD9CM','ICD10CM')
      AND (
            concept_code LIKE '6480%'   -- gestational DM ICD9
            OR concept_code LIKE 'O24.4%' -- gestational DM ICD10
          )
),

secondary_dm_dx_concepts AS (
    SELECT concept_id
    FROM concept
    WHERE vocabulary_id IN ('ICD9CM','ICD10CM')
      AND (
            concept_code LIKE '249%'    -- secondary DM ICD9
            OR concept_code LIKE 'E08%' -- secondary DM ICD10
            OR concept_code LIKE 'E09%'
            OR concept_code LIKE 'E13%'
          )
),

t2dm_med_concepts AS (
    SELECT c.concept_id
    FROM concept c
    WHERE c.vocabulary_id = 'RxNorm'
      AND (
            -- Biguanides
            c.concept_name ILIKE '%metformin%'
            OR c.concept_name ILIKE '%Glucophage%'
            OR c.concept_name ILIKE '%Fortamet%'
            OR c.concept_name ILIKE '%Glumetza%'
            OR c.concept_name ILIKE '%Riomet%'

            -- Sulfonylureas
            OR c.concept_name ILIKE '%glipizide%'
            OR c.concept_name ILIKE '%Glucotrol%'
            OR c.concept_name ILIKE '%glyburide%'
            OR c.concept_name ILIKE '%Micronase%'
            OR c.concept_name ILIKE '%Diabeta%'
            OR c.concept_name ILIKE '%Glynase%'
            OR c.concept_name ILIKE '%glimepiride%'
            OR c.concept_name ILIKE '%Amaryl%'

            -- Thiazolidinediones
            OR c.concept_name ILIKE '%pioglitazone%'
            OR c.concept_name ILIKE '%Actos%'
            OR c.concept_name ILIKE '%rosiglitazone%'
            OR c.concept_name ILIKE '%Avandia%'

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
            OR c.concept_name ILIKE '%lixisenatide%'
            OR c.concept_name ILIKE '%Adlyxin%'

            -- SGLT2 inhibitors
            OR c.concept_name ILIKE '%canagliflozin%'
            OR c.concept_name ILIKE '%Invokana%'
            OR c.concept_name ILIKE '%dapagliflozin%'
            OR c.concept_name ILIKE '%Farxiga%'
            OR c.concept_name ILIKE '%empagliflozin%'
            OR c.concept_name ILIKE '%Jardiance%'
            OR c.concept_name ILIKE '%ertugliflozin%'
            OR c.concept_name ILIKE '%Steglatro%'
          )
),

dm_lab_concepts AS (
    SELECT concept_id, 'A1C' AS lab_type
    FROM concept
    WHERE vocabulary_id = 'LOINC'
      AND concept_code IN ('4548-4','17856-6','41995-2')
    UNION ALL
    SELECT concept_id, 'FPG' AS lab_type
    FROM concept
    WHERE vocabulary_id = 'LOINC'
      AND concept_code IN ('1558-6','14771-0')
    UNION ALL
    SELECT concept_id, 'RPG' AS lab_type
    FROM concept
    WHERE vocabulary_id = 'LOINC'
      AND concept_code IN ('2345-7')
),

-- =========================================
-- Evidence CTEs
-- =========================================

t2dm_dx_evidence AS (
    SELECT
        co.person_id,
        MIN(co.condition_start_date) AS first_t2dm_dx_date,
        COUNT(DISTINCT co.condition_start_date) AS t2dm_dx_dates
    FROM condition_occurrence co
    JOIN t2dm_dx_concepts t2 ON co.condition_concept_id = t2.concept_id
    GROUP BY co.person_id
),

t1dm_dx_evidence AS (
    SELECT DISTINCT co.person_id
    FROM condition_occurrence co
    JOIN t1dm_dx_concepts t1 ON co.condition_concept_id = t1.concept_id
),

gest_dm_dx_evidence AS (
    SELECT DISTINCT co.person_id
    FROM condition_occurrence co
    JOIN gest_dm_dx_concepts g ON co.condition_concept_id = g.concept_id
),

secondary_dm_dx_evidence AS (
    SELECT DISTINCT co.person_id
    FROM condition_occurrence co
    JOIN secondary_dm_dx_concepts s ON co.condition_concept_id = s.concept_id
),

t2dm_med_evidence AS (
    SELECT
        de.person_id,
        MIN(de.drug_exposure_start_date) AS first_t2dm_med_date
    FROM drug_exposure de
    JOIN t2dm_med_concepts m ON de.drug_concept_id = m.concept_id
    GROUP BY de.person_id
),

dm_lab_evidence AS (
    SELECT
        m.person_id,
        MIN(m.measurement_date) AS first_abnormal_lab_date,
        COUNT(DISTINCT m.measurement_date) AS abnormal_lab_dates
    FROM measurement m
    JOIN dm_lab_concepts dl ON m.measurement_concept_id = dl.concept_id
    WHERE
        (
            dl.lab_type = 'A1C'
            AND m.value_as_number >= 6.5
        )
        OR (
            dl.lab_type = 'FPG'
            AND m.value_as_number >= 126
        )
        OR (
            dl.lab_type = 'RPG'
            AND m.value_as_number >= 200
        )
    GROUP BY m.person_id
),

-- =========================================
-- Combine evidence and apply logic
-- =========================================

candidate_t2dm AS (
    SELECT
        p.person_id,
        p.year_of_birth,
        tdx.t2dm_dx_dates,
        tdx.first_t2dm_dx_date,
        tmed.first_t2dm_med_date,
        dlab.abnormal_lab_dates,
        dlab.first_abnormal_lab_date
    FROM person p
    LEFT JOIN t2dm_dx_evidence tdx
        ON p.person_id = tdx.person_id
    LEFT JOIN t2dm_med_evidence tmed
        ON p.person_id = tmed.person_id
    LEFT JOIN dm_lab_evidence dlab
        ON p.person_id = dlab.person_id
),

excluded_patients AS (
    SELECT DISTINCT person_id
    FROM (
        SELECT person_id FROM t1dm_dx_evidence
        UNION
        SELECT person_id FROM gest_dm_dx_evidence
        UNION
        SELECT person_id FROM secondary_dm_dx_evidence
    ) x
),

-- Final T2DM phenotype logic:
--   (A) >=2 T2DM dx dates
--   OR (B) >=1 T2DM dx AND >=1 T2DM med
--   OR (C) >=2 abnormal DM lab dates
--   AND NOT in exclusion sets
--   AND age at first qualifying event >= 18

t2dm_cases AS (
    SELECT
        c.person_id,
        COALESCE(
            c.first_t2dm_dx_date,
            c.first_t2dm_med_date,
            c.first_abnormal_lab_date
        ) AS index_date
    FROM candidate_t2dm c
    WHERE
        (
            -- Criterion A: diagnosis-based
            (c.t2dm_dx_dates IS NOT NULL AND c.t2dm_dx_dates >= 2)
            OR
            -- Criterion B: diagnosis + medication
            (c.t2dm_dx_dates IS NOT NULL AND c.t2dm_dx_dates >= 1
             AND c.first_t2dm_med_date IS NOT NULL)
            OR
            -- Criterion C: lab-based
            (c.abnormal_lab_dates IS NOT NULL AND c.abnormal_lab_dates >= 2)
        )
        AND c.person_id NOT IN (SELECT person_id FROM excluded_patients)
        AND (
            -- Age at index >= 18
            EXTRACT(YEAR FROM COALESCE(
                c.first_t2dm_dx_date,
                c.first_t2dm_med_date,
                c.first_abnormal_lab_date
            )) - c.year_of_birth >= 18
        )
)

SELECT *
FROM t2dm_cases;
