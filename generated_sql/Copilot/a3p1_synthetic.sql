/* Type 2 Diabetes Mellitus (T2DM) phenotype
   Inclusion: patient meets ANY of:
   1) >=2 T2DM diagnoses on different dates (ICD9CM/ICD10CM mapped to standard concepts)
   2) >=1 T2DM diagnosis + >=1 antidiabetic drug exposure (excluding insulin-only evidence)
   3) Diabetes laboratory evidence:
        - HbA1c >= 6.5 %
        - Fasting plasma glucose >= 126 mg/dL
        - Random plasma glucose >= 200 mg/dL
      AND >=1 T2DM diagnosis or antidiabetic drug exposure
   Uses OMOP standard concepts obtained through ICD mappings, concept hierarchy expansion,
   RxNorm drug ingredients/products, and LOINC laboratory concepts.
*/

WITH
/* ICD9CM/ICD10CM Type 2 DM source concepts */
t2dm_icd_source AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
      AND (
            c.concept_code LIKE '250%'          /* ICD9CM T2DM family */
         OR c.concept_code LIKE 'E11%'          /* ICD10CM T2DM */
      )
      AND c.invalid_reason IS NULL
),

/* Map ICD source concepts to standard concepts */
t2dm_standard AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM t2dm_icd_source s
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = s.concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
),

/* Expand descendants from mapped standard concepts */
t2dm_condition_concepts AS (
    SELECT DISTINCT ca.descendant_concept_id AS concept_id
    FROM t2dm_standard ts
    JOIN public.concept_ancestor ca
      ON ca.ancestor_concept_id = ts.concept_id

    UNION

    SELECT concept_id
    FROM t2dm_standard
),

/* T2DM diagnosis events */
t2dm_dx AS (
    SELECT
        co.person_id,
        co.condition_start_date::date AS dx_date
    FROM public.condition_occurrence co
    JOIN t2dm_condition_concepts d
      ON d.concept_id = co.condition_concept_id
),

/* >=2 diagnoses on different dates */
t2dm_dx2 AS (
    SELECT person_id
    FROM t2dm_dx
    GROUP BY person_id
    HAVING COUNT(DISTINCT dx_date) >= 2
),

/* Antidiabetic drug ingredients/products */
antidiabetic_drug_concepts AS (
    SELECT DISTINCT ca.descendant_concept_id AS concept_id
    FROM public.concept a
    JOIN public.concept_ancestor ca
      ON ca.ancestor_concept_id = a.concept_id
    WHERE a.domain_id = 'Drug'
      AND a.standard_concept = 'S'
      AND (
            a.concept_name ILIKE '%metformin%'
         OR a.concept_name ILIKE '%glipizide%'
         OR a.concept_name ILIKE '%glyburide%'
         OR a.concept_name ILIKE '%glimepiride%'
         OR a.concept_name ILIKE '%pioglitazone%'
         OR a.concept_name ILIKE '%rosiglitazone%'
         OR a.concept_name ILIKE '%acarbose%'
         OR a.concept_name ILIKE '%miglitol%'
         OR a.concept_name ILIKE '%sitagliptin%'
         OR a.concept_name ILIKE '%saxagliptin%'
         OR a.concept_name ILIKE '%linagliptin%'
         OR a.concept_name ILIKE '%alogliptin%'
         OR a.concept_name ILIKE '%exenatide%'
         OR a.concept_name ILIKE '%liraglutide%'
         OR a.concept_name ILIKE '%dulaglutide%'
         OR a.concept_name ILIKE '%semaglutide%'
         OR a.concept_name ILIKE '%lixisenatide%'
         OR a.concept_name ILIKE '%empagliflozin%'
         OR a.concept_name ILIKE '%dapagliflozin%'
         OR a.concept_name ILIKE '%canagliflozin%'
         OR a.concept_name ILIKE '%ertugliflozin%'
         OR a.concept_name ILIKE '%tirzepatide%'
         OR a.concept_name ILIKE '%janumet%'
         OR a.concept_name ILIKE '%januvia%'
         OR a.concept_name ILIKE '%onglyza%'
         OR a.concept_name ILIKE '%tradjenta%'
         OR a.concept_name ILIKE '%victoza%'
         OR a.concept_name ILIKE '%ozempic%'
         OR a.concept_name ILIKE '%rybelsus%'
         OR a.concept_name ILIKE '%trulicity%'
         OR a.concept_name ILIKE '%farxiga%'
         OR a.concept_name ILIKE '%jardiance%'
         OR a.concept_name ILIKE '%invokana%'
      )
),

