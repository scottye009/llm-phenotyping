-- Type 2 Diabetes Mellitus Phenotyping Algorithm
WITH 
-- Identify individuals with a diagnosis of type 2 diabetes based on ICD9CM and ICD10CM concepts
diagnosed_type2 AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN public.concept_relationship cr ON co.condition_concept_id = cr.concept_id_2
    JOIN public.concept c ON cr.concept_id_1 = c.concept_id
    WHERE c.concept_name IN ('Type 2 diabetes mellitus', 'Diabetes mellitus type 2')
    AND cr.relationship_id = 'Maps to'
),
-- Identify individuals with diabetes-related medication use
medicated AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN public.concept c ON de.drug_concept_id = c.concept_id
    WHERE c.concept_name IN ('Metformin', 'Glyburide', 'Glipizide', 'Glimepiride', 'Pioglitazone', 'Sitagliptin', 'Empagliflozin', 'Canagliflozin', 'Dapagliflozin', 'Linagliptin')
),
-- Identify individuals with HbA1c lab results > 6.5%
hba1c_lab AS (
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN public.concept c ON m.measurement_concept_id = c.concept_id
    WHERE c.concept_name = 'Hemoglobin A1c'
    AND m.value_as_number > 6.5
)

-- Combine criteria for diagnosis, medication, and lab results, excluding gestational diabetes
SELECT DISTINCT d.person_id
FROM (
    SELECT person_id FROM diagnosed_type2
    UNION
    SELECT person_id FROM medicated
    UNION
    SELECT person_id FROM hba1c_lab
) d
WHERE d.person_id NOT IN (
    SELECT co.person_id
    FROM public.condition_occurrence co
    JOIN public.concept c ON co.condition_concept_id = c.concept_id
    WHERE c.concept_name = 'Gestational diabetes'
);