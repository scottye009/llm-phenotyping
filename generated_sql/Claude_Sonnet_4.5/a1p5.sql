
-- Type 2 Diabetes Phenotyping Algorithm
-- Creates a cohort of patients with Type 2 Diabetes Mellitus


WITH type2_diabetes_dx AS (
   -- Type 2 Diabetes diagnosis codes
   SELECT DISTINCT
       co.person_id,
       co.condition_start_date,
       co.condition_concept_id
   FROM public.condition_occurrence co
   WHERE (
       -- ICD-10-CM codes for Type 2 Diabetes
       co.condition_source_value LIKE 'E11%'  -- Type 2 diabetes mellitus
       OR
       -- ICD-9-CM codes for Type 2 Diabetes
       co.condition_source_value IN ('250.00', '250.02', '250.10', '250.12', '250.20', '250.22',
                                      '250.30', '250.32', '250.40', '250.42', '250.50', '250.52',
                                      '250.60', '250.62', '250.70', '250.72', '250.80', '250.82',
                                      '250.90', '250.92')
   )
),


type1_diabetes_exclusion AS (
   -- Exclude Type 1 Diabetes patients
   SELECT DISTINCT person_id
   FROM public.condition_occurrence
   WHERE (
       -- ICD-10-CM Type 1 Diabetes
       condition_source_value LIKE 'E10%'
       OR
       -- ICD-9-CM Type 1 Diabetes
       condition_source_value IN ('250.01', '250.03', '250.11', '250.13', '250.21', '250.23',
                                   '250.31', '250.33', '250.41', '250.43', '250.51', '250.53',
                                   '250.61', '250.63', '250.71', '250.73', '250.81', '250.83',
                                   '250.91', '250.93')
   )
),


gestational_diabetes_exclusion AS (
   -- Exclude gestational diabetes
   SELECT DISTINCT person_id
   FROM public.condition_occurrence
   WHERE condition_source_value IN ('O24.4', '648.8', '648.80', '648.81', '648.82', '648.83', '648.84')
),


t2dm_medications AS (
   -- Type 2 Diabetes medications
   SELECT DISTINCT
       de.person_id,
       de.drug_exposure_start_date,
       de.drug_concept_id
   FROM public.drug_exposure de
   WHERE (
       -- Metformin
       LOWER(de.drug_source_value) LIKE '%metformin%'
       OR LOWER(de.drug_source_value) LIKE '%glucophage%'
       OR LOWER(de.drug_source_value) LIKE '%fortamet%'
       OR LOWER(de.drug_source_value) LIKE '%glumetza%'
       -- Sulfonylureas
       OR LOWER(de.drug_source_value) LIKE '%glipizide%'
       OR LOWER(de.drug_source_value) LIKE '%glucotrol%'
       OR LOWER(de.drug_source_value) LIKE '%glyburide%'
       OR LOWER(de.drug_source_value) LIKE '%diabeta%'
       OR LOWER(de.drug_source_value) LIKE '%glimepiride%'
       OR LOWER(de.drug_source_value) LIKE '%amaryl%'
       -- DPP-4 Inhibitors
       OR LOWER(de.drug_source_value) LIKE '%sitagliptin%'
       OR LOWER(de.drug_source_value) LIKE '%januvia%'
       OR LOWER(de.drug_source_value) LIKE '%saxagliptin%'
       OR LOWER(de.drug_source_value) LIKE '%onglyza%'
       OR LOWER(de.drug_source_value) LIKE '%linagliptin%'
       OR LOWER(de.drug_source_value) LIKE '%tradjenta%'
       -- GLP-1 Agonists
       OR LOWER(de.drug_source_value) LIKE '%exenatide%'
       OR LOWER(de.drug_source_value) LIKE '%byetta%'
       OR LOWER(de.drug_source_value) LIKE '%liraglutide%'
       OR LOWER(de.drug_source_value) LIKE '%victoza%'
       OR LOWER(de.drug_source_value) LIKE '%dulaglutide%'
       OR LOWER(de.drug_source_value) LIKE '%trulicity%'
       OR LOWER(de.drug_source_value) LIKE '%semaglutide%'
       OR LOWER(de.drug_source_value) LIKE '%ozempic%'
       -- SGLT2 Inhibitors
       OR LOWER(de.drug_source_value) LIKE '%canagliflozin%'
       OR LOWER(de.drug_source_value) LIKE '%invokana%'
       OR LOWER(de.drug_source_value) LIKE '%dapagliflozin%'
       OR LOWER(de.drug_source_value) LIKE '%farxiga%'
       OR LOWER(de.drug_source_value) LIKE '%empagliflozin%'
       OR LOWER(de.drug_source_value) LIKE '%jardiance%'
       -- Thiazolidinediones
       OR LOWER(de.drug_source_value) LIKE '%pioglitazone%'
       OR LOWER(de.drug_source_value) LIKE '%actos%'
       OR LOWER(de.drug_source_value) LIKE '%rosiglitazone%'
       OR LOWER(de.drug_source_value) LIKE '%avandia%'
   )
),


