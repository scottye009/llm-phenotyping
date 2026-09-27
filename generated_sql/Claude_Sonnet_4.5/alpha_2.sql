

-- Type 2 Diabetes Phenotyping Algorithm
-- This query identifies patients with Type 2 Diabetes using OMOP CDM


WITH


-- Step 1: Identify patients with Type 2 Diabetes diagnosis codes
t2dm_diagnosis AS (
   SELECT DISTINCT
       co.person_id,
       'T2DM_Diagnosis' AS criterion
   FROM public.condition_occurrence co
   WHERE (
       -- ICD-10-CM codes for Type 2 Diabetes
       co.condition_source_value IN (
           'E11', 'E11.0', 'E11.00', 'E11.01', 'E11.1', 'E11.2', 'E11.21', 'E11.22',
           'E11.29', 'E11.3', 'E11.31', 'E11.32', 'E11.33', 'E11.34', 'E11.35',
           'E11.36', 'E11.37', 'E11.39', 'E11.4', 'E11.40', 'E11.41', 'E11.42',
           'E11.43', 'E11.44', 'E11.49', 'E11.5', 'E11.51', 'E11.52', 'E11.59',
           'E11.6', 'E11.61', 'E11.62', 'E11.63', 'E11.64', 'E11.65', 'E11.69',
           'E11.8', 'E11.9'
       )
       OR
       -- ICD-9-CM codes for Type 2 Diabetes
       co.condition_source_value IN (
           '250.00', '250.02', '250.10', '250.12', '250.20', '250.22', '250.30',
           '250.32', '250.40', '250.42', '250.50', '250.52', '250.60', '250.62',
           '250.70', '250.72', '250.80', '250.82', '250.90', '250.92'
       )
   )
   GROUP BY co.person_id
   HAVING COUNT(DISTINCT co.condition_occurrence_id) >= 2
),


-- Step 2: Identify patients with antidiabetic medications
t2dm_medications AS (
   SELECT DISTINCT
       de.person_id,
       'T2DM_Medication' AS criterion
   FROM public.drug_exposure de
   WHERE (
       -- Metformin
       LOWER(de.drug_source_value) LIKE '%metformin%' OR
       LOWER(de.drug_source_value) LIKE '%glucophage%' OR
       LOWER(de.drug_source_value) LIKE '%fortamet%' OR
       LOWER(de.drug_source_value) LIKE '%glumetza%' OR
      
       -- Sulfonylureas
       LOWER(de.drug_source_value) LIKE '%glyburide%' OR
       LOWER(de.drug_source_value) LIKE '%glipizide%' OR
       LOWER(de.drug_source_value) LIKE '%glimepiride%' OR
       LOWER(de.drug_source_value) LIKE '%diabeta%' OR
       LOWER(de.drug_source_value) LIKE '%glucotrol%' OR
       LOWER(de.drug_source_value) LIKE '%amaryl%' OR
      
       -- DPP-4 Inhibitors
       LOWER(de.drug_source_value) LIKE '%sitagliptin%' OR
       LOWER(de.drug_source_value) LIKE '%saxagliptin%' OR
       LOWER(de.drug_source_value) LIKE '%linagliptin%' OR
       LOWER(de.drug_source_value) LIKE '%alogliptin%' OR
       LOWER(de.drug_source_value) LIKE '%januvia%' OR
       LOWER(de.drug_source_value) LIKE '%onglyza%' OR
       LOWER(de.drug_source_value) LIKE '%tradjenta%' OR
       LOWER(de.drug_source_value) LIKE '%nesina%' OR
      
       -- GLP-1 Agonists
       LOWER(de.drug_source_value) LIKE '%exenatide%' OR
       LOWER(de.drug_source_value) LIKE '%liraglutide%' OR
       LOWER(de.drug_source_value) LIKE '%dulaglutide%' OR
       LOWER(de.drug_source_value) LIKE '%semaglutide%' OR
       LOWER(de.drug_source_value) LIKE '%byetta%' OR
       LOWER(de.drug_source_value) LIKE '%victoza%' OR
       LOWER(de.drug_source_value) LIKE '%trulicity%' OR
       LOWER(de.drug_source_value) LIKE '%ozempic%' OR
       LOWER(de.drug_source_value) LIKE '%wegovy%' OR
      
       -- SGLT2 Inhibitors
       LOWER(de.drug_source_value) LIKE '%canagliflozin%' OR
       LOWER(de.drug_source_value) LIKE '%dapagliflozin%' OR
       LOWER(de.drug_source_value) LIKE '%empagliflozin%' OR
       LOWER(de.drug_source_value) LIKE '%invokana%' OR
       LOWER(de.drug_source_value) LIKE '%farxiga%' OR
       LOWER(de.drug_source_value) LIKE '%jardiance%' OR
      
       -- Thiazolidinediones
       LOWER(de.drug_source_value) LIKE '%pioglitazone%' OR
       LOWER(de.drug_source_value) LIKE '%rosiglitazone%' OR
       LOWER(de.drug_source_value) LIKE '%actos%' OR
       LOWER(de.drug_source_value) LIKE '%avandia%'
   )
   GROUP BY de.person_id
   HAVING COUNT(DISTINCT de.drug_exposure_id) >= 2
),


