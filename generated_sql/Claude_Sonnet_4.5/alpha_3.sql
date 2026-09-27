
-- Type 2 Diabetes Phenotyping Algorithm
-- OMOP CDM Version 5.4


WITH type2_diabetes_dx AS (
   -- ICD-10-CM codes for Type 2 Diabetes
   SELECT DISTINCT
       co.person_id,
       co.condition_start_date,
       co.condition_concept_id
   FROM public.condition_occurrence co
   INNER JOIN public.concept c ON co.condition_concept_id = c.concept_id
   WHERE (
       -- ICD-10-CM Type 2 Diabetes codes
       co.condition_source_value LIKE 'E11%'
       OR c.concept_code LIKE 'E11%'
       -- ICD-9-CM Type 2 Diabetes codes
       OR co.condition_source_value IN ('250.00', '250.02', '250.10', '250.12', '250.20', '250.22',
                                        '250.30', '250.32', '250.40', '250.42', '250.50', '250.52',
                                        '250.60', '250.62', '250.70', '250.72', '250.80', '250.82',
                                        '250.90', '250.92')
       OR c.concept_code IN ('250.00', '250.02', '250.10', '250.12', '250.20', '250.22',
                             '250.30', '250.32', '250.40', '250.42', '250.50', '250.52',
                             '250.60', '250.62', '250.70', '250.72', '250.80', '250.82',
                             '250.90', '250.92')
   )
),


type1_diabetes_exclusion AS (
   -- Exclude Type 1 Diabetes
   SELECT DISTINCT person_id
   FROM public.condition_occurrence co
   INNER JOIN public.concept c ON co.condition_concept_id = c.concept_id
   WHERE (
       -- ICD-10-CM Type 1 Diabetes codes
       co.condition_source_value LIKE 'E10%'
       OR c.concept_code LIKE 'E10%'
       -- ICD-9-CM Type 1 Diabetes codes
       OR co.condition_source_value IN ('250.01', '250.03', '250.11', '250.13', '250.21', '250.23',
                                        '250.31', '250.33', '250.41', '250.43', '250.51', '250.53',
                                        '250.61', '250.63', '250.71', '250.73', '250.81', '250.83',
                                        '250.91', '250.93')
   )
),


gestational_diabetes_exclusion AS (
   -- Exclude Gestational Diabetes
   SELECT DISTINCT person_id
   FROM public.condition_occurrence co
   WHERE co.condition_source_value IN ('O24.4', 'O24.41', 'O24.42', 'O24.43', '648.8', '648.80', '648.81', '648.82', '648.83', '648.84')
),


diabetes_medications AS (
   -- Anti-diabetic medications (excluding insulin only for Type 1)
   SELECT DISTINCT
       de.person_id,
       de.drug_exposure_start_date,
       de.drug_concept_id
   FROM public.drug_exposure de
   INNER JOIN public.concept c ON de.drug_concept_id = c.concept_id
   WHERE (
       -- Metformin
       LOWER(de.drug_source_value) LIKE '%metformin%'
       OR LOWER(c.concept_name) LIKE '%metformin%'
       OR LOWER(c.concept_name) LIKE '%glucophage%'
       OR LOWER(c.concept_name) LIKE '%fortamet%'
       OR LOWER(c.concept_name) LIKE '%glumetza%'
      
       -- Sulfonylureas
       OR LOWER(c.concept_name) LIKE '%glipizide%'
       OR LOWER(c.concept_name) LIKE '%glyburide%'
       OR LOWER(c.concept_name) LIKE '%glimepiride%'
       OR LOWER(c.concept_name) LIKE '%glucotrol%'
       OR LOWER(c.concept_name) LIKE '%diabeta%'
       OR LOWER(c.concept_name) LIKE '%amaryl%'
      
       -- DPP-4 Inhibitors
       OR LOWER(c.concept_name) LIKE '%sitagliptin%'
       OR LOWER(c.concept_name) LIKE '%saxagliptin%'
       OR LOWER(c.concept_name) LIKE '%linagliptin%'
       OR LOWER(c.concept_name) LIKE '%alogliptin%'
       OR LOWER(c.concept_name) LIKE '%januvia%'
       OR LOWER(c.concept_name) LIKE '%onglyza%'
       OR LOWER(c.concept_name) LIKE '%tradjenta%'
       OR LOWER(c.concept_name) LIKE '%nesina%'
      
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


abnormal_labs AS (
   -- Abnormal laboratory values indicating diabetes
   SELECT DISTINCT
       m.person_id,
       m.measurement_date,
       m.measurement_concept_id,
       m.value_as_number
   FROM public.measurement m
   INNER JOIN public.concept c ON m.measurement_concept_id = c.concept_id
   WHERE (
       -- HbA1c >= 6.5%
       (LOWER(c.concept_name) LIKE '%hemoglobin a1c%' OR LOWER(c.concept_name) LIKE '%hba1c%')
       AND m.value_as_number >= 6.5
   ) OR (
       -- Fasting glucose >= 126 mg/dL
       (LOWER(c.concept_name) LIKE '%fasting glucose%' OR LOWER(c.concept_name) LIKE '%fasting blood glucose%')
       AND m.value_as_number >= 126
   ) OR (
       -- Random glucose >= 200 mg/dL
       (LOWER(c.concept_name) LIKE '%glucose%' AND LOWER(c.concept_name) NOT LIKE '%fasting%')
       AND m.value_as_number >= 200
   )
),


diagnosis_count AS (
   -- Count distinct diagnosis dates
   SELECT
       person_id,
       COUNT(DISTINCT condition_start_date) AS dx_count
   FROM type2_diabetes_dx
   GROUP BY person_id
),


final_cohort AS (
   SELECT DISTINCT p.person_id
   FROM public.person p
   WHERE (
       -- Criterion 1: At least 2 diagnoses on different dates
       p.person_id IN (
           SELECT person_id
           FROM diagnosis_count
           WHERE dx_count >= 2
       )
       OR
       -- Criterion 2: 1 diagnosis + 1 medication
       (
           p.person_id IN (SELECT person_id FROM type2_diabetes_dx)
           AND p.person_id IN (SELECT person_id FROM diabetes_medications)
       )
       OR
       -- Criterion 3: 1 diagnosis + abnormal lab
       (
           p.person_id IN (SELECT person_id FROM type2_diabetes_dx)
           AND p.person_id IN (SELECT person_id FROM abnormal_labs)
       )
       OR
       -- Criterion 4: Medication + abnormal lab
       (
           p.person_id IN (SELECT person_id FROM diabetes_medications)
           AND p.person_id IN (SELECT person_id FROM abnormal_labs)
       )
   )
   AND p.person_id NOT IN (SELECT person_id FROM type1_diabetes_exclusion)
   AND p.person_id NOT IN (SELECT person_id FROM gestational_diabetes_exclusion)
)


-- Final output with additional patient details
SELECT
   fc.person_id,
   p.year_of_birth,
   p.gender_concept_id,
   MIN(COALESCE(t2d.condition_start_date, dm.drug_exposure_start_date, al.measurement_date)) AS index_date
FROM final_cohort fc
INNER JOIN public.person p ON fc.person_id = p.person_id
LEFT JOIN type2_diabetes_dx t2d ON fc.person_id = t2d.person_id
LEFT JOIN diabetes_medications dm ON fc.person_id = dm.person_id
LEFT JOIN abnormal_labs al ON fc.person_id = al.person_id
GROUP BY fc.person_id, p.year_of_birth, p.gender_concept_id
ORDER BY fc.person_id;

