-- Type 2 Diabetes Mellitus Phenotyping Algorithm
SELECT DISTINCT person_id
FROM (
  -- Diagnosis of Type 2 Diabetes Mellitus
  SELECT person_id
  FROM condition_occurrence
  WHERE condition_source_value ILIKE '%250.%'  -- ICD9CM code for Type 2 Diabetes Mellitus
     OR condition_source_value ILIKE 'E11%'  -- ICD10CM code for Type 2 Diabetes Mellitus

  UNION ALL

  -- Laboratory results indicating hyperglycemia and medications used to treat Type 2 Diabetes Mellitus
  SELECT DISTINCT m.person_id
  FROM measurement m
  JOIN drug_exposure de ON m.person_id = de.person_id
  WHERE (m.measurement_source_value ILIKE '%HbA1c%' AND m.value_as_number >= 6.5)
     OR (m.measurement_source_value ILIKE '%glucose%' AND m.value_as_number >= 126)
     AND de.drug_source_value ILIKE '%metformin%'  -- Example medication for Type 2 Diabetes Mellitus
     OR de.drug_source_value ILIKE '%sulfonylurea%'  -- Example medication class for Type 2 Diabetes Mellitus
) AS type2_diabetes_mellitus;