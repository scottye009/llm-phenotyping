
-- Type 2 Diabetes Phenotyping Algorithm
-- This query identifies patients with Type 2 Diabetes from OMOP CDM


WITH t2dm_diagnoses AS (
   -- ICD-10-CM codes for Type 2 Diabetes
   SELECT DISTINCT
       co.person_id,
       co.condition_start_date AS diagnosis_date
   FROM public.condition_occurrence co
   JOIN public.concept c ON co.condition_concept_id = c.concept_id
   WHERE (
       -- ICD-10-CM: E11.x (Type 2 Diabetes)
       co.condition_source_value LIKE 'E11%'
       OR c.concept_code LIKE 'E11%'
       -- ICD-9-CM: 250.x0 and 250.x2 (Type 2 Diabetes)
       OR co.condition_source_value LIKE '250._0'
       OR co.condition_source_value LIKE '250._2'
       OR c.concept_code LIKE '250._0'
       OR c.concept_code LIKE '250._2'
   )
),


t1dm_exclusions AS (
   -- Exclude Type 1 Diabetes
   SELECT DISTINCT person_id
   FROM public.condition_occurrence co
   WHERE (
       -- ICD-10-CM: E10.x (Type 1 Diabetes)
       condition_source_value LIKE 'E10%'
       -- ICD-9-CM: 250.x1 and 250.x3 (Type 1 Diabetes)
       OR condition_source_value LIKE '250._1'
       OR condition_source_value LIKE '250._3'
   )
),


gestational_exclusions AS (
   -- Exclude Gestational Diabetes
   SELECT DISTINCT person_id
   FROM public.condition_occurrence
   WHERE (
       -- ICD-10-CM: O24.4x (Gestational Diabetes)
       condition_source_value LIKE 'O24.4%'
       -- ICD-9-CM: 648.8x (Gestational Diabetes)
       OR condition_source_value LIKE '648.8%'
   )
),


t2dm_medications AS (
   -- Antidiabetic medications (excluding insulin monotherapy)
   SELECT DISTINCT
       de.person_id,
       de.drug_exposure_start_date AS medication_date
   FROM public.drug_exposure de
   JOIN public.concept c ON de.drug_concept_id = c.concept_id
   WHERE (
       -- Metformin
       LOWER(c.concept_name) LIKE '%metformin%'
       OR LOWER(de.drug_source_value) LIKE '%metformin%'
       OR LOWER(c.concept_name) LIKE '%glucophage%'
       -- Sulfonylureas
       OR LOWER(c.concept_name) LIKE '%glyburide%'
       OR LOWER(c.concept_name) LIKE '%glipizide%'
       OR LOWER(c.concept_name) LIKE '%glimepiride%'
       OR LOWER(c.concept_name) LIKE '%diabeta%'
       OR LOWER(c.concept_name) LIKE '%glucotrol%'
       OR LOWER(c.concept_name) LIKE '%amaryl%'
       -- DPP-4 Inhibitors
       OR LOWER(c.concept_name) LIKE '%sitagliptin%'
       OR LOWER(c.concept_name) LIKE '%saxagliptin%'
       OR LOWER(c.concept_name) LIKE '%linagliptin%'
       OR LOWER(c.concept_name) LIKE '%januvia%'
       OR LOWER(c.concept_name) LIKE '%onglyza%'
       OR LOWER(c.concept_name) LIKE '%tradjenta%'
       -- GLP-1 Agonists
       OR LOWER(c.concept_name) LIKE '%exenatide%'
       OR LOWER(c.concept_name) LIKE '%liraglutide%'
       OR LOWER(c.concept_name) LIKE '%dulaglutide%'
       OR LOWER(c.concept_name) LIKE '%semaglutide%'
       OR LOWER(c.concept_name) LIKE '%byetta%'
       OR LOWER(c.concept_name) LIKE '%victoza%'
       OR LOWER(c.concept_name) LIKE '%trulicity%'
       OR LOWER(c.concept_name) LIKE '%ozempic%'
       -- SGLT2 Inhibitors
       OR LOWER(c.concept_name) LIKE '%canagliflozin%'
       OR LOWER(c.concept_name) LIKE '%dapagliflozin%'
       OR LOWER(c.concept_name) LIKE '%empagliflozin%'
       OR LOWER(c.concept_name) LIKE '%invokana%'
       OR LOWER(c.concept_name) LIKE '%farxiga%'
       OR LOWER(c.concept_name) LIKE '%jardiance%'
       -- Thiazolidinediones
       OR LOWER(c.concept_name) LIKE '%pioglitazone%'
       OR LOWER(c.concept_name) LIKE '%rosiglitazone%'
       OR LOWER(c.concept_name) LIKE '%actos%'
       OR LOWER(c.concept_name) LIKE '%avandia%'
   )
),


t2dm_labs AS (
   -- Abnormal glucose or HbA1c measurements
   SELECT DISTINCT
       m.person_id,
       m.measurement_date AS lab_date
   FROM public.measurement m
   JOIN public.concept c ON m.measurement_concept_id = c.concept_id
   WHERE (
       -- HbA1c >= 6.5%
       (LOWER(c.concept_name) LIKE '%hemoglobin a1c%'
        OR LOWER(c.concept_name) LIKE '%hba1c%')
       AND m.value_as_number >= 6.5
   ) OR (
       -- Fasting Glucose >= 126 mg/dL
       LOWER(c.concept_name) LIKE '%fasting glucose%'
       AND m.value_as_number >= 126
   ) OR (
       -- Random Glucose >= 200 mg/dL
       (LOWER(c.concept_name) LIKE '%glucose%'
        AND LOWER(c.concept_name) NOT LIKE '%fasting%')
       AND m.value_as_number >= 200
   )
),


multiple_diagnoses AS (
   -- At least 2 diagnoses on different dates
   SELECT person_id
   FROM t2dm_diagnoses
   GROUP BY person_id
   HAVING COUNT(DISTINCT diagnosis_date) >= 2
),


diagnosis_plus_medication AS (
   -- At least 1 diagnosis + 1 medication
   SELECT DISTINCT d.person_id
   FROM t2dm_diagnoses d
   INNER JOIN t2dm_medications m ON d.person_id = m.person_id
),


diagnosis_plus_lab AS (
   -- At least 1 diagnosis + 1 abnormal lab
   SELECT DISTINCT d.person_id
   FROM t2dm_diagnoses d
   INNER JOIN t2dm_labs l ON d.person_id = l.person_id
)


-- Final cohort: Union of all qualifying criteria, excluding Type 1 and gestational diabetes
SELECT DISTINCT
   p.person_id,
   p.gender_concept_id,
   p.year_of_birth,
   p.race_concept_id,
   p.ethnicity_concept_id,
   'Type 2 Diabetes' AS phenotype
FROM public.person p
WHERE p.person_id IN (
   SELECT person_id FROM multiple_diagnoses
   UNION
   SELECT person_id FROM diagnosis_plus_medication
   UNION
   SELECT person_id FROM diagnosis_plus_lab
)
AND p.person_id NOT IN (SELECT person_id FROM t1dm_exclusions)
AND p.person_id NOT IN (SELECT person_id FROM gestational_exclusions)
ORDER BY p.person_id;

