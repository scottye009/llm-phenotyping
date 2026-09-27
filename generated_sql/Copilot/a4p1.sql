/* ============================================================
   TYPE 2 DIABETES MELLITUS PHENOTYPE (OMOP CDM, PostgreSQL)
   Returns: person_id
   ============================================================ */

/* ------------------------------------------------------------
   1. Identify SNOMED standard concepts for Type 2 diabetes
   ------------------------------------------------------------ */
WITH t2dm_snomed AS (
    SELECT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    JOIN public.concept c ON ca.ancestor_concept_id = c.concept_id
    WHERE c.concept_name ~* 'type 2 diabetes'
      AND c.domain_id = 'Condition'
),

/* ------------------------------------------------------------
   2. Identify SNOMED standard concepts for Type 1 diabetes
      (exclusion)
   ------------------------------------------------------------ */
t1dm_snomed AS (
    SELECT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    JOIN public.concept c ON ca.ancestor_concept_id = c.concept_id
    WHERE c.concept_name ~* 'type 1 diabetes'
      AND c.domain_id = 'Condition'
),

/* ------------------------------------------------------------
   3. Map ICD9CM/ICD10CM → SNOMED using "Maps to"
   ------------------------------------------------------------ */
t2dm_mapped AS (
    SELECT cr.concept_id_2 AS concept_id
    FROM public.concept_relationship cr
    JOIN public.concept c ON cr.concept_id_1 = c.concept_id
    WHERE cr.relationship_id = 'Maps to'
      AND c.vocabulary_id IN ('ICD9CM','ICD10CM')
      AND c.concept_name ~* 'type 2 diabetes'
),

t1dm_mapped AS (
    SELECT cr.concept_id_2 AS concept_id
    FROM public.concept_relationship cr
    JOIN public.concept c ON cr.concept_id_1 = c.concept_id
    WHERE cr.relationship_id = 'Maps to'
      AND c.vocabulary_id IN ('ICD9CM','ICD10CM')
      AND c.concept_name ~* 'type 1 diabetes'
),

/* ------------------------------------------------------------
   4. Combine diagnosis concept sets
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
   5. Diagnosis-based T2DM
   ------------------------------------------------------------ */
t2dm_dx AS (
    SELECT DISTINCT person_id
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (SELECT concept_id FROM t2dm_dx_concepts)
),

/* ------------------------------------------------------------
   6. Exclusion: Type 1 diabetes diagnosis
   ------------------------------------------------------------ */
t1dm_exclusion AS (
    SELECT DISTINCT person_id
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (SELECT concept_id FROM t1dm_dx_concepts)
),

/* ------------------------------------------------------------
   7. Medication-based evidence
      Identify antidiabetic drug classes by concept name
   ------------------------------------------------------------ */
t2dm_drugs AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN public.concept c ON de.drug_concept_id = c.concept_id
    WHERE c.concept_name ~* 'metformin'
       OR c.concept_name ~* 'insulin'
       OR c.concept_name ~* 'gliptin'      -- DPP-4 inhibitors
       OR c.concept_name ~* 'glutide'      -- GLP-1 agonists
       OR c.concept_name ~* 'flozin'       -- SGLT2 inhibitors
       OR c.concept_name ~* 'sulfonylurea'
),

/* ------------------------------------------------------------
   8. Laboratory-based evidence
      HbA1c ≥ 6.5%
      Fasting glucose ≥ 126 mg/dL
      Random glucose ≥ 200 mg/dL
   ------------------------------------------------------------ */
t2dm_labs AS (
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN public.concept c ON m.measurement_concept_id = c.concept_id
    WHERE (
            /* HbA1c */
            c.concept_name ~* 'hba1c'
            AND m.value_as_number >= 6.5
          )
       OR (
            /* fasting glucose */
            c.concept_name ~* 'glucose'
            AND c.concept_name ~* 'fast'
            AND m.value_as_number >= 126
          )
       OR (
            /* random glucose */
            c.concept_name ~* 'glucose'
            AND m.value_as_number >= 200
          )
),

/* ------------------------------------------------------------
   9. Combine all inclusion criteria
   ------------------------------------------------------------ */
t2dm_included AS (
    SELECT person_id FROM t2dm_dx
    UNION
    SELECT person_id FROM t2dm_drugs
    UNION
    SELECT person_id FROM t2dm_labs
)

/* ------------------------------------------------------------
   10. Final cohort: include T2DM evidence, exclude Type 1 DM
   ------------------------------------------------------------ */
SELECT DISTINCT person_id
FROM t2dm_included
WHERE person_id NOT IN (SELECT person_id FROM t1dm_exclusion)
ORDER BY person_id;
