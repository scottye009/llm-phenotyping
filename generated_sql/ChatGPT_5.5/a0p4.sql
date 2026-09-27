WITH t2dm_dx_source_codes AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD10CM'
      AND concept_code LIKE 'E11%'

    UNION

    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD9CM'
      AND concept_code IN (
          '25000', '25002',
          '25010', '25012',
          '25020', '25022',
          '25030', '25032',
          '25040', '25042',
          '25050', '25052',
          '25060', '25062',
          '25070', '25072',
          '25080', '25082',
          '25090', '25092'
      )
),

t2dm_dx_standard_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM public.concept_relationship cr
    JOIN t2dm_dx_source_codes src
      ON cr.concept_id_1 = src.concept_id
    WHERE cr.relationship_id = 'Maps to'
),

t2dm_diagnosis AS (
    SELECT
        co.person_id,
        co.condition_start_date AS event_date
    FROM public.condition_occurrence co
    JOIN t2dm_dx_standard_concepts t2
      ON co.condition_concept_id = t2.concept_id
),

diabetes_lab_evidence AS (
    SELECT
        m.person_id,
        m.measurement_date AS event_date
    FROM public.measurement m
    JOIN public.concept c
      ON m.measurement_concept_id = c.concept_id
    WHERE
        (
            LOWER(c.concept_name) LIKE '%hemoglobin a1c%'
            AND m.value_as_number >= 6.5
        )
        OR
        (
            LOWER(c.concept_name) LIKE '%glucose%'
            AND LOWER(c.concept_name) LIKE '%fasting%'
            AND m.value_as_number >= 126
        )
        OR
        (
            LOWER(c.concept_name) LIKE '%glucose%'
            AND LOWER(c.concept_name) LIKE '%random%'
            AND m.value_as_number >= 200
        )
        OR
        (
            LOWER(c.concept_name) LIKE '%glucose%'
            AND (
                LOWER(c.concept_name) LIKE '%2 hour%'
                OR LOWER(c.concept_name) LIKE '%ogtt%'
                OR LOWER(c.concept_name) LIKE '%oral glucose tolerance%'
            )
            AND m.value_as_number >= 200
        )
),

t2dm_medication_concepts AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id IN ('RxNorm', 'RxNorm Extension')
      AND (
          LOWER(concept_name) LIKE '%metformin%'
          OR LOWER(concept_name) LIKE '%glucophage%'
          OR LOWER(concept_name) LIKE '%fortamet%'
          OR LOWER(concept_name) LIKE '%glumetza%'
          OR LOWER(concept_name) LIKE '%riomet%'

          OR LOWER(concept_name) LIKE '%sitagliptin%'
          OR LOWER(concept_name) LIKE '%januvia%'
          OR LOWER(concept_name) LIKE '%saxagliptin%'
          OR LOWER(concept_name) LIKE '%onglyza%'
          OR LOWER(concept_name) LIKE '%linagliptin%'
          OR LOWER(concept_name) LIKE '%tradjenta%'
          OR LOWER(concept_name) LIKE '%alogliptin%'
          OR LOWER(concept_name) LIKE '%nesina%'

          OR LOWER(concept_name) LIKE '%empagliflozin%'
          OR LOWER(concept_name) LIKE '%jardiance%'
          OR LOWER(concept_name) LIKE '%canagliflozin%'
          OR LOWER(concept_name) LIKE '%invokana%'
          OR LOWER(concept_name) LIKE '%dapagliflozin%'
          OR LOWER(concept_name) LIKE '%farxiga%'
          OR LOWER(concept_name) LIKE '%ertugliflozin%'
          OR LOWER(concept_name) LIKE '%steglatro%'

          OR LOWER(concept_name) LIKE '%semaglutide%'
          OR LOWER(concept_name) LIKE '%ozempic%'
          OR LOWER(concept_name) LIKE '%rybelsus%'
          OR LOWER(concept_name) LIKE '%wegovy%'
          OR LOWER(concept_name) LIKE '%liraglutide%'
          OR LOWER(concept_name) LIKE '%victoza%'
          OR LOWER(concept_name) LIKE '%saxenda%'
          OR LOWER(concept_name) LIKE '%dulaglutide%'
          OR LOWER(concept_name) LIKE '%trulicity%'
          OR LOWER(concept_name) LIKE '%exenatide%'
          OR LOWER(concept_name) LIKE '%byetta%'
          OR LOWER(concept_name) LIKE '%bydureon%'
          OR LOWER(concept_name) LIKE '%tirzepatide%'
          OR LOWER(concept_name) LIKE '%mounjaro%'
          OR LOWER(concept_name) LIKE '%zepbound%'

          OR LOWER(concept_name) LIKE '%glipizide%'
          OR LOWER(concept_name) LIKE '%glucotrol%'
          OR LOWER(concept_name) LIKE '%glyburide%'
          OR LOWER(concept_name) LIKE '%diabeta%'
          OR LOWER(concept_name) LIKE '%glynase%'
          OR LOWER(concept_name) LIKE '%glimepiride%'
          OR LOWER(concept_name) LIKE '%amaryl%'

          OR LOWER(concept_name) LIKE '%pioglitazone%'
          OR LOWER(concept_name) LIKE '%actos%'
          OR LOWER(concept_name) LIKE '%rosiglitazone%'
          OR LOWER(concept_name) LIKE '%avandia%'

          OR LOWER(concept_name) LIKE '%repaglinide%'
          OR LOWER(concept_name) LIKE '%prandin%'
          OR LOWER(concept_name) LIKE '%nateglinide%'
          OR LOWER(concept_name) LIKE '%starlix%'

          OR LOWER(concept_name) LIKE '%acarbose%'
          OR LOWER(concept_name) LIKE '%precose%'
          OR LOWER(concept_name) LIKE '%miglitol%'
          OR LOWER(concept_name) LIKE '%glyset%'
      )
),

