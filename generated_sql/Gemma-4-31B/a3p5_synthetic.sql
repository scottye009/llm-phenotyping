-- Type 2 Diabetes Mellitus (T2DM) Phenotyping Algorithm
-- Target: Synthetic OMOP CDM L3 (PostgreSQL)

WITH t2dm_concepts AS (
    -- Identify the standard concept for Type 2 Diabetes and all its descendants
    -- Typically, the ancestor concept for T2DM in SNOMED is used
    SELECT descendant_concept_id AS concept_id
    FROM public.concept_ancestor
    WHERE ancestor_concept_id IN (
        SELECT concept_id 
        FROM public.concept 
        WHERE concept_name ILIKE '%Type 2 diabetes mellitus%' 
        AND standard_concept = 'S'
    )
),

diag_evidence AS (
    -- Rule 1: Patients with T2DM diagnosis codes
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN t2dm_concepts tc ON co.condition_concept_id = tc.concept_id
),

drug_evidence AS (
    -- Rule 2: Patients using T2DM medications
    -- We look for common T2DM drugs via concept names (Metformin, Glimepiride, Sitagliptin, etc.)
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN public.concept c ON de.drug_concept_id = c.concept_id
    WHERE (
        c.concept_name ILIKE '%Metformin%' OR 
        c.concept_name ILIKE '%Glipizide%' OR 
        c.concept_name ILIKE '%Glyburide%' OR 
        c.concept_name ILIKE '%Glimepiride%' OR 
        c.concept_name ILIKE '%Sitagliptin%' OR 
        c.concept_name ILIKE '%Empagliflozin%' OR 
        c.concept_name ILIKE '%Dapagliflozin%' OR 
        c.concept_name ILIKE '%Liraglutide%' OR 
        c.concept_name ILIKE '%Exenatide%'
    )
),

lab_evidence AS (
    -- Rule 3: Patients with laboratory results meeting T2DM thresholds
    -- HbA1c >= 6.5% or Fasting Glucose >= 126 mg/dL
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN public.concept c ON m.measurement_concept_id = c.concept_id
    WHERE (
        -- HbA1c Logic
        (c.concept_name ILIKE '%Hemoglobin A1c%' AND m.value_as_number >= 6.5)
        OR 
        -- Fasting Glucose Logic (assuming mg/dL)
        (c.concept_name ILIKE '%Glucose%' AND m.value_as_number >= 126 
         AND (m.unit_source_value ILIKE '%mg/dL%' OR m.unit_concept_id IN (
             SELECT concept_id FROM public.concept WHERE concept_name = 'mg/dL'
         )))
    )
)

-- Final Selection: Combine all evidence streams
SELECT person_id 
FROM diag_evidence
UNION 
SELECT person_id 
FROM drug_evidence
UNION 
SELECT person_id 
FROM lab_evidence;