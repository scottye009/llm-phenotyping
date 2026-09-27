-- ========================================================================
-- TYPE 2 DIABETES PHENOTYPING ALGORITHM
-- Based on OMOP CDM v5.4
-- SHIRE-ready adaptation
-- ========================================================================

WITH

t2dm_diagnosis AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date AS index_date,
        'Diagnosis' AS criterion_type
    FROM memory.condition_occurrence co
    WHERE (
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
            '250.90', '250.92',
            'E11.00', 'E11.01',
            'E11.10', 'E11.11',
            'E11.21', 'E11.22', 'E11.29',
            'E11.311', 'E11.319', 'E11.32', 'E11.33', 'E11.34', 'E11.35', 'E11.36', 'E11.39',
            'E11.40', 'E11.41', 'E11.42', 'E11.43', 'E11.44', 'E11.49',
            'E11.51', 'E11.52', 'E11.59',
            'E11.610', 'E11.618', 'E11.620', 'E11.621', 'E11.622', 'E11.628', 'E11.630', 'E11.638', 'E11.641', 'E11.649', 'E11.65', 'E11.69',
            'E11.8', 'E11.9'
        )
    )
    AND co.person_id IN (
        SELECT person_id
        FROM memory.person
        WHERE (EXTRACT(YEAR FROM current_date) - year_of_birth) >= 18
    )
),

abnormal_labs AS (
    SELECT DISTINCT
        m.person_id,
        m.measurement_date AS index_date,
        'Laboratory' AS criterion_type
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
            AND m.value_as_number >= 200
        )
    )
    AND m.measurement_date IS NOT NULL
),

confirmed_labs AS (
    SELECT
        al.person_id,
        MIN(al.index_date) AS index_date,
        al.criterion_type
    FROM abnormal_labs al
    GROUP BY al.person_id, al.criterion_type
    HAVING COUNT(DISTINCT al.index_date) >= 2
),

t2dm_medications AS (
    SELECT DISTINCT
        de.person_id,
        de.drug_exposure_start_date AS index_date,
        'Medication' AS criterion_type
    FROM memory.drug_exposure de
    WHERE (
        de.drug_source_value ILIKE '%metformin%' OR de.drug_source_value ILIKE '%glyburide%' OR de.drug_source_value ILIKE '%glipizide%' OR de.drug_source_value ILIKE '%glimepiride%' OR
        de.drug_source_value ILIKE '%pioglitazone%' OR de.drug_source_value ILIKE '%rosiglitazone%' OR
        de.drug_source_value ILIKE '%sitagliptin%' OR de.drug_source_value ILIKE '%saxagliptin%' OR de.drug_source_value ILIKE '%linagliptin%' OR de.drug_source_value ILIKE '%alogliptin%' OR
        de.drug_source_value ILIKE '%exenatide%' OR de.drug_source_value ILIKE '%liraglutide%' OR de.drug_source_value ILIKE '%dulaglutide%' OR de.drug_source_value ILIKE '%semaglutide%' OR
        de.drug_source_value ILIKE '%canagliflozin%' OR de.drug_source_value ILIKE '%dapagliflozin%' OR de.drug_source_value ILIKE '%empagliflozin%' OR de.drug_source_value ILIKE '%ertugliflozin%' OR
        de.drug_source_value ILIKE '%repaglinide%' OR de.drug_source_value ILIKE '%nateglinide%' OR
        de.drug_source_value ILIKE '%acarbose%' OR de.drug_source_value ILIKE '%miglitol%' OR
        de.drug_source_value ILIKE '%glucophage%' OR de.drug_source_value ILIKE '%fortamet%' OR de.drug_source_value ILIKE '%glumetza%' OR de.drug_source_value ILIKE '%riomet%' OR
        de.drug_source_value ILIKE '%diabeta%' OR de.drug_source_value ILIKE '%glynase%' OR de.drug_source_value ILIKE '%glucotrol%' OR de.drug_source_value ILIKE '%amaryl%' OR
        de.drug_source_value ILIKE '%actos%' OR de.drug_source_value ILIKE '%avandia%' OR
        de.drug_source_value ILIKE '%januvia%' OR de.drug_source_value ILIKE '%onglyza%' OR de.drug_source_value ILIKE '%tradjenta%' OR de.drug_source_value ILIKE '%nesina%' OR
        de.drug_source_value ILIKE '%byetta%' OR de.drug_source_value ILIKE '%bydureon%' OR de.drug_source_value ILIKE '%victoza%' OR de.drug_source_value ILIKE '%trulicity%' OR de.drug_source_value ILIKE '%ozempic%' OR de.drug_source_value ILIKE '%rybelsus%' OR
        de.drug_source_value ILIKE '%invokana%' OR de.drug_source_value ILIKE '%farxiga%' OR de.drug_source_value ILIKE '%jardiance%' OR de.drug_source_value ILIKE '%steglatro%' OR
        de.drug_source_value ILIKE '%prandin%' OR de.drug_source_value ILIKE '%starlix%' OR
        de.drug_source_value ILIKE '%precose%' OR de.drug_source_value ILIKE '%glyset%'
    )
    AND de.person_id IN (
        SELECT person_id
        FROM memory.person
        WHERE (EXTRACT(YEAR FROM current_date) - year_of_birth) >= 18
    )
),

