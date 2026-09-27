-- filepath: 
WITH t2dm_concepts AS (
    -- Get T2DM and all descendant concepts
    SELECT descendant_concept_id AS concept_id
    FROM public.concept_ancestor
    WHERE ancestor_concept_id = 201826 -- Type 2 diabetes mellitus
),
t1dm_concepts AS (
    -- Get T1DM concepts for exclusion
    SELECT descendant_concept_id AS concept_id
    FROM public.concept_ancestor
    WHERE ancestor_concept_id = 201254 -- Type 1 diabetes mellitus
),
t2dm_meds AS (
    -- Get anti-diabetic drug concepts (excluding insulin-only logic for simplicity)
    -- Ancestors: Metformin (1503297), Sulfonylureas (1547504), DPP-4 (1580747)
    SELECT descendant_concept_id AS concept_id
    FROM public.concept_ancestor
    WHERE ancestor_concept_id IN (1503297, 1547504, 1580747, 43526465, 45774435)
),
patient_dx AS (
    -- Patients with T2DM diagnosis and count of distinct dates
    SELECT 
        person_id, 
        COUNT(DISTINCT condition_start_date) as dx_count,
        MIN(condition_start_date) as first_dx
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (SELECT concept_id FROM t2dm_concepts)
    GROUP BY person_id
),
patient_meds AS (
    -- Patients prescribed T2DM medications
    SELECT DISTINCT person_id
    FROM public.drug_exposure
    WHERE drug_concept_id IN (SELECT concept_id FROM t2dm_meds)
),
patient_labs AS (
    -- Patients with HbA1c >= 6.5%
    SELECT DISTINCT person_id
    FROM public.measurement
    WHERE measurement_concept_id IN (3004410, 3007263, 3003309) -- HbA1c LOINC concepts
      AND value_as_number >= 6.5
),
excluded_t1dm AS (
    -- Patients with more T1DM records than T2DM records
    SELECT co.person_id
    FROM public.condition_occurrence co
    JOIN t1dm_concepts t1 ON co.condition_concept_id = t1.concept_id
    GROUP BY co.person_id
    HAVING COUNT(*) > (
        SELECT COUNT(*) 
        FROM public.condition_occurrence co2 
        WHERE co2.person_id = co.person_id 
        AND co2.condition_concept_id IN (SELECT concept_id FROM t2dm_concepts)
    )
)
-- Combine logic to find final person_ids
SELECT DISTINCT dx.person_id
FROM patient_dx dx
LEFT JOIN patient_meds pm ON dx.person_id = pm.person_id
LEFT JOIN patient_labs pl ON dx.person_id = pl.person_id
WHERE (
    dx.dx_count >= 2  -- 2+ Diag dates
    OR (dx.dx_count >= 1 AND pm.person_id IS NOT NULL) -- 1 Diag + Med
    OR (dx.dx_count >= 1 AND pl.person_id IS NOT NULL) -- 1 Diag + Lab
)
AND dx.person_id NOT IN (SELECT person_id FROM excluded_t1dm);