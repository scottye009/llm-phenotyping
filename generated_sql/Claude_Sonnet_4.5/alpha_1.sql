
-- Type 2 Diabetes Phenotyping Algorithm
-- This algorithm identifies patients with Type 2 Diabetes using OMOP CDM


WITH


-- Step 1: Identify Type 2 Diabetes diagnosis codes
t2dm_diagnosis AS (
   SELECT DISTINCT
       co.person_id,
       co.condition_start_date AS index_date,
       'Diagnosis' AS criteria_type
   FROM public.condition_occurrence co
   INNER JOIN public.concept c ON co.condition_concept_id = c.concept_id
   WHERE (
       -- ICD-10-CM codes for Type 2 Diabetes
       co.condition_source_value IN ('E11', 'E11.0', 'E11.00', 'E11.01', 'E11.1', 'E11.2', 'E11.21',
           'E11.22', 'E11.29', 'E11.3', 'E11.31', 'E11.32', 'E11.33', 'E11.34', 'E11.35', 'E11.36',
           'E11.37', 'E11.39', 'E11.4', 'E11.40', 'E11.41', 'E11.42', 'E11.43', 'E11.44', 'E11.49',
           'E11.5', 'E11.51', 'E11.52', 'E11.59', 'E11.6', 'E11.61', 'E11.62', 'E11.63', 'E11.64',
           'E11.65', 'E11.69', 'E11.8', 'E11.9')
       OR
       -- ICD-9-CM codes for Type 2 Diabetes
       co.condition_source_value IN ('250.00', '250.02', '250.10', '250.12', '250.20', '250.22',
           '250.30', '250.32', '250.40', '250.42', '250.50', '250.52', '250.60', '250.62',
           '250.70', '250.72', '250.80', '250.82', '250.90', '250.92')
   )
),


-- Step 2: Identify elevated lab values
abnormal_labs AS (
   SELECT DISTINCT
       m.person_id,
       m.measurement_date AS index_date,
       'Laboratory' AS criteria_type
   FROM public.measurement m
   INNER JOIN public.concept c ON m.measurement_concept_id = c.concept_id
   WHERE (
       -- HbA1c >= 6.5%
       (c.concept_name ILIKE '%hemoglobin a1c%' OR c.concept_name ILIKE '%hba1c%')
       AND m.value_as_number >= 6.5
       AND (m.unit_concept_id IN (SELECT concept_id FROM public.concept WHERE concept_name = '%')
            OR m.unit_source_value = '%')
   )
   OR (
       -- Fasting glucose >= 126 mg/dL
       (c.concept_name ILIKE '%fasting glucose%' OR c.concept_name ILIKE '%fasting blood glucose%')
       AND m.value_as_number >= 126
       AND (m.unit_concept_id IN (SELECT concept_id FROM public.concept WHERE concept_name = 'mg/dL')
            OR m.unit_source_value IN ('mg/dL', 'mg/dl'))
   )
   OR (
       -- Random glucose >= 200 mg/dL (with symptoms)
       (c.concept_name ILIKE '%glucose%' AND c.concept_name NOT ILIKE '%fasting%')
       AND m.value_as_number >= 200
       AND (m.unit_concept_id IN (SELECT concept_id FROM public.concept WHERE concept_name = 'mg/dL')
            OR m.unit_source_value IN ('mg/dL', 'mg/dl'))
   )
),


