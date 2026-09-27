WITH
/* -----------------------------
   1) ICD9CM / ICD10CM source concepts for T2DM diagnosis
   ----------------------------- */
t2dm_icd_source_concepts AS (
    SELECT
        c.concept_id AS source_concept_id
    FROM public.concept c
    WHERE
        (
            c.vocabulary_id = 'ICD10CM'
            AND c.concept_code LIKE 'E11%'
        )
        OR
        (
            c.vocabulary_id = 'ICD9CM'
            AND c.concept_code ~ '^250\.[0-9][02]$'
        )
),

/* Map ICD source concepts to OMOP standard condition concepts */
t2dm_mapped_condition_concepts AS (
    SELECT DISTINCT
        cr.concept_id_2 AS condition_concept_id
    FROM t2dm_icd_source_concepts s
    JOIN public.concept_relationship cr
        ON cr.concept_id_1 = s.source_concept_id
       AND cr.relationship_id = 'Maps to'
),

/* Direct T2DM diagnosis evidence */
t2dm_diagnosis AS (
    SELECT
        co.person_id,
        MIN(co.condition_start_date) AS first_t2dm_dx_date
    FROM public.condition_occurrence co
    JOIN t2dm_mapped_condition_concepts t2
        ON co.condition_concept_id = t2.condition_concept_id
    GROUP BY co.person_id
),

/* -----------------------------
   2) Exclusion diagnosis concepts
      Type 1, secondary, gestational/pregnancy-related, neonatal diabetes
   ----------------------------- */
exclusion_icd_source_concepts AS (
    SELECT
        c.concept_id AS source_concept_id
    FROM public.concept c
    WHERE
        (
            c.vocabulary_id = 'ICD10CM'
            AND (
                c.concept_code LIKE 'E10%'  -- type 1 diabetes
                OR c.concept_code LIKE 'E08%' -- due to underlying condition
                OR c.concept_code LIKE 'E09%' -- drug/chemical induced
                OR c.concept_code LIKE 'E13%' -- other specified diabetes
                OR c.concept_code LIKE 'O24%' -- pregnancy/gestational diabetes
                OR c.concept_code LIKE 'P70%' -- neonatal glucose disorders
            )
        )
        OR
        (
            c.vocabulary_id = 'ICD9CM'
            AND (
                c.concept_code ~ '^250\.[0-9][13]$' -- type 1-coded diabetes patterns
                OR c.concept_code LIKE '249%'       -- secondary diabetes
                OR c.concept_code LIKE '648.8%'     -- diabetes/abnormal glucose in pregnancy
                OR c.concept_code LIKE '775.1%'     -- neonatal diabetes
            )
        )
),

exclusion_mapped_condition_concepts AS (
    SELECT DISTINCT
        cr.concept_id_2 AS condition_concept_id
    FROM exclusion_icd_source_concepts s
    JOIN public.concept_relationship cr
        ON cr.concept_id_1 = s.source_concept_id
       AND cr.relationship_id = 'Maps to'
),

exclusion_diagnosis AS (
    SELECT
        co.person_id,
        MIN(co.condition_start_date) AS first_exclusion_dx_date
    FROM public.condition_occurrence co
    JOIN exclusion_mapped_condition_concepts ex
        ON co.condition_concept_id = ex.condition_concept_id
    GROUP BY co.person_id
),

/* -----------------------------
   3) Non-insulin diabetes medication evidence
      Generic + common brand names, expanded through concept_ancestor
   ----------------------------- */
