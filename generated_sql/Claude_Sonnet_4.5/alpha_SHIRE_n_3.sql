-- =====================================================
-- Type 2 Diabetes Phenotyping Algorithm
-- Based on OMOP CDM v5.x
-- SHIRE-ready adaptation
-- =====================================================

WITH

t2dm_diagnosis AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date AS event_date,
        co.condition_source_value AS concept_name,
        'Diagnosis' AS criterion_type
    FROM memory.condition_occurrence co
    WHERE
        co.condition_source_value IN (
            'E11', 'E11.0', 'E11.00', 'E11.01', 'E11.1', 'E11.10', 'E11.11',
            'E11.2', 'E11.21', 'E11.22', 'E11.29',
            'E11.3', 'E11.31', 'E11.32', 'E11.33', 'E11.34', 'E11.35', 'E11.36', 'E11.39',
            'E11.4', 'E11.40', 'E11.41', 'E11.42', 'E11.43', 'E11.44', 'E11.49',
            'E11.5', 'E11.51', 'E11.52', 'E11.59',
            'E11.6', 'E11.61', 'E11.62', 'E11.63', 'E11.64', 'E11.65', 'E11.69',
            'E11.8', 'E11.9'
        )
        OR co.condition_source_value IN (
            '250.00', '250.02', '250.10', '250.12', '250.20', '250.22',
            '250.30', '250.32', '250.40', '250.42', '250.50', '250.52',
            '250.60', '250.62', '250.70', '250.72', '250.80', '250.82',
            '250.90', '250.92'
        )
),

exclusion_diagnosis AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date AS event_date,
        'Exclusion' AS criterion_type
    FROM memory.condition_occurrence co
    WHERE
        co.condition_source_value LIKE 'E10%'
        OR co.condition_source_value LIKE 'O24%'
        OR co.condition_source_value LIKE 'E08%'
        OR co.condition_source_value LIKE 'E09%'
        OR co.condition_source_value LIKE 'E13%'
        OR co.condition_source_value IN (
            '250.01', '250.03', '250.11', '250.13', '250.21', '250.23',
            '250.31', '250.33', '250.41', '250.43', '250.51', '250.53',
            '250.61', '250.63', '250.71', '250.73', '250.81', '250.83',
            '250.91', '250.93',
            '648.8', '648.80', '648.81', '648.82', '648.83', '648.84'
        )
),

t2dm_medications AS (
    SELECT DISTINCT
        de.person_id,
        de.drug_exposure_start_date AS event_date,
        de.drug_source_value AS concept_name,
        'Medication' AS criterion_type
    FROM memory.drug_exposure de
    WHERE
        de.drug_source_value ILIKE '%metformin%'
        OR de.drug_source_value ILIKE '%glucophage%'
        OR de.drug_source_value ILIKE '%glyburide%'
        OR de.drug_source_value ILIKE '%glipizide%'
        OR de.drug_source_value ILIKE '%glimepiride%'
        OR de.drug_source_value ILIKE '%pioglitazone%'
        OR de.drug_source_value ILIKE '%actos%'
        OR de.drug_source_value ILIKE '%rosiglitazone%'
        OR de.drug_source_value ILIKE '%avandia%'
        OR de.drug_source_value ILIKE '%sitagliptin%'
        OR de.drug_source_value ILIKE '%januvia%'
        OR de.drug_source_value ILIKE '%saxagliptin%'
        OR de.drug_source_value ILIKE '%onglyza%'
        OR de.drug_source_value ILIKE '%linagliptin%'
        OR de.drug_source_value ILIKE '%tradjenta%'
        OR de.drug_source_value ILIKE '%exenatide%'
        OR de.drug_source_value ILIKE '%byetta%'
        OR de.drug_source_value ILIKE '%bydureon%'
        OR de.drug_source_value ILIKE '%liraglutide%'
        OR de.drug_source_value ILIKE '%victoza%'
        OR de.drug_source_value ILIKE '%dulaglutide%'
        OR de.drug_source_value ILIKE '%trulicity%'
        OR de.drug_source_value ILIKE '%semaglutide%'
        OR de.drug_source_value ILIKE '%ozempic%'
        OR de.drug_source_value ILIKE '%rybelsus%'
        OR de.drug_source_value ILIKE '%canagliflozin%'
        OR de.drug_source_value ILIKE '%invokana%'
        OR de.drug_source_value ILIKE '%dapagliflozin%'
        OR de.drug_source_value ILIKE '%farxiga%'
        OR de.drug_source_value ILIKE '%empagliflozin%'
        OR de.drug_source_value ILIKE '%jardiance%'
        OR de.drug_source_value ILIKE '%acarbose%'
        OR de.drug_source_value ILIKE '%precose%'
),

t2dm_labs AS (
    SELECT DISTINCT
        m.person_id,
        m.measurement_date AS event_date,
        m.measurement_source_value AS concept_name,
        m.value_as_number,
        m.unit_source_value AS unit_concept_id,
        'Laboratory' AS criterion_type
    FROM memory.measurement m
    WHERE (
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
        AND m.value_as_number >= 200
    )
),

all_criteria AS (
    SELECT person_id, event_date, criterion_type FROM t2dm_diagnosis
    UNION ALL
    SELECT person_id, event_date, criterion_type FROM t2dm_medications
    UNION ALL
    SELECT person_id, event_date, criterion_type FROM t2dm_labs
),

criteria_counts AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS num_events,
        COUNT(DISTINCT criterion_type) AS num_criteria_types,
        MIN(event_date) AS first_event_date,
        MAX(event_date) AS last_event_date
    FROM all_criteria
    GROUP BY person_id
),

t2dm_cohort AS (
    SELECT
        cc.person_id,
        cc.first_event_date AS index_date,
        cc.num_events,
        cc.num_criteria_types,
        p.birth_datetime,
        EXTRACT(YEAR FROM cc.first_event_date) - p.year_of_birth AS age_at_index
    FROM criteria_counts cc
    INNER JOIN memory.person p ON cc.person_id = p.person_id
    WHERE (
        cc.num_events >= 2
        OR cc.num_criteria_types >= 2
    )
    AND NOT EXISTS (
        SELECT 1
        FROM exclusion_diagnosis ed
        WHERE ed.person_id = cc.person_id
          AND ed.event_date <= cc.last_event_date
    )
)

SELECT
    tc.person_id,
    tc.index_date,
    tc.age_at_index,
    tc.num_events AS supporting_events,
    tc.num_criteria_types AS supporting_criteria_types,
    p.gender_concept_id,
    CAST(NULL AS VARCHAR) AS gender,
    p.race_concept_id,
    CAST(NULL AS VARCHAR) AS race,
    p.ethnicity_concept_id,
    CAST(NULL AS VARCHAR) AS ethnicity
FROM t2dm_cohort tc
INNER JOIN memory.person p ON tc.person_id = p.person_id
ORDER BY tc.person_id;