drug_evidence AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN antidiabetic_drug_concepts adc
      ON adc.concept_id = de.drug_concept_id
),

/* HbA1c concepts (LOINC and descendants) */
hba1c_concepts AS (
    SELECT DISTINCT ca.descendant_concept_id AS concept_id
    FROM public.concept c
    JOIN public.concept_ancestor ca
      ON ca.ancestor_concept_id = c.concept_id
    WHERE c.vocabulary_id = 'LOINC'
      AND c.concept_code IN ('4548-4','17856-6')

    UNION

    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'LOINC'
      AND concept_code IN ('4548-4','17856-6')
),

/* Fasting glucose concepts */
fasting_glucose_concepts AS (
    SELECT DISTINCT ca.descendant_concept_id AS concept_id
    FROM public.concept c
    JOIN public.concept_ancestor ca
      ON ca.ancestor_concept_id = c.concept_id
    WHERE c.vocabulary_id = 'LOINC'
      AND c.concept_code IN ('1558-6')

    UNION

    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'LOINC'
      AND concept_code IN ('1558-6')
),

/* Random/plasma glucose concepts */
random_glucose_concepts AS (
    SELECT DISTINCT ca.descendant_concept_id AS concept_id
    FROM public.concept c
    JOIN public.concept_ancestor ca
      ON ca.ancestor_concept_id = c.concept_id
    WHERE c.vocabulary_id = 'LOINC'
      AND c.concept_code IN ('2345-7','2339-0')

    UNION

    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'LOINC'
      AND concept_code IN ('2345-7','2339-0')
),

lab_evidence AS (
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    WHERE m.value_as_number IS NOT NULL
      AND (
            (
              m.measurement_concept_id IN (
                  SELECT concept_id FROM hba1c_concepts
              )
              AND m.value_as_number >= 6.5
            )
         OR (
              m.measurement_concept_id IN (
                  SELECT concept_id FROM fasting_glucose_concepts
              )
              AND m.value_as_number >= 126
              AND (
                    m.unit_source_value ILIKE '%mg/dl%'
                 OR m.unit_source_value ILIKE '%mg/dL%'
                 OR m.unit_source_value IS NULL
                 OR m.unit_source_value = ''
              )
            )
         OR (
              m.measurement_concept_id IN (
                  SELECT concept_id FROM random_glucose_concepts
              )
              AND m.value_as_number >= 200
              AND (
                    m.unit_source_value ILIKE '%mg/dl%'
                 OR m.unit_source_value ILIKE '%mg/dL%'
                 OR m.unit_source_value IS NULL
                 OR m.unit_source_value = ''
              )
            )
      )
),

/* Diagnosis + drug evidence */
dx_plus_drug AS (
    SELECT DISTINCT d.person_id
    FROM t2dm_dx d
    JOIN drug_evidence rx
      ON rx.person_id = d.person_id
),

/* Lab evidence plus diagnostic support */
lab_supported AS (
    SELECT DISTINCT l.person_id
    FROM lab_evidence l
    WHERE EXISTS (
        SELECT 1
        FROM t2dm_dx d
        WHERE d.person_id = l.person_id
    )
    OR EXISTS (
        SELECT 1
        FROM drug_evidence rx
        WHERE rx.person_id = l.person_id
    )
)

/* Final cohort: union of all three inclusion paths */
SELECT DISTINCT person_id
FROM (
    SELECT person_id FROM t2dm_dx2
    UNION
    SELECT person_id FROM dx_plus_drug
    UNION
    SELECT person_id FROM lab_supported
) t2dm_cohort;