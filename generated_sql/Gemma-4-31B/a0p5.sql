/* 
  TYPE 2 DIABETES MELLITUS (T2DM) PHENOTYPE 
  Logic: (Diagnosis OR (Lab Evidence AND Medication) OR Medication) AND NOT (Exclusions)
*/

WITH T2DM_Criteria AS (
    SELECT patient_id
    FROM clinical_data
    WHERE (
        -- 1. Diagnosis Criteria (ICD-10 and ICD-9)
        -- OMOP Concept: Type 2 diabetes mellitus (443234)
        (condition_code IN (
            'E11.9', 'E11.0', 'E11.1', 'E11.2', 'E11.3', 'E11.4', 'E11.5', 'E11.6', 'E11.8', 'E11.9' -- ICD-10 T2DM
            , '250.00', '250.01', '250.02', '250.03', '250.10', '250.11', '250.12', '250.13' -- ICD-9 T2DM
        ))
        
        OR 
        
        -- 2. Medication Criteria (Generic and Brand Names)
        -- OMOP Concept: Oral hypoglycemic agents (1308286) / Insulin (1116422)
        (drug_name IN (
            -- Biguanides
            'Metformin', 'Glucophage', 'Fortamet', 'Glumetza', 
            -- Sulfonylureas
            'Glipizide', 'Glyburide', 'Glimepiride', 'Diamicron', 'Amaryl',
            -- SGLT2 Inhibitors
            'Canagliflozin', 'Dapagliflozin', 'Empagliflozin', 'Invokana', 'Farxiga', 'Jardiance',
            -- DPP-4 Inhibitors
            'Sitagliptin', 'Saxagliptin', 'Linagliptin', 'Januvia', 'Onglyza', 'Tradjenta',
            -- GLP-1 Receptor Agonists
            'Exenatide', 'Liraglutide', 'Dulaglutide', 'Semaglutide', 'Byetta', 'Victoza', 'Trulicity', 'Ozempic', 'Rybelsus'
        ))
        
        OR 
        
        -- 3. Lab Evidence (Combined with either Diagnosis or Medication to ensure specificity)
        -- OMOP Concept: Hemoglobin A1c (3004426) / Glucose (3004422)
        (
            (lab_test = 'HbA1c' AND lab_value >= 6.5) 
            OR 
            (lab_test = 'Fasting Plasma Glucose' AND lab_value >= 126)
        ) 
        AND 
        (
            condition_code LIKE 'E11%' -- ICD-10 T2DM
            OR drug_name IS NOT NULL    -- Any diabetes medication
        )
    )
),

Exclusion_Criteria AS (
    SELECT patient_id
    FROM clinical_data
    WHERE (
        -- Exclusion of Type 1 Diabetes (OMOP Concept: 443233)
        (condition_code IN ('E10.9', 'E10.1', '250.00')) -- ICD-10/9 Type 1
        
        OR 
        
        -- Exclusion of Gestational Diabetes (OMOP Concept: 443235)
        (condition_code IN ('O24.4', '248.01')) -- ICD-10/9 GDM
        
        OR 
        
        -- Biomarker for T1DM: GAD Antibodies (OMOP Concept: 4026512)
        (lab_test = 'GAD65_Antibody' AND lab_result = 'Positive')
    )
)

-- Final Phenotype Derivation
SELECT DISTINCT a.patient_id
FROM T2DM_Criteria a
LEFT JOIN Exclusion_Criteria b ON a.patient_id = b.patient_id
WHERE b.patient_id IS NULL; -- (T2DM_Criteria) AND NOT (Exclusion_Criteria)