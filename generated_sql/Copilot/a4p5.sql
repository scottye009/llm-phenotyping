/* ============================================================
   TYPE 2 DIABETES MELLITUS (T2DM) PHENOTYPE — OMOP CDM (PostgreSQL)
   Returns: person_id
   Logic:
     1. Diagnosis: ICD9CM/ICD10CM → SNOMED via 'Maps to'
     2. Medications: antidiabetic drug classes (standard concepts)
     3. Labs: HbA1c ≥ 6.5%, fasting glucose ≥ 126 mg/dL, random glucose ≥ 200 mg/dL
     4. Exclusion: Type 1 diabetes diagnosis
   ============================================================ */

WITH
/* ------------------------------------------------------------
   1. Identify SNOMED standard concepts for Type 2 diabetes
   ------------------------------------------------------------ */
t2dm_snomed AS (
    SELECT ca.descendant_concept_id AS concept_id
    FROM public.concept c
    JOIN public.concept_ancestor ca
      ON c.concept_id = ca.ancestor_concept_id
    WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
      AND c.concept_code ~* '250\.0|250\.2|E11'  -- ICD9/ICD10 T2DM patterns
),
/* ------------------------------------------------------------
   2. Identify SNOMED standard concepts for Type 1 diabetes
   ------------------------------------------------------------ */
t1dm_snomed AS (
    SELECT ca.descendant_concept_id AS concept_id
    FROM public.concept c
    JOIN public.concept_ancestor ca
      ON c.concept_id = ca.ancestor_concept_id
    WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
      AND c.concept_code ~* '250\.1|E10'  -- ICD9/ICD10 T1DM patterns
),
/* ------------------------------------------------------------
   3. Diagnosis evidence: condition_occurrence mapped to SNOMED
   ------------------------------------------------------------ */
dx_t2dm AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN public.concept_relationship cr
      ON co.condition_source_concept_id = cr.concept_id_1
     AND cr.relationship_id = 'Maps to'
    WHERE cr.concept_id_2 IN (SELECT concept_id FROM t2dm_snomed)
),
dx_t1dm AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN public.concept_relationship cr
      ON co.condition_source_concept_id = cr.concept_id_1
     AND cr.relationship_id = 'Maps to'
    WHERE cr.concept_id_2 IN (SELECT concept_id FROM t1dm_snomed)
),
/* ------------------------------------------------------------
   4. Medication evidence: antidiabetic drug classes
   ------------------------------------------------------------ */
antidiabetic_drugs AS (
    SELECT ca.descendant_concept_id AS concept_id
    FROM public.concept c
    JOIN public.concept_ancestor ca
      ON c.concept_id = ca.ancestor_concept_id
    WHERE c.concept_name ~* 'metformin|insulin|sulfonylurea|glp-1|sglt2|dpp-4'
      AND c.domain_id = 'Drug'
),
rx_t2dm AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    WHERE de.drug_concept_id IN (SELECT concept_id FROM antidiabetic_drugs)
),
/* ------------------------------------------------------------
   5. Laboratory evidence: HbA1c, fasting glucose, random glucose
   ------------------------------------------------------------ */
lab_hba1c AS (
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN public.concept c ON m.measurement_concept_id = c.concept_id
    WHERE c.concept_name ~* 'hba1c'
      AND m.value_as_number >= 6.5
),
lab_fasting_glucose AS (
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN public.concept c ON m.measurement_concept_id = c.concept_id
    WHERE c.concept_name ~* 'glucose'
      AND m.value_as_number >= 126
      AND m.unit_concept_id IN (SELECT concept_id FROM public.concept WHERE concept_name ~* 'mg/dl')
),
lab_random_glucose AS (
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN public.concept c ON m.measurement_concept_id = c.concept_id
    WHERE c.concept_name ~* 'glucose'
      AND m.value_as_number >= 200
),
lab_t2dm AS (
    SELECT person_id FROM lab_hba1c
    UNION
    SELECT person_id FROM lab_fasting_glucose
    UNION
    SELECT person_id FROM lab_random_glucose
)
/* ------------------------------------------------------------
   6. Combine criteria and apply exclusion
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
