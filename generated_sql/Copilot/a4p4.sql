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
      AND c.concept_name ~* 'type 2 diabetes'
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
      AND c.concept_name ~* 'type 1 diabetes'
),
/* ------------------------------------------------------------
   3. Map ICD → SNOMED using 'Maps to'
   ------------------------------------------------------------ */
mapped_t2dm AS (
    SELECT cr.concept_id_2 AS concept_id
    FROM public.concept c
    JOIN public.concept_relationship cr
      ON c.concept_id = cr.concept_id_1
    WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
      AND cr.relationship_id = 'Maps to'
      AND c.concept_name ~* 'type 2 diabetes'
),
mapped_t1dm AS (
    SELECT cr.concept_id_2 AS concept_id
    FROM public.concept c
    JOIN public.concept_relationship cr
      ON c.concept_id = cr.concept_id_1
    WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
      AND cr.relationship_id = 'Maps to'
      AND c.concept_name ~* 'type 1 diabetes'
),
/* ------------------------------------------------------------
   4. Diagnosis evidence in condition_occurrence
   ------------------------------------------------------------ */
dx_t2dm AS (
    SELECT DISTINCT person_id
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (
        SELECT concept_id FROM t2dm_snomed
        UNION
        SELECT concept_id FROM mapped_t2dm
    )
),
dx_t1dm AS (
    SELECT DISTINCT person_id
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (
        SELECT concept_id FROM t1dm_snomed
        UNION
        SELECT concept_id FROM mapped_t1dm
    )
),
/* ------------------------------------------------------------
   5. Medication evidence (antidiabetic drug classes)
   ------------------------------------------------------------ */
antidiabetic_drugs AS (
    SELECT descendant_concept_id AS concept_id
    FROM public.concept_ancestor
    WHERE ancestor_concept_id IN (
        /* Metformin, sulfonylureas, DPP4 inhibitors, GLP1 agonists,
           SGLT2 inhibitors, insulin — use standard class ancestor IDs */
        1503297,  /* Metformin */
        1502809,  /* Sulfonylureas */
        40213154, /* DPP-4 inhibitors */
        40213156, /* GLP-1 agonists */
        45774751, /* SGLT2 inhibitors */
        21600712  /* Insulin */
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
    SELECT DISTINCT person_id
    FROM public.measurement
    WHERE measurement_concept_id IN (
        /* HbA1c LOINC codes */
        3004410,  /* 4548-4 */
        3005673   /* 17856-6 */
    )
      AND value_as_number >= 6.5
),
lab_fasting_glucose AS (
    SELECT DISTINCT person_id
    FROM public.measurement
    WHERE measurement_concept_id IN (
        3020630, /* 1558-6 fasting glucose */
        3020631  /* 1557-8 fasting glucose */
    )
      AND value_as_number >= 126
),
lab_random_glucose AS (
    SELECT DISTINCT person_id
    FROM public.measurement
    WHERE measurement_concept_id IN (
        3004501, /* 2339-0 glucose */
        3023103  /* 2345-7 glucose */
    )
      AND value_as_number >= 200
),
lab_t2dm AS (
    SELECT DISTINCT person_id
    FROM (
        SELECT person_id FROM lab_hba1c
        UNION
        SELECT person_id FROM lab_fasting_glucose
        UNION
        SELECT person_id FROM lab_random_glucose
    ) x
)
/* ------------------------------------------------------------
   7. Combine evidence and exclude Type 1 diabetes
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
