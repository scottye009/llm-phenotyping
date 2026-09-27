-- filepath: 

WITH t2dm_dx AS (
    -- Identify T2DM diagnosis codes (ICD9: 250.x0, 250.x2; ICD10: E11)
    SELECT person_id, condition_start_date AS event_date
    FROM condition_occurrence
    WHERE condition_source_value ILIKE 'E11%'
       OR condition_source_value ILIKE '250.00%'
       OR condition_source_value ILIKE '250.10%'
       OR condition_source_value ILIKE '250.20%'
       OR condition_source_value ILIKE '250.30%'
       OR condition_source_value ILIKE '250.40%'
       OR condition_source_value ILIKE '250.50%'
       OR condition_source_value ILIKE '250.60%'
       OR condition_source_value ILIKE '250.70%'
       OR condition_source_value ILIKE '250.80%'
       OR condition_source_value ILIKE '250.90%'
       OR condition_source_value ILIKE '250.02%'
       OR condition_source_value ILIKE '250.12%'
       OR condition_source_value ILIKE '250.22%'
       OR condition_source_value ILIKE '250.32%'
       OR condition_source_value ILIKE '250.42%'
       OR condition_source_value ILIKE '250.52%'
       OR condition_source_value ILIKE '250.62%'
       OR condition_source_value ILIKE '250.72%'
       OR condition_source_value ILIKE '250.82%'
       OR condition_source_value ILIKE '250.92%'
),
t2dm_meds AS (
    -- Identify T2DM medications (Generic and Brand names)
    SELECT DISTINCT person_id
    FROM drug_exposure
    WHERE EXISTS (
        SELECT 1 FROM (VALUES 
            ('metformin'), ('glucophage'), ('glipizide'), ('glucotrol'), 
            ('glyburide'), ('micronase'), ('glimepiride'), ('amaryl'), 
            ('sitagliptin'), ('januvia'), ('pioglitazone'), ('actos'), 
            ('empagliflozin'), ('jardiance'), ('liraglutide'), ('victoza'),
            ('insulin'), ('humalog'), ('novolog'), ('lantus'), ('levemir')
        ) AS t(med)
        WHERE drug_exposure.drug_source_value ILIKE '%' || t.med || '%'
           OR drug_exposure.drug_concept_name ILIKE '%' || t.med || '%'
    )
),
t2dm_labs AS (
    -- Identify abnormal HbA1c (>= 6.5%)
    SELECT person_id, measurement_date AS event_date
    FROM measurement
    WHERE (measurement_source_value ILIKE '%A1c%' 
           OR measurement_source_value ILIKE '%HbA1c%'
           OR measurement_concept_name ILIKE '%hemoglobin A1c%')
      AND value_as_number >= 6.5
),
dx_counts AS (
    -- Aggregate distinct diagnosis dates
    SELECT person_id, COUNT(DISTINCT event_date) as distinct_dx_dates
    FROM t2dm_dx
    GROUP BY person_id
),
lab_counts AS (
    -- Aggregate distinct lab dates
    SELECT person_id, COUNT(DISTINCT event_date) as distinct_lab_dates
    FROM t2dm_labs
    GROUP BY person_id
)
-- Final Cohort Selection
SELECT DISTINCT p.person_id
FROM person p
LEFT JOIN dx_counts d ON p.person_id = d.person_id
LEFT JOIN t2dm_meds m ON p.person_id = m.person_id
LEFT JOIN lab_counts l ON p.person_id = l.person_id
WHERE d.distinct_dx_dates >= 2 -- Criteria 1: 2+ Diags
   OR (d.distinct_dx_dates >= 1 AND m.person_id IS NOT NULL) -- Criteria 2: Diag + Med
   OR (d.distinct_dx_dates >= 1 AND l.distinct_lab_dates >= 1) -- Criteria 3: Diag + Lab
   OR l.distinct_lab_dates >= 2; -- Criteria 4: 2+ Labs