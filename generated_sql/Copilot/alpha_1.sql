
-- ============================================
-- TYPE 2 DIABETES PHENOTYPE (OMOP CDM, PUBLIC)
-- ============================================

WITH

-- --------------------------------------------
-- 1. Concept sets (diagnoses)
-- --------------------------------------------

t2dm_dx_concepts AS (
    SELECT DISTINCT c.concept_id
    FROM public.concept c
    JOIN public.concept_ancestor ca
      ON ca.descendant_concept_id = c.concept_id
    WHERE ca.ancestor_concept_id IN (
        -- TODO: insert standard T2DM condition concept_ids (e.g., SNOMED T2DM)
        -- e.g., 201826 (Type 2 diabetes mellitus) in many OMOP vocabularies
        201826
    )
      AND c.domain_id = 'Condition'
),

t1dm_dx_concepts AS (
    SELECT DISTINCT c.concept_id
    FROM public.concept c
    JOIN public.concept_ancestor ca
      ON ca.descendant_concept_id = c.concept_id
    WHERE ca.ancestor_concept_id IN (
        -- TODO: standard Type 1 DM concept_ids
        -- e.g., 201254 (Type 1 diabetes mellitus)
        201254
    )
      AND c.domain_id = 'Condition'
),

gest_dm_dx_concepts AS (
    SELECT DISTINCT c.concept_id
    FROM public.concept c
    JOIN public.concept_ancestor ca
      ON ca.descendant_concept_id = c.concept_id
    WHERE ca.ancestor_concept_id IN (
        -- TODO: standard Gestational diabetes concept_ids
        -- e.g., 4029488 (Gestational diabetes mellitus)
        4029488
    )
      AND c.domain_id = 'Condition'
),

secondary_dm_dx_concepts AS (
    SELECT DISTINCT c.concept_id
    FROM public.concept c
    JOIN public.concept_ancestor ca
      ON ca.descendant_concept_id = c.concept_id
    WHERE ca.ancestor_concept_id IN (
        -- TODO: standard Secondary diabetes concept_ids
        -- e.g., 40484648 (Secondary diabetes mellitus)
        40484648
    )
      AND c.domain_id = 'Condition'
),

-- --------------------------------------------
-- 2. Concept sets (labs)
-- --------------------------------------------

dm_lab_concepts AS (
    SELECT DISTINCT c.concept_id
    FROM public.concept c
    JOIN public.concept_ancestor ca
      ON ca.descendant_concept_id = c.concept_id
    WHERE ca.ancestor_concept_id IN (
        -- TODO: standard HbA1c, fasting glucose, OGTT ancestor concept_ids
        -- Example placeholders:
        -- HbA1c: 3004410
        -- Fasting plasma glucose: 3004501
        -- OGTT glucose: 3005673
        3004410, 3004501, 3005673
    )
      AND c.domain_id = 'Measurement'
),

-- --------------------------------------------
-- 3. Concept sets (medications)
-- --------------------------------------------

non_insulin_dm_drug_concepts AS (
    SELECT DISTINCT c.concept_id
    FROM public.concept c
    JOIN public.concept_ancestor ca
      ON ca.descendant_concept_id = c.concept_id
    WHERE ca.ancestor_concept_id IN (
        -- TODO: RxNorm ingredient concept_ids for non-insulin antihyperglycemics
        -- Examples (placeholders, not guaranteed for your vocab):
        -- Metformin (Glucophage, Glumetza)
        1503297,
        -- Sulfonylureas: glipizide (Glucotrol), glyburide (Diabeta), glimepiride (Amaryl)
        1502809, 1502826, 1502855,
        -- TZDs: pioglitazone (Actos), rosiglitazone (Avandia)
        1503298, 1503299,
        -- DPP-4 inhibitors: sitagliptin (Januvia), saxagliptin (Onglyza), linagliptin (Tradjenta)
        1580747, 1583722, 1597756,
        -- SGLT2 inhibitors: canagliflozin (Invokana), dapagliflozin (Farxiga), empagliflozin (Jardiance)
        1594973, 1597758, 1597757,
        -- GLP-1 RAs: exenatide (Byetta), liraglutide (Victoza), semaglutide (Ozempic, Rybelsus)
        1583725, 1583724, 40239216
        -- Combination products (e.g., Janumet, Xigduo, etc.) can be added similarly
    )
      AND c.domain_id = 'Drug'
),

