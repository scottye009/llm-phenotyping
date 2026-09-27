/* ============================================================
   TYPE 2 DIABETES MELLITUS (T2DM) PHENOTYPE — OMOP CDM (PostgreSQL)
   Returns: person_id
   ------------------------------------------------------------
   Logic:
   1. Diagnosis: ≥1 T2DM diagnosis (ICD9/10 mapped → SNOMED)
   2. Medication: ≥1 antidiabetic drug exposure
   3. Labs: HbA1c ≥ 6.5 OR fasting glucose ≥ 126 OR random glucose ≥ 200
   4. Exclusion: NO Type 1 diabetes diagnosis ever
   ============================================================ */

/* ------------------------------------------------------------
   STEP A — Identify SNOMED standard concepts for T2DM
   ------------------------------------------------------------ */
WITH t2dm_snomed AS (
    SELECT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    JOIN public.concept c ON ca.ancestor_concept_id = c.concept_id
    WHERE c.concept_name ~* 'type 2 diabetes'
      AND c.domain_id = 'Condition'
),

/* ------------------------------------------------------------
   STEP B — Identify SNOMED standard concepts for Type 1 DM (exclusion)
   ------------------------------------------------------------ */
t1dm_snomed AS (
    SELECT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    JOIN public.concept c ON ca.ancestor_concept_id = c.concept_id
    WHERE c.concept_name ~* 'type 1 diabetes'
      AND c.domain_id = 'Condition'
),

/* ------------------------------------------------------------
   STEP C — Map ICD9CM/ICD10CM → SNOMED via "Maps to"
   ------------------------------------------------------------ */
t2dm_mapped AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM public.concept_relationship cr
    JOIN public.concept c ON cr.concept_id_1 = c.concept_id
    WHERE cr.relationship_id = 'Maps to'
      AND c.vocabulary_id IN ('ICD9CM','ICD10CM')
      AND c.concept_name ~* 'diabetes'
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
   STEP D — Combine diagnosis concept sets
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
   STEP E — Identify antidiabetic medications
   (metformin, sulfonylureas, DPP4i, GLP1a, SGLT2i, insulin)
   ------------------------------------------------------------ */
antidiabetic_drugs AS (
    SELECT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    JOIN public.concept c ON ca.ancestor_concept_id = c.concept_id
    WHERE c.concept_name ~* 'metformin'
       OR c.concept_name ~* 'insulin'
       OR c.concept_name ~* 'sulfonylurea'
       OR c.concept_name ~* 'glp'
       OR c.concept_name ~* 'sglt2'
       OR c.concept_name ~* 'dpp'
),

/* ------------------------------------------------------------
   STEP F — Identify lab concepts for glucose & HbA1c
   ------------------------------------------------------------ */
lab_hba1c AS (
    SELECT concept_id
    FROM public.concept
    WHERE concept_name ~* 'hba1c'
       OR concept_code ~* '4548-4'
),

lab_glucose AS (
    SELECT concept_id
    FROM public.concept
    WHERE concept_name ~* 'glucose'
),

/* ------------------------------------------------------------
   STEP G — Diagnosis evidence
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
   STEP H — Medication evidence
   ------------------------------------------------------------ */
rx_t2dm AS (
    SELECT DISTINCT person_id
    FROM public.drug_exposure
    WHERE drug_concept_id IN (SELECT concept_id FROM antidiabetic_drugs)
),

/* ------------------------------------------------------------
   STEP I — Laboratory evidence
   ------------------------------------------------------------ */
lab_t2dm AS (
    SELECT DISTINCT person_id
    FROM public.measurement m
    WHERE (
            /* HbA1c ≥ 6.5 */
            m.measurement_concept_id IN (SELECT concept_id FROM lab_hba1c)
            AND m.value_as_number >= 6.5
          )
       OR (
            /* Fasting glucose ≥ 126 mg/dL */
            m.measurement_concept_id IN (SELECT concept_id FROM lab_glucose)
            AND m.value_as_number >= 126
            AND m.unit_concept_id IN (SELECT concept_id FROM public.concept WHERE concept_name ~* 'mg/dl')
          )
       OR (
            /* Random glucose ≥ 200 mg/dL */
            m.measurement_concept_id IN (SELECT concept_id FROM lab_glucose)
            AND m.value_as_number >= 200
          )
)

/* ------------------------------------------------------------
   FINAL COHORT:
   Must have (Diagnosis OR Medication OR Labs)
   AND must NOT have Type 1 DM
   ------------------------------------------------------------ */
SELECT DISTINCT person_id
FROM (
    SELECT person_id FROM dx_t2dm
    UNION
    SELECT person_id FROM rx_t2dm
    UNION
    SELECT person_id FROM lab_t2dm
) AS combined
WHERE person_id NOT IN (SELECT person_id FROM dx_t1dm)
ORDER BY person_id;
