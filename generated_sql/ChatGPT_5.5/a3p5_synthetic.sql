WITH
/* 1) ICD9CM / ICD10CM source concepts for Type 2 diabetes.
   ICD10CM: E11.*
   ICD9CM: 250.x0 or 250.x2, where final digit 0/2 indicates type 2 or unspecified-not-type-1 coding.
*/
t2d_icd_source_concepts AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND invalid_reason IS NULL
      AND (
            (vocabulary_id = 'ICD10CM' AND concept_code ILIKE 'E11%')
         OR (vocabulary_id = 'ICD9CM'
             AND concept_code ~ '^250(\.[0-9]{2})?$'
             AND RIGHT(REPLACE(concept_code, '.', ''), 1) IN ('0', '2'))
      )
),

/* 2) Map ICD source concepts to standard OMOP concepts when mappings exist. */
t2d_mapped_standard_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM public.concept_relationship cr
    JOIN t2d_icd_source_concepts src
      ON cr.concept_id_1 = src.concept_id
    JOIN public.concept std
      ON std.concept_id = cr.concept_id_2
    WHERE cr.relationship_id = 'Maps to'
      AND cr.invalid_reason IS NULL
      AND std.invalid_reason IS NULL
      AND std.standard_concept = 'S'
),

/* 3) Add standard concepts directly identifiable as Type 2 diabetes. */
t2d_named_standard_concepts AS (
    SELECT concept_id
    FROM public.concept
    WHERE invalid_reason IS NULL
      AND standard_concept = 'S'
      AND domain_id = 'Condition'
      AND (
            concept_name ILIKE '%type 2 diabetes%'
         OR concept_name ILIKE '%type II diabetes%'
         OR concept_name ILIKE '%non-insulin-dependent diabetes%'
         OR concept_name ILIKE '%NIDDM%'
      )
),

/* 4) Expand standard Type 2 diabetes concepts through concept_ancestor when populated. */
t2d_condition_concepts AS (
    SELECT concept_id FROM t2d_mapped_standard_concepts
    UNION
    SELECT concept_id FROM t2d_named_standard_concepts
    UNION
    SELECT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    JOIN (
        SELECT concept_id FROM t2d_mapped_standard_concepts
        UNION
        SELECT concept_id FROM t2d_named_standard_concepts
    ) base
      ON ca.ancestor_concept_id = base.concept_id
),

/* 5) Patient-level Type 2 diabetes diagnosis evidence from standard or source ICD concepts. */
t2d_diagnosis_events AS (
    SELECT DISTINCT
        co.person_id,
        COALESCE(co.condition_start_date, co.condition_start_datetime::date) AS event_date
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (SELECT concept_id FROM t2d_condition_concepts)
       OR co.condition_source_concept_id IN (SELECT concept_id FROM t2d_icd_source_concepts)
       OR co.condition_source_value ILIKE 'E11%'
       OR (
            co.condition_source_value ~ '^250(\.[0-9]{2})?$'
            AND RIGHT(REPLACE(co.condition_source_value, '.', ''), 1) IN ('0', '2')
          )
),

t2d_diagnosis_summary AS (
    SELECT
        person_id,
        COUNT(*) AS t2d_dx_count,
        COUNT(DISTINCT event_date) AS t2d_dx_distinct_dates
    FROM t2d_diagnosis_events
    WHERE event_date IS NOT NULL
    GROUP BY person_id
),

/* 6) Type 1 diabetes concepts for exclusion logic when Type 2 evidence is weak. */
t1d_condition_concepts AS (
    SELECT concept_id
    FROM public.concept
    WHERE invalid_reason IS NULL
      AND domain_id = 'Condition'
      AND (
            (vocabulary_id = 'ICD10CM' AND concept_code ILIKE 'E10%')
         OR (vocabulary_id = 'ICD9CM'
             AND concept_code ~ '^250(\.[0-9]{2})?$'
             AND RIGHT(REPLACE(concept_code, '.', ''), 1) IN ('1', '3'))
         OR (standard_concept = 'S' AND concept_name ILIKE '%type 1 diabetes%')
         OR (standard_concept = 'S' AND concept_name ILIKE '%type I diabetes%')
      )
),