diabetes_labs AS (
   -- Laboratory values indicative of diabetes
   SELECT DISTINCT
       m.person_id,
       m.measurement_date,
       m.measurement_concept_id,
       m.value_as_number
   FROM public.measurement m
   WHERE (
       -- HbA1c >= 6.5%
       (LOWER(m.measurement_source_value) LIKE '%hba1c%'
        OR LOWER(m.measurement_source_value) LIKE '%hemoglobin a1c%'
        OR LOWER(m.measurement_source_value) LIKE '%glycohemoglobin%')
       AND m.value_as_number >= 6.5
   )
   OR (
       -- Fasting glucose >= 126 mg/dL
       (LOWER(m.measurement_source_value) LIKE '%fasting glucose%'
        OR LOWER(m.measurement_source_value) LIKE '%fasting blood glucose%')
       AND m.value_as_number >= 126
   )
   OR (
       -- Random glucose >= 200 mg/dL
       (LOWER(m.measurement_source_value) LIKE '%glucose%'
        OR LOWER(m.measurement_source_value) LIKE '%blood glucose%')
       AND m.value_as_number >= 200
   )
),


-- Combine criteria for final cohort
final_cohort AS (
   SELECT DISTINCT
       p.person_id,
       MIN(COALESCE(dx.condition_start_date, med.drug_exposure_start_date, lab.measurement_date)) AS cohort_start_date,
       'Type 2 Diabetes' AS cohort_definition_name
   FROM public.person p
   LEFT JOIN type2_diabetes_dx dx ON p.person_id = dx.person_id
   LEFT JOIN t2dm_medications med ON p.person_id = med.person_id
   LEFT JOIN diabetes_labs lab ON p.person_id = lab.person_id
   WHERE p.person_id NOT IN (SELECT person_id FROM type1_diabetes_exclusion)
     AND p.person_id NOT IN (SELECT person_id FROM gestational_diabetes_exclusion)
     AND (
         -- At least 2 diagnoses on different dates
         (SELECT COUNT(DISTINCT condition_start_date)
          FROM type2_diabetes_dx dx2
          WHERE dx2.person_id = p.person_id) >= 2
         OR
         -- 1 diagnosis AND medications
         (dx.person_id IS NOT NULL AND med.person_id IS NOT NULL)
         OR
         -- 1 diagnosis AND abnormal labs
         (dx.person_id IS NOT NULL AND lab.person_id IS NOT NULL)
         OR
         -- Medications AND abnormal labs (without diagnosis code)
         (med.person_id IS NOT NULL AND lab.person_id IS NOT NULL)
     )
   GROUP BY p.person_id
)


-- Final output
SELECT
   fc.person_id,
   fc.cohort_start_date,
   fc.cohort_definition_name,
   p.year_of_birth,
   p.gender_concept_id,
   EXTRACT(YEAR FROM fc.cohort_start_date) - p.year_of_birth AS age_at_diagnosis
FROM final_cohort fc
JOIN public.person p ON fc.person_id = p.person_id
ORDER BY fc.person_id;

