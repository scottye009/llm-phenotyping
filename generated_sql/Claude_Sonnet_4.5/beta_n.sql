-- ============================================================================
-- REFINED TYPE 2 DIABETES PHENOTYPING ALGORITHM
-- Based on OMOP Common Data Model v5.x
-- Combines best practices from multiple validated algorithms
-- ============================================================================


SELECT DISTINCT
   p.person_id,
   p.gender_concept_id,
   gc.concept_name AS gender,
   p.year_of_birth,
   p.race_concept_id,
   rc.concept_name AS race,
   p.ethnicity_concept_id,
   ec.concept_name AS ethnicity,
   MIN(all_evidence.event_date) AS t2dm_index_date,
   MAX(all_evidence.event_date) AS last_evidence_date,
   COUNT(DISTINCT all_evidence.event_date) AS total_evidence_count,
   COUNT(DISTINCT CASE WHEN all_evidence.criterion_type = 'diagnosis' THEN all_evidence.event_date END) AS diagnosis_count,
   COUNT(DISTINCT CASE WHEN all_evidence.criterion_type = 'laboratory' THEN all_evidence.event_date END) AS lab_count,
   COUNT(DISTINCT CASE WHEN all_evidence.criterion_type = 'medication' THEN all_evidence.event_date END) AS medication_count,
   COUNT(DISTINCT all_evidence.criterion_type) AS distinct_criterion_types,
   EXTRACT(YEAR FROM AGE(MIN(all_evidence.event_date),
       MAKE_DATE(p.year_of_birth, COALESCE(p.month_of_birth, 1), COALESCE(p.day_of_birth, 1)))) AS age_at_index,
   CASE
       WHEN COUNT(DISTINCT all_evidence.criterion_type) >= 2 AND COUNT(DISTINCT all_evidence.event_date) >= 2 THEN 'High'
       WHEN COUNT(DISTINCT CASE WHEN all_evidence.criterion_type = 'diagnosis' THEN all_evidence.event_date END) >= 2 THEN 'High'
       WHEN (COUNT(DISTINCT CASE WHEN all_evidence.criterion_type = 'diagnosis' THEN all_evidence.event_date END) >= 1
             AND COUNT(DISTINCT CASE WHEN all_evidence.criterion_type IN ('laboratory', 'medication') THEN all_evidence.event_date END) >= 1) THEN 'Medium'
       ELSE 'Low'
   END AS confidence_level