t1d_diagnosis_events AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (SELECT concept_id FROM t1d_condition_concepts)
       OR co.condition_source_concept_id IN (SELECT concept_id FROM t1d_condition_concepts)
       OR co.condition_source_value ILIKE 'E10%'
       OR (
            co.condition_source_value ~ '^250(\.[0-9]{2})?$'
            AND RIGHT(REPLACE(co.condition_source_value, '.', ''), 1) IN ('1', '3')
          )
),

/* 7) Non-insulin Type 2 diabetes medication evidence using drug concept names.
   Drug source values are often numeric, so use mapped drug_concept_id names.
*/
t2d_medication_events AS (
    SELECT DISTINCT
        de.person_id,
        COALESCE(de.drug_exposure_start_date, de.drug_exposure_start_datetime::date) AS event_date
    FROM public.drug_exposure de
    JOIN public.concept dc
      ON dc.concept_id = de.drug_concept_id
    WHERE dc.invalid_reason IS NULL
      AND dc.domain_id = 'Drug'
      AND (
            dc.concept_name ILIKE '%metformin%'
         OR dc.concept_name ILIKE '%glucophage%'
         OR dc.concept_name ILIKE '%glyburide%'
         OR dc.concept_name ILIKE '%glipizide%'
         OR dc.concept_name ILIKE '%glimepiride%'
         OR dc.concept_name ILIKE '%sitagliptin%'
         OR dc.concept_name ILIKE '%januvia%'
         OR dc.concept_name ILIKE '%linagliptin%'
         OR dc.concept_name ILIKE '%tradjenta%'
         OR dc.concept_name ILIKE '%saxagliptin%'
         OR dc.concept_name ILIKE '%onglyza%'
         OR dc.concept_name ILIKE '%alogliptin%'
         OR dc.concept_name ILIKE '%pioglitazone%'
         OR dc.concept_name ILIKE '%actos%'
         OR dc.concept_name ILIKE '%rosiglitazone%'
         OR dc.concept_name ILIKE '%empagliflozin%'
         OR dc.concept_name ILIKE '%jardiance%'
         OR dc.concept_name ILIKE '%dapagliflozin%'
         OR dc.concept_name ILIKE '%farxiga%'
         OR dc.concept_name ILIKE '%canagliflozin%'
         OR dc.concept_name ILIKE '%invokana%'
         OR dc.concept_name ILIKE '%ertugliflozin%'
         OR dc.concept_name ILIKE '%semaglutide%'
         OR dc.concept_name ILIKE '%ozempic%'
         OR dc.concept_name ILIKE '%rybelsus%'
         OR dc.concept_name ILIKE '%liraglutide%'
         OR dc.concept_name ILIKE '%victoza%'
         OR dc.concept_name ILIKE '%dulaglutide%'
         OR dc.concept_name ILIKE '%trulicity%'
         OR dc.concept_name ILIKE '%exenatide%'
         OR dc.concept_name ILIKE '%byetta%'
         OR dc.concept_name ILIKE '%tirzepatide%'
         OR dc.concept_name ILIKE '%mounjaro%'
         OR dc.concept_name ILIKE '%acarbose%'
         OR dc.concept_name ILIKE '%miglitol%'
         OR dc.concept_name ILIKE '%repaglinide%'
         OR dc.concept_name ILIKE '%nateglinide%'
      )
),

t2d_medication_summary AS (
    SELECT
        person_id,
        COUNT(*) AS t2d_med_count,
        COUNT(DISTINCT event_date) AS t2d_med_distinct_dates
    FROM t2d_medication_events
    WHERE event_date IS NOT NULL
    GROUP BY person_id
),

