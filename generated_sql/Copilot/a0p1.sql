--error
WITH

-- 1. Concept sets (replace with your own concept_id lists or concept set tables)
t2dm_dx_concepts AS (
    SELECT concept_id
    FROM concept
    WHERE (
        -- ICD9CM 250.x0, 250.x2 mapped to standard concepts
        concept_code LIKE '250%' AND vocabulary_id = 'ICD9CM'
        AND SUBSTRING(concept_code, 5, 1) IN ('0','2')
    )
    OR (
        -- ICD10CM E11.* mapped to standard concepts
        concept_code LIKE 'E11%' AND vocabulary_id = 'ICD10CM'
    )
),

t1dm_dx_concepts AS (
    SELECT concept_id
    FROM concept
    WHERE (
        -- ICD9CM 250.x1, 250.x3
        concept_code LIKE '250%' AND vocabulary_id = 'ICD9CM'
        AND SUBSTRING(concept_code, 5, 1) IN ('1','3')
    )
    OR (
        -- ICD10CM E10.*
        concept_code LIKE 'E10%' AND vocabulary_id = 'ICD10CM'
    )
),

gest_dm_dx_concepts AS (
    SELECT concept_id
    FROM concept
    WHERE (
        vocabulary_id = 'ICD9CM' AND concept_code LIKE '6488%'
    )
    OR (
        vocabulary_id = 'ICD10CM' AND concept_code LIKE 'O24.4%'
    )
),

secondary_dm_dx_concepts AS (
    SELECT concept_id
    FROM concept
    WHERE vocabulary_id = 'ICD10CM'
      AND concept_code LIKE 'E0[89]%'  -- E08.*, E09.*
    UNION ALL
    SELECT concept_id
    FROM concept
    WHERE vocabulary_id = 'ICD10CM'
      AND concept_code LIKE 'E13%'     -- E13.*
),

-- Non–insulin glucose-lowering drugs (RxNorm standard concepts)
non_insulin_dm_drug_concepts AS (
    SELECT concept_id
    FROM concept
    WHERE vocabulary_id = 'RxNorm'
      AND (
          -- Biguanides
          concept_name ILIKE '%metformin%'
          -- Sulfonylureas
          OR concept_name ILIKE '%glipizide%'
          OR concept_name ILIKE '%glyburide%'
          OR concept_name ILIKE '%glimepiride%'
          -- Thiazolidinediones
          OR concept_name ILIKE '%pioglitazone%'
          OR concept_name ILIKE '%rosiglitazone%'
          -- DPP-4 inhibitors
          OR concept_name ILIKE '%sitagliptin%'
          OR concept_name ILIKE '%saxagliptin%'
          OR concept_name ILIKE '%linagliptin%'
          OR concept_name ILIKE '%alogliptin%'
          -- GLP-1 receptor agonists
          OR concept_name ILIKE '%exenatide%'
          OR concept_name ILIKE '%liraglutide%'
          OR concept_name ILIKE '%dulaglutide%'
          OR concept_name ILIKE '%semaglutide%'
          OR concept_name ILIKE '%lixisenatide%'
          -- SGLT2 inhibitors
          OR concept_name ILIKE '%canagliflozin%'
          OR concept_name ILIKE '%dapagliflozin%'
          OR concept_name ILIKE '%empagliflozin%'
          OR concept_name ILIKE '%ertugliflozin%'
          -- Meglitinides
          OR concept_name ILIKE '%repaglinide%'
          OR concept_name ILIKE '%nateglinide%'
          -- Alpha-glucosidase inhibitors
          OR concept_name ILIKE '%acarbose%'
          OR concept_name ILIKE '%miglitol%'
      )
),

-- Insulin (optional, supportive)
insulin_drug_concepts AS (
    SELECT concept_id
    FROM concept
    WHERE vocabulary_id = 'RxNorm'
      AND (
          concept_name ILIKE '%insulin%'
      )
),

-- Diabetes-defining labs (HbA1c, FPG, OGTT, random glucose)
dm_lab_concepts AS (
    SELECT concept_id, 'HBA1C' AS lab_type
    FROM concept
    WHERE vocabulary_id = 'LOINC'
      AND concept_code IN ('4548-4','17856-6','41995-2','59261-8') -- example HbA1c codes
    UNION ALL
    SELECT concept_id, 'FPG' AS lab_type
    FROM concept
    WHERE vocabulary_id = 'LOINC'
      AND concept_code IN ('1558-6','14771-0') -- example fasting glucose
    UNION ALL
    SELECT concept_id, 'OGTT' AS lab_type
    FROM concept
    WHERE vocabulary_id = 'LOINC'
      AND concept_code IN ('20436-2','14779-1') -- example 2h OGTT
    UNION ALL
    SELECT concept_id, 'RPG' AS lab_type
    FROM concept
    WHERE vocabulary_id = 'LOINC'
      AND concept_code IN ('2339-0','2345-7') -- example random glucose
),

-- 2. Evidence counts per person