FROM public.person p
INNER JOIN (
   -- T2DM Diagnosis Codes
   SELECT DISTINCT
       co.person_id,
       co.condition_start_date AS event_date,
       'diagnosis' AS criterion_type
   FROM public.condition_occurrence co
   INNER JOIN public.concept c ON co.condition_concept_id = c.concept_id
   WHERE (
       -- ICD-10-CM Type 2 Diabetes codes
       (c.vocabulary_id = 'ICD10CM' AND (
           c.concept_code = 'E11' OR
           c.concept_code = 'E11.0' OR c.concept_code = 'E11.00' OR c.concept_code = 'E11.01' OR
           c.concept_code = 'E11.1' OR c.concept_code = 'E11.10' OR c.concept_code = 'E11.11' OR
           c.concept_code = 'E11.2' OR c.concept_code = 'E11.21' OR c.concept_code = 'E11.22' OR c.concept_code = 'E11.29' OR
           c.concept_code = 'E11.3' OR c.concept_code = 'E11.31' OR c.concept_code = 'E11.311' OR c.concept_code = 'E11.319' OR
           c.concept_code = 'E11.32' OR c.concept_code = 'E11.321' OR c.concept_code = 'E11.329' OR
           c.concept_code = 'E11.33' OR c.concept_code = 'E11.331' OR c.concept_code = 'E11.339' OR
           c.concept_code = 'E11.34' OR c.concept_code = 'E11.341' OR c.concept_code = 'E11.349' OR
           c.concept_code = 'E11.35' OR c.concept_code = 'E11.351' OR c.concept_code = 'E11.359' OR
           c.concept_code = 'E11.36' OR c.concept_code = 'E11.37' OR c.concept_code = 'E11.37X1' OR c.concept_code = 'E11.37X2' OR
           c.concept_code = 'E11.37X3' OR c.concept_code = 'E11.37X9' OR
           c.concept_code = 'E11.39' OR
           c.concept_code = 'E11.4' OR c.concept_code = 'E11.40' OR c.concept_code = 'E11.41' OR c.concept_code = 'E11.42' OR
           c.concept_code = 'E11.43' OR c.concept_code = 'E11.44' OR c.concept_code = 'E11.49' OR
           c.concept_code = 'E11.5' OR c.concept_code = 'E11.51' OR c.concept_code = 'E11.52' OR c.concept_code = 'E11.59' OR
           c.concept_code = 'E11.6' OR c.concept_code = 'E11.61' OR c.concept_code = 'E11.610' OR c.concept_code = 'E11.618' OR
           c.concept_code = 'E11.62' OR c.concept_code = 'E11.620' OR c.concept_code = 'E11.621' OR c.concept_code = 'E11.622' OR
           c.concept_code = 'E11.628' OR c.concept_code = 'E11.63' OR c.concept_code = 'E11.630' OR c.concept_code = 'E11.638' OR
           c.concept_code = 'E11.64' OR c.concept_code = 'E11.641' OR c.concept_code = 'E11.649' OR
           c.concept_code = 'E11.65' OR c.concept_code = 'E11.69' OR
           c.concept_code = 'E11.8' OR c.concept_code = 'E11.9'
       ))
       OR
       -- ICD-9-CM Type 2 Diabetes codes
       (c.vocabulary_id = 'ICD9CM' AND c.concept_code IN (
           '250.00', '250.02',
           '250.10', '250.12',
           '250.20', '250.22',
           '250.30', '250.32',
           '250.40', '250.42',
           '250.50', '250.52',
           '250.60', '250.62',
           '250.70', '250.72',
           '250.80', '250.82',
           '250.90', '250.92'
       ))
   )
   AND co.condition_start_date IS NOT NULL


   UNION ALL


   -- Abnormal Laboratory Values
   SELECT DISTINCT
       m.person_id,
       m.measurement_date AS event_date,
       'laboratory' AS criterion_type
   FROM public.measurement m
   WHERE (
       -- HbA1c >= 6.5% (LOINC concepts: 3004410, 3003309, 3005673, 40758583, 40758559)
       (m.measurement_concept_id IN (3004410, 3003309, 3005673, 40758583, 40758559)
        AND m.value_as_number >= 6.5)
       OR
       -- Fasting glucose >= 126 mg/dL (LOINC concepts: 3004501, 3005131, 3016723)
       (m.measurement_concept_id IN (3004501, 3005131, 3016723)
        AND m.value_as_number >= 126
        AND m.unit_concept_id IN (8840, 9028))
       OR
       -- Random/casual glucose >= 200 mg/dL (LOINC concepts: 3027018, 3034426, 3051925, 3000483)
       (m.measurement_concept_id IN (3027018, 3034426, 3051925, 3000483)
        AND m.value_as_number >= 200
        AND m.unit_concept_id IN (8840, 9028))
   )
   AND m.measurement_date IS NOT NULL


   UNION ALL


   -- Type 2 Diabetes Medications
   SELECT DISTINCT
       de.person_id,
       de.drug_exposure_start_date AS event_date,
       'medication' AS criterion_type
   FROM public.drug_exposure de
   INNER JOIN public.concept c ON de.drug_concept_id = c.concept_id
   WHERE (
       -- Metformin
       LOWER(c.concept_name) LIKE '%metformin%' OR
       LOWER(c.concept_name) LIKE '%glucophage%' OR
       LOWER(c.concept_name) LIKE '%fortamet%' OR
       LOWER(c.concept_name) LIKE '%glumetza%' OR
       LOWER(c.concept_name) LIKE '%riomet%' OR
       -- Sulfonylureas
       LOWER(c.concept_name) LIKE '%glyburide%' OR
       LOWER(c.concept_name) LIKE '%glibenclamide%' OR
       LOWER(c.concept_name) LIKE '%diabeta%' OR
       LOWER(c.concept_name) LIKE '%glynase%' OR
       LOWER(c.concept_name) LIKE '%micronase%' OR
       LOWER(c.concept_name) LIKE '%glipizide%' OR
       LOWER(c.concept_name) LIKE '%glucotrol%' OR
       LOWER(c.concept_name) LIKE '%glimepiride%' OR
       LOWER(c.concept_name) LIKE '%amaryl%' OR
       -- Thiazolidinediones
       LOWER(c.concept_name) LIKE '%pioglitazone%' OR
       LOWER(c.concept_name) LIKE '%actos%' OR
       LOWER(c.concept_name) LIKE '%rosiglitazone%' OR
       LOWER(c.concept_name) LIKE '%avandia%' OR
       -- DPP-4 Inhibitors
       LOWER(c.concept_name) LIKE '%sitagliptin%' OR
       LOWER(c.concept_name) LIKE '%januvia%' OR
       LOWER(c.concept_name) LIKE '%saxagliptin%' OR
       LOWER(c.concept_name) LIKE '%onglyza%' OR
       LOWER(c.concept_name) LIKE '%linagliptin%' OR
       LOWER(c.concept_name) LIKE '%tradjenta%' OR
       LOWER(c.concept_name) LIKE '%alogliptin%' OR
       LOWER(c.concept_name) LIKE '%nesina%' OR
       -- GLP-1 Receptor Agonists
       LOWER(c.concept_name) LIKE '%exenatide%' OR
       LOWER(c.concept_name) LIKE '%byetta%' OR
       LOWER(c.concept_name) LIKE '%bydureon%' OR
       LOWER(c.concept_name) LIKE '%liraglutide%' OR
       LOWER(c.concept_name) LIKE '%victoza%' OR
       LOWER(c.concept_name) LIKE '%saxenda%' OR
       LOWER(c.concept_name) LIKE '%dulaglutide%' OR
       LOWER(c.concept_name) LIKE '%trulicity%' OR
       LOWER(c.concept_name) LIKE '%semaglutide%' OR
       LOWER(c.concept_name) LIKE '%ozempic%' OR
       LOWER(c.concept_name) LIKE '%rybelsus%' OR
       LOWER(c.concept_name) LIKE '%wegovy%' OR
       LOWER(c.concept_name) LIKE '%tirzepatide%' OR
       LOWER(c.concept_name) LIKE '%mounjaro%' OR
       LOWER(c.concept_name) LIKE '%zepbound%' OR
       -- SGLT2 Inhibitors
       LOWER(c.concept_name) LIKE '%canagliflozin%' OR
       LOWER(c.concept_name) LIKE '%invokana%' OR
       LOWER(c.concept_name) LIKE '%dapagliflozin%' OR
       LOWER(c.concept_name) LIKE '%farxiga%' OR
       LOWER(c.concept_name) LIKE '%empagliflozin%' OR
       LOWER(c.concept_name) LIKE '%jardiance%' OR
       LOWER(c.concept_name) LIKE '%ertugliflozin%' OR
       LOWER(c.concept_name) LIKE '%steglatro%' OR
       LOWER(c.concept_name) LIKE '%bexagliflozin%' OR
       LOWER(c.concept_name) LIKE '%brenzavvy%' OR
       -- Meglitinides
       LOWER(c.concept_name) LIKE '%repaglinide%' OR
       LOWER(c.concept_name) LIKE '%prandin%' OR
       LOWER(c.concept_name) LIKE '%nateglinide%' OR
       LOWER(c.concept_name) LIKE '%starlix%' OR
       -- Alpha-glucosidase Inhibitors
       LOWER(c.concept_name) LIKE '%acarbose%' OR
       LOWER(c.concept_name) LIKE '%precose%' OR
       LOWER(c.concept_name) LIKE '%miglitol%' OR
       LOWER(c.concept_name) LIKE '%glyset%' OR
       -- Basal Insulin (commonly used in T2DM)
       LOWER(c.concept_name) LIKE '%insulin glargine%' OR
       LOWER(c.concept_name) LIKE '%lantus%' OR
       LOWER(c.concept_name) LIKE '%basaglar%' OR
       LOWER(c.concept_name) LIKE '%toujeo%' OR
       LOWER(c.concept_name) LIKE '%insulin detemir%' OR
       LOWER(c.concept_name) LIKE '%levemir%' OR
       LOWER(c.concept_name) LIKE '%insulin degludec%' OR
       LOWER(c.concept_name) LIKE '%tresiba%' OR
       LOWER(c.concept_name) LIKE '%insulin nph%'
   )
   AND de.drug_exposure_start_date IS NOT NULL
) AS all_evidence ON p.person_id = all_evidence.person_id
LEFT JOIN public.concept gc ON p.gender_concept_id = gc.concept_id
LEFT JOIN public.concept rc ON p.race_concept_id = rc.concept_id
LEFT JOIN public.concept ec ON p.ethnicity_concept_id = ec.concept_id
INNER JOIN public.observation_period op ON p.person_id = op.person_id
   AND all_evidence.event_date >= op.observation_period_start_date
   AND all_evidence.event_date <= op.observation_period_end_date
