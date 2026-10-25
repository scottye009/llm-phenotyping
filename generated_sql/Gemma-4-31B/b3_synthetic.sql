-- Type 2 Diabetes Mellitus (T2DM) Phenotyping Algorithm
-- Target: Synthetic OMOP CDM L3 (PostgreSQL)
-- Logic: (T2DM Diagnosis) OR (T2DM Medications) OR (Hyperglycemic Labs) MINUS (Type 1 Diabetes)

WITH t2dm_standard_concepts AS (
    -- Capture the standard T2DM concept and all its descendants in the hierarchy
    SELECT descendant_concept_id AS concept_id
    FROM public.concept_ancestor
    WHERE ancestor_concept_id IN (
        SELECT concept_id 
        FROM public.concept 
        WHERE concept_name ILIKE '%Type 2 diabetes mellitus%' 
        AND standard_concept = 'S'
    )
),

t1dm_exclusion_concepts AS (
    -- Identify concepts related to Type 1 Diabetes for exclusion
    SELECT concept_id 
    FROM public.concept 
    WHERE concept_name ILIKE '%Type 1 diabetes%' 
    AND standard_concept = 'S'
),

diagnosis_evidence AS (
    -- Patients with a standardized T2DM diagnosis
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN t2dm_standard_concepts tc ON co.condition_concept_id = tc.concept_id
),

medication_evidence AS (
    -- Patients taking T2DM-specific medications
    -- Includes Biguanides, Sulfonylureas, DPP-4s, SGLT2s, and GLP-1s
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN public.concept c ON de.drug_concept_id = c.concept_id
    WHERE (
        c.concept_name ILIKE '%Metformin%' OR 
        c.concept_name ILIKE '%Glimepiride%' OR 
        c.concept_name ILIKE '%Glipizide%' OR 
        c.concept_name ILIKE '%Glyburide%' OR 
        c.concept_name ILIKE '%Sitagliptin%' OR 
        c.concept_name ILIKE '%Saxagliptin%' OR 
        c.concept_name ILIKE '%Empagliflozin%' OR 
        c.concept_name ILIKE '%Dapagliflozin%' OR 
        c.concept_name ILIKE '%Canagliflozin%' OR 
        c.concept_name ILIKE '%Liraglutide%' OR 
        c.concept_name ILIKE '%Exenatide%' OR 
        c.concept_name ILIKE '%Pioglitazone%'
    )
),

lab_evidence AS (
    -- Patients meeting diagnostic thresholds with unit validation
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN public.concept c ON m.measurement_concept_id = c.concept_id
    WHERE (
        -- HbA1c >= 6.5%
        (c.concept_name ILIKE '%Hemoglobin A1c%' AND m.value_as_number >= 6.5)
        OR 
        -- Fasting Glucose >= 126 mg/dL (Validate unit to avoid mmol/L errors)
        (
            c.concept_name ILIKE '%Glucose%' 
            AND c.concept_name ILIKE '%Fasting%' 
            AND m.value_as_number >= 126 
            AND (m.unit_source_value ILIKE '%mg/dL%' OR m.unit_concept_id IN (
                SELECT concept_id FROM public.concept WHERE concept_name = 'mg/dL'
            ))
        )
        OR
        -- Random Glucose >= 200 mg/dL
        (
            c.concept_name ILIKE '%Glucose%' 
            AND m.value_as_number >= 200 
            AND (m.unit_source_value ILIKE '%mg/dL%' OR m.unit_concept_id IN (
                SELECT concept_id FROM public.concept WHERE concept_name = 'mg/dL'
            ))
        )
    )
),

combined_cohort AS (
    -- Union all evidence streams
    SELECT person_id FROM diagnosis_evidence
    UNION
    SELECT person_id FROM medication_evidence
    UNION
    SELECT person_id FROM lab_evidence
)

-- Final selection: All T2DM candidates minus those with Type 1 Diabetes
SELECT DISTINCT cc.person_id
FROM combined_cohort cc
WHERE cc.person_id NOT IN (
    SELECT co.person_id 
    FROM public.condition_occurrence co
    JOIN t1dm_exclusion_concepts te ON co.condition_concept_id = te.concept_id
);