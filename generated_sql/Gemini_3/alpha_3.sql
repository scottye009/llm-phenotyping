
WITH t2dm_diagnosis AS (
    -- Step 1: Identify T2DM diagnoses (ICD9: 250.00, 250.02; ICD10: E11.x)
    SELECT person_id, condition_start_date
    FROM public.condition_occurrence
    WHERE condition_source_value ~* '^(250\.00|250\.02|E11)' 
),
t2dm_meds AS (
    -- Step 2: Identify T2DM specific medications (Generic and Brand)
    -- Includes: Metformin (Glucophage), Glipizide (Glucotrol), Empagliflozin (Jardiance), etc.
    SELECT person_id, drug_exposure_start_date
    FROM public.drug_exposure
    WHERE drug_source_value ~* '(metformin|glucophage|glipizide|glucotrol|glyburide|micronase|pioglitazone|actos|sitagliptin|januvia|empagliflozin|jardiance|liraglutide|victoza)'
),
t2dm_labs AS (
    -- Step 3: Identify Lab results (HbA1c >= 6.5%)
    -- LOINC 4548-4 is the standard for HbA1c
    SELECT person_id, measurement_date
    FROM public.measurement
    WHERE measurement_source_value ~* '(4548-4|hba1c|a1c)'
    AND value_as_number >= 6.5
),
t1dm_exclusion AS (
    -- Step 4: Identify Type 1 Diabetes for exclusion (ICD9: 250.01, 250.03; ICD10: E10.x)
    SELECT DISTINCT person_id
    FROM public.condition_occurrence
    WHERE condition_source_value ~* '^(250\.01|250\.03|E10)'
)

-- Final Selection Logic
SELECT DISTINCT d.person_id
FROM t2dm_diagnosis d
LEFT JOIN t2dm_meds m ON d.person_id = m.person_id
LEFT JOIN t2dm_labs l ON d.person_id = l.person_id
WHERE d.person_id NOT IN (SELECT person_id FROM t1dm_exclusion)
AND (
    -- Rule: 2+ diagnoses on different days
    (SELECT COUNT(DISTINCT condition_start_date) FROM t2dm_diagnosis d2 WHERE d2.person_id = d.person_id) >= 2
    OR 
    -- Rule: 1 diagnosis AND 1 medication
    m.person_id IS NOT NULL
    OR 
    -- Rule: 1 diagnosis AND 1 abnormal lab
    l.person_id IS NOT NULL
);