insulin_drug_concepts AS (
    SELECT DISTINCT c.concept_id
    FROM public.concept c
    JOIN public.concept_ancestor ca
      ON ca.descendant_concept_id = c.concept_id
    WHERE ca.ancestor_concept_id IN (
        -- TODO: RxNorm ingredient concept_ids for insulin products
        -- e.g., insulin glargine, lispro, aspart, etc.
        1502905, 1502906, 1502907
    )
      AND c.domain_id = 'Drug'
),

-- --------------------------------------------
-- 4. Raw evidence tables
-- --------------------------------------------

t2dm_dx AS (
    SELECT
        co.person_id,
        co.condition_start_date,
        co.condition_concept_id
    FROM public.condition_occurrence co
    JOIN t2dm_dx_concepts t2
      ON co.condition_concept_id = t2.concept_id
),

t1dm_dx AS (
    SELECT
        co.person_id,
        co.condition_start_date,
        co.condition_concept_id
    FROM public.condition_occurrence co
    JOIN t1dm_dx_concepts t1
      ON co.condition_concept_id = t1.concept_id
),

gest_dm_dx AS (
    SELECT
        co.person_id,
        co.condition_start_date,
        co.condition_concept_id
    FROM public.condition_occurrence co
    JOIN gest_dm_dx_concepts g
      ON co.condition_concept_id = g.concept_id
),

secondary_dm_dx AS (
    SELECT
        co.person_id,
        co.condition_start_date,
        co.condition_concept_id
    FROM public.condition_occurrence co
    JOIN secondary_dm_dx_concepts s
      ON co.condition_concept_id = s.concept_id
),

dm_labs AS (
    SELECT
        m.person_id,
        m.measurement_date,
        m.measurement_concept_id,
        m.value_as_number
    FROM public.measurement m
    JOIN dm_lab_concepts dl
      ON m.measurement_concept_id = dl.concept_id
    WHERE m.value_as_number IS NOT NULL
),

non_insulin_dm_drugs AS (
    SELECT
        de.person_id,
        de.drug_exposure_start_date,
        de.drug_concept_id
    FROM public.drug_exposure de
    JOIN non_insulin_dm_drug_concepts d
      ON de.drug_concept_id = d.concept_id
),

insulin_drugs AS (
    SELECT
        de.person_id,
        de.drug_exposure_start_date,
        de.drug_concept_id
    FROM public.drug_exposure de
    JOIN insulin_drug_concepts i
      ON de.drug_concept_id = i.concept_id
),

-- --------------------------------------------
-- 5. Derived evidence flags
-- --------------------------------------------

-- Criterion A: >= 2 T2DM diagnoses on distinct dates
criterion_a AS (
    SELECT
        person_id,
        MIN(condition_start_date) AS index_date,
        COUNT(DISTINCT condition_start_date) AS dx_dates
    FROM t2dm_dx
    GROUP BY person_id
    HAVING COUNT(DISTINCT condition_start_date) >= 2
),

-- Criterion B: >= 1 T2DM diagnosis AND >= 1 non-insulin DM drug
criterion_b AS (
    SELECT
        d.person_id,
        MIN(d.condition_start_date) AS dx_date,
        MIN(n.drug_exposure_start_date) AS drug_date,
        LEAST(MIN(d.condition_start_date), MIN(n.drug_exposure_start_date)) AS index_date
    FROM t2dm_dx d
    JOIN non_insulin_dm_drugs n
      ON d.person_id = n.person_id
    GROUP BY d.person_id
),