t2dm_dx AS (
    SELECT
        co.person_id,
        MIN(co.condition_start_date) AS first_t2dm_dx_date,
        COUNT(DISTINCT co.condition_start_date) AS t2dm_dx_distinct_dates
    FROM condition_occurrence co
    JOIN t2dm_dx_concepts c
      ON co.condition_concept_id = c.concept_id
    GROUP BY co.person_id
),

t1dm_dx AS (
    SELECT DISTINCT person_id
    FROM condition_occurrence co
    JOIN t1dm_dx_concepts c
      ON co.condition_concept_id = c.concept_id
),

gest_dm_dx AS (
    SELECT DISTINCT person_id
    FROM condition_occurrence co
    JOIN gest_dm_dx_concepts c
      ON co.condition_concept_id = c.concept_id
),

secondary_dm_dx AS (
    SELECT DISTINCT person_id
    FROM condition_occurrence co
    JOIN secondary_dm_dx_concepts c
      ON co.condition_concept_id = c.concept_id
),

non_insulin_dm_drug AS (
    SELECT
        de.person_id,
        MIN(de.drug_exposure_start_date) AS first_non_insulin_dm_drug_date,
        COUNT(*) AS non_insulin_dm_drug_count
    FROM drug_exposure de
    JOIN non_insulin_dm_drug_concepts c
      ON de.drug_concept_id = c.concept_id
    GROUP BY de.person_id
),

dm_labs AS (
    SELECT
        m.person_id,
        MIN(m.measurement_date) AS first_abnormal_dm_lab_date,
        COUNT(DISTINCT m.measurement_date) AS abnormal_dm_lab_distinct_dates
    FROM measurement m
    JOIN dm_lab_concepts c
      ON m.measurement_concept_id = c.concept_id
    WHERE
        (
            c.lab_type = 'HBA1C' AND m.value_as_number >= 6.5
        )
        OR (
            c.lab_type = 'FPG' AND m.value_as_number >= 126
        )
        OR (
            c.lab_type = 'OGTT' AND m.value_as_number >= 200
        )
        OR (
            c.lab_type = 'RPG' AND m.value_as_number >= 200
        )
    GROUP BY m.person_id
),

-- 3. Combine evidence into inclusion candidates

candidate_t2dm AS (
    SELECT
        p.person_id,
        -- Evidence flags
        COALESCE(t2.t2dm_dx_distinct_dates, 0) AS t2dm_dx_dates,
        COALESCE(nid.non_insulin_dm_drug_count, 0) AS non_insulin_dm_drug_count,
        COALESCE(dl.abnormal_dm_lab_distinct_dates, 0) AS abnormal_dm_lab_dates,
        -- Index date: earliest of any qualifying event
        MIN(
            LEAST(
                COALESCE(t2.first_t2dm_dx_date, DATE '9999-12-31'),
                COALESCE(nid.first_non_insulin_dm_drug_date, DATE '9999-12-31'),
                COALESCE(dl.first_abnormal_dm_lab_date, DATE '9999-12-31')
            )
        ) AS index_date
    FROM person p
    LEFT JOIN t2dm_dx t2
      ON p.person_id = t2.person_id
    LEFT JOIN non_insulin_dm_drug nid
      ON p.person_id = nid.person_id
    LEFT JOIN dm_labs dl
      ON p.person_id = dl.person_id
    GROUP BY
        p.person_id,
        t2.t2dm_dx_distinct_dates,
        nid.non_insulin_dm_drug_count,
        dl.abnormal_dm_lab_distinct_dates
),

-- 4. Apply inclusion logic (AND/OR)

included_t2dm AS (
    SELECT
        c.*
    FROM candidate_t2dm c
    WHERE
        (
            -- Criterion 1: ≥2 T2DM diagnosis dates
            c.t2dm_dx_dates >= 2
            OR
            -- Criterion 2: ≥1 T2DM dx AND ≥1 non–insulin DM drug
            (c.t2dm_dx_dates >= 1 AND c.non_insulin_dm_drug_count >= 1)
            OR
            -- Criterion 3: ≥1 non–insulin DM drug AND ≥1 abnormal lab
            (c.non_insulin_dm_drug_count >= 1 AND c.abnormal_dm_lab_dates >= 1)
            OR
            -- Criterion 4: ≥2 abnormal labs
            (c.abnormal_dm_lab_dates >= 2)
        )
),

-- 5. Apply exclusions (NOT)

excluded_persons AS (
    SELECT person_id FROM t1dm_dx
    UNION
    SELECT person_id FROM gest_dm_dx
    UNION
    SELECT person_id FROM secondary_dm_dx
),

final_t2dm_cohort AS (
    SELECT
        i.person_id,
        i.index_date
    FROM included_t2dm i
    LEFT JOIN excluded_persons e
      ON i.person_id = e.person_id
    WHERE
        e.person_id IS NULL  -- NOT (Type 1 OR Gestational OR Secondary)
)

-- 6. Age restriction at index date

SELECT
    f.person_id,
    f.index_date
FROM final_t2dm_cohort f
JOIN person p
  ON f.person_id = p.person_id
WHERE
    -- Age >= 18 at index date
    DATEDIFF('year', p.birth_datetime, f.index_date) >= 18
;