-- Step 3: Identify patients with abnormal lab values
t2dm_labs AS (
   SELECT DISTINCT
       m.person_id,
       'T2DM_Labs' AS criterion
   FROM public.measurement m
   WHERE (
       -- HbA1c >= 6.5%
       (LOWER(m.measurement_source_value) LIKE '%hba1c%' OR
        LOWER(m.measurement_source_value) LIKE '%hemoglobin a1c%' OR
        LOWER(m.measurement_source_value) LIKE '%glycohemoglobin%')
       AND m.value_as_number >= 6.5
   )
   OR (
       -- Fasting Glucose >= 126 mg/dL
       (LOWER(m.measurement_source_value) LIKE '%fasting glucose%' OR
        LOWER(m.measurement_source_value) LIKE '%fasting blood glucose%')
       AND m.value_as_number >= 126
   )
   OR (
       -- Random Glucose >= 200 mg/dL
       (LOWER(m.measurement_source_value) LIKE '%glucose%' AND
        LOWER(m.measurement_source_value) NOT LIKE '%fasting%')
       AND m.value_as_number >= 200
   )
),


-- Step 4: Identify exclusions (Type 1 Diabetes, Gestational Diabetes)
exclusions AS (
   SELECT DISTINCT
       co.person_id
   FROM public.condition_occurrence co
   WHERE (
       -- Type 1 Diabetes ICD-10-CM
       co.condition_source_value LIKE 'E10%' OR
      
       -- Type 1 Diabetes ICD-9-CM
       co.condition_source_value IN (
           '250.01', '250.03', '250.11', '250.13', '250.21', '250.23',
           '250.31', '250.33', '250.41', '250.43', '250.51', '250.53',
           '250.61', '250.63', '250.71', '250.73', '250.81', '250.83',
           '250.91', '250.93'
       ) OR
      
       -- Gestational Diabetes ICD-10-CM
       co.condition_source_value LIKE 'O24%' OR
      
       -- Gestational Diabetes ICD-9-CM
       co.condition_source_value IN ('648.8', '648.80', '648.81', '648.82', '648.83', '648.84')
   )
),


-- Step 5: Combine criteria
t2dm_cohort AS (
   SELECT DISTINCT person_id
   FROM (
       -- Patients with diagnosis codes
       SELECT person_id FROM t2dm_diagnosis
      
       UNION
      
       -- Patients with medications
       SELECT person_id FROM t2dm_medications
      
       UNION
      
       -- Patients with abnormal labs AND medications
       SELECT l.person_id
       FROM t2dm_labs l
       INNER JOIN t2dm_medications m ON l.person_id = m.person_id
   ) combined
   WHERE person_id NOT IN (SELECT person_id FROM exclusions)
)


-- Final output: Type 2 Diabetes cohort
SELECT
   tc.person_id,
   p.gender_concept_id,
   p.birth_datetime,
   EXTRACT(YEAR FROM AGE(CURRENT_DATE, p.birth_datetime)) AS age,
   CASE
       WHEN EXISTS (SELECT 1 FROM t2dm_diagnosis d WHERE d.person_id = tc.person_id)
       THEN 'Yes' ELSE 'No'
   END AS has_diagnosis,
   CASE
       WHEN EXISTS (SELECT 1 FROM t2dm_medications m WHERE m.person_id = tc.person_id)
       THEN 'Yes' ELSE 'No'
   END AS has_medication,
   CASE
       WHEN EXISTS (SELECT 1 FROM t2dm_labs l WHERE l.person_id = tc.person_id)
       THEN 'Yes' ELSE 'No'
   END AS has_abnormal_labs
FROM t2dm_cohort tc
INNER JOIN public.person p ON tc.person_id = p.person_id
ORDER BY tc.person_id;