confirmed_medications AS (
    SELECT
        tm.person_id,
        MIN(tm.index_date) AS index_date,
        tm.criterion_type
    FROM t2dm_medications tm
    LEFT JOIN memory.drug_exposure de ON tm.person_id = de.person_id
        AND tm.index_date = de.drug_exposure_start_date
    GROUP BY tm.person_id, tm.criterion_type
    HAVING COUNT(DISTINCT tm.index_date) >= 2
        OR SUM(COALESCE(TRY_CAST(de.days_supply AS DOUBLE), 30)) >= 30
),

type1_exclusion AS (
    SELECT DISTINCT
        co.person_id
    FROM memory.condition_occurrence co
    WHERE
        co.condition_source_value IN (
            '250.01', '250.03', '250.11', '250.13', '250.21', '250.23',
            '250.31', '250.33', '250.41', '250.43', '250.51', '250.53',
            '250.61', '250.63', '250.71', '250.73', '250.81', '250.83',
            '250.91', '250.93'
        )
        OR co.condition_source_value LIKE 'E10%'
),

gestational_exclusion AS (
    SELECT DISTINCT
        p.person_id
    FROM memory.person p
    INNER JOIN memory.condition_occurrence co ON p.person_id = co.person_id
    WHERE (
        co.condition_source_value LIKE '648.8%'
        OR co.condition_source_value LIKE 'O24.4%'
        OR co.condition_source_value LIKE '648.0%'
    )
    AND NOT EXISTS (
        SELECT 1
        FROM memory.condition_occurrence co2
        WHERE co2.person_id = p.person_id
          AND co2.condition_start_date > co.condition_start_date + INTERVAL 12 MONTH
          AND (
              co2.condition_source_value IN ('250.00', '250.02', '250.10', '250.12', '250.20', '250.22',
                                             '250.30', '250.32', '250.40', '250.42', '250.50', '250.52',
                                             '250.60', '250.62', '250.70', '250.72', '250.80', '250.82',
                                             '250.90', '250.92')
              OR co2.condition_source_value LIKE 'E11%'
          )
    )
),

secondary_exclusion AS (
    SELECT DISTINCT
        co.person_id
    FROM memory.condition_occurrence co
    WHERE
        co.condition_source_value LIKE '249.%'
        OR co.condition_source_value LIKE 'E08%'
        OR co.condition_source_value LIKE 'E09%'
),

all_inclusions AS (
    SELECT person_id, index_date, criterion_type FROM t2dm_diagnosis
    UNION
    SELECT person_id, index_date, criterion_type FROM confirmed_labs
    UNION
    SELECT person_id, index_date, criterion_type FROM confirmed_medications
),

t2dm_cohort AS (
    SELECT DISTINCT
        ai.person_id,
        MIN(ai.index_date) AS earliest_index_date,
        STRING_AGG(DISTINCT ai.criterion_type, ', ' ORDER BY ai.criterion_type) AS criteria_met,
        COUNT(DISTINCT ai.criterion_type) AS num_criteria_met
    FROM all_inclusions ai
    WHERE ai.person_id NOT IN (SELECT person_id FROM type1_exclusion)
      AND ai.person_id NOT IN (SELECT person_id FROM gestational_exclusion)
      AND ai.person_id NOT IN (SELECT person_id FROM secondary_exclusion)
    GROUP BY ai.person_id
)

SELECT
    tc.person_id,
    p.gender_concept_id,
    p.year_of_birth,
    EXTRACT(YEAR FROM tc.earliest_index_date) - p.year_of_birth AS age_at_diagnosis,
    tc.earliest_index_date,
    tc.criteria_met,
    tc.num_criteria_met,
    CASE WHEN EXISTS (SELECT 1 FROM t2dm_diagnosis td WHERE td.person_id = tc.person_id) THEN 'Yes' ELSE 'No' END AS has_diagnosis_code,
    CASE WHEN EXISTS (SELECT 1 FROM confirmed_labs cl WHERE cl.person_id = tc.person_id) THEN 'Yes' ELSE 'No' END AS has_abnormal_labs,
    CASE WHEN EXISTS (SELECT 1 FROM confirmed_medications cm WHERE cm.person_id = tc.person_id) THEN 'Yes' ELSE 'No' END AS has_t2dm_medication
FROM t2dm_cohort tc
INNER JOIN memory.person p ON tc.person_id = p.person_id
ORDER BY tc.person_id;

