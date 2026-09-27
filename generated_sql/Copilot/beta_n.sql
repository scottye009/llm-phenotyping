SELECT
    x.person_id,
    x.index_date,
    x.age_at_index
FROM (
    SELECT
        p.person_id,

        -- First T2DM diagnosis date
        t2dx.first_t2dm_dx_date,
        t2dx.t2dm_dx_count,

        -- First T2DM medication date
        t2med.first_t2dm_med_date,
        t2med.t2dm_med_count,

        -- First abnormal diabetes lab date
        labs.first_abnl_lab_date,
        labs.abnl_lab_count,

        -- Exclusion flags
        t1dx.has_t1dm,
        gsdm.has_gest_dm,
        sdm.has_secondary_dm,

        -- Index date = earliest of dx / med / lab
        LEAST(
            COALESCE(t2dx.first_t2dm_dx_date, DATE '9999-12-31'),
            COALESCE(t2med.first_t2dm_med_date, DATE '9999-12-31'),
            COALESCE(labs.first_abnl_lab_date, DATE '9999-12-31')
        ) AS index_date,

        -- Age at index (birthday-aware)
        DATE_PART(
            'year',
            LEAST(
                COALESCE(t2dx.first_t2dm_dx_date, DATE '9999-12-31'),
                COALESCE(t2med.first_t2dm_med_date, DATE '9999-12-31'),
                COALESCE(labs.first_abnl_lab_date, DATE '9999-12-31')
            )
        )
        - DATE_PART('year', p.birth_datetime)
        - CASE
            WHEN TO_CHAR(
                     LEAST(
                         COALESCE(t2dx.first_t2dm_dx_date, DATE '9999-12-31'),
                         COALESCE(t2med.first_t2dm_med_date, DATE '9999-12-31'),
                         COALESCE(labs.first_abnl_lab_date, DATE '9999-12-31')
                     ),
                     'MMDD'
                 )
                 < TO_CHAR(p.birth_datetime, 'MMDD')
            THEN 1
            ELSE 0
          END AS age_at_index

    FROM public.person p

    -- T2DM diagnoses (ICD9CM 250.x0/250.x2; ICD10CM E11%)
    LEFT JOIN (
        SELECT
            co.person_id,
            COUNT(DISTINCT co.condition_start_date) AS t2dm_dx_count,
            MIN(co.condition_start_date) AS first_t2dm_dx_date
        FROM public.condition_occurrence co
        JOIN public.concept c
          ON co.condition_source_concept_id = c.concept_id
        WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
          AND (
                (
                    c.vocabulary_id = 'ICD9CM'
                    AND c.concept_code LIKE '250.%'
                    AND RIGHT(c.concept_code, 1) IN ('0','2')
                )
                OR (
                    c.vocabulary_id = 'ICD10CM'
                    AND c.concept_code LIKE 'E11%'
                )
              )
        GROUP BY co.person_id
    ) t2dx
      ON p.person_id = t2dx.person_id

    -- T1DM diagnoses (exclusion: ICD9CM 250.x1/250.x3; ICD10CM E10%)
    LEFT JOIN (
        SELECT DISTINCT
            co.person_id,
            1 AS has_t1dm
        FROM public.condition_occurrence co
        JOIN public.concept c
          ON co.condition_source_concept_id = c.concept_id
        WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
          AND (
                (
                    c.vocabulary_id = 'ICD9CM'
                    AND c.concept_code LIKE '250.%'
                    AND RIGHT(c.concept_code, 1) IN ('1','3')
                )
                OR (
                    c.vocabulary_id = 'ICD10CM'
                    AND c.concept_code LIKE 'E10%'
                )
              )
    ) t1dx
      ON p.person_id = t1dx.person_id

    -- Gestational diabetes diagnoses (exclusion)
    LEFT JOIN (
        SELECT DISTINCT
            co.person_id,
            1 AS has_gest_dm
        FROM public.condition_occurrence co
        JOIN public.concept c
          ON co.condition_source_concept_id = c.concept_id
        WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
          AND (
                (
                    c.vocabulary_id = 'ICD9CM'
                    AND c.concept_code LIKE '648.8%'
                )
                OR (
                    c.vocabulary_id = 'IC9CM'
                    AND c.concept_code LIKE '648.0%'
                )
                OR (
                    c.vocabulary_id = 'ICD10CM'
                    AND c.concept_code LIKE 'O24.4%'
                )
                OR (
                    c.vocabulary_id = 'ICD10CM'
                    AND c.concept_code LIKE 'O24.9%'
                )
              )
    ) gsdm
      ON p.person_id = gsdm.person_id

    -- Secondary diabetes diagnoses (exclusion)
    LEFT JOIN (
        SELECT DISTINCT
            co.person_id,
            1 AS has_secondary_dm
        FROM public.condition_occurrence co
        JOIN public.concept c
          ON co.condition_source_concept_id = c.concept_id
        WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
          AND (
                (
                    c.vocabulary_id = 'ICD9CM'
                    AND c.concept_code LIKE '249.%'
                )
                OR (
                    c.vocabulary_id = 'ICD10CM'
                    AND (
                        c.concept_code LIKE 'E08%'
                        OR c.concept_code LIKE 'E09%'
                        OR c.concept_code LIKE 'E13%'
                    )
                )
              )
    ) sdm
      ON p.person_id = sdm.person_id

    -- T2DM medications (RxNorm, generic + brand)
    LEFT JOIN (
        SELECT
            de.person_id,
            COUNT(DISTINCT de.drug_exposure_start_date) AS t2dm_med_count,
            MIN(de.drug_exposure_start_date) AS first_t2dm_med_date
        FROM public.drug_exposure de
        JOIN public.concept c
          ON de.drug_concept_id = c.concept_id
        WHERE c.vocabulary_id = 'RxNorm'
          AND (
                -- Biguanides
                LOWER(c.concept_name) LIKE '%metformin%'
                OR LOWER(c.concept_name) LIKE '%glucophage%'
                OR LOWER(c.concept_name) LIKE '%glumetza%'
                OR LOWER(c.concept_name) LIKE '%fortamet%'
                OR LOWER(c.concept_name) LIKE '%riomet%'

                -- Sulfonylureas
                OR LOWER(c.concept_name) LIKE '%glipizide%'
                OR LOWER(c.concept_name) LIKE '%glucotrol%'
                OR LOWER(c.concept_name) LIKE '%glyburide%'
                OR LOWER(c.concept_name) LIKE '%diabeta%'
                OR LOWER(c.concept_name) LIKE '%micronase%'
                OR LOWER(c.concept_name) LIKE '%glynase%'
                OR LOWER(c.concept_name) LIKE '%glimepiride%'
                OR LOWER(c.concept_name) LIKE '%amaryl%'

                -- Thiazolidinediones
                OR LOWER(c.concept_name) LIKE '%pioglitazone%'
                OR LOWER(c.concept_name) LIKE '%actos%'
                OR LOWER(c.concept_name) LIKE '%rosiglitazone%'
                OR LOWER(c.concept_name) LIKE '%avandia%'

                -- DPP-4 inhibitors
                OR LOWER(c.concept_name) LIKE '%sitagliptin%'
                OR LOWER(c.concept_name) LIKE '%januvia%'
                OR LOWER(c.concept_name) LIKE '%saxagliptin%'
                OR LOWER(c.concept_name) LIKE '%onglyza%'
                OR LOWER(c.concept_name) LIKE '%linagliptin%'
                OR LOWER(c.concept_name) LIKE '%tradjenta%'
                OR LOWER(c.concept_name) LIKE '%alogliptin%'
                OR LOWER(c.concept_name) LIKE '%nesina%'

                -- GLP-1 receptor agonists
                OR LOWER(c.concept_name) LIKE '%exenatide%'
                OR LOWER(c.concept_name) LIKE '%byetta%'
                OR LOWER(c.concept_name) LIKE '%bydureon%'
                OR LOWER(c.concept_name) LIKE '%liraglutide%'
                OR LOWER(c.concept_name) LIKE '%victoza%'
                OR LOWER(c.concept_name) LIKE '%dulaglutide%'
                OR LOWER(c.concept_name) LIKE '%trulicity%'
                OR LOWER(c.concept_name) LIKE '%semaglutide%'
                OR LOWER(c.concept_name) LIKE '%ozempic%'
                OR LOWER(c.concept_name) LIKE '%rybelsus%'
                OR LOWER(c.concept_name) LIKE '%lixisenatide%'
                OR LOWER(c.concept_name) LIKE '%adlyxin%'

                -- SGLT2 inhibitors
                OR LOWER(c.concept_name) LIKE '%canagliflozin%'
                OR LOWER(c.concept_name) LIKE '%invokana%'
                OR LOWER(c.concept_name) LIKE '%dapagliflozin%'
                OR LOWER(c.concept_name) LIKE '%farxiga%'
                OR LOWER(c.concept_name) LIKE '%empagliflozin%'
                OR LOWER(c.concept_name) LIKE '%jardiance%'
                OR LOWER(c.concept_name) LIKE '%ertugliflozin%'
                OR LOWER(c.concept_name) LIKE '%steglatro%'

                -- Insulins (supportive; still counted as diabetes meds)
                OR LOWER(c.concept_name) LIKE '%insulin%'
                OR LOWER(c.concept_name) LIKE '%lantus%'
                OR LOWER(c.concept_name) LIKE '%levemir%'
                OR LOWER(c.concept_name) LIKE '%tresiba%'
                OR LOWER(c.concept_name) LIKE '%humalog%'
                OR LOWER(c.concept_name) LIKE '%novolog%'
              )
        GROUP BY de.person_id
    ) t2med
      ON p.person_id = t2med.person_id

    -- Abnormal diabetes labs (HbA1c, fasting glucose, OGTT, random glucose)
    LEFT JOIN (
        SELECT
            m.person_id,
            COUNT(DISTINCT m.measurement_date) AS abnl_lab_count,
            MIN(m.measurement_date) AS first_abnl_lab_date
        FROM public.measurement m
        JOIN public.concept c
          ON m.measurement_concept_id = c.concept_id
        WHERE c.vocabulary_id = 'LOINC'
          AND m.value_as_number IS NOT NULL
          AND (
                -- HbA1c ≥ 6.5%
                (
                    c.concept_code IN ('4548-4','17856-6','41995-2')
                    AND m.value_as_number >= 6.5
                )

                -- Fasting glucose ≥ 126 mg/dL
                OR (
                    c.concept_code IN ('14771-0')
                    AND m.value_as_number >= 126
                )

                -- OGTT ≥ 200 mg/dL
                OR (
                    c.concept_code IN ('20436-2')
                    AND m.value_as_number >= 200
                )

                -- Other serum/plasma glucose (treat as random) ≥ 200 mg/dL
                OR (
                    c.concept_code IN ('1558-6','2345-7')
                    AND m.value_as_number >= 200
                )

                -- Fallback: any glucose LOINC name with high value
                OR (
                    LOWER(c.concept_name) LIKE '%glucose%'
                    AND m.value_as_number >= 200
                )
              )
        GROUP BY m.person_id
    ) labs
      ON p.person_id = labs.person_id

    -- Observation period anchoring: ensure index date is within an observation period
    JOIN public.observation_period op
      ON p.person_id = op.person_id
     AND LEAST(
            COALESCE(t2dx.first_t2dm_dx_date, DATE '9999-12-31'),
            COALESCE(t2med.first_t2dm_med_date, DATE '9999-12-31'),
            COALESCE(labs.first_abnl_lab_date, DATE '9999-12-31')
        )
        BETWEEN op.observation_period_start_date
            AND op.observation_period_end_date
) x
WHERE
    -- Valid index date
    x.index_date < DATE '9999-12-31'

    -- Age ≥ 18 at index
    AND x.age_at_index >= 18

    -- Inclusion logic: DX / MED / LAB combinations
    AND (
        -- ≥2 T2DM diagnosis dates
        (x.t2dm_dx_count >= 2)

        OR

        -- ≥1 T2DM diagnosis + ≥1 T2DM medication
        (x.t2dm_dx_count >= 1 AND x.t2dm_med_count >= 1)

        OR

        -- ≥2 abnormal diabetes labs
        (x.abnl_lab_count >= 2)

        OR

        -- ≥1 abnormal diabetes lab + ≥1 T2DM medication
        (x.abnl_lab_count >= 1 AND x.t2dm_med_count >= 1)
    )

    -- Exclusions: T1DM, gestational, secondary diabetes
    AND x.has_t1dm IS NULL
    AND x.has_gest_dm IS NULL
    AND x.has_secondary_dm IS NULL;