/* 8) Diabetes-range laboratory evidence.
   Uses measurement_concept_id names and measurement_source_value LOINC where available.
*/
diabetes_lab_events AS (
    SELECT DISTINCT
        m.person_id,
        COALESCE(m.measurement_date, m.measurement_datetime::date) AS event_date
    FROM public.measurement m
    LEFT JOIN public.concept mc
      ON mc.concept_id = m.measurement_concept_id
    WHERE m.value_as_number IS NOT NULL
      AND (
            /* HbA1c >= 6.5% */
            (
                (
                    mc.concept_name ILIKE '%hemoglobin a1c%'
                 OR mc.concept_name ILIKE '%hba1c%'
                 OR m.measurement_source_value IN ('4548-4', '17856-6', '59261-8')
                )
                AND m.value_as_number >= 6.5
                AND (
                    m.unit_source_value ILIKE '%\%%' ESCAPE '\'
                    OR m.unit_source_value ILIKE '%percent%'
                    OR m.unit_source_value IS NULL
                    OR m.unit_source_value = ''
                )
            )

            OR

            /* Fasting plasma glucose >= 126 mg/dL */
            (
                (
                    mc.concept_name ILIKE '%fasting glucose%'
                 OR m.measurement_source_value IN ('1558-6', '1556-0')
                )
                AND m.value_as_number >= 126
                AND (
                    m.unit_source_value ILIKE '%mg/dL%'
                    OR m.unit_source_value ILIKE '%mg/dl%'
                    OR m.unit_source_value IS NULL
                    OR m.unit_source_value = ''
                )
            )

            OR

            /* Random plasma glucose or oral glucose tolerance test >= 200 mg/dL */
            (
                (
                    mc.concept_name ILIKE '%glucose%'
                 OR m.measurement_source_value IN ('2345-7', '15074-8', '14749-6')
                )
                AND m.value_as_number >= 200
                AND (
                    m.unit_source_value ILIKE '%mg/dL%'
                    OR m.unit_source_value ILIKE '%mg/dl%'
                    OR m.unit_source_value IS NULL
                    OR m.unit_source_value = ''
                )
            )
      )
),

diabetes_lab_summary AS (
    SELECT
        person_id,
        COUNT(*) AS diabetes_lab_count,
        COUNT(DISTINCT event_date) AS diabetes_lab_distinct_dates
    FROM diabetes_lab_events
    WHERE event_date IS NOT NULL
    GROUP BY person_id
),

/* 9) Final phenotype:
   Include patients with strong diagnosis evidence, or a diagnosis plus treatment/lab support,
   or medication plus repeated abnormal lab support.
   Exclude likely Type 1 diabetes only when there is no direct Type 2 diagnosis evidence.
*/
candidate_t2d AS (
    SELECT p.person_id
    FROM public.person p
    LEFT JOIN t2d_diagnosis_summary dx
      ON dx.person_id = p.person_id
    LEFT JOIN t2d_medication_summary med
      ON med.person_id = p.person_id
    LEFT JOIN diabetes_lab_summary lab
      ON lab.person_id = p.person_id
    LEFT JOIN t1d_diagnosis_events t1
      ON t1.person_id = p.person_id
    WHERE
        (
            COALESCE(dx.t2d_dx_distinct_dates, 0) >= 2
         OR (
                COALESCE(dx.t2d_dx_count, 0) >= 1
                AND (
                    COALESCE(med.t2d_med_count, 0) >= 1
                    OR COALESCE(lab.diabetes_lab_count, 0) >= 1
                )
            )
         OR (
                COALESCE(med.t2d_med_count, 0) >= 1
                AND COALESCE(lab.diabetes_lab_distinct_dates, 0) >= 2
            )
        )
        AND (
            t1.person_id IS NULL
            OR COALESCE(dx.t2d_dx_count, 0) >= 1
        )
)

SELECT DISTINCT person_id
FROM candidate_t2d
ORDER BY person_id;