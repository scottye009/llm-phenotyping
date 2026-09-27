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
    FROM public.concept_ancestor ca
    JOIN public.concept c ON ca.ancestor_concept_id = c.concept_id
    WHERE c.concept_name ILIKE '%type 2 diabetes%'
      AND c.domain_id = 'Condition'
),

/* ------------------------------------------------------------
   2. Identify ICD9CM/ICD10CM source concepts that map → T2DM SNOMED
   ------------------------------------------------------------ */
t2dm_mapped AS (
    SELECT cr.concept_id_1 AS source_concept_id
    FROM public.concept_relationship cr
    JOIN t2dm_snomed t2 ON cr.concept_id_2 = t2.concept_id
    JOIN public.concept c ON cr.concept_id_1 = c.concept_id
    WHERE cr.relationship_id = 'Maps to'
      AND c.vocabulary_id IN ('ICD9CM','ICD10CM')
),

/* ------------------------------------------------------------
   3. Identify SNOMED standard concepts for Type 1 diabetes (exclusion)
   ------------------------------------------------------------ */
t1dm_snomed AS (
    SELECT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    JOIN public.concept c ON ca.ancestor_concept_id = c.concept_id
    WHERE c.concept_name ILIKE '%type 1 diabetes%'
      AND c.domain_id = 'Condition'
),

/* ------------------------------------------------------------
   4. Diagnosis evidence for T2DM
   ------------------------------------------------------------ */
dx_t2dm AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (SELECT concept_id FROM t2dm_snomed)
       OR co.condition_source_concept_id IN (SELECT source_concept_id FROM t2dm_mapped)
),

/* ------------------------------------------------------------
   5. Exclusion: Type 1 diabetes diagnosis
   ------------------------------------------------------------ */
dx_t1dm AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (SELECT concept_id FROM t1dm_snomed)
),

/* ------------------------------------------------------------
   6. Medication evidence — antidiabetic drugs
      (metformin, sulfonylureas, DPP-4 inhibitors, GLP-1 agonists,
       SGLT2 inhibitors, insulin)
   ------------------------------------------------------------ */
antidiabetic_drugs AS (
    SELECT DISTINCT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    JOIN public.concept c ON ca.ancestor_concept_id = c.concept_id
    WHERE c.concept_name ~* '(metformin|insulin|gliptin|glutide|flozin|sulfonylurea)'
      AND c.domain_id = 'Drug'
),

rx_t2dm AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    WHERE de.drug_concept_id IN (SELECT concept_id FROM antidiabetic_drugs)
),

/* ------------------------------------------------------------
   7. Laboratory evidence
      HbA1c ≥ 6.5%
      Fasting glucose ≥ 126 mg/dL
      Random glucose ≥ 200 mg/dL
   ------------------------------------------------------------ */
lab_hba1c AS (
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN public.concept c ON m.measurement_concept_id = c.concept_id
    WHERE c.concept_name ILIKE '%hba1c%'
      AND m.value_as_number >= 6.5
),

lab_glucose_fasting AS (
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN public.concept c ON m.measurement_concept_id = c.concept_id
    WHERE c.concept_name ILIKE '%glucose%'
      AND c.concept_name ILIKE '%fast%'
      AND m.value_as_number >= 126
),

lab_glucose_random AS (
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN public.concept c ON m.measurement_concept_id = c.concept_id
    WHERE c.concept_name ILIKE '%glucose%'
      AND m.value_as_number >= 200
),

lab_t2dm AS (
    SELECT person_id FROM lab_hba1c
    UNION
    SELECT person_id FROM lab_glucose_fasting
    UNION
    SELECT person_id FROM lab_glucose_random
)

/* ------------------------------------------------------------
   8. Final phenotype:
      Must have (Diagnosis OR Medication OR Lab)
      AND must NOT have Type 1 diabetes
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
