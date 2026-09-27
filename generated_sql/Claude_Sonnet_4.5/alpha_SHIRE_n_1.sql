-- =====================================================
-- TYPE 2 DIABETES PHENOTYPING ALGORITHM
-- SHIRE-ready adaptation
-- Schema: memory
-- =====================================================

-- Step 1: Identify patients with T2DM diagnosis codes
WITH t2dm_diagnosis AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date,
        co.condition_source_value AS concept_name,
        'DIAGNOSIS' AS criterion_type
    FROM memory.condition_occurrence co
    WHERE (
        co.condition_source_value LIKE 'E11%'
        OR co.condition_source_value IN (
            '250.00', '250.02', '250.10', '250.12',
            '250.20', '250.22', '250.30', '250.32',
            '250.40', '250.42', '250.50', '250.52',
            '250.60', '250.62', '250.70', '250.72',
            '250.80', '250.82', '250.90', '250.92'
        )
    )
    AND co.condition_start_date IS NOT NULL
),

-- Step 2: Identify patients with T2DM-related laboratory values
t2dm_lab AS (
    SELECT DISTINCT
        m.person_id,
        m.measurement_date,
        m.measurement_source_value AS concept_name,
        m.value_as_number,
        m.unit_source_value AS unit_concept_id,
        'LABORATORY' AS criterion_type
    FROM memory.measurement m
    WHERE (
        (
            (
                m.measurement_source_value ILIKE '%a1c%'
                OR m.measurement_source_value ILIKE '%hba1c%'
                OR m.measurement_source_value ILIKE '%hemoglobin a1c%'
                OR m.measurement_source_value ILIKE '%glycohemoglobin%'
            )
            AND m.value_as_number >= 6.5
        )
        OR (
            (
                m.measurement_source_value ILIKE '%fasting glucose%'
                OR m.measurement_source_value ILIKE '%fasting blood glucose%'
            )
            AND m.value_as_number >= 126
        )
        OR (
            m.measurement_source_value ILIKE '%glucose%'
            AND m.measurement_source_value NOT ILIKE '%fasting%'
            AND m.value_as_number >= 200
        )
    )
    AND m.measurement_date IS NOT NULL
),

