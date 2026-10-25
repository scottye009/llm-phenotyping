-- Type 2 Diabetes Mellitus (T2DM) Phenotype
-- Logic: Diagnosis OR Medication OR Lab Thresholds

WITH t2dm_concepts AS (
    -- Identify standard concepts for T2DM and their descendants
    SELECT descendant_concept_id AS concept_id
    FROM public.concept_ancestor
    WHERE ancestor_concept_id IN (
        SELECT concept_id 
        FROM public.concept 
        WHERE concept_name ILIKE '%type 2 diabetes mellitus%' 
          AND standard_concept = 'S'
    )
    UNION
    -- Include specific ICD-10 (E11) and ICD-9 (250) mappings
    SELECT concept_id_2 
    FROM public.concept_relationship cr
    JOIN public.concept c ON cr.concept_id_1 = c.concept_id
    WHERE c.vocabulary_id IN ('ICD10CM', 'ICD9CM')
      AND (c.concept_code LIKE 'E11%' OR c.concept_code LIKE '250%')
      AND cr.relationship_id = 'Maps to'
),

t2dm_meds AS (
    -- Identify drugs used for T2DM (Metformin, etc.)
    -- We look for ingredients/classes associated with T2DM treatment
    SELECT concept_id
    FROM public.concept
    WHERE (concept_name ILIKE '%Metformin%' 
       OR concept_name ILIKE '%Glipizide%' 
       OR concept_name ILIKE '%Glyburide%' 
       OR concept_name ILIKE '%Sitagliptin%' 
       OR concept_name ILIKE '%Empagliflozin%' 
       OR concept_name ILIKE '%Canagliflozin%' 
       OR concept_name ILIKE '%Liraglutide%' 
       OR concept_name ILIKE '%Exenatide%')
      AND domain_id = 'Drug'
),

lab_criteria AS (
    -- Identify patients based on HbA1c or Glucose thresholds
    SELECT person_id
    FROM public.measurement m
    JOIN public.concept c ON m.measurement_concept_id = c.concept_id
    WHERE (
        -- HbA1c >= 6.5%
        (c.concept_name ILIKE '%Hemoglobin A1c%' AND m.value_as_number >= 6.5)
        OR 
        -- Fasting Glucose >= 126 mg/dL
        (c.concept_name ILIKE '%Glucose%' AND c.concept_name ILIKE '%Fasting%' AND m.value_as_number >= 126)
        OR
        -- Random Glucose >= 200 mg/dL
        (c.concept_name ILIKE '%Glucose%' AND m.value_as_number >= 200)
    )
)

SELECT DISTINCT p.person_id
FROM public.person p
WHERE 
    -- 1. Diagnosis Criteria
    EXISTS (
        SELECT 1 
        FROM public.condition_occurrence co 
        WHERE co.person_id = p.person_id 
          AND co.condition_concept_id IN (SELECT concept_id FROM t2dm_concepts)
    )
    OR 
    -- 2. Medication Criteria
    EXISTS (
        SELECT 1 
        FROM public.drug_exposure de 
        WHERE de.person_id = p.person_id 
          AND de.drug_concept_id IN (SELECT concept_id FROM t2dm_meds)
    )
    OR 
    -- 3. Laboratory Criteria
    EXISTS (
        SELECT 1 
        FROM lab_criteria lc 
        WHERE lc.person_id = p.person_id
    );