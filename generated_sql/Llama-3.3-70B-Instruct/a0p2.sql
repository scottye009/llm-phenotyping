--error
SELECT person_id
FROM 
(
  -- Diagnosis Codes for Type 2 Diabetes
  SELECT person_id
  FROM condition_occurrence
  WHERE condition_concept_id IN (SELECT concept_id FROM concept WHERE concept_class='ICD10CM' AND concept_code IN ('E11.0', 'E11.1', 'E11.2', 'E11.3', 'E11.4', 'E11.5', 'E11.6', 'E11.7', 'E11.8', 'E11.9'))
  OR condition_concept_id IN (SELECT concept_id FROM concept WHERE concept_class='ICD9CM' AND concept_code IN ('250.00', '250.02'))

  -- Medications for Type 2 Diabetes
  UNION
  SELECT person_id
  FROM drug_exposure
  WHERE drug_concept_id IN (
    SELECT concept_id FROM concept WHERE concept_class='RxNorm' AND lower(concept_name) IN (
      'metformin', 'glucophage', 'glyburide', 'glucovance', 'pioglitazone', 'actos', 'sitagliptin', 'januvia', 'canagliflozin', 'invokana'
    )
  )

  -- Supporting Evidence: Elevated HbA1c Levels
  UNION
  SELECT person_id
  FROM measurement
  WHERE measurement_concept_id IN (SELECT concept_id FROM concept WHERE concept_class='LOINC' AND concept_code IN ('4548-4', '4549-2'))  -- LOINC codes for HbA1c
  AND value_as_number >= 6.5  -- HbA1c ≥ 6.5%
)
WHERE person_id NOT IN (
  -- Exclude Type 1 Diabetes Diagnoses
  SELECT person_id
  FROM condition_occurrence
  WHERE condition_concept_id IN (SELECT concept_id FROM concept WHERE concept_class='ICD10CM' AND concept_code IN ('E10.*'))
  OR condition_concept_id IN (SELECT concept_id FROM concept WHERE concept_class='ICD9CM' AND concept_code IN ('250.01', '250.03', '250.1', '250.13'))
)
;