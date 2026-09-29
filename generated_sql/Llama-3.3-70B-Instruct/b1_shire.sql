SELECT DISTINCT p.person_id
FROM person p
WHERE p.person_id IN (
  -- Diagnosis of Type 2 Diabetes
  SELECT co.person_id
  FROM condition_occurrence co
  WHERE
    (
      -- ICD9CM-ish pattern: 250.xx excluding type 1 digits (llama used 250.x1/250.x3 concept codes)
      -- We approximate on source codes: exclude the known type 1 ICD9 list used in your pipeline
      co.condition_source_value LIKE '250.%'
      AND co.condition_source_value NOT IN (
        '250.01','250.03','250.11','250.13','250.21','250.23',
        '250.31','250.33','250.41','250.43','250.51','250.53',
        '250.61','250.63','250.71','250.73','250.81','250.83',
        '250.91','250.93'
      )
    )
    OR (
      -- ICD10CM-ish pattern: E11.*
      co.condition_source_value ILIKE 'E11%'
    )
)
OR p.person_id IN (
  -- Symptoms/Signs and Hyperglycemia
  SELECT m.person_id
  FROM measurement m
  WHERE
    (
      (
        m.measurement_source_value ILIKE '%hemoglobin a1c%'
        OR m.measurement_source_value ILIKE '%hba1c%'
        OR m.measurement_source_value ILIKE '%a1c%'
      )
      AND m.value_as_number > 6.5
    )
    OR (
      (m.measurement_source_value ILIKE '%fasting%glucose%')
      AND m.value_as_number > 126
    )
    OR (
      (
        m.measurement_source_value ILIKE '%2-hour%plasma%glucose%'
        OR m.measurement_source_value ILIKE '%2 hour%plasma%glucose%'
        OR m.measurement_source_value ILIKE '%ogtt%'
        OR m.measurement_source_value ILIKE '%oral glucose tolerance%'
      )
      AND m.value_as_number > 200
    )
)
OR p.person_id IN (
  -- Medications for Type 2 Diabetes
  SELECT de.person_id
  FROM drug_exposure de
  WHERE
    de.drug_source_value ILIKE '%metformin%'
    OR de.drug_source_value ILIKE '%glipizide%'
    OR de.drug_source_value ILIKE '%glimepiride%'
    OR de.drug_source_value ILIKE '%pioglitazone%'
    OR de.drug_source_value ILIKE '%sitagliptin%'
    OR de.drug_source_value ILIKE '%januvia%'
    OR de.drug_source_value ILIKE '%metformin hydrochloride%'
    OR de.drug_source_value ILIKE '%glipizide%extended release%'
)
AND p.person_id NOT IN (
  -- Exclude Type 1 Diabetes Diagnosis
  SELECT co.person_id
  FROM condition_occurrence co
  WHERE
    -- ICD9 T1DM list (exact, matches your prior work)
    co.condition_source_value IN (
      '250.01','250.03','250.11','250.13','250.21','250.23',
      '250.31','250.33','250.41','250.43','250.51','250.53',
      '250.61','250.63','250.71','250.73','250.81','250.83',
      '250.91','250.93'
    )
    OR co.condition_source_value ILIKE 'E10%'
)
AND p.person_id NOT IN (
  -- Exclude Exclusive Insulin Use
  SELECT de.person_id
  FROM drug_exposure de
  WHERE
    de.drug_source_value ILIKE '%insulin%'
    AND de.person_id NOT IN (
      SELECT de2.person_id
      FROM drug_exposure de2
      WHERE de2.drug_source_value NOT ILIKE '%insulin%'
    )
);
