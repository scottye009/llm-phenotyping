--0row
WITH T2DM_Codes AS (
    SELECT concept_id FROM concept WHERE concept_code IN ('250.00', '250.02', '250.10', '250.12') AND vocabulary_id = 'ICD9CM'
    UNION
    SELECT concept_id FROM concept WHERE concept_code LIKE 'E11%' AND vocabulary_id = 'ICD10CM'
),
T1DM_Codes AS (
    SELECT concept_id FROM concept WHERE concept_code IN ('250.01', '250.03') AND vocabulary_id = 'ICD9CM'
    UNION
    SELECT concept_id FROM concept WHERE concept_code LIKE 'E10%' AND vocabulary_id = 'ICD10CM'
),
T2DM_Meds AS (
    -- Generic (Brand)
    -- Metformin (Glucophage), Glipizide (Glucotrol), Glyburide (Diabeta), 
    -- Pioglitazone (Actos), Sitagliptin (Januvia), Empagliflozin (Jardiance), 
    -- Liraglutide (Victoza), Semaglutide (Ozempic)
    SELECT concept_id FROM concept WHERE concept_name ILIKE '%Metformin%' OR concept_name ILIKE '%Glucophage%'
    OR concept_name ILIKE '%Glipizide%' OR concept_name ILIKE '%Glucotrol%'
    OR concept_name ILIKE '%Sitagliptin%' OR concept_name ILIKE '%Januvia%'
    OR concept_name ILIKE '%Empagliflozin%' OR concept_name ILIKE '%Jardiance%'
),
Labs AS (
    SELECT person_id FROM measurement 
    WHERE (measurement_concept_id IN (3004410, 3005673) AND value_as_number >= 6.5) -- HbA1c
    OR (measurement_concept_id = 3000845 AND value_as_number >= 126) -- Fasting Glucose
)

SELECT DISTINCT person_id
FROM condition_occurrence co
JOIN T2DM_Codes tc ON co.condition_concept_id = tc.concept_id
WHERE (
    -- Inclusion 1 & 2: Frequency/Setting logic
    co.person_id IN (SELECT person_id FROM condition_occurrence GROUP BY person_id HAVING COUNT(DISTINCT condition_start_date) >= 2)
    OR co.visit_occurrence_id IN (SELECT visit_occurrence_id FROM visit_occurrence WHERE visit_concept_id = 9201) -- Inpatient
    -- Inclusion 3: Medication
    OR co.person_id IN (SELECT person_id FROM drug_exposure WHERE drug_concept_id IN (SELECT concept_id FROM T2DM_Meds))
    -- Inclusion 4: Labs
    OR co.person_id IN (SELECT person_id FROM Labs)
)
AND co.person_id NOT IN (
    -- Exclusion: More T1DM codes than T2DM codes
    SELECT person_id FROM condition_occurrence WHERE condition_concept_id IN (SELECT concept_id FROM T1DM_Codes)
    GROUP BY person_id HAVING COUNT(*) > (SELECT COUNT(*) FROM condition_occurrence c2 WHERE c2.person_id = condition_occurrence.person_id AND c2.condition_concept_id IN (SELECT concept_id FROM T2DM_Codes))
);