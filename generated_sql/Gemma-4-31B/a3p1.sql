/* 
Phenotyping Algorithm for Type 2 Diabetes Mellitus
Logic: (Diagnostic Code) OR (T2DM Medication) OR (Hyperglycemia Labs)
*/

-- 1. Patients identified by T2DM Diagnostic Codes (ICD-10 E11 or ICD-9 250)
WITH diag_t2dm AS (
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE (
        -- ICD-10: E11 is Type 2 DM
        condition_source_value ILIKE 'E11%' 
        -- ICD-9: 250 is Diabetes Mellitus (mostly T2DM in adult populations)
        OR condition_source_value ILIKE '250%'
    )
    -- Exclude explicit Type 1 Diabetes to increase specificity
    AND NOT EXISTS (
        SELECT 1 FROM condition_occurrence co2 
        WHERE co2.person_id = condition_occurrence.person_id 
        AND (co2.condition_source_value ILIKE 'E10%' OR co2.condition_source_value ILIKE '250.0%')
    )
),

-- 2. Patients identified by T2DM-specific Medications
med_t2dm AS (
    SELECT DISTINCT person_id
    FROM drug_exposure
    WHERE (
        -- Generic and Brand names for T2DM medications
        drug_source_value ILIKE '%Metformin%' OR
        drug_source_value ILIKE '%Glipizide%' OR 
        drug_source_value ILIKE '%Glyburide%' OR 
        drug_source_value ILIKE '%Glimepiride%' OR
        drug_source_value ILIKE '%Sitagliptin%' OR 
        drug_source_value ILIKE '%Januvia%' OR
        drug_source_value ILIKE '%Saxagliptin%' OR 
        drug_source_value ILIKE '%Linagliptin%' OR
        drug_source_value ILIKE '%Canagliflozin%' OR 
        drug_source_value ILIKE '%Invokana%' OR
        drug_source_value ILIKE '%Dapagliflozin%' OR 
        drug_source_value ILIKE '%Farxiga%' OR
        drug_source_value ILIKE '%Empagliflozin%' OR 
        drug_source_value ILIKE '%Jardiance%' OR
        drug_source_value ILIKE '%Exenatide%' OR 
        drug_source_value ILIKE '%Byetta%' OR
        drug_source_value ILIKE '%Liraglutide%' OR 
        drug_source_value ILIKE '%Victoza%' OR
        drug_source_value ILIKE '%Semaglutide%' OR 
        drug_source_value ILIKE '%Ozempic%' OR
        drug_source_value ILIKE '%Pioglitazone%' OR 
        drug_source_value ILIKE '%Rosiglitazone%'
    )
),

-- 3. Patients identified by laboratory criteria (HbA1c >= 6.5 or Glucose >= 126/200)
lab_t2dm AS (
    SELECT person_id
    FROM measurement
    WHERE (
        -- HbA1c >= 6.5%
        (measurement_source_value ILIKE '%HbA1c%' AND value_as_number >= 6.5)
        OR 
        -- Fasting Glucose >= 126 mg/dL
        (measurement_source_value ILIKE '%Glucose%' AND measurement_source_value ILIKE '%Fasting%' AND value_as_number >= 126)
        OR 
        -- Random Glucose >= 200 mg/dL
        (measurement_source_value ILIKE '%Glucose%' AND value_as_number >= 200)
    )
    GROUP BY person_id
    -- Require at least 2 measurements to be considered a phenotype via labs alone
    HAVING COUNT(DISTINCT measurement_date) >= 2
)

-- Final combination: any of the three criteria
SELECT person_id FROM diag_t2dm
UNION
SELECT person_id FROM med_t2dm
UNION
SELECT person_id FROM lab_t2dm;