t2dm_drug_seed_concepts AS (
    SELECT
        c.concept_id
    FROM public.concept c
    WHERE
        c.domain_id = 'Drug'
        AND (
            c.concept_name ILIKE '%metformin%'
            OR c.concept_name ILIKE '%glucophage%'

            OR c.concept_name ILIKE '%glipizide%'
            OR c.concept_name ILIKE '%glucotrol%'
            OR c.concept_name ILIKE '%glyburide%'
            OR c.concept_name ILIKE '%glibenclamide%'
            OR c.concept_name ILIKE '%diabeta%'
            OR c.concept_name ILIKE '%glynase%'
            OR c.concept_name ILIKE '%glimepiride%'
            OR c.concept_name ILIKE '%amaryl%'

            OR c.concept_name ILIKE '%pioglitazone%'
            OR c.concept_name ILIKE '%actos%'
            OR c.concept_name ILIKE '%rosiglitazone%'
            OR c.concept_name ILIKE '%avandia%'

            OR c.concept_name ILIKE '%sitagliptin%'
            OR c.concept_name ILIKE '%januvia%'
            OR c.concept_name ILIKE '%saxagliptin%'
            OR c.concept_name ILIKE '%onglyza%'
            OR c.concept_name ILIKE '%linagliptin%'
            OR c.concept_name ILIKE '%tradjenta%'
            OR c.concept_name ILIKE '%alogliptin%'
            OR c.concept_name ILIKE '%nesina%'

            OR c.concept_name ILIKE '%exenatide%'
            OR c.concept_name ILIKE '%byetta%'
            OR c.concept_name ILIKE '%bydureon%'
            OR c.concept_name ILIKE '%liraglutide%'
            OR c.concept_name ILIKE '%victoza%'
            OR c.concept_name ILIKE '%dulaglutide%'
            OR c.concept_name ILIKE '%trulicity%'
            OR c.concept_name ILIKE '%semaglutide%'
            OR c.concept_name ILIKE '%ozempic%'
            OR c.concept_name ILIKE '%rybelsus%'
            OR c.concept_name ILIKE '%tirzepatide%'
            OR c.concept_name ILIKE '%mounjaro%'

            OR c.concept_name ILIKE '%canagliflozin%'
            OR c.concept_name ILIKE '%invokana%'
            OR c.concept_name ILIKE '%dapagliflozin%'
            OR c.concept_name ILIKE '%farxiga%'
            OR c.concept_name ILIKE '%empagliflozin%'
            OR c.concept_name ILIKE '%jardiance%'
            OR c.concept_name ILIKE '%ertugliflozin%'
            OR c.concept_name ILIKE '%steglatro%'

            OR c.concept_name ILIKE '%acarbose%'
            OR c.concept_name ILIKE '%precose%'
            OR c.concept_name ILIKE '%miglitol%'
            OR c.concept_name ILIKE '%glyset%'

            OR c.concept_name ILIKE '%repaglinide%'
            OR c.concept_name ILIKE '%prandin%'
            OR c.concept_name ILIKE '%nateglinide%'
            OR c.concept_name ILIKE '%starlix%'
        )
),

t2dm_drug_concepts AS (
    SELECT DISTINCT
        concept_id AS drug_concept_id
    FROM t2dm_drug_seed_concepts

    UNION

    SELECT DISTINCT
        ca.descendant_concept_id AS drug_concept_id
    FROM t2dm_drug_seed_concepts s
    JOIN public.concept_ancestor ca
        ON ca.ancestor_concept_id = s.concept_id
),

t2dm_medication AS (
    SELECT
        de.person_id,
        MIN(de.drug_exposure_start_date) AS first_t2dm_med_date
    FROM public.drug_exposure de
    JOIN t2dm_drug_concepts dc
        ON de.drug_concept_id = dc.drug_concept_id
    GROUP BY de.person_id
),

/* -----------------------------
   4) Diabetic-range lab evidence
      HbA1c >= 6.5%
      fasting glucose >= 126 mg/dL
      random/unspecified glucose >= 200 mg/dL
   ----------------------------- */