-- Step 3: Identify diabetes medications
diabetes_medications AS (
   SELECT DISTINCT
       de.person_id,
       de.drug_exposure_start_date AS index_date,
       'Medication' AS criteria_type
   FROM public.drug_exposure de
   INNER JOIN public.concept c ON de.drug_concept_id = c.concept_id
   WHERE (
       -- Metformin
       c.concept_name ILIKE '%metformin%' OR de.drug_source_value ILIKE '%metformin%'
       OR de.drug_source_value ILIKE '%glucophage%' OR de.drug_source_value ILIKE '%fortamet%'
       OR de.drug_source_value ILIKE '%glumetza%' OR de.drug_source_value ILIKE '%riomet%'
   )
   OR (
       -- Sulfonylureas
       c.concept_name ILIKE ANY(ARRAY['%glipizide%', '%glyburide%', '%glimepiride%', '%gliclazide%'])
       OR de.drug_source_value ILIKE ANY(ARRAY['%glucotrol%', '%diabeta%', '%micronase%', '%amaryl%'])
   )
   OR (
       -- DPP-4 inhibitors
       c.concept_name ILIKE ANY(ARRAY['%sitagliptin%', '%saxagliptin%', '%linagliptin%', '%alogliptin%'])
       OR de.drug_source_value ILIKE ANY(ARRAY['%januvia%', '%onglyza%', '%tradjenta%', '%nesina%'])
   )
   OR (
       -- GLP-1 agonists
       c.concept_name ILIKE ANY(ARRAY['%exenatide%', '%liraglutide%', '%dulaglutide%', '%semaglutide%'])
       OR de.drug_source_value ILIKE ANY(ARRAY['%byetta%', '%victoza%', '%trulicity%', '%ozempic%', '%wegovy%'])
   )
   OR (
       -- SGLT2 inhibitors
       c.concept_name ILIKE ANY(ARRAY['%canagliflozin%', '%dapagliflozin%', '%empagliflozin%', '%ertugliflozin%'])
       OR de.drug_source_value ILIKE ANY(ARRAY['%invokana%', '%farxiga%', '%jardiance%', '%steglatro%'])
   )
   OR (
       -- Thiazolidinediones
       c.concept_name ILIKE ANY(ARRAY['%pioglitazone%', '%rosiglitazone%'])
       OR de.drug_source_value ILIKE ANY(ARRAY['%actos%', '%avandia%'])
   )
   OR (
       -- Meglitinides
       c.concept_name ILIKE ANY(ARRAY['%repaglinide%', '%nateglinide%'])
       OR de.drug_source_value ILIKE ANY(ARRAY['%prandin%', '%starlix%'])
   )
),


-- Step 4: Exclude Type 1 Diabetes and other forms
exclusions AS (
   SELECT DISTINCT person_id
   FROM public.condition_occurrence co
   WHERE (
       -- ICD-10-CM Type 1 Diabetes
       co.condition_source_value LIKE 'E10%'
       OR
       -- ICD-9-CM Type 1 Diabetes
       co.condition_source_value IN ('250.01', '250.03', '250.11', '250.13', '250.21', '250.23',
           '250.31', '250.33', '250.41', '250.43', '250.51', '250.53', '250.61', '250.63',
           '250.71', '250.73', '250.81', '250.83', '250.91', '250.93')
       OR
       -- Gestational diabetes
       co.condition_source_value IN ('O24.4', 'O24.41', 'O24.42', 'O24.43', '648.8', '648.80', '648.81', '648.82')
       OR
       -- Secondary diabetes
       co.condition_source_value LIKE 'E08%' OR co.condition_source_value LIKE 'E09%' OR co.condition_source_value LIKE 'E13%'
   )
),


-- Step 5: Combine all inclusion criteria
all_evidence AS (
   SELECT * FROM t2dm_diagnosis
   UNION ALL
   SELECT * FROM abnormal_labs
   UNION ALL
   SELECT * FROM diabetes_medications
),


-- Step 6: Require at least 2 occurrences on different dates
qualified_patients AS (
   SELECT
       person_id,
       MIN(index_date) AS first_index_date,
       COUNT(DISTINCT index_date) AS evidence_count,
       STRING_AGG(DISTINCT criteria_type, ', ' ORDER BY criteria_type) AS criteria_met
   FROM all_evidence
   GROUP BY person_id
   HAVING COUNT(DISTINCT index_date) >= 2
)


-- Final cohort: Patients with evidence AND without exclusions
SELECT
   qp.person_id,
   qp.first_index_date,
   qp.evidence_count,
   qp.criteria_met,
   p.year_of_birth,
   p.gender_concept_id,
   p.race_concept_id,
   p.ethnicity_concept_id
FROM qualified_patients qp
INNER JOIN public.person p ON qp.person_id = p.person_id
LEFT JOIN exclusions e ON qp.person_id = e.person_id
WHERE e.person_id IS NULL  -- Exclude patients with Type 1 or other excluded conditions
ORDER BY qp.person_id;


