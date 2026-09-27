-- =====================================================
-- Type 2 Diabetes Phenotyping Algorithm
-- OMOP CDM v5.x Compatible
-- SHIRE-ready adaptation
-- =====================================================

WITH t2dm_diagnosis AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date,
        co.condition_source_value AS concept_code,
        co.condition_source_value AS concept_name
    FROM memory.condition_occurrence co
    WHERE (
        co.condition_source_value IN (
            'E11', 'E11.9', 'E11.0', 'E11.00', 'E11.01',
            'E11.1', 'E11.10', 'E11.11',
            'E11.2', 'E11.21', 'E11.22', 'E11.29',
            'E11.3', 'E11.31', 'E11.32', 'E11.33', 'E11.34', 'E11.35', 'E11.36', 'E11.37', 'E11.39',
            'E11.4', 'E11.40', 'E11.41', 'E11.42', 'E11.43', 'E11.44', 'E11.49',
            'E11.5', 'E11.51', 'E11.52', 'E11.59',
            'E11.6', 'E11.61', 'E11.62', 'E11.63', 'E11.64', 'E11.65', 'E11.69',
            'E11.8', 'E11.9'
        )
        OR co.condition_source_value IN (
            '250.00', '250.02',
            '250.10', '250.12',
            '250.20', '250.22',
            '250.30', '250.32',
            '250.40', '250.42',
            '250.50', '250.52',
            '250.60', '250.62',
            '250.70', '250.72',
            '250.80', '250.82',
            '250.90', '250.92'
        )
    )
),

exclusion_diagnosis AS (
    SELECT DISTINCT
        co.person_id
    FROM memory.condition_occurrence co
    WHERE (
        co.condition_source_value LIKE 'E10%'
        OR co.condition_source_value IN (
            '250.01', '250.03', '250.11', '250.13', '250.21', '250.23',
            '250.31', '250.33', '250.41', '250.43', '250.51', '250.53',
            '250.61', '250.63', '250.71', '250.73', '250.81', '250.83',
            '250.91', '250.93'
        )
        OR co.condition_source_value IN ('O24.4', 'O24.41', 'O24.42', 'O24.43', 'O24.419', 'O24.429', 'O24.439', '648.8')
        OR co.condition_source_value LIKE 'E08%'
        OR co.condition_source_value LIKE 'E09%'
        OR co.condition_source_value LIKE 'E13%'
    )
),

t2dm_medications AS (
    SELECT DISTINCT
        de.person_id,
        de.drug_exposure_start_date,
        de.drug_source_value AS concept_name
    FROM memory.drug_exposure de
    WHERE
        de.drug_source_value ILIKE '%metformin%' OR de.drug_source_value ILIKE '%glucophage%' OR de.drug_source_value ILIKE '%fortamet%' OR de.drug_source_value ILIKE '%glumetza%' OR
        de.drug_source_value ILIKE '%glipizide%' OR de.drug_source_value ILIKE '%glucotrol%' OR
        de.drug_source_value ILIKE '%glyburide%' OR de.drug_source_value ILIKE '%diabeta%' OR de.drug_source_value ILIKE '%glynase%' OR de.drug_source_value ILIKE '%micronase%' OR
        de.drug_source_value ILIKE '%glimepiride%' OR de.drug_source_value ILIKE '%amaryl%' OR
        de.drug_source_value ILIKE '%sitagliptin%' OR de.drug_source_value ILIKE '%januvia%' OR
        de.drug_source_value ILIKE '%saxagliptin%' OR de.drug_source_value ILIKE '%onglyza%' OR
        de.drug_source_value ILIKE '%linagliptin%' OR de.drug_source_value ILIKE '%tradjenta%' OR
        de.drug_source_value ILIKE '%alogliptin%' OR de.drug_source_value ILIKE '%nesina%' OR
        de.drug_source_value ILIKE '%exenatide%' OR de.drug_source_value ILIKE '%byetta%' OR de.drug_source_value ILIKE '%bydureon%' OR
        de.drug_source_value ILIKE '%liraglutide%' OR de.drug_source_value ILIKE '%victoza%' OR
        de.drug_source_value ILIKE '%dulaglutide%' OR de.drug_source_value ILIKE '%trulicity%' OR
        de.drug_source_value ILIKE '%semaglutide%' OR de.drug_source_value ILIKE '%ozempic%' OR de.drug_source_value ILIKE '%rybelsus%' OR
        de.drug_source_value ILIKE '%canagliflozin%' OR de.drug_source_value ILIKE '%invokana%' OR
        de.drug_source_value ILIKE '%dapagliflozin%' OR de.drug_source_value ILIKE '%farxiga%' OR
        de.drug_source_value ILIKE '%empagliflozin%' OR de.drug_source_value ILIKE '%jardiance%' OR
        de.drug_source_value ILIKE '%ertugliflozin%' OR de.drug_source_value ILIKE '%steglatro%' OR
        de.drug_source_value ILIKE '%pioglitazone%' OR de.drug_source_value ILIKE '%actos%' OR
        de.drug_source_value ILIKE '%rosiglitazone%' OR de.drug_source_value ILIKE '%avandia%' OR
        de.drug_source_value ILIKE '%acarbose%' OR de.drug_source_value ILIKE '%precose%' OR
        de.drug_source_value ILIKE '%miglitol%' OR de.drug_source_value ILIKE '%glyset%' OR
        de.drug_source_value ILIKE '%repaglinide%' OR de.drug_source_value ILIKE '%prandin%' OR
        de.drug_source_value ILIKE '%nateglinide%' OR de.drug_source_value ILIKE '%starlix%'
),