-- Criterion C: >= 2 abnormal DM labs on distinct dates AND >= 1 non-insulin DM drug
abnormal_dm_labs AS (
    SELECT
        l.person_id,
        l.measurement_date
    FROM dm_labs l
    JOIN public.concept c
      ON l.measurement_concept_id = c.concept_id
    WHERE
        (
            -- HbA1c >= 6.5%
            c.concept_id IN (3004410) -- TODO: HbA1c concept_ids
            AND l.value_as_number >= 6.5
        )
        OR
        (
            -- Fasting plasma glucose >= 126 mg/dL
            c.concept_id IN (3004501) -- TODO: fasting glucose concept_ids
            AND l.value_as_number >= 126
        )
        OR
        (
            -- OGTT glucose >= 200 mg/dL
            c.concept_id IN (3005673) -- TODO: OGTT concept_ids
            AND l.value_as_number >= 200
        )
),

criterion_c AS (
    SELECT
        a.person_id,
        MIN(a.measurement_date) AS first_abnormal_date,
        COUNT(DISTINCT a.measurement_date) AS abnormal_dates,
        MIN(n.drug_exposure_start_date) AS drug_date,
        LEAST(MIN(a.measurement_date), MIN(n.drug_exposure_start_date)) AS index_date
    FROM abnormal_dm_labs a
    JOIN non_insulin_dm_drugs n
      ON a.person_id = n.person_id
    GROUP BY a.person_id
    HAVING COUNT(DISTINCT a.measurement_date) >= 2
),

-- --------------------------------------------
-- 6. Exclusion patterns
-- --------------------------------------------

type1_only AS (
    SELECT person_id
    FROM t1dm_dx
    GROUP BY person_id
    HAVING COUNT(*) >= 1
       AND person_id NOT IN (SELECT person_id FROM t2dm_dx)
),

gestational_only AS (
    SELECT person_id
    FROM gest_dm_dx
    GROUP BY person_id
    HAVING COUNT(*) >= 1
       AND person_id NOT IN (SELECT person_id FROM t2dm_dx)
),

secondary_only AS (
    SELECT person_id
    FROM secondary_dm_dx
    GROUP BY person_id
    HAVING COUNT(*) >= 1
       AND person_id NOT IN (SELECT person_id FROM t2dm_dx)
),

-- --------------------------------------------
-- 7. Combine criteria A, B, C
-- --------------------------------------------

combined_cases AS (
    SELECT person_id, index_date, 'A' AS criterion
    FROM criterion_a

    UNION

    SELECT person_id, index_date, 'B' AS criterion
    FROM criterion_b

    UNION

    SELECT person_id, index_date, 'C' AS criterion
    FROM criterion_c
),

-- --------------------------------------------
-- 8. Add age and observation period filters
-- --------------------------------------------

eligible_cases AS (
    SELECT
        cc.person_id,
        cc.index_date,
        cc.criterion,
        p.year_of_birth,
        (EXTRACT(YEAR FROM cc.index_date) - p.year_of_birth) AS age_at_index
    FROM combined_cases cc
    JOIN public.person p
      ON cc.person_id = p.person_id
    WHERE (EXTRACT(YEAR FROM cc.index_date) - p.year_of_birth) >= 18
),

-- Optional: require at least 365 days of observation around index
eligible_cases_with_observation AS (
    SELECT
        e.person_id,
        e.index_date,
        e.criterion,
        e.age_at_index
    FROM eligible_cases e
    JOIN public.observation_period op
      ON e.person_id = op.person_id
     AND e.index_date BETWEEN op.observation_period_start_date AND op.observation_period_end_date
     AND (op.observation_period_end_date - op.observation_period_start_date) >= 365
),

-- --------------------------------------------
-- 9. Apply exclusions (Type1-only, Gestational-only, Secondary-only)
-- --------------------------------------------

final_t2dm_cases AS (
    SELECT DISTINCT
        ec.person_id,
        ec.index_date,
        ec.criterion,
        ec.age_at_index
    FROM eligible_cases_with_observation ec
    WHERE ec.person_id NOT IN (SELECT person_id FROM type1_only)
      AND ec.person_id NOT IN (SELECT person_id FROM gestational_only)
      AND ec.person_id NOT IN (SELECT person_id FROM secondary_only)
)

-- --------------------------------------------
-- 10. Final output
-- --------------------------------------------

SELECT
    f.person_id,
    f.index_date,
    f.criterion,
    f.age_at_index
FROM final_t2dm_cases f
ORDER BY f.person_id, f.index_date;