-- Step 3: Identify patients with T2DM medications
t2dm_medications AS (
    SELECT DISTINCT
        de.person_id,
        de.drug_exposure_start_date,
        de.drug_source_value AS concept_name,
        de.drug_source_value,
        'MEDICATION' AS criterion_type
    FROM memory.drug_exposure de
    WHERE (
        de.drug_source_value ILIKE '%metformin%'
        OR de.drug_source_value ILIKE '%glucophage%'
        OR de.drug_source_value ILIKE '%fortamet%'
        OR de.drug_source_value ILIKE '%glumetza%'
        OR de.drug_source_value ILIKE '%riomet%'
        OR de.drug_source_value ILIKE '%glyburide%'
        OR de.drug_source_value ILIKE '%glipizide%'
        OR de.drug_source_value ILIKE '%glimepiride%'
        OR de.drug_source_value ILIKE '%diabeta%'
        OR de.drug_source_value ILIKE '%glucotrol%'
        OR de.drug_source_value ILIKE '%amaryl%'
        OR de.drug_source_value ILIKE '%sitagliptin%'
        OR de.drug_source_value ILIKE '%saxagliptin%'
        OR de.drug_source_value ILIKE '%linagliptin%'
        OR de.drug_source_value ILIKE '%alogliptin%'
        OR de.drug_source_value ILIKE '%januvia%'
        OR de.drug_source_value ILIKE '%onglyza%'
        OR de.drug_source_value ILIKE '%tradjenta%'
        OR de.drug_source_value ILIKE '%nesina%'
        OR de.drug_source_value ILIKE '%exenatide%'
        OR de.drug_source_value ILIKE '%liraglutide%'
        OR de.drug_source_value ILIKE '%dulaglutide%'
        OR de.drug_source_value ILIKE '%semaglutide%'
        OR de.drug_source_value ILIKE '%byetta%'
        OR de.drug_source_value ILIKE '%victoza%'
        OR de.drug_source_value ILIKE '%trulicity%'
        OR de.drug_source_value ILIKE '%ozempic%'
        OR de.drug_source_value ILIKE '%rybelsus%'
        OR de.drug_source_value ILIKE '%canagliflozin%'
        OR de.drug_source_value ILIKE '%dapagliflozin%'
        OR de.drug_source_value ILIKE '%empagliflozin%'
        OR de.drug_source_value ILIKE '%ertugliflozin%'
        OR de.drug_source_value ILIKE '%invokana%'
        OR de.drug_source_value ILIKE '%farxiga%'
        OR de.drug_source_value ILIKE '%jardiance%'
        OR de.drug_source_value ILIKE '%steglatro%'
        OR de.drug_source_value ILIKE '%pioglitazone%'
        OR de.drug_source_value ILIKE '%rosiglitazone%'
        OR de.drug_source_value ILIKE '%actos%'
        OR de.drug_source_value ILIKE '%avandia%'
        OR de.drug_source_value ILIKE '%repaglinide%'
        OR de.drug_source_value ILIKE '%nateglinide%'
        OR de.drug_source_value ILIKE '%prandin%'
        OR de.drug_source_value ILIKE '%starlix%'
        OR de.drug_source_value ILIKE '%insulin glargine%'
        OR de.drug_source_value ILIKE '%insulin detemir%'
        OR de.drug_source_value ILIKE '%insulin nph%'
        OR de.drug_source_value ILIKE '%lantus%'
        OR de.drug_source_value ILIKE '%levemir%'
        OR de.drug_source_value ILIKE '%basaglar%'
        OR de.drug_source_value ILIKE '%toujeo%'
        OR de.drug_source_value ILIKE '%tresiba%'
    )
    AND de.drug_exposure_start_date IS NOT NULL
    AND de.person_id IN (
        SELECT DISTINCT person_id
        FROM memory.drug_exposure de2
        WHERE
            de2.drug_source_value ILIKE '%metformin%'
            OR de2.drug_source_value ILIKE '%glyburide%'
            OR de2.drug_source_value ILIKE '%glipizide%'
            OR de2.drug_source_value ILIKE '%glimepiride%'
            OR de2.drug_source_value ILIKE '%sitagliptin%'
            OR de2.drug_source_value ILIKE '%saxagliptin%'
            OR de2.drug_source_value ILIKE '%linagliptin%'
            OR de2.drug_source_value ILIKE '%alogliptin%'
            OR de2.drug_source_value ILIKE '%canagliflozin%'
            OR de2.drug_source_value ILIKE '%dapagliflozin%'
            OR de2.drug_source_value ILIKE '%empagliflozin%'
            OR de2.drug_source_value ILIKE '%ertugliflozin%'
            OR de2.drug_source_value ILIKE '%pioglitazone%'
            OR de2.drug_source_value ILIKE '%rosiglitazone%'
    )
),

-- Step 4: Exclusion - Type 1 Diabetes
exclusion_t1dm AS (
    SELECT DISTINCT
        co.person_id,
        'T1DM_EXCLUSION' AS exclusion_type
    FROM memory.condition_occurrence co
    WHERE (
        co.condition_source_value LIKE 'E10%'
        OR co.condition_source_value IN (
            '250.01', '250.03', '250.11', '250.13',
            '250.21', '250.23', '250.31', '250.33',
            '250.41', '250.43', '250.51', '250.53',
            '250.61', '250.63', '250.71', '250.73',
            '250.81', '250.83', '250.91', '250.93'
        )
    )
),

-- Step 5: Exclusion - Gestational Diabetes
exclusion_gestational AS (
    SELECT DISTINCT
        co.person_id,
        'GESTATIONAL_EXCLUSION' AS exclusion_type
    FROM memory.condition_occurrence co
    WHERE (
        co.condition_source_value LIKE 'O24%'
        OR co.condition_source_value IN ('648.8', '648.80', '648.81', '648.82', '648.83', '648.84')
    )
),

