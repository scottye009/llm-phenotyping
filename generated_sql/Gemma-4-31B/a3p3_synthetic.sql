-- Type 2 Diabetes Mellitus (T2DM) Phenotyping Algorithm
-- Logic: Diagnosis OR (Medications >= 2) OR (Lab Results >= 2)

WITH t2dm_concepts AS (
    -- Identify standardized concepts for T2DM using concept_ancestor for hierarchy
    -- Includes ICD10: E11.*, ICD9: 250.00, 250.01, etc.
    SELECT descendant_concept_id AS concept_id
    FROM public.concept_ancestor
    WHERE ancestor_concept_id IN (
        SELECT concept_id 
        FROM public.concept 
        WHERE concept_name ILIKE '%type 2 diabetes mellitus%' 
          AND standard_concept = 'S'
          AND domain_id = 'Condition'
    )
),

diagnosis_cohort AS (
    -- Rule A: Patients with a documented T2DM diagnosis
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN t2dm_concepts tc ON co.condition_concept_id = tc.concept_id
    -- Explicitly exclude Type 1 Diabetes concepts to increase specificity
    WHERE co.person_id NOT IN (
        SELECT person_id 
        FROM public.condition_occurrence 
        WHERE condition_concept_id IN (
            SELECT concept_id FROM public.concept WHERE concept_name ILIKE '%type 1 diabetes%'
        )
    )
),

medication_cohort AS (
    -- Rule B: Patients with >= 2 distinct T2DM medications
    -- Focus on Metformin, SGLT2, GLP-1, DPP-4, and Sulfonylureas
    SELECT de.person_id
    FROM public.drug_exposure de
    JOIN public.concept c ON de.drug_concept_id = c.concept_id
    WHERE (c.concept_name ILIKE '%Metformin%' 
       OR c.concept_name ILIKE '%Glipizide%' 
       OR c.concept_name ILIKE '%Glyburide%' 
       OR c.concept_name ILIKE '%Sitagliptin%' 
       OR c.concept_name ILIKE '%Empagliflozin%' 
       OR c.concept_name ILIKE '%Canagliflozin%' 
       OR c.concept_name ILIKE '%Liraglutide%' 
       OR c.concept_name ILIKE '%Exenatide%')
    GROUP BY de.person_id
    HAVING COUNT(DISTINCT de.drug_concept_id) >= 2
),

lab_cohort AS (
    -- Rule C: Patients with >= 2 hyperglycemic lab results
    -- HbA1c >= 6.5% (LOINC 4548-4) or Fasting Glucose >= 126 mg/dL (LOINC 1558-6)
    SELECT m.person_id
    FROM public.measurement m
    JOIN public.concept c ON m.measurement_concept_id = c.concept_id
    WHERE (
        (c.concept_name ILIKE '%Hemoglobin A1c%' AND m.value_as_number >= 6.5)
        OR 
        (c.concept_name ILIKE '%Glucose%Fasting%' AND m.value_as_number >= 126)
    )
    GROUP BY m.person_id
    HAVING COUNT(DISTINCT m.measurement_id) >= 2
)

-- Final Selection: Combine all rules
SELECT DISTINCT p.person_id
FROM public.person p
WHERE p.person_id IN (SELECT person_id FROM diagnosis_cohort)
   OR p.person_id IN (SELECT person_id FROM medication_cohort)
   OR p.person_id IN (SELECT person_id FROM lab_cohort);