INSERT INTO public.cohort (person_id)
SELECT DISTINCT person_id
FROM (
    SELECT person_id
    FROM public.condition_occurrence 
    WHERE condition_concept_id IN (
        SELECT concept_id
        FROM public.concept
        WHERE concept_code IN ('250.00', '250.02', 'E11.0', 'E11.1', 'E11.2', 'E11.3', 'E11.4', 'E11.5', 'E11.6', 'E11.7', 'E11.8', 'E11.9')
        AND vocabulary_id IN ('ICD9CM', 'ICD10CM')
    )
    UNION
    SELECT person_id
    FROM public.drug_exposure 
    WHERE drug_concept_id IN (
        SELECT concept_id
        FROM public.concept
        WHERE concept_name IN ('Metformin', 'Glipizide', 'Glyburide', 'Repaglinide', 'Nateglinide', 'Pioglitazone', 'Rosiglitazone', 'Sitagliptin', 'Saxagliptin', 'Exenatide', 'Liraglutide', 'Canagliflozin', 'Empagliflozin', 'Glucophage', 'Glucotrol', 'Micronase')
        AND vocabulary_id = 'RxNorm'
    )
    UNION
    SELECT person_id
    FROM public.measurement 
    WHERE measurement_concept_id IN (
        SELECT concept_id
        FROM public.concept
        WHERE concept_name IN ('Hemoglobin A1c', 'Fasting Plasma Glucose', '2-hour Plasma Glucose')
        AND vocabulary_id = 'LOINC'
    )
    AND value_as_number > (
        CASE
            WHEN measurement_concept_id = (SELECT concept_id FROM public.concept WHERE concept_name = 'Hemoglobin A1c' AND vocabulary_id = 'LOINC') THEN 6.5
            WHEN measurement_concept_id = (SELECT concept_id FROM public.concept WHERE concept_name = 'Fasting Plasma Glucose' AND vocabulary_id = 'LOINC') THEN 126
            WHEN measurement_concept_id = (SELECT concept_id FROM public.concept WHERE concept_name = '2-hour Plasma Glucose' AND vocabulary_id = 'LOINC') THEN 200
        END
    )
    UNION
    SELECT person_id
    FROM public.condition_occurrence 
    WHERE condition_concept_id IN (
        SELECT concept_id
        FROM public.concept
        WHERE concept_name IN ('Polyuria', 'Polydipsia', 'Polyphagia', 'Unexplained weight loss')
        AND vocabulary_id = 'SNOMED'
    )
) AS combined
WHERE person_id NOT IN (
    SELECT person_id
    FROM public.condition_occurrence 
    WHERE condition_concept_id IN (
        SELECT concept_id
        FROM public.concept
        WHERE concept_name IN ('Type 1 diabetes mellitus', 'Diabetes mellitus type 1', 'Gestational diabetes', 'Secondary diabetes')
        AND vocabulary_id IN ('ICD9CM', 'ICD10CM')
    )
)