t2dm_medication AS (
    SELECT
        de.person_id,
        de.drug_exposure_start_date AS event_date
    FROM public.drug_exposure de
    JOIN t2dm_medication_concepts med
      ON de.drug_concept_id = med.concept_id
),

type1_dx_source_codes AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD10CM'
      AND concept_code LIKE 'E10%'

    UNION

    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD9CM'
      AND concept_code IN (
          '25001', '25003',
          '25011', '25013',
          '25021', '25023',
          '25031', '25033',
          '25041', '25043',
          '25051', '25053',
          '25061', '25063',
          '25071', '25073',
          '25081', '25083',
          '25091', '25093'
      )
),

type1_standard_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM public.concept_relationship cr
    JOIN type1_dx_source_codes src
      ON cr.concept_id_1 = src.concept_id
    WHERE cr.relationship_id = 'Maps to'
),

type1_evidence AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN type1_standard_concepts t1
      ON co.condition_concept_id = t1.concept_id
),

gestational_or_secondary_diabetes AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN public.concept c
      ON co.condition_concept_id = c.concept_id
    WHERE
        LOWER(c.concept_name) LIKE '%gestational diabetes%'
        OR LOWER(c.concept_name) LIKE '%secondary diabetes%'
        OR LOWER(c.concept_name) LIKE '%drug or chemical induced diabetes%'
        OR LOWER(c.concept_name) LIKE '%diabetes mellitus due to underlying condition%'
),

all_t2dm_evidence AS (
    SELECT person_id, event_date, 'diagnosis' AS evidence_type
    FROM t2dm_diagnosis

    UNION ALL

    SELECT person_id, event_date, 'lab' AS evidence_type
    FROM diabetes_lab_evidence

    UNION ALL

    SELECT person_id, event_date, 'medication' AS evidence_type
    FROM t2dm_medication
),

evidence_summary AS (
    SELECT
        person_id,
        COUNT(*) AS total_evidence_count,
        COUNT(DISTINCT event_date) AS distinct_evidence_dates,
        COUNT(DISTINCT evidence_type) AS distinct_evidence_types,
        MIN(event_date) AS phenotype_index_date
    FROM all_t2dm_evidence
    GROUP BY person_id
)

SELECT
    es.person_id,
    es.phenotype_index_date
FROM evidence_summary es
WHERE
    (
        es.distinct_evidence_dates >= 2
        OR es.distinct_evidence_types >= 2
    )
    AND NOT EXISTS (
        SELECT 1
        FROM type1_evidence t1
        WHERE t1.person_id = es.person_id
    )
    AND NOT EXISTS (
        SELECT 1
        FROM gestational_or_secondary_diabetes ex
        WHERE ex.person_id = es.person_id
    );