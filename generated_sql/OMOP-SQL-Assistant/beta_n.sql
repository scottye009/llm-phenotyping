SELECT
    c.person_id,
    MIN(c.index_date) AS index_date
FROM
(
    /* Pathway A: >=2 T2DM diagnosis dates (confirmed T2) */
    SELECT
        co.person_id,
        MIN(co.condition_start_date) AS index_date
    FROM public.condition_occurrence co
    WHERE co.condition_source_concept_id IN
    (
        SELECT c.concept_id
        FROM public.concept c
        WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
          AND (
                /* ICD-10-CM: E11.* */
                (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E11%')
             OR /* ICD-9-CM: 250.x0 or 250.x2 */
                (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~ '^250\\.[0-9][02]$')
          )
    )
    GROUP BY co.person_id
    HAVING COUNT(DISTINCT co.condition_start_date) >= 2

    UNION

    /* Pathway B: >=1 T2DM dx AND >=1 non-insulin antidiabetic drug */
    SELECT
        d.person_id,
        LEAST(MIN(d.condition_start_date), MIN(rx.drug_exposure_start_date)) AS index_date
    FROM public.condition_occurrence d
    JOIN public.drug_exposure rx
      ON rx.person_id = d.person_id
    WHERE d.condition_source_concept_id IN
    (
        SELECT c.concept_id
        FROM public.concept c
        WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
          AND (
                (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E11%')
             OR (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~ '^250\\.[0-9][02]$')
          )
    )
      AND rx.drug_concept_id IN
    (
        SELECT DISTINCT ca.descendant_concept_id
        FROM public.concept_ancestor ca
        WHERE ca.ancestor_concept_id IN
        (
            /* Non-insulin antidiabetic ingredients */
            SELECT concept_id
            FROM public.concept
            WHERE vocabulary_id IN ('RxNorm','RxNorm Extension')
              AND concept_class_id = 'Ingredient'
              AND concept_name IN (
                    /* Biguanide */
                    'metformin',
                    /* Sulfonylureas */
                    'glipizide','glyburide','glimepiride','tolbutamide','chlorpropamide',
                    /* Thiazolidinediones */
                    'pioglitazone','rosiglitazone',
                    /* DPP-4 inhibitors */
                    'sitagliptin','saxagliptin','linagliptin','alogliptin',
                    /* GLP-1 receptor agonists */
                    'liraglutide','semaglutide','dulaglutide','exenatide','lixisenatide',
                    /* SGLT2 inhibitors */
                    'canagliflozin','dapagliflozin','empagliflozin','ertugliflozin',
                    /* Other non-insulin agents */
                    'acarbose','miglitol','pramlintide','repaglinide','nateglinide'
              )
            UNION
            /* Non-insulin antidiabetic brand names */
            SELECT concept_id
            FROM public.concept
            WHERE vocabulary_id IN ('RxNorm','RxNorm Extension')
              AND concept_class_id = 'Brand Name'
              AND concept_name IN (
                    /* metformin brands */
                    'Glucophage','Glucophage XR','Fortamet','Glumetza','Riomet',
                    /* sulfonylurea brands */
                    'Glucotrol','Glucotrol XL','Diabeta','Micronase','Glynase','Amaryl',
                    /* TZD brands */
                    'Actos','Avandia',
                    /* DPP-4 brands */
                    'Januvia','Onglyza','Tradjenta','Nesina',
                    /* GLP-1 brands */
                    'Victoza','Ozempic','Rybelsus','Trulicity','Byetta','Bydureon','Adlyxin',
                    /* SGLT2 brands */
                    'Invokana','Farxiga','Jardiance','Steglatro',
                    /* Other brands (if present) */
                    'Starlix','Precose','Glyset','Prandin'
              )
        )
    )
    GROUP BY d.person_id

    UNION

    /* Pathway C: >=1 T2DM dx AND >=1 diabetes-range lab */
    SELECT
        d.person_id,
        LEAST(MIN(d.condition_start_date), MIN(m.measurement_date)) AS index_date
    FROM public.condition_occurrence d
    JOIN public.measurement m
      ON m.person_id = d.person_id
    WHERE d.condition_source_concept_id IN
    (
        SELECT c.concept_id
        FROM public.concept c
        WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
          AND (
                (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E11%')
             OR (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~ '^250\\.[0-9][02]$')
          )
    )
      AND
    (
        /* A1c >= 6.5% */
        (
            m.measurement_concept_id IN
            (
                SELECT concept_id
                FROM public.concept
                WHERE vocabulary_id = 'LOINC'
                  AND concept_code IN ('4548-4','17856-6','41995-2')
            )
            AND m.value_as_number IS NOT NULL
            AND m.value_as_number >= 6.5
        )
        OR
        /* Glucose in diabetes range: >=200 mg/dL (random/2hr) or >=126 mg/dL (fasting, best-effort) */
        (
            m.measurement_concept_id IN
            (
                SELECT concept_id
                FROM public.concept
                WHERE vocabulary_id = 'LOINC'
                  AND concept_code IN ('1558-6','2345-7','2339-0')
            )
            AND m.value_as_number IS NOT NULL
            AND m.value_as_number >= 126
        )
    )
    GROUP BY d.person_id

    UNION

    /* Pathway D: >=2 diabetes-range labs on different dates */
    SELECT
        m.person_id,
        MIN(m.measurement_date) AS index_date
    FROM public.measurement m
    WHERE
    (
        /* A1c >= 6.5% */
        (
            m.measurement_concept_id IN
            (
                SELECT concept_id
                FROM public.concept
                WHERE vocabulary_id = 'LOINC'
                  AND concept_code IN ('4548-4','17856-6','41995-2')
            )
            AND m.value_as_number IS NOT NULL
            AND m.value_as_number >= 6.5
        )
        OR
        /* Glucose in diabetes range */
        (
            m.measurement_concept_id IN
            (
                SELECT concept_id
                FROM public.concept
                WHERE vocabulary_id = 'LOINC'
                  AND concept_code IN ('1558-6','2345-7','2339-0')
            )
            AND m.value_as_number IS NOT NULL
            AND m.value_as_number >= 126
        )
    )
    GROUP BY m.person_id
    HAVING COUNT(DISTINCT m.measurement_date) >= 2
) c
WHERE
    /* Exclude gestational diabetes */
    NOT EXISTS
    (
        SELECT 1
        FROM public.condition_occurrence g
        WHERE g.person_id = c.person_id
          AND g.condition_source_concept_id IN
          (
              SELECT concept_id
              FROM public.concept
              WHERE vocabulary_id IN ('ICD9CM','ICD10CM')
                AND (
                      (vocabulary_id = 'ICD9CM' AND concept_code LIKE '6488%')
                   OR (vocabulary_id = 'ICD10CM' AND (concept_code LIKE 'O244%' OR concept_code LIKE 'O249%'))
                )
          )
    )
    AND
    /* Exclude secondary diabetes */
    NOT EXISTS
    (
        SELECT 1
        FROM public.condition_occurrence s
        WHERE s.person_id = c.person_id
          AND s.condition_source_concept_id IN
          (
              SELECT concept_id
              FROM public.concept
              WHERE vocabulary_id IN ('ICD9CM','ICD10CM')
                AND (
                      (vocabulary_id = 'IC10CM' AND (concept_code LIKE 'E08%' OR concept_code LIKE 'E09%' OR concept_code LIKE 'E13%'))
                   OR (vocabulary_id = 'ICD9CM' AND concept_code LIKE '249%')
                )
          )
    )
    AND
    /* Exclude Type 1 DM ONLY if no strong T2 evidence (no T2 dx, no non-insulin meds, no diabetes-range labs) */
    NOT EXISTS
    (
        SELECT 1
        FROM public.condition_occurrence t1
        WHERE t1.person_id = c.person_id
          AND t1.condition_source_concept_id IN
          (
              SELECT concept_id
              FROM public.concept
              WHERE vocabulary_id IN ('ICD9CM','ICD10CM')
                AND (
                      (vocabulary_id = 'ICD10CM' AND concept_code LIKE 'E10%')
                   OR (vocabulary_id = 'ICD9CM' AND concept_code ~ '^250\\.[0-9][13]$')
                )
          )
          AND NOT EXISTS
          (
              /* Strong T2 evidence: any T2 dx */
              SELECT 1
              FROM public.condition_occurrence t2
              WHERE t2.person_id = t1.person_id
                AND t2.condition_source_concept_id IN
                (
                    SELECT concept_id
                    FROM public.concept
                    WHERE vocabulary_id IN ('ICD9CM','ICD10CM')
                      AND (
                            (vocabulary_id = 'ICD10CM' AND concept_code LIKE 'E11%')
                         OR (vocabulary_id = 'ICD9CM' AND concept_code ~ '^250\\.[0-9][02]$')
                      )
                )
          )
          AND NOT EXISTS
          (
              /* Strong T2 evidence: any non-insulin antidiabetic exposure */
              SELECT 1
              FROM public.drug_exposure de
              WHERE de.person_id = t1.person_id
                AND de.drug_concept_id IN
                (
                    SELECT DISTINCT ca.descendant_concept_id
                    FROM public.concept_ancestor ca
                    WHERE ca.ancestor_concept_id IN
                    (
                        SELECT concept_id
                        FROM public.concept
                        WHERE vocabulary_id IN ('RxNorm','RxNorm Extension')
                          AND concept_class_id = 'Ingredient'
                          AND concept_name IN (
                                'metformin','glipizide','glyburide','glimepiride','tolbutamide','chlorpropamide',
                                'pioglitazone','rosiglitazone',
                                'sitagliptin','saxagliptin','linagliptin','alogliptin',
                                'liraglutide','semaglutide','dulaglutide','exenatide','lixisenatide',
                                'canagliflozin','dapagliflozin','empagliflozin','ertugliflozin',
                                'acarbose','miglitol','pramlintide','repaglinide','nateglinide'
                          )
                        UNION
                        SELECT concept_id
                        FROM public.concept
                        WHERE vocabulary_id IN ('RxNorm','RxNorm Extension')
                          AND concept_class_id = 'Brand Name'
                          AND concept_name IN (
                                'Glucophage','Glucophage XR','Fortamet','Glumetza','Riomet',
                                'Glucotrol','Glucotrol XL','Diabeta','Micronase','Glynase','Amaryl',
                                'Actos','Avandia',
                                'Januvia','Onglyza','Tradjenta','Nesina',
                                'Victoza','Ozempic','Rybelsus','Trulicity','Byetta','Bydureon','Adlyxin',
                                'Invokana','Farxiga','Jardiance','Steglatro',
                                'Starlix','Precose','Glyset','Prandin'
                          )
                    )
                )
          )
          AND NOT EXISTS
          (
              /* Strong T2 evidence: any diabetes-range lab */
              SELECT 1
              FROM public.measurement m2
              WHERE m2.person_id = t1.person_id
                AND
                (
                    (
                        m2.measurement_concept_id IN
                        (
                            SELECT concept_id
                            FROM public.concept
                            WHERE vocabulary_id = 'LOINC'
                              AND concept_code IN ('4548-4','17856-6','41995-2')
                        )
                        AND m2.value_as_number IS NOT NULL
                        AND m2.value_as_number >= 6.5
                    )
                    OR
                    (
                        m2.measurement_concept_id IN
                        (
                            SELECT concept_id
                            FROM public.concept
                            WHERE vocabulary_id = 'LOINC'
                              AND concept_code IN ('1558-6','2345-7','2339-0')
                        )
                        AND m2.value_as_number IS NOT NULL
                        AND m2.value_as_number >= 126
                    )
                )
          )
    )
GROUP BY c.person_id
ORDER BY c.person_id;