t2dm_labs AS (
    SELECT DISTINCT
        m.person_id,
        m.measurement_date,
        m.value_as_number,
        m.measurement_source_value AS lab_name
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

diagnosis_count AS (
    SELECT
        person_id,
        COUNT(DISTINCT condition_start_date) AS dx_count,
        MIN(condition_start_date) AS first_dx_date,
        MAX(condition_start_date) AS last_dx_date
    FROM t2dm_diagnosis
    GROUP BY person_id
    HAVING COUNT(DISTINCT condition_start_date) >= 2
       AND date_diff('day', MIN(condition_start_date), MAX(condition_start_date)) <= 730
),

dx_plus_labs AS (
    SELECT DISTINCT
        d.person_id,
        d.condition_start_date AS index_date
    FROM t2dm_diagnosis d
    INNER JOIN t2dm_labs l ON d.person_id = l.person_id
        AND l.measurement_date BETWEEN d.condition_start_date - INTERVAL 90 DAY AND d.condition_start_date + INTERVAL 90 DAY
),

dx_plus_meds AS (
    SELECT DISTINCT
        d.person_id,
        d.condition_start_date AS index_date
    FROM t2dm_diagnosis d
    INNER JOIN t2dm_medications m ON d.person_id = m.person_id
        AND m.drug_exposure_start_date >= d.condition_start_date
        AND m.drug_exposure_start_date <= d.condition_start_date + INTERVAL 365 DAY
),

t2dm_cohort AS (
    SELECT DISTINCT person_id, 'Multiple Diagnoses' AS inclusion_criteria FROM diagnosis_count
    UNION
    SELECT DISTINCT person_id, 'Diagnosis + Labs' AS inclusion_criteria FROM dx_plus_labs
    UNION
    SELECT DISTINCT person_id, 'Diagnosis + Medications' AS inclusion_criteria FROM dx_plus_meds
)

SELECT DISTINCT
    tc.person_id,
    p.gender_concept_id,
    p.year_of_birth,
    p.race_concept_id,
    p.ethnicity_concept_id,
    STRING_AGG(DISTINCT tc.inclusion_criteria, '; ') AS criteria_met,
    MIN(d.condition_start_date) AS earliest_t2dm_date
FROM t2dm_cohort tc
INNER JOIN memory.person p ON tc.person_id = p.person_id
LEFT JOIN t2dm_diagnosis d ON tc.person_id = d.person_id
WHERE tc.person_id NOT IN (SELECT person_id FROM exclusion_diagnosis)
GROUP BY tc.person_id, p.gender_concept_id, p.year_of_birth, p.race_concept_id, p.ethnicity_concept_id
ORDER BY tc.person_id;
