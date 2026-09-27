--error
SELECT * 
FROM patients
WHERE 
  -- Diagnosis of type 2 diabetes
  (EXISTS (
    SELECT 1 
    FROM conditions 
    WHERE condition_concept_id IN (
      -- ICD9CM codes for type 2 diabetes
      SELECT concept_id FROM concept WHERE concept_code IN ('250.0', '250.1', '250.2', '250.3') AND vocabulary_id = 'ICD9CM'
      -- ICD10CM codes for type 2 diabetes
      UNION SELECT concept_id FROM concept WHERE concept_code IN ('E11.0', 'E11.1', 'E11.2', 'E11.3', 'E11.4', 'E11.5', 'E11.6', 'E11.7', 'E11.8', 'E11.9') AND vocabulary_id = 'ICD10CM'
    ) AND condition_start_date < DATE '2026-06-10'
  ))
  
  -- OR use of type 2 diabetes medications
  OR (EXISTS (
    SELECT 1 
    FROM drug_exposure 
    WHERE drug_concept_id IN (
      -- Generic and brand names for diabetes medications
      SELECT concept_id FROM concept WHERE concept_name IN ('Metformin', 'Glucophage', 'Glyburide', 'DiaBeta', 'Pioglitazone', 'Actos', 'Sitagliptin', 'Januvia', 'Liraglutide', 'Victoza', 'Canagliflozin', 'Invokana') AND vocabulary_id = 'RxNorm'
    ) AND drug_exposure_start_date < DATE '2026-06-10'
  ))
  
  -- OR laboratory evidence of diabetes
  OR (EXISTS (
    SELECT 1 
    FROM measurement 
    WHERE measurement_concept_id IN (
      -- HbA1c, fasting glucose, 2-hour OGTT
      SELECT concept_id FROM concept WHERE concept_name IN ('Hemoglobin A1c', 'Fasting glucose', '2-hour plasma glucose') AND vocabulary_id = 'LOINC'
    ) AND value_as_number >= (
      -- Threshold values for diabetes diagnosis
      CASE 
        WHEN measurement_concept_id IN (SELECT concept_id FROM concept WHERE concept_name = 'Hemoglobin A1c' AND vocabulary_id = 'LOINC') THEN 6.5
        WHEN measurement_concept_id IN (SELECT concept_id FROM concept WHERE concept_name = 'Fasting glucose' AND vocabulary_id = 'LOINC') THEN 126
        WHEN measurement_concept_id IN (SELECT concept_id FROM concept WHERE concept_name = '2-hour plasma glucose' AND vocabulary_id = 'LOINC') THEN 200
      END
    ) AND measurement_date < DATE '2026-06-10'
  ))
  
  -- Excluding type 1 or gestational diabetes
  AND NOT EXISTS (
    SELECT 1 
    FROM conditions 
    WHERE condition_concept_id IN (
      -- Type 1 diabetes ICD9CM codes
      SELECT concept_id FROM concept WHERE concept_code IN ('250.1') AND vocabulary_id = 'ICD9CM'
      -- Type 1 diabetes ICD10CM codes
      UNION SELECT concept_id FROM concept WHERE concept_code IN ('E10.0', 'E10.1', 'E10.2', 'E10.3', 'E10.4', 'E10.5', 'E10.6', 'E10.7', 'E10.8', 'E10.9') AND vocabulary_id = 'ICD10CM'
      -- Gestational diabetes ICD9CM codes
      UNION SELECT concept_id FROM concept WHERE concept_code IN ('648.8') AND vocabulary_id = 'ICD9CM'
      -- Gestational diabetes ICD10CM codes
      UNION SELECT concept_id FROM concept WHERE concept_code IN ('O24.0', 'O24.1', 'O24.2', 'O24.3', 'O24.4', 'O24.8', 'O24.9') AND vocabulary_id = 'ICD10CM'
    ) AND condition_start_date < DATE '2026-06-10'
  );