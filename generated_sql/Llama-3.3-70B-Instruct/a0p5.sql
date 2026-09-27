--error
SELECT *
FROM patients
WHERE 
  -- Diagnosis criteria
  (EXISTS (
    SELECT 1
    FROM conditions
    WHERE condition_concept_id IN (SELECT concept_id FROM CONCEPT WHERE concept_code IN ('250.x', 'E11.x'))
    AND condition_start_date <= DATE '2026-06-10'
    AND (condition_end_date IS NULL OR condition_end_date > DATE '2026-06-10')
  ))
  OR 
  -- Laboratory and medication criteria
  (
    (
      EXISTS (
        SELECT 1
        FROM measurements
        WHERE measurement_concept_id IN (SELECT concept_id FROM CONCEPT WHERE concept_code IN ('HbA1c', 'FPG'))
        AND value_as_number > 6.5  -- Adjust threshold based on HbA1c or FPG criteria
        AND measurement_date <= DATE '2026-06-10'
      )
    )
    AND 
    (
      EXISTS (
        SELECT 1
        FROM drug_exposure
        WHERE drug_concept_id IN (SELECT concept_id FROM CONCEPT WHERE concept_name IN ('Metformin', 'Glimepiride', 'Insulin', 'Glucophage', 'Amaryl'))
        AND drug_exposure_start_date <= DATE '2026-06-10'
        AND (drug_exposure_end_date IS NULL OR drug_exposure_end_date > DATE '2026-06-10')
      )
    )
  );