hba1c_concepts AS (
    SELECT
        c.concept_id AS measurement_concept_id
    FROM public.concept c
    WHERE
        c.domain_id = 'Measurement'
        AND (
            c.concept_code IN ('4548-4', '17856-6', '59261-8')
            OR c.concept_name ILIKE '%hemoglobin a1c%'
            OR c.concept_name ILIKE '%glycated hemoglobin%'
            OR c.concept_name ILIKE '%hba1c%'
        )
),

glucose_concepts AS (
    SELECT
        c.concept_id AS measurement_concept_id
    FROM public.concept c
    WHERE
        c.domain_id = 'Measurement'
        AND (
            c.concept_code IN (
                '2345-7',  -- glucose
                '1558-6',  -- fasting glucose
                '1557-8',  -- fasting glucose
                '14749-6', -- glucose
                '2339-0'   -- glucose
            )
            OR c.concept_name ILIKE '%glucose%'
        )
),

diabetic_labs AS (
    SELECT
        m.person_id,
        MIN(m.measurement_date) AS first_diabetic_lab_date
    FROM public.measurement m
    WHERE
        m.value_as_number IS NOT NULL
        AND (
            (
                m.measurement_concept_id IN (
                    SELECT measurement_concept_id FROM hba1c_concepts
                )
                AND m.value_as_number >= 6.5
            )
            OR
            (
                m.measurement_concept_id IN (
                    SELECT measurement_concept_id FROM glucose_concepts
                )
                AND m.value_as_number >= 126
                AND (
                    m.measurement_source_value IN ('1558-6', '1557-8')
                    OR m.measurement_source_value ILIKE '%fasting%'
                    OR m.measurement_source_value ILIKE '%fast%'
                )
            )
            OR
            (
                m.measurement_concept_id IN (
                    SELECT measurement_concept_id FROM glucose_concepts
                )
                AND m.value_as_number >= 200
            )
        )
    GROUP BY m.person_id
),

/* -----------------------------
   5) Combine evidence
      Include:
      - direct T2DM diagnosis, OR
      - T2DM medication + diabetic-range lab
      Exclude non-T2DM diabetes phenotypes only when no direct T2DM diagnosis exists.
   ----------------------------- */
candidate_cohort AS (
    SELECT
        p.person_id,
        dx.first_t2dm_dx_date,
        med.first_t2dm_med_date,
        lab.first_diabetic_lab_date,
        ex.first_exclusion_dx_date,
        CASE WHEN dx.person_id IS NOT NULL THEN 1 ELSE 0 END AS has_t2dm_diagnosis,
        CASE WHEN med.person_id IS NOT NULL THEN 1 ELSE 0 END AS has_t2dm_medication,
        CASE WHEN lab.person_id IS NOT NULL THEN 1 ELSE 0 END AS has_diabetic_lab,
        CASE WHEN ex.person_id IS NOT NULL THEN 1 ELSE 0 END AS has_exclusion_diagnosis
    FROM public.person p
    LEFT JOIN t2dm_diagnosis dx
        ON p.person_id = dx.person_id
    LEFT JOIN t2dm_medication med
        ON p.person_id = med.person_id
    LEFT JOIN diabetic_labs lab
        ON p.person_id = lab.person_id
    LEFT JOIN exclusion_diagnosis ex
        ON p.person_id = ex.person_id
)

SELECT
    person_id,
    LEAST(
        COALESCE(first_t2dm_dx_date, DATE '9999-12-31'),
        COALESCE(first_t2dm_med_date, DATE '9999-12-31'),
        COALESCE(first_diabetic_lab_date, DATE '9999-12-31')
    ) AS index_date,
    has_t2dm_diagnosis,
    has_t2dm_medication,
    has_diabetic_lab,
    has_exclusion_diagnosis
FROM candidate_cohort
WHERE
    (
        has_t2dm_diagnosis = 1
        OR (
            has_t2dm_medication = 1
            AND has_diabetic_lab = 1
        )
    )
    AND NOT (
        has_t2dm_diagnosis = 0
        AND has_exclusion_diagnosis = 1
    )
ORDER BY person_id;