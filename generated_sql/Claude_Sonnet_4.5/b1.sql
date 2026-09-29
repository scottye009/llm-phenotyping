-- Type 2 Diabetes Phenotyping Algorithm - Refined Version
-- OMOP CDM Compatible


SELECT DISTINCT
   p.person_id,
   MIN(COALESCE(co_dx.condition_start_date, de_med.drug_exposure_start_date, m_lab.measurement_date)) AS index_date,
   p.year_of_birth,
   p.gender_concept_id,
   p.race_concept_id,
   p.ethnicity_concept_id
FROM public.person p
WHERE EXISTS (
   -- Criterion 1: At least 2 Type 2 Diabetes diagnoses on different dates
   SELECT 1
   FROM public.condition_occurrence co1
   WHERE co1.person_id = p.person_id
       AND (
           co1.condition_source_value IN ('E11', 'E11.0', 'E11.00', 'E11.01', 'E11.1', 'E11.2', 'E11.21', 'E11.22', 'E11.29',
               'E11.3', 'E11.31', 'E11.32', 'E11.33', 'E11.34', 'E11.35', 'E11.36', 'E11.37', 'E11.39',
               'E11.4', 'E11.40', 'E11.41', 'E11.42', 'E11.43', 'E11.44', 'E11.49',
               'E11.5', 'E11.51', 'E11.52', 'E11.59', 'E11.6', 'E11.61', 'E11.618', 'E11.62', 'E11.620', 'E11.621', 'E11.622', 'E11.628', 'E11.63', 'E11.630', 'E11.638', 'E11.64', 'E11.641', 'E11.649', 'E11.65', 'E11.69',
               'E11.7', 'E11.8', 'E11.9',
               '250.00', '250.02', '250.10', '250.12', '250.20', '250.22', '250.30', '250.32', '250.40', '250.42', '250.50', '250.52', '250.60', '250.62', '250.70', '250.72', '250.80', '250.82', '250.90', '250.92')
       )
   GROUP BY co1.person_id
   HAVING COUNT(DISTINCT co1.condition_start_date) >= 2
)
OR (
   -- Criterion 2: At least 1 diagnosis AND at least 1 diabetes medication
   EXISTS (
       SELECT 1
       FROM public.condition_occurrence co2
       WHERE co2.person_id = p.person_id
           AND (
               co2.condition_source_value IN ('E11', 'E11.0', 'E11.00', 'E11.01', 'E11.1', 'E11.2', 'E11.21', 'E11.22', 'E11.29',
                   'E11.3', 'E11.31', 'E11.32', 'E11.33', 'E11.34', 'E11.35', 'E11.36', 'E11.37', 'E11.39',
                   'E11.4', 'E11.40', 'E11.41', 'E11.42', 'E11.43', 'E11.44', 'E11.49',
                   'E11.5', 'E11.51', 'E11.52', 'E11.59', 'E11.6', 'E11.61', 'E11.618', 'E11.62', 'E11.620', 'E11.621', 'E11.622', 'E11.628', 'E11.63', 'E11.630', 'E11.638', 'E11.64', 'E11.641', 'E11.649', 'E11.65', 'E11.69',
                   'E11.7', 'E11.8', 'E11.9',
                   '250.00', '250.02', '250.10', '250.12', '250.20', '250.22', '250.30', '250.32', '250.40', '250.42', '250.50', '250.52', '250.60', '250.62', '250.70', '250.72', '250.80', '250.82', '250.90', '250.92')
           )
   )
   AND EXISTS (
       SELECT 1
       FROM public.drug_exposure de
       INNER JOIN public.concept c ON de.drug_concept_id = c.concept_id
       WHERE de.person_id = p.person_id
           AND (
               LOWER(c.concept_name) LIKE '%metformin%' OR LOWER(de.drug_source_value) LIKE '%metformin%'
               OR LOWER(c.concept_name) LIKE '%glucophage%' OR LOWER(de.drug_source_value) LIKE '%glucophage%'
               OR LOWER(c.concept_name) LIKE '%fortamet%' OR LOWER(de.drug_source_value) LIKE '%fortamet%'
               OR LOWER(c.concept_name) LIKE '%glumetza%' OR LOWER(de.drug_source_value) LIKE '%glumetza%'
               OR LOWER(c.concept_name) LIKE '%riomet%' OR LOWER(de.drug_source_value) LIKE '%riomet%'
               OR LOWER(c.concept_name) LIKE '%glipizide%' OR LOWER(de.drug_source_value) LIKE '%glipizide%'
               OR LOWER(c.concept_name) LIKE '%glucotrol%' OR LOWER(de.drug_source_value) LIKE '%glucotrol%'
               OR LOWER(c.concept_name) LIKE '%glyburide%' OR LOWER(de.drug_source_value) LIKE '%glyburide%'
               OR LOWER(c.concept_name) LIKE '%diabeta%' OR LOWER(de.drug_source_value) LIKE '%diabeta%'
               OR LOWER(c.concept_name) LIKE '%micronase%' OR LOWER(de.drug_source_value) LIKE '%micronase%'
               OR LOWER(c.concept_name) LIKE '%glimepiride%' OR LOWER(de.drug_source_value) LIKE '%glimepiride%'
               OR LOWER(c.concept_name) LIKE '%amaryl%' OR LOWER(de.drug_source_value) LIKE '%amaryl%'
               OR LOWER(c.concept_name) LIKE '%gliclazide%' OR LOWER(de.drug_source_value) LIKE '%gliclazide%'
               OR LOWER(c.concept_name) LIKE '%sitagliptin%' OR LOWER(de.drug_source_value) LIKE '%sitagliptin%'
               OR LOWER(c.concept_name) LIKE '%januvia%' OR LOWER(de.drug_source_value) LIKE '%januvia%'
               OR LOWER(c.concept_name) LIKE '%saxagliptin%' OR LOWER(de.drug_source_value) LIKE '%saxagliptin%'
               OR LOWER(c.concept_name) LIKE '%onglyza%' OR LOWER(de.drug_source_value) LIKE '%onglyza%'
               OR LOWER(c.concept_name) LIKE '%linagliptin%' OR LOWER(de.drug_source_value) LIKE '%linagliptin%'
               OR LOWER(c.concept_name) LIKE '%tradjenta%' OR LOWER(de.drug_source_value) LIKE '%tradjenta%'
               OR LOWER(c.concept_name) LIKE '%alogliptin%' OR LOWER(de.drug_source_value) LIKE '%alogliptin%'
               OR LOWER(c.concept_name) LIKE '%nesina%' OR LOWER(de.drug_source_value) LIKE '%nesina%'
               OR LOWER(c.concept_name) LIKE '%exenatide%' OR LOWER(de.drug_source_value) LIKE '%exenatide%'
               OR LOWER(c.concept_name) LIKE '%byetta%' OR LOWER(de.drug_source_value) LIKE '%byetta%'
               OR LOWER(c.concept_name) LIKE '%bydureon%' OR LOWER(de.drug_source_value) LIKE '%bydureon%'
               OR LOWER(c.concept_name) LIKE '%liraglutide%' OR LOWER(de.drug_source_value) LIKE '%liraglutide%'
               OR LOWER(c.concept_name) LIKE '%victoza%' OR LOWER(de.drug_source_value) LIKE '%victoza%'
               OR LOWER(c.concept_name) LIKE '%saxenda%' OR LOWER(de.drug_source_value) LIKE '%saxenda%'
               OR LOWER(c.concept_name) LIKE '%dulaglutide%' OR LOWER(de.drug_source_value) LIKE '%dulaglutide%'
               OR LOWER(c.concept_name) LIKE '%trulicity%' OR LOWER(de.drug_source_value) LIKE '%trulicity%'
               OR LOWER(c.concept_name) LIKE '%semaglutide%' OR LOWER(de.drug_source_value) LIKE '%semaglutide%'
               OR LOWER(c.concept_name) LIKE '%ozempic%' OR LOWER(de.drug_source_value) LIKE '%ozempic%'
               OR LOWER(c.concept_name) LIKE '%wegovy%' OR LOWER(de.drug_source_value) LIKE '%wegovy%'
               OR LOWER(c.concept_name) LIKE '%rybelsus%' OR LOWER(de.drug_source_value) LIKE '%rybelsus%'
               OR LOWER(c.concept_name) LIKE '%canagliflozin%' OR LOWER(de.drug_source_value) LIKE '%canagliflozin%'
               OR LOWER(c.concept_name) LIKE '%invokana%' OR LOWER(de.drug_source_value) LIKE '%invokana%'
               OR LOWER(c.concept_name) LIKE '%dapagliflozin%' OR LOWER(de.drug_source_value) LIKE '%dapagliflozin%'
               OR LOWER(c.concept_name) LIKE '%farxiga%' OR LOWER(de.drug_source_value) LIKE '%farxiga%'
               OR LOWER(c.concept_name) LIKE '%empagliflozin%' OR LOWER(de.drug_source_value) LIKE '%empagliflozin%'
               OR LOWER(c.concept_name) LIKE '%jardiance%' OR LOWER(de.drug_source_value) LIKE '%jardiance%'
               OR LOWER(c.concept_name) LIKE '%ertugliflozin%' OR LOWER(de.drug_source_value) LIKE '%ertugliflozin%'
               OR LOWER(c.concept_name) LIKE '%steglatro%' OR LOWER(de.drug_source_value) LIKE '%steglatro%'
               OR LOWER(c.concept_name) LIKE '%pioglitazone%' OR LOWER(de.drug_source_value) LIKE '%pioglitazone%'
               OR LOWER(c.concept_name) LIKE '%actos%' OR LOWER(de.drug_source_value) LIKE '%actos%'
               OR LOWER(c.concept_name) LIKE '%rosiglitazone%' OR LOWER(de.drug_source_value) LIKE '%rosiglitazone%'
               OR LOWER(c.concept_name) LIKE '%avandia%' OR LOWER(de.drug_source_value) LIKE '%avandia%'
               OR LOWER(c.concept_name) LIKE '%repaglinide%' OR LOWER(de.drug_source_value) LIKE '%repaglinide%'
               OR LOWER(c.concept_name) LIKE '%prandin%' OR LOWER(de.drug_source_value) LIKE '%prandin%'
               OR LOWER(c.concept_name) LIKE '%nateglinide%' OR LOWER(de.drug_source_value) LIKE '%nateglinide%'
               OR LOWER(c.concept_name) LIKE '%starlix%' OR LOWER(de.drug_source_value) LIKE '%starlix%'
               OR LOWER(c.concept_name) LIKE '%acarbose%' OR LOWER(de.drug_source_value) LIKE '%acarbose%'
               OR LOWER(c.concept_name) LIKE '%precose%' OR LOWER(de.drug_source_value) LIKE '%precose%'
               OR LOWER(c.concept_name) LIKE '%miglitol%' OR LOWER(de.drug_source_value) LIKE '%miglitol%'
               OR LOWER(c.concept_name) LIKE '%glyset%' OR LOWER(de.drug_source_value) LIKE '%glyset%'
           )
   )
)
OR (
   -- Criterion 3: At least 1 diagnosis AND abnormal lab values
   EXISTS (
       SELECT 1
       FROM public.condition_occurrence co3
       WHERE co3.person_id = p.person_id
           AND (
               co3.condition_source_value IN ('E11', 'E11.0', 'E11.00', 'E11.01', 'E11.1', 'E11.2', 'E11.21', 'E11.22', 'E11.29',
                   'E11.3', 'E11.31', 'E11.32', 'E11.33', 'E11.34', 'E11.35', 'E11.36', 'E11.37', 'E11.39',
                   'E11.4', 'E11.40', 'E11.41', 'E11.42', 'E11.43', 'E11.44', 'E11.49',
                   'E11.5', 'E11.51', 'E11.52', 'E11.59', 'E11.6', 'E11.61', 'E11.618', 'E11.62', 'E11.620', 'E11.621', 'E11.622', 'E11.628', 'E11.63', 'E11.630', 'E11.638', 'E11.64', 'E11.641', 'E11.649', 'E11.65', 'E11.69',
                   'E11.7', 'E11.8', 'E11.9',
                   '250.00', '250.02', '250.10', '250.12', '250.20', '250.22', '250.30', '250.32', '250.40', '250.42', '250.50', '250.52', '250.60', '250.62', '250.70', '250.72', '250.80', '250.82', '250.90', '250.92')
           )
   )
   AND EXISTS (
       SELECT 1
       FROM public.measurement m
       INNER JOIN public.concept c ON m.measurement_concept_id = c.concept_id
       WHERE m.person_id = p.person_id
           AND (
               (
                   (LOWER(c.concept_name) LIKE '%hemoglobin a1c%' OR LOWER(c.concept_name) LIKE '%hba1c%' OR LOWER(c.concept_name) LIKE '%glycohemoglobin%' OR LOWER(c.concept_name) LIKE '%glycated hemoglobin%')
                   AND m.value_as_number >= 6.5
               )
               OR (
                   (LOWER(c.concept_name) LIKE '%fasting glucose%' OR LOWER(c.concept_name) LIKE '%fasting blood glucose%' OR LOWER(c.concept_name) LIKE '%fasting plasma glucose%')
                   AND m.value_as_number >= 126
               )
               OR (
                   (LOWER(c.concept_name) LIKE '%glucose%' AND LOWER(c.concept_name) NOT LIKE '%fasting%' AND (LOWER(c.concept_name) LIKE '%2 hour%' OR LOWER(c.concept_name) LIKE '%2-hour%' OR LOWER(c.concept_name) LIKE '%ogtt%' OR LOWER(c.concept_name) LIKE '%oral glucose tolerance%'))
                   AND m.value_as_number >= 200
               )
           )
   )
)
OR (
   -- Criterion 4: Diabetes medication AND abnormal lab values
   EXISTS (
       SELECT 1
       FROM public.drug_exposure de2
       INNER JOIN public.concept c ON de2.drug_concept_id = c.concept_id
       WHERE de2.person_id = p.person_id
           AND (
               LOWER(c.concept_name) LIKE '%metformin%' OR LOWER(de2.drug_source_value) LIKE '%metformin%'
               OR LOWER(c.concept_name) LIKE '%glucophage%' OR LOWER(de2.drug_source_value) LIKE '%glucophage%'
               OR LOWER(c.concept_name) LIKE '%fortamet%' OR LOWER(de2.drug_source_value) LIKE '%fortamet%'
               OR LOWER(c.concept_name) LIKE '%glumetza%' OR LOWER(de2.drug_source_value) LIKE '%glumetza%'
               OR LOWER(c.concept_name) LIKE '%riomet%' OR LOWER(de2.drug_source_value) LIKE '%riomet%'
               OR LOWER(c.concept_name) LIKE '%glipizide%' OR LOWER(de2.drug_source_value) LIKE '%glipizide%'
               OR LOWER(c.concept_name) LIKE '%glucotrol%' OR LOWER(de2.drug_source_value) LIKE '%glucotrol%'
               OR LOWER(c.concept_name) LIKE '%glyburide%' OR LOWER(de2.drug_source_value) LIKE '%glyburide%'
               OR LOWER(c.concept_name) LIKE '%diabeta%' OR LOWER(de2.drug_source_value) LIKE '%diabeta%'
               OR LOWER(c.concept_name) LIKE '%micronase%' OR LOWER(de2.drug_source_value) LIKE '%micronase%'
               OR LOWER(c.concept_name) LIKE '%glimepiride%' OR LOWER(de2.drug_source_value) LIKE '%glimepiride%'
               OR LOWER(c.concept_name) LIKE '%amaryl%' OR LOWER(de2.drug_source_value) LIKE '%amaryl%'
               OR LOWER(c.concept_name) LIKE '%gliclazide%' OR LOWER(de2.drug_source_value) LIKE '%gliclazide%'
               OR LOWER(c.concept_name) LIKE '%sitagliptin%' OR LOWER(de2.drug_source_value) LIKE '%sitagliptin%'
               OR LOWER(c.concept_name) LIKE '%januvia%' OR LOWER(de2.drug_source_value) LIKE '%januvia%'
               OR LOWER(c.concept_name) LIKE '%saxagliptin%' OR LOWER(de2.drug_source_value) LIKE '%saxagliptin%'
               OR LOWER(c.concept_name) LIKE '%onglyza%' OR LOWER(de2.drug_source_value) LIKE '%onglyza%'
               OR LOWER(c.concept_name) LIKE '%linagliptin%' OR LOWER(de2.drug_source_value) LIKE '%linagliptin%'
               OR LOWER(c.concept_name) LIKE '%tradjenta%' OR LOWER(de2.drug_source_value) LIKE '%tradjenta%'
               OR LOWER(c.concept_name) LIKE '%alogliptin%' OR LOWER(de2.drug_source_value) LIKE '%alogliptin%'
               OR LOWER(c.concept_name) LIKE '%nesina%' OR LOWER(de2.drug_source_value) LIKE '%nesina%'
               OR LOWER(c.concept_name) LIKE '%exenatide%' OR LOWER(de2.drug_source_value) LIKE '%exenatide%'
               OR LOWER(c.concept_name) LIKE '%byetta%' OR LOWER(de2.drug_source_value) LIKE '%byetta%'
               OR LOWER(c.concept_name) LIKE '%bydureon%' OR LOWER(de2.drug_source_value) LIKE '%bydureon%'
               OR LOWER(c.concept_name) LIKE '%liraglutide%' OR LOWER(de2.drug_source_value) LIKE '%liraglutide%'
               OR LOWER(c.concept_name) LIKE '%victoza%' OR LOWER(de2.drug_source_value) LIKE '%victoza%'
               OR LOWER(c.concept_name) LIKE '%saxenda%' OR LOWER(de2.drug_source_value) LIKE '%saxenda%'
               OR LOWER(c.concept_name) LIKE '%dulaglutide%' OR LOWER(de2.drug_source_value) LIKE '%dulaglutide%'
               OR LOWER(c.concept_name) LIKE '%trulicity%' OR LOWER(de2.drug_source_value) LIKE '%trulicity%'
               OR LOWER(c.concept_name) LIKE '%semaglutide%' OR LOWER(de2.drug_source_value) LIKE '%semaglutide%'
               OR LOWER(c.concept_name) LIKE '%ozempic%' OR LOWER(de2.drug_source_value) LIKE '%ozempic%'
               OR LOWER(c.concept_name) LIKE '%wegovy%' OR LOWER(de2.drug_source_value) LIKE '%wegovy%'
               OR LOWER(c.concept_name) LIKE '%rybelsus%' OR LOWER(de2.drug_source_value) LIKE '%rybelsus%'
               OR LOWER(c.concept_name) LIKE '%canagliflozin%' OR LOWER(de2.drug_source_value) LIKE '%canagliflozin%'
               OR LOWER(c.concept_name) LIKE '%invokana%' OR LOWER(de2.drug_source_value) LIKE '%invokana%'
               OR LOWER(c.concept_name) LIKE '%dapagliflozin%' OR LOWER(de2.drug_source_value) LIKE '%dapagliflozin%'
               OR LOWER(c.concept_name) LIKE '%farxiga%' OR LOWER(de2.drug_source_value) LIKE '%farxiga%'
               OR LOWER(c.concept_name) LIKE '%empagliflozin%' OR LOWER(de2.drug_source_value) LIKE '%empagliflozin%'
               OR LOWER(c.concept_name) LIKE '%jardiance%' OR LOWER(de2.drug_source_value) LIKE '%jardiance%'
               OR LOWER(c.concept_name) LIKE '%ertugliflozin%' OR LOWER(de2.drug_source_value) LIKE '%ertugliflozin%'
               OR LOWER(c.concept_name) LIKE '%steglatro%' OR LOWER(de2.drug_source_value) LIKE '%steglatro%'
               OR LOWER(c.concept_name) LIKE '%pioglitazone%' OR LOWER(de2.drug_source_value) LIKE '%pioglitazone%'
               OR LOWER(c.concept_name) LIKE '%actos%' OR LOWER(de2.drug_source_value) LIKE '%actos%'
               OR LOWER(c.concept_name) LIKE '%rosiglitazone%' OR LOWER(de2.drug_source_value) LIKE '%rosiglitazone%'
               OR LOWER(c.concept_name) LIKE '%avandia%' OR LOWER(de2.drug_source_value) LIKE '%avandia%'
               OR LOWER(c.concept_name) LIKE '%repaglinide%' OR LOWER(de2.drug_source_value) LIKE '%repaglinide%'
               OR LOWER(c.concept_name) LIKE '%prandin%' OR LOWER(de2.drug_source_value) LIKE '%prandin%'
               OR LOWER(c.concept_name) LIKE '%nateglinide%' OR LOWER(de2.drug_source_value) LIKE '%nateglinide%'
               OR LOWER(c.concept_name) LIKE '%starlix%' OR LOWER(de2.drug_source_value) LIKE '%starlix%'
               OR LOWER(c.concept_name) LIKE '%acarbose%' OR LOWER(de2.drug_source_value) LIKE '%acarbose%'
               OR LOWER(c.concept_name) LIKE '%precose%' OR LOWER(de2.drug_source_value) LIKE '%precose%'
               OR LOWER(c.concept_name) LIKE '%miglitol%' OR LOWER(de2.drug_source_value) LIKE '%miglitol%'
               OR LOWER(c.concept_name) LIKE '%glyset%' OR LOWER(de2.drug_source_value) LIKE '%glyset%'
           )
   )
   AND EXISTS (
       SELECT 1
       FROM public.measurement m2
       INNER JOIN public.concept c ON m2.measurement_concept_id = c.concept_id
       WHERE m2.person_id = p.person_id
           AND (
               (
                   (LOWER(c.concept_name) LIKE '%hemoglobin a1c%' OR LOWER(c.concept_name) LIKE '%hba1c%' OR LOWER(c.concept_name) LIKE '%glycohemoglobin%' OR LOWER(c.concept_name) LIKE '%glycated hemoglobin%')
                   AND m2.value_as_number >= 6.5
               )
               OR (
                   (LOWER(c.concept_name) LIKE '%fasting glucose%' OR LOWER(c.concept_name) LIKE '%fasting blood glucose%' OR LOWER(c.concept_name) LIKE '%fasting plasma glucose%')
                   AND m2.value_as_number >= 126
               )
               OR (
                   (LOWER(c.concept_name) LIKE '%glucose%' AND LOWER(c.concept_name) NOT LIKE '%fasting%' AND (LOWER(c.concept_name) LIKE '%2 hour%' OR LOWER(c.concept_name) LIKE '%2-hour%' OR LOWER(c.concept_name) LIKE '%ogtt%' OR LOWER(c.concept_name) LIKE '%oral glucose tolerance%'))
                   AND m2.value_as_number >= 200
               )
           )
   )
)
AND NOT EXISTS (
   -- Exclude Type 1 Diabetes
   SELECT 1
   FROM public.condition_occurrence co_excl
   WHERE co_excl.person_id = p.person_id
       AND (
           co_excl.condition_source_value IN ('E10', 'E10.1', 'E10.10', 'E10.11', 'E10.2', 'E10.21', 'E10.22', 'E10.29',
               'E10.3', 'E10.31', 'E10.32', 'E10.33', 'E10.34', 'E10.35', 'E10.36', 'E10.37', 'E10.39',
               'E10.4', 'E10.40', 'E10.41', 'E10.42', 'E10.43', 'E10.44', 'E10.49',
               'E10.5', 'E10.51', 'E10.52', 'E10.59', 'E10.6', 'E10.61', 'E10.618', 'E10.62', 'E10.620', 'E10.621', 'E10.622', 'E10.628', 'E10.63', 'E10.630', 'E10.638', 'E10.64', 'E10.641', 'E10.649', 'E10.65', 'E10.69',
               'E10.7', 'E10.8', 'E10.9',
               '250.01', '250.03', '250.11', '250.13', '250.21', '250.23', '250.31', '250.33', '250.41', '250.43', '250.51', '250.53', '250.61', '250.63', '250.71', '250.73', '250.81', '250.83', '250.91', '250.93')
       )
)
AND NOT EXISTS (
   -- Exclude Gestational Diabetes
   SELECT 1
   FROM public.condition_occurrence co_gest
   WHERE co_gest.person_id = p.person_id
       AND (
           co_gest.condition_source_value IN ('O24.4', 'O24.41', 'O24.410', 'O24.414', 'O24.415', 'O24.419', 'O24.42', 'O24.420', 'O24.424', 'O24.425', 'O24.429', 'O24.43', 'O24.430', 'O24.434', 'O24.435', 'O24.439',
               '648.8', '648.80', '648.81', '648.82', '648.83', '648.84')
       )
)
AND NOT EXISTS (
   -- Exclude Secondary Diabetes
   SELECT 1
   FROM public.condition_occurrence co_sec
   WHERE co_sec.person_id = p.person_id
       AND (
           co_sec.condition_source_value LIKE 'E08%' OR co_sec.condition_source_value LIKE 'E09%' OR co_sec.condition_source_value LIKE 'E13%'
       )
)
LEFT JOIN public.condition_occurrence co_dx ON p.person_id = co_dx.person_id
   AND co_dx.condition_source_value IN ('E11', 'E11.0', 'E11.00', 'E11.01', 'E11.1', 'E11.2', 'E11.21', 'E11.22', 'E11.29',
       'E11.3', 'E11.31', 'E11.32', 'E11.33', 'E11.34', 'E11.35', 'E11.36', 'E11.37', 'E11.39',
       'E11.4', 'E11.40', 'E11.41', 'E11.42', 'E11.43', 'E11.44', 'E11.49',
       'E11.5', 'E11.51', 'E11.52', 'E11.59', 'E11.6', 'E11.61', 'E11.618', 'E11.62', 'E11.620', 'E11.621', 'E11.622', 'E11.628', 'E11.63', 'E11.630', 'E11.638', 'E11.64', 'E11.641', 'E11.649', 'E11.65', 'E11.69',
       'E11.7', 'E11.8', 'E11.9',
       '250.00', '250.02', '250.10', '250.12', '250.20', '250.22', '250.30', '250.32', '250.40', '250.42', '250.50', '250.52', '250.60', '250.62', '250.70', '250.72', '250.80', '250.82', '250.90', '250.92')
LEFT JOIN public.drug_exposure de_med ON p.person_id = de_med.person_id
LEFT JOIN public.measurement m_lab ON p.person_id = m_lab.person_id
GROUP BY p.person_id, p.year_of_birth, p.gender_concept_id, p.race_concept_id, p.ethnicity_concept_id
ORDER BY p.person_id;


