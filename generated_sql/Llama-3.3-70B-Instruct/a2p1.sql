WITH 
-- Define the criteria for diagnosis of type 2 diabetes
diagnosis AS (
    SELECT person_id, condition_start_date, condition_end_date
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (
        SELECT concept_id
        FROM public.concept
        WHERE concept_code IN ('250.00', '250.01', '250.02', '250.03', 'E11.0', 'E11.1', 'E11.2', 'E11.3', 'E11.4', 'E11.5', 'E11.6', 'E11.7', 'E11.8', 'E11.9')
        AND vocabulary_id IN ('ICD9CM', 'ICD10CM')
    )
),

-- Define the criteria for medication use
medication AS (
    SELECT person_id, drug_exposure_start_date, drug_exposure_end_date
    FROM public.drug_exposure
    WHERE drug_concept_id IN (
        SELECT concept_id
        FROM public.concept
        WHERE concept_name IN ('Metformin', 'Glipizide', 'Glyburide', 'Repaglinide', 'Nateglinide', 'Pioglitazone', 'Rosiglitazone', 'Sitagliptin', 'Saxagliptin', 'Exenatide', 'Liraglutide', 'Canagliflozin', 'Empagliflozin')
        AND vocabulary_id = 'RxNorm'
    )
),

-- Define the criteria for abnormal laboratory test results
lab_results AS (
    SELECT person_id, measurement_date
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
),

-- Define the criteria for symptoms
symptoms AS (
    SELECT person_id, condition_start_date
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (
        SELECT concept_id
        FROM public.concept
        WHERE concept_name IN ('Polyuria', 'Polydipsia', 'Polyphagia', 'Unexplained weight loss')
        AND vocabulary_id = 'SNOMED'
    )
)

-- Identify individuals with type 2 diabetes based on diagnosis and at least one of the other criteria
INSERT INTO public.cohort (person_id)
SELECT DISTINCT d.person_id
FROM diagnosis d
WHERE EXISTS (
    SELECT 1
    FROM medication m
    WHERE m.person_id = d.person_id
    AND m.drug_exposure_start_date BETWEEN d.condition_start_date AND d.condition_end_date
)
OR EXISTS (
    SELECT 1
    FROM lab_results l
    WHERE l.person_id = d.person_id
    AND l.measurement_date BETWEEN d.condition_start_date AND d.condition_end_date
)
OR EXISTS (
    SELECT 1
    FROM symptoms s
    WHERE s.person_id = d.person_id
    AND s.condition_start_date BETWEEN d.condition_start_date AND d.condition_end_date
)

-- Identify individuals with no diagnosis but with medication use and abnormal lab results or symptoms
INSERT INTO public.cohort (person_id)
SELECT DISTINCT m.person_id
FROM medication m
WHERE NOT EXISTS (
    SELECT 1
    FROM diagnosis d
    WHERE d.person_id = m.person_id
)
AND EXISTS (
    SELECT 1
    FROM lab_results l
    WHERE l.person_id = m.person_id
    AND l.measurement_date BETWEEN m.drug_exposure_start_date AND m.drug_exposure_end_date
)
AND EXISTS (
    SELECT 1
    FROM symptoms s
    WHERE s.person_id = m.person_id
    AND s.condition_start_date BETWEEN m.drug_exposure_start_date AND m.drug_exposure_end_date
);

