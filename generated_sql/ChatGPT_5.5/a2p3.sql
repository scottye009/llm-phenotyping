WITH t2dm_icd_source AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD9CM'
      AND concept_code IN (
          '25000','25002','25010','25012','25020','25022',
          '25030','25032','25040','25042','25050','25052',
          '25060','25062','25070','25072','25080','25082',
          '25090','25092'
      )

    UNION

    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD10CM'
      AND concept_code IN (
          'E1100','E1101','E1110','E1111','E1121','E1122','E1129',
          'E11311','E11319','E11321','E113211','E113212','E113213',
          'E113219','E11329','E113291','E113292','E113293','E113299',
          'E11331','E113311','E113312','E113313','E113319','E11339',
          'E11341','E113411','E113412','E113413','E113419','E11349',
          'E11351','E113521','E113522','E113523','E113529','E113531',
          'E113532','E113533','E113539','E113541','E113542','E113543',
          'E113549','E11355','E11359','E1136','E1137X1','E1137X2',
          'E1137X3','E1137X9','E1139','E1140','E1141','E1142','E1143',
          'E1144','E1149','E1151','E1152','E1159','E11610','E11618',
          'E11620','E11621','E11622','E11628','E11630','E11638',
          'E11641','E11649','E1165','E1169','E118','E119'
      )
),

t2dm_standard_dx AS (
    SELECT DISTINCT cr.concept_id_2 AS condition_concept_id
    FROM t2dm_icd_source s
    JOIN public.concept_relationship cr
      ON s.concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'
),

t2dm_dx_patients AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN t2dm_standard_dx dx
      ON co.condition_concept_id = dx.condition_concept_id
),

exclude_icd_source AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD9CM'
      AND (
          concept_code LIKE '250%1'
          OR concept_code LIKE '250%3'
          OR concept_code LIKE '6488%'
          OR concept_code LIKE '249%'
      )

    UNION

    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD10CM'
      AND (
          concept_code LIKE 'E10%'
          OR concept_code LIKE 'O24%'
          OR concept_code LIKE 'E08%'
          OR concept_code LIKE 'E09%'
          OR concept_code LIKE 'E13%'
      )
),

exclude_standard_dx AS (
    SELECT DISTINCT cr.concept_id_2 AS condition_concept_id
    FROM exclude_icd_source s
    JOIN public.concept_relationship cr
      ON s.concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'
),

excluded_patients AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN exclude_standard_dx ex
      ON co.condition_concept_id = ex.condition_concept_id
),

t2dm_drug_concepts AS (
    SELECT concept_id
    FROM public.concept
    WHERE domain_id = 'Drug'
      AND vocabulary_id IN ('RxNorm', 'RxNorm Extension')
      AND (
          LOWER(concept_name) LIKE '%metformin%'
          OR LOWER(concept_name) LIKE '%glucophage%'
          OR LOWER(concept_name) LIKE '%glumetza%'
          OR LOWER(concept_name) LIKE '%fortamet%'
          OR LOWER(concept_name) LIKE '%riomet%'

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
          OR LOWER(concept_name) LIKE '%liraglutide%'
          OR LOWER(concept_name) LIKE '%victoza%'
          OR LOWER(concept_name) LIKE '%dulaglutide%'
          OR LOWER(concept_name) LIKE '%trulicity%'
          OR LOWER(concept_name) LIKE '%exenatide%'
          OR LOWER(concept_name) LIKE '%byetta%'
          OR LOWER(concept_name) LIKE '%bydureon%'
          OR LOWER(concept_name) LIKE '%tirzepatide%'
          OR LOWER(concept_name) LIKE '%mounjaro%'
      )
),

t2dm_med_patients AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN t2dm_drug_concepts dc
      ON de.drug_concept_id = dc.concept_id
),

diabetes_lab_concepts AS (
    SELECT concept_id, concept_name
    FROM public.concept
    WHERE domain_id = 'Measurement'
      AND (
          LOWER(concept_name) LIKE '%hemoglobin a1c%'
          OR LOWER(concept_name) LIKE '%hba1c%'
          OR LOWER(concept_name) LIKE '%glucose%fasting%'
          OR LOWER(concept_name) LIKE '%fasting glucose%'
          OR LOWER(concept_name) LIKE '%glucose%random%'
          OR LOWER(concept_name) LIKE '%oral glucose tolerance%'
          OR LOWER(concept_name) LIKE '%glucose tolerance%'
      )
),

t2dm_lab_patients AS (
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN diabetes_lab_concepts lc
      ON m.measurement_concept_id = lc.concept_id
    WHERE m.value_as_number IS NOT NULL
      AND (
          (
              (
                  LOWER(lc.concept_name) LIKE '%hemoglobin a1c%'
                  OR LOWER(lc.concept_name) LIKE '%hba1c%'
              )
              AND m.value_as_number >= 6.5
          )
          OR
          (
              (
                  LOWER(lc.concept_name) LIKE '%fasting glucose%'
                  OR LOWER(lc.concept_name) LIKE '%glucose%fasting%'
              )
              AND m.value_as_number >= 126
          )
          OR
          (
              (
                  LOWER(lc.concept_name) LIKE '%random%'
                  OR LOWER(lc.concept_name) LIKE '%oral glucose tolerance%'
                  OR LOWER(lc.concept_name) LIKE '%glucose tolerance%'
              )
              AND m.value_as_number >= 200
          )
      )
),

candidate_patients AS (
    SELECT person_id, 'Diagnosis' AS evidence_type
    FROM t2dm_dx_patients

    UNION ALL

    SELECT person_id, 'Medication' AS evidence_type
    FROM t2dm_med_patients

    UNION ALL

    SELECT person_id, 'Laboratory' AS evidence_type
    FROM t2dm_lab_patients
),

evidence_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT evidence_type) AS evidence_count,
        MAX(CASE WHEN evidence_type = 'Diagnosis' THEN 1 ELSE 0 END) AS has_t2dm_diagnosis,
        MAX(CASE WHEN evidence_type = 'Medication' THEN 1 ELSE 0 END) AS has_t2dm_medication,
        MAX(CASE WHEN evidence_type = 'Laboratory' THEN 1 ELSE 0 END) AS has_diabetes_lab
    FROM candidate_patients
    GROUP BY person_id
)

SELECT DISTINCT
    p.person_id,
    es.has_t2dm_diagnosis,
    es.has_t2dm_medication,
    es.has_diabetes_lab,
    es.evidence_count
FROM public.person p
JOIN evidence_summary es
  ON p.person_id = es.person_id
LEFT JOIN excluded_patients ex
  ON p.person_id = ex.person_id
WHERE
    (
        es.has_t2dm_diagnosis = 1
        OR (
            es.has_t2dm_medication = 1
            AND es.has_diabetes_lab = 1
        )
        OR es.evidence_count >= 2
    )
    AND ex.person_id IS NULL;