WHERE
   -- Age restriction: >= 18 years at index date
   EXTRACT(YEAR FROM AGE(MIN(all_evidence.event_date),
       MAKE_DATE(p.year_of_birth, COALESCE(p.month_of_birth, 1), COALESCE(p.day_of_birth, 1)))) >= 18
   -- Observation period: >= 365 days
   AND EXTRACT(DAY FROM (op.observation_period_end_date - op.observation_period_start_date)) >= 365
   -- Exclude Type 1 Diabetes
   AND p.person_id NOT IN (
       SELECT DISTINCT co.person_id
       FROM public.condition_occurrence co
       INNER JOIN public.concept c ON co.condition_concept_id = c.concept_id
       WHERE (
           (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E10.%')
           OR
           (c.vocabulary_id = 'ICD9CM' AND c.concept_code IN (
               '250.01', '250.03', '250.11', '250.13', '250.21', '250.23',
               '250.31', '250.33', '250.41', '250.43', '250.51', '250.53',
               '250.61', '250.63', '250.71', '250.73', '250.81', '250.83',
               '250.91', '250.93'
           ))
       )
   )
   -- Exclude Gestational Diabetes (without subsequent T2DM diagnosis)
   AND p.person_id NOT IN (
       SELECT DISTINCT co.person_id
       FROM public.condition_occurrence co
       INNER JOIN public.concept c ON co.condition_concept_id = c.concept_id
       WHERE (
           (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'O24.4%')
           OR
           (c.vocabulary_id = 'ICD9CM' AND c.concept_code IN ('648.80', '648.81', '648.82', '648.83', '648.84'))
       )
       AND NOT EXISTS (
           SELECT 1
           FROM public.condition_occurrence co2
           INNER JOIN public.concept c2 ON co2.condition_concept_id = c2.concept_id
           WHERE co2.person_id = co.person_id
           AND co2.condition_start_date > co.condition_start_date + INTERVAL '12 months'
           AND (
               (c2.vocabulary_id = 'ICD10CM' AND c2.concept_code LIKE 'E11.%')
               OR
               (c2.vocabulary_id = 'ICD9CM' AND c2.concept_code IN (
                   '250.00', '250.02', '250.10', '250.12', '250.20', '250.22',
                   '250.30', '250.32', '250.40', '250.42', '250.50', '250.52',
                   '250.60', '250.62', '250.70', '250.72', '250.80', '250.82',
                   '250.90', '250.92'
               ))
           )
       )
   )
   -- Exclude Secondary Diabetes
   AND p.person_id NOT IN (
       SELECT DISTINCT co.person_id
       FROM public.condition_occurrence co
       INNER JOIN public.concept c ON co.condition_concept_id = c.concept_id
       WHERE (
           (c.vocabulary_id = 'ICD10CM' AND (
               c.concept_code LIKE 'E08.%' OR
               c.concept_code LIKE 'E09.%' OR
               c.concept_code LIKE 'E13.%'
           ))
       )
   )
GROUP BY
   p.person_id,
   p.gender_concept_id,
   gc.concept_name,
   p.year_of_birth,
   p.race_concept_id,
   rc.concept_name,
   p.ethnicity_concept_id,
   ec.concept_name
HAVING
   -- Inclusion criteria: Must have strong evidence
   (
       -- Option 1: Multiple diagnoses on different dates
       COUNT(DISTINCT CASE WHEN all_evidence.criterion_type = 'diagnosis' THEN all_evidence.event_date END) >= 2
       OR
       -- Option 2: At least one diagnosis + one other criterion type
       (COUNT(DISTINCT CASE WHEN all_evidence.criterion_type = 'diagnosis' THEN all_evidence.event_date END) >= 1
        AND COUNT(DISTINCT CASE WHEN all_evidence.criterion_type IN ('laboratory', 'medication') THEN all_evidence.event_date END) >= 1)
       OR
       -- Option 3: Multiple laboratory values + medications
       (COUNT(DISTINCT CASE WHEN all_evidence.criterion_type = 'laboratory' THEN all_evidence.event_date END) >= 2
        AND COUNT(DISTINCT CASE WHEN all_evidence.criterion_type = 'medication' THEN all_evidence.event_date END) >= 2)
   )
ORDER BY t2dm_index_date, p.person_id;



