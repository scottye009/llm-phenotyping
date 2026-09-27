WITH t2dm_icd_source_concepts AS (
    -- ICD10CM E11 = Type 2 diabetes mellitus
    -- ICD9CM 250.x0 / 250.x2 = type 2 or unspecified type diabetes
    SELECT
        c.concept_id
    FROM public.concept c
    WHERE
        (
            c.vocabulary_id = 'ICD10CM'
            AND c.concept_code ~ '^E11(\.|$)'
        )
        OR (
            c.vocabulary_id = 'ICD9CM'
            AND c.concept_code ~ '^250\.?[0-9][02]$'
        )
),

t2dm_mapped_concepts AS (
    -- Map ICD source concepts to standard OMOP condition concepts
    SELECT DISTINCT
        cr.concept_id_2 AS condition_concept_id
    FROM t2dm_icd_source_concepts src
    JOIN public.concept_relationship cr
        ON src.concept_id = cr.concept_id_1
    WHERE
        cr.relationship_id = 'Maps to'
),

t2dm_diagnosis_evidence AS (
    SELECT
        co.person_id,
        co.condition_start_date AS evidence_date,
        'diagnosis' AS evidence_type
    FROM public.condition_occurrence co
    JOIN t2dm_mapped_concepts t2
        ON co.condition_concept_id = t2.condition_concept_id
    WHERE
        co.condition_start_date IS NOT NULL
),

t2dm_medication_evidence AS (
    -- Non-insulin diabetes medications; insulin alone is not specific enough for T2DM
    SELECT
        de.person_id,
        de.drug_exposure_start_date AS evidence_date,
        'medication' AS evidence_type
    FROM public.drug_exposure de
    JOIN public.concept dc
        ON de.drug_concept_id = dc.concept_id
    WHERE
        de.drug_exposure_start_date IS NOT NULL
        AND (
            dc.concept_name ~* '\m(metformin|glucophage|fortamet|glumetza|riomet)\M'
            OR dc.concept_name ~* '\m(glipizide|glucotrol|glyburide|diabeta|glynase|micronase|glimepiride|amaryl|tolbutamide|chlorpropamide)\M'
            OR dc.concept_name ~* '\m(pioglitazone|actos|rosiglitazone|avandia)\M'
            OR dc.concept_name ~* '\m(sitagliptin|januvia|janumet|linagliptin|tradjenta|saxagliptin|onglyza|alogliptin|nesina)\M'
            OR dc.concept_name ~* '\m(empagliflozin|jardiance|dapagliflozin|farxiga|canagliflozin|invokana|ertugliflozin|steglatro)\M'
            OR dc.concept_name ~* '\m(liraglutide|victoza|semaglutide|ozempic|rybelsus|dulaglutide|trulicity|exenatide|byetta|bydureon|tirzepatide|mounjaro)\M'
            OR dc.concept_name ~* '\m(repaglinide|prandin|nateglinide|starlix)\M'
            OR dc.concept_name ~* '\m(acarbose|precose|miglitol|glyset)\M'
            OR dc.concept_name ~* '\m(pramlintide|symlin)\M'
        )
),

lab_concepts AS (
    SELECT
        c.concept_id,
        c.concept_name,
        c.concept_code
    FROM public.concept c
    WHERE
        c.domain_id = 'Measurement'
),

t2dm_lab_evidence AS (
    SELECT
        m.person_id,
        m.measurement_date AS evidence_date,
        'lab' AS evidence_type
    FROM public.measurement m
    LEFT JOIN lab_concepts lc
        ON m.measurement_concept_id = lc.concept_id
    WHERE
        m.measurement_date IS NOT NULL
        AND m.value_as_number IS NOT NULL
        AND (
            -- HbA1c diagnostic threshold: >= 6.5%
            (
                m.value_as_number >= 6.5
                AND (
                    lc.concept_name ~* '(hemoglobin A1c|HbA1c|glycohemoglobin)'
                    OR m.measurement_source_value IN ('4548-4', '4549-2', '17856-6')
                )
            )

            OR

            -- Fasting plasma/serum glucose threshold: >= 126 mg/dL
            (
                m.value_as_number >= 126
                AND (
                    lc.concept_name ~* '(fasting).*glucose'
                    OR m.measurement_source_value IN ('1558-6', '1556-0')
                )
            )

            OR

            -- Random plasma/serum glucose threshold: >= 200 mg/dL
            (
                m.value_as_number >= 200
                AND (
                    (
                        lc.concept_name ~* 'glucose'
                        AND lc.concept_name !~* 'urine'
                    )
                    OR m.measurement_source_value IN ('2345-7', '14749-6', '14771-0')
                )
            )
        )
),

exclusion_icd_source_concepts AS (
    -- Exclude type 1, gestational, secondary, neonatal, and other specified diabetes
    SELECT
        c.concept_id
    FROM public.concept c
    WHERE
        (
            c.vocabulary_id = 'ICD10CM'
            AND (
                c.concept_code ~ '^E10(\.|$)'      -- Type 1 diabetes
                OR c.concept_code ~ '^O24\.4'     -- Gestational diabetes
                OR c.concept_code ~ '^E08(\.|$)'  -- Diabetes due to underlying condition
                OR c.concept_code ~ '^E09(\.|$)'  -- Drug or chemical induced diabetes
                OR c.concept_code ~ '^E13(\.|$)'  -- Other specified diabetes
                OR c.concept_code ~ '^P70\.2'     -- Neonatal diabetes
            )
        )
        OR (
            c.vocabulary_id = 'ICD9CM'
            AND (
                c.concept_code ~ '^250\.?[0-9][13]$' -- Type 1 diabetes
                OR c.concept_code ~ '^648\.?8'       -- Diabetes mellitus complicating pregnancy
                OR c.concept_code ~ '^249\.?'        -- Secondary diabetes mellitus
                OR c.concept_code ~ '^775\.?1'       -- Neonatal diabetes mellitus
            )
        )
),

exclusion_mapped_concepts AS (
    SELECT DISTINCT
        cr.concept_id_2 AS condition_concept_id
    FROM exclusion_icd_source_concepts src
    JOIN public.concept_relationship cr
        ON src.concept_id = cr.concept_id_1
    WHERE
        cr.relationship_id = 'Maps to'
),

excluded_persons AS (
    SELECT DISTINCT
        co.person_id
    FROM public.condition_occurrence co
    JOIN exclusion_mapped_concepts ex
        ON co.condition_concept_id = ex.condition_concept_id
),

all_t2dm_evidence AS (
    SELECT * FROM t2dm_diagnosis_evidence
    UNION ALL
    SELECT * FROM t2dm_medication_evidence
    UNION ALL
    SELECT * FROM t2dm_lab_evidence
)

SELECT
    e.person_id,
    MIN(e.evidence_date) AS index_date
FROM all_t2dm_evidence e
WHERE
    NOT EXISTS (
        SELECT 1
        FROM excluded_persons ex
        WHERE ex.person_id = e.person_id
    )
GROUP BY
    e.person_id
ORDER BY
    index_date,
    person_id;