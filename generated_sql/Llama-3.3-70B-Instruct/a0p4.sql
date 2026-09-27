--error
SELECT *
FROM person
WHERE (
    -- Diagnosis Codes
    EXISTS (
        SELECT 1
        FROM condition_occurrence
        WHERE condition_concept_id IN (
            -- ICD9CM codes for Type 2 diabetes
            SELECT concept_id
            FROM concept
            WHERE concept_code IN ('250.0', '250.1', '250.2', '250.3') AND vocabulary_id = 'ICD9CM'
        )
        OR condition_concept_id IN (
            -- ICD10CM codes for Type 2 diabetes
            SELECT concept_id
            FROM concept
            WHERE concept_code IN ('E11.0', 'E11.1', 'E11.2', 'E11.3', 'E11.4', 'E11.5', 'E11.6', 'E11.7', 'E11.8', 'E11.9') AND vocabulary_id = 'ICD10CM'
        )
        AND person_id = person.person_id
    )
    OR (
        -- Laboratory Findings
        EXISTS (
            SELECT 1
            FROM measurement
            WHERE measurement_concept_id IN (
                -- Concept IDs for HbA1c, fasting glucose, and 2-hour OGTT glucose
                SELECT concept_id
                FROM concept
                WHERE concept_name IN ('HbA1c', 'Fasting glucose', '2-hour OGTT glucose') AND vocabulary_id = 'LOINC'
            )
            AND value_as_number >= (
                CASE
                    WHEN measurement_concept_id IN (SELECT concept_id FROM concept WHERE concept_name = 'HbA1c' AND vocabulary_id = 'LOINC') THEN 6.5
                    WHEN measurement_concept_id IN (SELECT concept_id FROM concept WHERE concept_name = 'Fasting glucose' AND vocabulary_id = 'LOINC') THEN 126
                    WHEN measurement_concept_id IN (SELECT concept_id FROM concept WHERE concept_name = '2-hour OGTT glucose' AND vocabulary_id = 'LOINC') THEN 200
                END
            )
            AND person_id = person.person_id
        )
        AND (
            -- Medication Use
            EXISTS (
                SELECT 1
                FROM drug_exposure
                WHERE drug_concept_id IN (
                    -- Concept IDs for diabetes medications
                    SELECT concept_id
                    FROM concept
                    WHERE concept_name IN (
                        'metformin',
                        'glyburide',
                        'repaglinide',
                        'pioglitazone',
                        'sitagliptin',
                        'exenatide',
                        'canagliflozin',
                        'Glucophage',
                        'Micronase',
                        'Prandin',
                        'Actos',
                        'Januvia',
                        'Byetta',
                        'Invokana'
                    ) AND vocabulary_id = 'RxNorm'
                )
                AND person_id = person.person_id
            )
        )
    )
)
AND NOT EXISTS (
    -- Exclusion criteria, e.g., type 1 diabetes
    SELECT 1
    FROM condition_occurrence
    WHERE condition_concept_id IN (
        -- ICD9CM and ICD10CM codes for Type 1 diabetes
        SELECT concept_id
        FROM concept
        WHERE concept_code IN ('250.1') AND vocabulary_id = 'ICD9CM'
        OR concept_code IN ('E10.0', 'E10.1', 'E10.2', 'E10.3', 'E10.4', 'E10.5', 'E10.6', 'E10.7', 'E10.8', 'E10.9') AND vocabulary_id = 'ICD10CM'
    )
    AND person_id = person.person_id
);