-- Step 6: Exclusion - Secondary Diabetes
exclusion_secondary AS (
    SELECT DISTINCT
        co.person_id,
        'SECONDARY_EXCLUSION' AS exclusion_type
    FROM memory.condition_occurrence co
    WHERE (
        co.condition_source_value LIKE 'E08%'
        OR co.condition_source_value LIKE 'E09%'
    )
),

-- Step 7: Combine all T2DM evidence
all_t2dm_evidence AS (
    SELECT person_id, condition_start_date AS event_date, criterion_type FROM t2dm_diagnosis
    UNION ALL
    SELECT person_id, measurement_date AS event_date, criterion_type FROM t2dm_lab
    UNION ALL
    SELECT person_id, drug_exposure_start_date AS event_date, criterion_type FROM t2dm_medications
),

-- Step 8: Calculate evidence strength per person
evidence_summary AS (
    SELECT
        person_id,
        MIN(event_date) AS first_t2dm_date,
        MAX(event_date) AS last_t2dm_date,
        COUNT(DISTINCT criterion_type) AS num_criterion_types,
        COUNT(DISTINCT event_date) AS num_occurrences,
        STRING_AGG(DISTINCT criterion_type, ', ') AS criterion_types
    FROM all_t2dm_evidence
    GROUP BY person_id
    HAVING COUNT(DISTINCT criterion_type) >= 2
       AND COUNT(DISTINCT event_date) >= 2
),

-- Step 9: Apply observation period requirement using visit_occurrence
visit_observation AS (
    SELECT
        person_id,
        MIN(visit_start_date) AS observation_period_start_date,
        MAX(COALESCE(visit_end_date, visit_start_date)) AS observation_period_end_date
    FROM memory.visit_occurrence
    GROUP BY person_id
),

valid_observation AS (
    SELECT
        es.*,
        vo.observation_period_start_date,
        vo.observation_period_end_date,
        date_diff('day', vo.observation_period_start_date, vo.observation_period_end_date) AS obs_days
    FROM evidence_summary es
    INNER JOIN visit_observation vo ON es.person_id = vo.person_id
    WHERE es.first_t2dm_date >= vo.observation_period_start_date
      AND es.first_t2dm_date <= vo.observation_period_end_date
      AND date_diff('day', vo.observation_period_start_date, vo.observation_period_end_date) >= 365
),

-- Step 10: Final T2DM Cohort (with exclusions applied)
final_t2dm_cohort AS (
    SELECT
        vo.person_id,
        vo.first_t2dm_date AS index_date,
        vo.last_t2dm_date,
        vo.num_criterion_types,
        vo.num_occurrences,
        vo.criterion_types,
        vo.obs_days,
        p.gender_concept_id,
        p.year_of_birth,
        EXTRACT(YEAR FROM vo.first_t2dm_date) - p.year_of_birth AS age_at_diagnosis,
        CASE WHEN e1.person_id IS NOT NULL THEN 1 ELSE 0 END AS has_t1dm_exclusion,
        CASE WHEN e2.person_id IS NOT NULL THEN 1 ELSE 0 END AS has_gestational_exclusion,
        CASE WHEN e3.person_id IS NOT NULL THEN 1 ELSE 0 END AS has_secondary_exclusion
    FROM valid_observation vo
    INNER JOIN memory.person p ON vo.person_id = p.person_id
    LEFT JOIN exclusion_t1dm e1 ON vo.person_id = e1.person_id
    LEFT JOIN exclusion_gestational e2 ON vo.person_id = e2.person_id
    LEFT JOIN exclusion_secondary e3 ON vo.person_id = e3.person_id
    WHERE e1.person_id IS NULL
      AND e2.person_id IS NULL
      AND e3.person_id IS NULL
      AND (EXTRACT(YEAR FROM vo.first_t2dm_date) - p.year_of_birth) >= 18
)

SELECT
    person_id,
    index_date,
    last_t2dm_date,
    age_at_diagnosis,
    gender_concept_id,
    num_criterion_types,
    num_occurrences,
    criterion_types,
    obs_days AS observation_days
FROM final_t2dm_cohort
ORDER BY person_id;
