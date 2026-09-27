/* ============================================================
   TYPE 2 DIABETES MELLITUS (T2DM) PHENOTYPE — OMOP CDM (PostgreSQL)
   ---------------------------------------------------------------
   Evidence sources:
     1. Diagnosis: SNOMED descendants of T2DM + ICD9/ICD10 mapped via 'Maps to'
     2. Medications: antidiabetic drug classes (metformin, insulin,
        sulfonylureas, DPP-4 inhibitors, GLP-1 agonists, SGLT2 inhibitors)
     3. Labs: HbA1c ≥ 6.5%, fasting glucose ≥ 126 mg/dL, random glucose ≥ 200 mg/dL
     4. Exclusion: Type 1 diabetes diagnoses (SNOMED + ICD mapped)
   ============================================================ */

WITH
/* ------------------------------------------------------------
   1. SNOMED standard concepts for Type 2 and Type 1 diabetes
   ------------------------------------------------------------ */
t2dm_snomed AS (
    SELECT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    JOIN public.concept c ON ca.ancestor_concept_id = c.concept_id
    WHERE c.domain_id = 'Condition'
      AND c.concept_name ~* 'type 2 diabetes'
),

t1dm_snomed AS (
    SELECT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    JOIN public.concept c ON ca.ancestor_concept_id = c.concept_id
    WHERE c.domain_id = 'Condition'
      AND c.concept_name ~* 'type 1 diabetes'
),

/* ------------------------------------------------------------
   2. ICD9/ICD10 → SNOMED mappings via 'Maps to'
   ------------------------------------------------------------ */
t2dm_mapped AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM public.concept_relationship cr
    JOIN public.concept c ON cr.concept_id_1 = c.concept_id
    WHERE cr.relationship_id = 'Maps to'
      AND c.vocabulary_id IN ('ICD9CM','ICD10CM')
      AND c.concept_name ~* 'type 2 diabetes'
),

t1dm_mapped AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM public.concept_relationship cr
    JOIN public.concept c ON cr.concept_id_1 = c.concept_id
    WHERE cr.relationship_id = 'Maps to'
      AND c.vocabulary_id IN ('ICD9CM','ICD10CM')
      AND c.concept_name ~* 'type 1 diabetes'
),

/* ------------------------------------------------------------
   3. Final diagnosis concept sets
   ------------------------------------------------------------ */
t2dm_dx_concepts AS (
    SELECT concept_id FROM t2dm_snomed
    UNION
    SELECT concept_id FROM t2dm_mapped
),

t1dm_dx_concepts AS (
    SELECT concept_id FROM t1dm_snomed
    UNION
    SELECT concept_id FROM t1dm_mapped
),

/* ------------------------------------------------------------
   4. Diagnosis evidence
   ------------------------------------------------------------ */
dx_t2dm AS (
    SELECT DISTINCT person_id
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (SELECT concept_id FROM t2dm_dx_concepts)
),

dx_t1dm AS (
    SELECT DISTINCT person_id
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (SELECT concept_id FROM t1dm_dx_concepts)
),

/* ------------------------------------------------------------
   5. Medication evidence — antidiabetic drug classes
      Uses OMOP hierarchy via concept_ancestor
   ------------------------------------------------------------ */
antidiabetic_drugs AS (
    SELECT DISTINCT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    JOIN public.concept c ON ca.ancestor_concept_id = c.concept_id
    WHERE c.domain_id = 'Drug'
      AND (
           c.concept_name ~* 'metformin'
        OR c.concept_name ~* 'insulin'
        OR c.concept_name ~* 'sulfonylurea'
        OR c.concept_name ~* 'gliptin'      -- DPP-4 inhibitors
        OR c.concept_name ~* 'glutide'      -- GLP-1 agonists
        OR c.concept_name ~* 'flozin'       -- SGLT2 inhibitors
      )
),

rx_t2dm AS (
    SELECT DISTINCT person_id
    FROM public.drug_exposure
    WHERE drug_concept_id IN (SELECT concept_id FROM antidiabetic_drugs)
),

/* ------------------------------------------------------------
   6. Laboratory evidence
   ------------------------------------------------------------ */
lab_hba1c AS (
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN public.concept c ON m.measurement_concept_id = c.concept_id
    WHERE c.concept_name ~* 'hba1c'
      AND m.value_as_number >= 6.5
),

lab_glucose_fasting AS (
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN public.concept c ON m.measurement_concept_id = c.concept_id
    WHERE c.concept_name ~* 'glucose'
      AND c.concept_name ~* 'fast'
      AND m.value_as_number >= 126
),

lab_glucose_random AS (
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN public.concept c ON m.measurement_concept_id = c.concept_id
    WHERE c.concept_name ~* 'glucose'
      AND m.value_as_number >= 200
),

lab_t2dm AS (
    SELECT person_id FROM lab_hba1c
    UNION
    SELECT person_id FROM lab_glucose_fasting
    UNION
    SELECT person_id FROM lab_glucose_random
),

/* ------------------------------------------------------------
   7. Combine all inclusion evidence
   ------------------------------------------------------------ */
t2dm_included AS (
    SELECT person_id FROM dx_t2dm
    UNION
    SELECT person_id FROM rx_t2dm
    UNION
    SELECT person_id FROM lab_t2dm
)

SELECT DISTINCT person_id
FROM t2dm_included
WHERE person_id NOT IN (SELECT person_id FROM dx_t1dm)
ORDER BY person_id;
