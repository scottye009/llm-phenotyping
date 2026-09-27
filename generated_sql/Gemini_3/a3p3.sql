-- Identify T2DM Diagnosis
WITH t2dm_codes AS (
    SELECT person_id, condition_start_date AS event_date
    FROM condition_occurrence
    WHERE condition_source_value ILIKE 'E11%' -- ICD10 T2DM
       OR condition_source_value ILIKE '250.%0' -- ICD9 T2DM non-insulin dependent
       OR condition_source_value ILIKE '250.%2' -- ICD9 T2DM uncontrolled
       OR condition_source_concept_name ILIKE '%Type 2 diabetes%'
),

-- Identify T1DM Diagnosis (Exclusion Logic)
t1dm_codes AS (
    SELECT person_id, COUNT(*) as t1_count
    FROM condition_occurrence
    WHERE condition_source_value ILIKE 'E10%' -- ICD10 T1DM
       OR condition_source_value ILIKE '250.%1' -- ICD9 T1DM
       OR condition_source_value ILIKE '250.%3' -- ICD9 T1DM uncontrolled
    GROUP BY person_id
),

-- Identify T2DM Medications (Generic and Brand)
t2dm_meds AS (
    SELECT DISTINCT person_id
    FROM drug_exposure
    WHERE drug_source_value ILIKE '%metformin%' OR drug_source_value ILIKE '%glucophage%'
       OR drug_source_value ILIKE '%glipizide%' OR drug_source_value ILIKE '%glucotrol%'
       OR drug_source_value ILIKE '%glyburide%' OR drug_source_value ILIKE '%micronase%'
       OR drug_source_value ILIKE '%glimepiride%' OR drug_source_value ILIKE '%amaryl%'
       OR drug_source_value ILIKE '%sitagliptin%' OR drug_source_value ILIKE '%januvia%'
       OR drug_source_value ILIKE '%pioglitazone%' OR drug_source_value ILIKE '%actos%'
       OR drug_source_value ILIKE '%empagliflozin%' OR drug_source_value ILIKE '%jardiance%'
       OR drug_source_value ILIKE '%liraglutide%' OR drug_source_value ILIKE '%victoza%'
),

-- Identify Abnormal Labs (A1c >= 6.5 or Glucose >= 200)
t2dm_labs AS (
    SELECT DISTINCT person_id
    FROM measurement
    WHERE (
        (measurement_source_value ILIKE '%A1c%' OR measurement_source_value ILIKE '%hemoglobin A1c%')
        AND value_as_number >= 6.5
    ) OR (
        (measurement_source_value ILIKE '%glucose%' AND measurement_source_value NOT ILIKE '%urine%')
        AND value_as_number >= 200
    )
),

-- Aggregate Diagnosis Counts by Patient
dx_counts AS (
    SELECT person_id, COUNT(DISTINCT event_date) as dx_date_count
    FROM t2dm_codes
    GROUP BY person_id
)

-- Final Selection Logic
SELECT DISTINCT d.person_id
FROM dx_counts d
LEFT JOIN t1dm_codes t1 ON d.person_id = t1.person_id
WHERE (
    -- Criteria: 2+ dx dates OR (1 dx date AND (med OR lab))
    d.dx_date_count >= 2 
    OR (d.dx_date_count >= 1 AND EXISTS (SELECT 1 FROM t2dm_meds m WHERE m.person_id = d.person_id))
    OR (d.dx_date_count >= 1 AND EXISTS (SELECT 1 FROM t2dm_labs l WHERE l.person_id = d.person_id))
)
AND (
    -- Exclude if T1DM codes are more frequent than T2DM code dates
    t1.t1_count IS NULL OR t1.t1_count < d.dx_date_count
);