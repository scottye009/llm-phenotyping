

SELECT DISTINCT p.person_id
FROM public.person p
JOIN public.condition_occurrence co ON p.person_id = co.person_id
JOIN public.concept c ON co.concept_id = c.concept_id
JOIN public.vocabulary v ON c.vocabulary_id = v.vocabulary_id
-- Diagnosis of Type 2 Diabetes
WHERE (v.vocabulary_name = 'ICD10CM' AND c.concept_code IN ('E11.0', 'E11.1', 'E11.2', 'E11.3', 'E11.4', 'E11.5', 'E11.6', 'E11.7', 'E11.8', 'E11.9'))
   OR (v.vocabulary_name = 'ICD9CM' AND c.concept_code IN ('250.00', '250.01', '250.02', '250.03'))
-- OR Elevated HbA1c or Fasting Glucose
UNION
SELECT DISTINCT p.person_id
FROM public.person p
JOIN public.measurement m ON p.person_id = m.person_id
JOIN public.concept c ON m.measurement_concept_id = c.concept_id
JOIN public.vocabulary v ON c.vocabulary_id = v.vocabulary_id
WHERE (v.vocabulary_name = 'LOINC' AND c.concept_code IN ('4548-4', '4549-2') AND m.value_as_number > 6.5)
   OR (v.vocabulary_name = 'LOINC' AND c.concept_code IN ('14743-9', '14826-3') AND m.value_as_number > 126)
-- OR Exposure to Diabetes Medications
UNION
SELECT DISTINCT p.person_id
FROM public.person p
JOIN public.drug_exposure de ON p.person_id = de.person_id
JOIN public.concept c ON de.concept_id = c.concept_id
JOIN public.vocabulary v ON c.vocabulary_id = v.vocabulary_id
WHERE v.vocabulary_name = 'RxNorm' AND c.concept_code IN (
  -- List of diabetes medications by generic or brand name
  'Metformin', 'Glipizide', 'Glimepiride', 'Pioglitazone', 'Sitagliptin', 'Saxagliptin', 'Linagliptin', 'Alogliptin', 'Repaglinide', 'Nateglinide',
  'Insulin glargine', 'Insulin detemir', 'Insulin aspart', 'Insulin lispro', 'Insulin regular', 'Insulin NPH', 'Novolog', 'Humalog', 'Lantus', 'Levemir'
)
-- Excluding conditions that might mimic diabetes
EXCEPT
SELECT DISTINCT p.person_id
FROM public.person p
JOIN public.condition_occurrence co ON p.person_id = co.person_id
JOIN public.concept c ON co.concept_id = c.concept_id
JOIN public.vocabulary v ON c.vocabulary_id = v.vocabulary_id
WHERE (v.vocabulary_name = 'ICD10CM' AND c.concept_code IN ('E08.0', 'E08.1', 'E08.2', 'E08.3', 'E08.4', 'E08.5', 'E08.6', 'E08.7', 'E08.8', 'E08.9'))
   OR (v.vocabulary_name = 'ICD9CM' AND c.concept_code IN ('249.00', '249.01', '249.02', '249.03'));

