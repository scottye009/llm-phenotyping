-- ============================================================================
-- Type 2 Diabetes Phenotyping Algorithm
-- Based on OMOP Common Data Model (CDM)
-- SHIRE-ready adaptation
-- ============================================================================

WITH

diabetes_diagnosis AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date AS event_date,
        'diagnosis' AS criterion_type,
        co.condition_source_value AS concept_code,
        co.condition_source_value AS concept_name
    FROM memory.condition_occurrence co
    WHERE (
        co.condition_source_value IN (
            'E11', 'E11.0', 'E11.00', 'E11.01',
            'E11.1', 'E11.2', 'E11.21', 'E11.22', 'E11.29',
            'E11.3', 'E11.31', 'E11.32', 'E11.33', 'E11.34', 'E11.35', 'E11.36', 'E11.37', 'E11.39',
            'E11.4', 'E11.40', 'E11.41', 'E11.42', 'E11.43', 'E11.44', 'E11.49',
            'E11.5', 'E11.51', 'E11.52', 'E11.59',
            'E11.6', 'E11.61', 'E11.62', 'E11.63', 'E11.64', 'E11.65', 'E11.69',
            'E11.8', 'E11.9'
        )
    )
    OR (
        co.condition_source_value IN (
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

diabetes_labs AS (
    SELECT DISTINCT
        m.person_id,
        m.measurement_date AS event_date,
        'laboratory' AS criterion_type,
        m.measurement_source_value AS concept_name,
        m.value_as_number,
        m.unit_source_value AS unit_concept_id
    FROM memory.measurement m
    WHERE (
        (
            m.measurement_source_value ILIKE '%hemoglobin a1c%'
            OR m.measurement_source_value ILIKE '%hba1c%'
            OR m.measurement_source_value ILIKE '%glycohemoglobin%'
            OR m.measurement_source_value ILIKE '%a1c%'
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
),

diabetes_medications AS (
    SELECT DISTINCT
        de.person_id,
        de.drug_exposure_start_date AS event_date,
        'medication' AS criterion_type,
        de.drug_source_value AS concept_name
    FROM memory.drug_exposure de
    WHERE (
        de.drug_source_value ILIKE '%metformin%' OR de.drug_source_value ILIKE '%glucophage%' OR de.drug_source_value ILIKE '%fortamet%' OR de.drug_source_value ILIKE '%glumetza%'
    )
    OR (
        de.drug_source_value ILIKE '%glyburide%' OR de.drug_source_value ILIKE '%glibenclamide%' OR de.drug_source_value ILIKE '%diabeta%' OR de.drug_source_value ILIKE '%glynase%'
        OR de.drug_source_value ILIKE '%glipizide%' OR de.drug_source_value ILIKE '%glucotrol%'
        OR de.drug_source_value ILIKE '%glimepiride%' OR de.drug_source_value ILIKE '%amaryl%'
    )
    OR (
        de.drug_source_value ILIKE '%pioglitazone%' OR de.drug_source_value ILIKE '%actos%'
        OR de.drug_source_value ILIKE '%rosiglitazone%' OR de.drug_source_value ILIKE '%avandia%'
    )
    OR (
        de.drug_source_value ILIKE '%sitagliptin%' OR de.drug_source_value ILIKE '%januvia%'
        OR de.drug_source_value ILIKE '%saxagliptin%' OR de.drug_source_value ILIKE '%onglyza%'
        OR de.drug_source_value ILIKE '%linagliptin%' OR de.drug_source_value ILIKE '%tradjenta%'
        OR de.drug_source_value ILIKE '%alogliptin%' OR de.drug_source_value ILIKE '%nesina%'
    )
    OR (
        de.drug_source_value ILIKE '%exenatide%' OR de.drug_source_value ILIKE '%byetta%' OR de.drug_source_value ILIKE '%bydureon%'
        OR de.drug_source_value ILIKE '%liraglutide%' OR de.drug_source_value ILIKE '%victoza%'
        OR de.drug_source_value ILIKE '%dulaglutide%' OR de.drug_source_value ILIKE '%trulicity%'
        OR de.drug_source_value ILIKE '%semaglutide%' OR de.drug_source_value ILIKE '%ozempic%' OR de.drug_source_value ILIKE '%rybelsus%'
    )
    OR (
        de.drug_source_value ILIKE '%canagliflozin%' OR de.drug_source_value ILIKE '%invokana%'
        OR de.drug_source_value ILIKE '%dapagliflozin%' OR de.drug_source_value ILIKE '%farxiga%'
        OR de.drug_source_value ILIKE '%empagliflozin%' OR de.drug_source_value ILIKE '%jardiance%'
        OR de.drug_source_value ILIKE '%ertugliflozin%' OR de.drug_source_value ILIKE '%steglatro%'
    )
    OR (
        de.drug_source_value ILIKE '%insulin%'
    )
    OR (
        de.drug_source_value ILIKE '%repaglinide%' OR de.drug_source_value ILIKE '%prandin%'
        OR de.drug_source_value ILIKE '%nateglinide%' OR de.drug_source_value ILIKE '%starlix%'
    )
    OR (
        de.drug_source_value ILIKE '%acarbose%' OR de.drug_source_value ILIKE '%precose%'
        OR de.drug_source_value ILIKE '%miglitol%' OR de.drug_source_value ILIKE '%glyset%'
    )
),

exclusion_type1_diabetes AS (
    SELECT DISTINCT
        co.person_id
    FROM memory.condition_occurrence co
    WHERE (
        co.condition_source_value LIKE 'E10%'
    )
    OR (
        co.condition_source_value IN (
            '250.01', '250.03', '250.11', '250.13', '250.21', '250.23',
            '250.31', '250.33', '250.41', '250.43', '250.51', '250.53',
            '250.61', '250.63', '250.71', '250.73', '250.81', '250.83',
            '250.91', '250.93'
        )
    )
),

exclusion_gestational_diabetes AS (
    SELECT DISTINCT
        co.person_id
    FROM memory.condition_occurrence co
    WHERE (
        co.condition_source_value LIKE 'O24.4%'
    )
    OR (
        co.condition_source_value IN ('648.80', '648.81', '648.82', '648.83', '648.84')
    )
),

exclusion_secondary_diabetes AS (
    SELECT DISTINCT
        co.person_id
    FROM memory.condition_occurrence co
    WHERE (
        co.condition_source_value LIKE 'E08%'
        OR co.condition_source_value LIKE 'E09%'
        OR co.condition_source_value LIKE 'E13%'
    )
),

all_diabetes_evidence AS (
    SELECT person_id, event_date, criterion_type FROM diabetes_diagnosis
    UNION ALL
    SELECT person_id, event_date, criterion_type FROM diabetes_labs
    UNION ALL
    SELECT person_id, event_date, criterion_type FROM diabetes_medications
),

evidence_summary AS (
    SELECT
        person_id,
        MIN(event_date) AS first_evidence_date,
        MAX(event_date) AS last_evidence_date,
        COUNT(DISTINCT event_date) AS total_evidence_count,
        COUNT(DISTINCT CASE WHEN criterion_type = 'diagnosis' THEN event_date END) AS diagnosis_count,
        COUNT(DISTINCT CASE WHEN criterion_type = 'laboratory' THEN event_date END) AS lab_count,
        COUNT(DISTINCT CASE WHEN criterion_type = 'medication' THEN event_date END) AS medication_count,
        COUNT(DISTINCT criterion_type) AS distinct_criterion_types
    FROM all_diabetes_evidence
    GROUP BY person_id
)

SELECT
    p.person_id,
    p.gender_concept_id,
    p.year_of_birth,
    p.race_concept_id,
    p.ethnicity_concept_id,
    es.first_evidence_date AS t2dm_index_date,
    es.last_evidence_date,
    es.total_evidence_count,
    es.diagnosis_count,
    es.lab_count,
    es.medication_count,
    es.distinct_criterion_types,
    CASE
        WHEN es.distinct_criterion_types >= 2 AND es.total_evidence_count >= 2 THEN 'High'
        WHEN es.diagnosis_count >= 1 OR es.lab_count >= 1 THEN 'Medium'
        WHEN es.medication_count >= 2 THEN 'Low'
        ELSE 'Very Low'
    END AS confidence_level
FROM memory.person p
INNER JOIN evidence_summary es ON p.person_id = es.person_id
WHERE
    es.total_evidence_count >= 1
    AND (
        es.diagnosis_count >= 1
        OR es.lab_count >= 1
        OR es.medication_count >= 2
    )
    AND p.person_id NOT IN (SELECT person_id FROM exclusion_type1_diabetes)
    AND p.person_id NOT IN (SELECT person_id FROM exclusion_gestational_diabetes)
    AND p.person_id NOT IN (SELECT person_id FROM exclusion_secondary_diabetes)
ORDER BY confidence_level DESC, es.first_evidence_date;
