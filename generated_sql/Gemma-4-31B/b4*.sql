/*
Professional Type 2 Diabetes Mellitus (T2DM) Phenotype
Logic:
- Inclusion: (2+ DX) OR (1+ DX + [Med or Lab]) OR (Med + Lab)
- Exclusion: T1DM, Gestational Diabetes, Diabetic Ketoacidosis
- Standard: OMOP CDM based on Clinical Guidelines
*/

WITH T2DM_Concept_Set AS (
    -- Capture all T2DM descendants from known root concepts
    SELECT descendant_concept_id AS concept_id
    FROM public.concept_ancestor
    WHERE ancestor_concept_id IN (
        201826, -- Type 2 diabetes mellitus
        201313, -- T2DM with complications
        201350, -- T2DM without complications
        201820  -- T2DM root
    )
    UNION
    -- Add ICD-10/9 based mapping through ancestors to be exhaustive
    SELECT descendant_concept_id
    FROM public.concept_ancestor
    WHERE ancestor_concept_id IN (
        SELECT concept_id FROM public.concept 
        WHERE (vocabulary_id = 'ICD10CM' AND concept_code LIKE 'E11%')
           OR (vocabulary_id = 'ICD9CM' AND concept_code LIKE '250.0%')
    )
),

Exclusion_Concept_Set AS (
    -- T1DM, Gestational, and Ketoacidosis
    SELECT descendant_concept_id AS concept_id
    FROM public.concept_ancestor
    WHERE ancestor_concept_id IN (
        4042514, 444442, 4144310, -- T1DM root concepts
        4042515, 4042516 -- Ketoacidosis related
    )
    UNION
    SELECT descendant_concept_id
    FROM public.concept_ancestor
    WHERE ancestor_concept_id IN (
        SELECT concept_id FROM public.concept 
        WHERE (vocabulary_id = 'ICD10CM' AND (concept_code LIKE 'E10%' OR concept_code LIKE 'O24.4%'))
           OR (vocabulary_id = 'ICD9CM' AND concept_code LIKE '250.1%')
    )
),

T2DM_Med_Set AS (
    -- Use ancestors to capture all generic and brand forms of T2DM drugs
    SELECT descendant_concept_id AS concept_id
    FROM public.concept_ancestor
    WHERE ancestor_concept_id IN (
        SELECT concept_id FROM public.concept 
        WHERE (
            UPPER(concept_name) LIKE '%METFORMIN%' OR UPPER(concept_name) LIKE '%GLUCOPHAGE%' OR
            UPPER(concept_name) LIKE '%GLIMEPIRIDE%' OR UPPER(concept_name) LIKE '%AMARYL%' OR
            UPPER(concept_name) LIKE '%GLIPIZIDE%' OR UPPER(concept_name) LIKE '%GLYBURIDE%' OR
            UPPER(concept_name) LIKE '%SITAGLIPTIN%' OR UPPER(concept_name) LIKE '%JANUVIA%' OR
            UPPER(concept_name) LIKE '%EMPAGLIFLOZIN%' OR UPPER(concept_name) LIKE '%JARDIANCE%' OR
            UPPER(concept_name) LIKE '%LIRAGLUTIDE%' OR UPPER(concept_name) LIKE '%VICTOZA%' OR
            UPPER(concept_name) LIKE '%PIOGLITAZONE%' OR UPPER(concept_name) LIKE '%ACTOS%'
        ) AND domain_id = 'Drug'
    )
),

Lab_Evidence AS (
    -- Differentiate thresholds by lab type
    SELECT person_id
    FROM public.measurement
    WHERE (
        (measurement_concept_id IN (
            SELECT descendant_concept_id FROM public.concept_ancestor 
            WHERE ancestor_concept_id IN (SELECT concept_id FROM public.concept WHERE UPPER(concept_name) LIKE '%HBA1C%' OR UPPER(concept_name) LIKE '%HEMOGLOBIN A1C%')
        ) AND value_as_number >= 6.5)
        OR 
        (measurement_concept_id IN (
            SELECT descendant_concept_id FROM public.concept_ancestor 
            WHERE ancestor_concept_id IN (SELECT concept_id FROM public.concept WHERE UPPER(concept_name) LIKE '%GLUCOSE%' AND UPPER(concept_name) LIKE '%FASTING%')
        ) AND value_as_number >= 126)
        OR
        (measurement_concept_id IN (
            SELECT descendant_concept_id FROM public.concept_ancestor 
            WHERE ancestor_concept_id IN (SELECT concept_id FROM public.concept WHERE UPPER(concept_name) LIKE '%GLUCOSE%' AND UPPER(concept_name) LIKE '%RANDOM%')
        ) AND value_as_number >= 200)
    )
),

Patient_Evidence_Summary AS (
    SELECT 
        p.person_id,
        COUNT(DISTINCT co.condition_occurrence_id) as dx_count,
        MAX(CASE WHEN dr.drug_exposure_id IS NOT NULL THEN 1 ELSE 0 END) as has_med,
        MAX(CASE WHEN lb.person_id IS NOT NULL THEN 1 ELSE 0 END) as has_lab
    FROM public.person p
    LEFT JOIN public.condition_occurrence co ON p.person_id = co.person_id 
        AND co.condition_concept_id IN (SELECT concept_id FROM T2DM_Concept_Set)
    LEFT JOIN public.drug_exposure dr ON p.person_id = dr.person_id 
        AND dr.drug_concept_id IN (SELECT concept_id FROM T2DM_Med_Set)
    LEFT JOIN Lab_Evidence lb ON p.person_id = lb.person_id
    GROUP BY p.person_id
)

SELECT person_id
FROM Patient_Evidence_Summary
WHERE (
    -- Tier 1: High Confidence - Multiple Diagnosis records
    (dx_count >= 2) 
    OR 
    -- Tier 2: Moderate Confidence - One Diagnosis supported by clinical markers
    (dx_count >= 1 AND (has_med = 1 OR has_lab = 1)) 
    OR 
    -- Tier 3: Clinical Confirmation - Confirmed by both Lab and Med regardless of DX code
    (has_med = 1 AND has_lab = 1)
)
AND person_id NOT IN (
    -- Exclusion: Any record of T1DM or Gestational Diabetes
    SELECT person_id FROM public.condition_occurrence 
    WHERE condition_concept_id IN (SELECT concept_id FROM Exclusion_Concept_Set)
);