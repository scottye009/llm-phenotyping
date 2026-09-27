WITH t2dm_icd_source AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD9CM'
      AND concept_code IN (
          '25000','25002',
          '25010','25012',
          '25020','25022',
          '25030','25032',
          '25040','25042',
          '25050','25052',
          '25060','25062',
          '25070','25072',
          '25080','25082',
          '25090','25092'
      )

    UNION

    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD10CM'
      AND (
          concept_code = 'E11'
          OR concept_code LIKE 'E11%'
      )
),

t2dm_standard_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM t2dm_icd_source s
    JOIN public.concept_relationship cr
      ON s.concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'

    UNION

    SELECT concept_id
    FROM t2dm_icd_source
),

t2dm_diagnosis AS (
    SELECT DISTINCT
        co.person_id,
        MIN(co.condition_start_date) AS first_t2dm_diagnosis_date,
        COUNT(*) AS t2dm_diagnosis_count
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (
        SELECT concept_id FROM t2dm_standard_concepts
    )
    GROUP BY co.person_id
),

diabetes_med_ancestor AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id IN ('RxNorm', 'RxNorm Extension')
      AND LOWER(concept_name) IN (
          -- generic names
          'metformin',
          'glipizide',
          'glyburide',
          'glimepiride',
          'pioglitazone',
          'rosiglitazone',
          'sitagliptin',
          'saxagliptin',
          'linagliptin',
          'alogliptin',
          'empagliflozin',
          'canagliflozin',
          'dapagliflozin',
          'ertugliflozin',
          'liraglutide',
          'semaglutide',
          'dulaglutide',
          'exenatide',
          'tirzepatide',
          'acarbose',
          'miglitol',
          'repaglinide',
          'nateglinide',
          'insulin glargine',
          'insulin detemir',
          'insulin degludec',
          'insulin lispro',
          'insulin aspart',
          'insulin regular human',

          -- common brand names
          'glucophage',
          'glucotrol',
          'diabeta',
          'amaryl',
          'actos',
          'avandia',
          'januvia',
          'onglyza',
          'tradjenta',
          'nesina',
          'jardiance',
          'invokana',
          'farxiga',
          'steglatro',
          'victoza',
          'ozempic',
          'rybelsus',
          'trulicity',
          'byetta',
          'bydureon',
          'mounjaro',
          'precose',
          'glyset',
          'prandin',
          'starlix',
          'lantus',
          'levemir',
          'tresiba',
          'humalog',
          'novolog',
          'novolin',
          'humulin'
      )
),

diabetes_med_concepts AS (
    SELECT DISTINCT ca.descendant_concept_id AS concept_id
    FROM public.concept_ancestor ca
    JOIN diabetes_med_ancestor a
      ON ca.ancestor_concept_id = a.concept_id

    UNION

    SELECT concept_id
    FROM diabetes_med_ancestor
),

diabetes_medication AS (
    SELECT DISTINCT
        de.person_id,
        MIN(de.drug_exposure_start_date) AS first_diabetes_med_date,
        COUNT(*) AS diabetes_med_count
    FROM public.drug_exposure de
    WHERE de.drug_concept_id IN (
        SELECT concept_id FROM diabetes_med_concepts
    )
    GROUP BY de.person_id
),

a1c_concepts AS (
    SELECT concept_id
    FROM public.concept
    WHERE domain_id = 'Measurement'
      AND (
          LOWER(concept_name) LIKE '%hemoglobin a1c%'
          OR LOWER(concept_name) LIKE '%hba1c%'
      )
),

glucose_concepts AS (
    SELECT concept_id
    FROM public.concept
    WHERE domain_id = 'Measurement'
      AND LOWER(concept_name) LIKE '%glucose%'
),

abnormal_labs AS (
    SELECT DISTINCT
        m.person_id,
        MIN(m.measurement_date) AS first_abnormal_lab_date,
        COUNT(*) AS abnormal_lab_count
    FROM public.measurement m
    WHERE m.value_as_number IS NOT NULL
      AND (
          (
              m.measurement_concept_id IN (
                  SELECT concept_id FROM a1c_concepts
              )
              AND m.value_as_number >= 6.5
          )
          OR
          (
              m.measurement_concept_id IN (
                  SELECT concept_id FROM glucose_concepts
              )
              AND m.value_as_number >= 126
          )
      )
    GROUP BY m.person_id
),

exclusion_icd_source AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD9CM'
      AND (
          concept_code LIKE '250_1'
          OR concept_code LIKE '250_3'
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

exclusion_standard_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM exclusion_icd_source s
    JOIN public.concept_relationship cr
      ON s.concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'

    UNION

    SELECT concept_id
    FROM exclusion_icd_source
),

exclusions AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (
        SELECT concept_id FROM exclusion_standard_concepts
    )
),

candidate_t2dm AS (
    SELECT
        p.person_id,
        d.first_t2dm_diagnosis_date,
        d.t2dm_diagnosis_count,
        med.first_diabetes_med_date,
        med.diabetes_med_count,
        lab.first_abnormal_lab_date,
        lab.abnormal_lab_count
    FROM public.person p
    LEFT JOIN t2dm_diagnosis d
      ON p.person_id = d.person_id
    LEFT JOIN diabetes_medication med
      ON p.person_id = med.person_id
    LEFT JOIN abnormal_labs lab
      ON p.person_id = lab.person_id
    WHERE
        (
            d.t2dm_diagnosis_count >= 1

            OR (
                med.diabetes_med_count >= 1
                AND lab.abnormal_lab_count >= 1
            )

            OR (
                d.t2dm_diagnosis_count >= 1
                AND med.diabetes_med_count >= 1
            )
        )
        AND NOT EXISTS (
            SELECT 1
            FROM exclusions e
            WHERE e.person_id = p.person_id
        )
)

SELECT DISTINCT
    person_id,
    LEAST(
        COALESCE(first_t2dm_diagnosis_date, DATE '9999-12-31'),
        COALESCE(first_diabetes_med_date, DATE '9999-12-31'),
        COALESCE(first_abnormal_lab_date, DATE '9999-12-31')
    ) AS index_date,
    t2dm_diagnosis_count,
    diabetes_med_count,
    abnormal_lab_count
FROM candidate_t2dm;