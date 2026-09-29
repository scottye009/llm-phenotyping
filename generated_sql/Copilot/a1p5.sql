
WITH

-- 1. Concept sets --------------------------------------------------------

-- Type 2 diabetes diagnosis concepts (standard condition_concept_id)
t2dm_concepts AS (
    SELECT DISTINCT c.concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Condition'
      AND c.standard_concept = 'S'
      AND c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (
            -- ICD-9-CM 250.x0, 250.x2
            (c.vocabulary_id = 'ICD9CM'
             AND c.concept_code LIKE '250.%'
             AND RIGHT(c.concept_code, 1) IN ('0','2'))
         OR -- ICD-10-CM E11.*
            (c.vocabulary_id = 'ICD10CM'
             AND c.concept_code LIKE 'E11%')
      )
),

-- Type 1 diabetes diagnosis concepts
t1dm_concepts AS (
    SELECT DISTINCT c.concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Condition'
      AND c.standard_concept = 'S'
      AND c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (
            -- ICD-9-CM 250.x1, 250.x3
            (c.vocabulary_id = 'ICD9CM'
             AND c.concept_code LIKE '250.%'
             AND RIGHT(c.concept_code, 1) IN ('1','3'))
         OR -- ICD-10-CM E10.*
            (c.vocabulary_id = 'ICD10CM'
             AND c.concept_code LIKE 'E10%')
      )
),

-- Gestational / secondary diabetes concepts
gdm_secondary_concepts AS (
    SELECT DISTINCT c.concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Condition'
      AND c.standard_concept = 'S'
      AND c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (
            -- ICD-9-CM gestational / secondary
            (c.vocabulary_id = 'ICD9CM'
             AND (c.concept_code LIKE '648.0%' OR c.concept_code LIKE '249.%'))
         OR -- ICD-10-CM gestational / secondary
            (c.vocabulary_id = 'ICD10CM'
             AND (c.concept_code LIKE 'O24%' 
                  OR c.concept_code LIKE 'E08%' 
                  OR c.concept_code LIKE 'E09%' 
                  OR c.concept_code LIKE 'E13%'))
      )
),

-- Antidiabetic medication concepts (RxNorm, standard drug_concept_id)
antidiabetic_drug_concepts AS (
    SELECT DISTINCT c.concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Drug'
      AND c.standard_concept = 'S'
      AND c.vocabulary_id = 'RxNorm'
      AND (
            -- Biguanides
            LOWER(c.concept_name) LIKE '%metformin%'
         OR LOWER(c.concept_name) LIKE '%glucophage%'
         OR LOWER(c.concept_name) LIKE '%fortamet%'
         OR LOWER(c.concept_name) LIKE '%glumetza%'
         OR LOWER(c.concept_name) LIKE '%riomet%'

            -- Sulfonylureas
         OR LOWER(c.concept_name) LIKE '%glipizide%'
         OR LOWER(c.concept_name) LIKE '%glucotrol%'
         OR LOWER(c.concept_name) LIKE '%glyburide%'
         OR LOWER(c.concept_name) LIKE '%diabeta%'
         OR LOWER(c.concept_name) LIKE '%micronase%'
         OR LOWER(c.concept_name) LIKE '%glimepiride%'
         OR LOWER(c.concept_name) LIKE '%amaryl%'

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

            -- Thiazolidinediones
         OR LOWER(c.concept_name) LIKE '%pioglitazone%'
         OR LOWER(c.concept_name) LIKE '%actos%'
         OR LOWER(c.concept_name) LIKE '%rosiglitazone%'
         OR LOWER(c.concept_name) LIKE '%avandia%'

            -- Insulins (keep, but interpret carefully)
         OR LOWER(c.concept_name) LIKE '%insulin%'
      )
),

-- HbA1c measurement concepts
hba1c_concepts AS (
    SELECT DISTINCT c.concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Measurement'
      AND c.standard_concept = 'S'
      AND (
            LOWER(c.concept_name) LIKE '%hemoglobin a1c%'
         OR LOWER(c.concept_name) LIKE '%hba1c%'
      )
),

-- Fasting plasma glucose measurement concepts
fpg_concepts AS (
    SELECT DISTINCT c.concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Measurement'
      AND c.standard_concept = 'S'
      AND LOWER(c.concept_name) LIKE '%glucose%'
),

-- 2h OGTT and random glucose could be further refined by concept_name or LOINC codes
ogtt_concepts AS (
    SELECT DISTINCT c.concept_id
    FROM public.concept c
    WHERE c.domain_id = 'Measurement'
      AND c.standard_concept = 'S'
      AND LOWER(c.concept_name) LIKE '%glucose%'
),

-- 2. Raw events ----------------------------------------------------------

t2dm_dx AS (
    SELECT
        co.person_id,
        co.condition_start_date AS event_date
    FROM public.condition_occurrence co
    JOIN t2dm_concepts t2
      ON co.condition_concept_id = t2.concept_id
),

t1dm_dx AS (
    SELECT
        co.person_id,
        co.condition_start_date AS event_date
    FROM public.condition_occurrence co
    JOIN t1dm_concepts t1
      ON co.condition_concept_id = t1.concept_id
),

gdm_secondary_dx AS (
    SELECT
        co.person_id,
        co.condition_start_date AS event_date
    FROM public.condition_occurrence co
    JOIN gdm_secondary_concepts g
      ON co.condition_concept_id = g.concept_id
),

antidiabetic_rx AS (
    SELECT
        de.person_id,
        de.drug_exposure_start_date AS event_date
    FROM public.drug_exposure de
    JOIN antidiabetic_drug_concepts d
      ON de.drug_concept_id = d.concept_id
),

abnormal_hba1c AS (
    SELECT
        m.person_id,
        m.measurement_date AS event_date
    FROM public.measurement m
    JOIN hba1c_concepts h
      ON m.measurement_concept_id = h.concept_id
    WHERE m.value_as_number >= 6.5
),

abnormal_fpg AS (
    SELECT
        m.person_id,
        m.measurement_date AS event_date
    FROM public.measurement m
    JOIN fpg_concepts f
      ON m.measurement_concept_id = f.concept_id
    WHERE m.value_as_number >= 126
      AND LOWER(COALESCE(m.unit_source_value, '')) LIKE '%mg/dl%'
),

abnormal_ogtt AS (
    SELECT
        m.person_id,
        m.measurement_date AS event_date
    FROM public.measurement m
    JOIN ogtt_concepts o
      ON m.measurement_concept_id = o.concept_id
    WHERE m.value_as_number >= 200
      AND LOWER(COALESCE(m.unit_source_value, '')) LIKE '%mg/dl%'
),

all_abnormal_labs AS (
    SELECT * FROM abnormal_hba1c
    UNION ALL
    SELECT * FROM abnormal_fpg
    UNION ALL
    SELECT * FROM abnormal_ogtt
),

-- 3. Aggregated criteria -------------------------------------------------

t2dm_dx_agg AS (
    SELECT
        person_id,
        MIN(event_date) AS first_t2dm_dx_date,
        COUNT(DISTINCT event_date) AS distinct_t2dm_dx_dates
    FROM t2dm_dx
    GROUP BY person_id
),

t1dm_dx_agg AS (
    SELECT
        person_id,
        MIN(event_date) AS first_t1dm_dx_date
    FROM t1dm_dx
    GROUP BY person_id
),

gdm_secondary_agg AS (
    SELECT
        person_id,
        MIN(event_date) AS first_gdm_secondary_date
    FROM gdm_secondary_dx
    GROUP BY person_id
),

antidiabetic_rx_agg AS (
    SELECT
        person_id,
        MIN(event_date) AS first_rx_date,
        COUNT(DISTINCT event_date) AS distinct_rx_dates
    FROM antidiabetic_rx
    GROUP BY person_id
),

abnormal_labs_agg AS (
    SELECT
        person_id,
        MIN(event_date) AS first_abnormal_lab_date,
        COUNT(DISTINCT event_date) AS distinct_abnormal_lab_dates
    FROM all_abnormal_labs
    GROUP BY person_id
),

-- 4. Combine criteria into phenotype logic -------------------------------

candidate_cases AS (
    SELECT
        p.person_id,

        -- Bring in all components
        t2.first_t2dm_dx_date,
        t2.distinct_t2dm_dx_dates,
        rx.first_rx_date,
        rx.distinct_rx_dates,
        lab.first_abnormal_lab_date,
        lab.distinct_abnormal_lab_dates,
        t1.first_t1dm_dx_date,
        gdm.first_gdm_secondary_date
    FROM public.person p
    LEFT JOIN t2dm_dx_agg t2
        ON p.person_id = t2.person_id
    LEFT JOIN antidiabetic_rx_agg rx
        ON p.person_id = rx.person_id
    LEFT JOIN abnormal_labs_agg lab
        ON p.person_id = lab.person_id
    LEFT JOIN t1dm_dx_agg t1
        ON p.person_id = t1.person_id
    LEFT JOIN gdm_secondary_agg gdm
        ON p.person_id = gdm.person_id
),

-- Determine index date based on first qualifying event
candidate_with_index AS (
    SELECT
        c.*,
        LEAST(
            COALESCE(first_t2dm_dx_date, '9999-12-31'),
            COALESCE(first_rx_date, '9999-12-31'),
            COALESCE(first_abnormal_lab_date, '9999-12-31')
        ) AS index_date
    FROM candidate_cases c
),

-- 5. Apply logical rules (AND / OR / NOT) --------------------------------

phenotype_logic AS (
    SELECT
        c.person_id,
        c.index_date,

        -- Core inclusion criteria
        (
            -- T2DM diagnosis criterion:
            (c.distinct_t2dm_dx_dates >= 2)

            OR

            -- Diagnosis + medication:
            (
                c.distinct_t2dm_dx_dates >= 1
                AND c.distinct_rx_dates >= 1
            )

            OR

            -- Medication-only criterion:
            (c.distinct_rx_dates >= 2)

            OR

            -- Lab-based criterion:
            (c.distinct_abnormal_lab_dates >= 2)

            OR

            -- Lab + diagnosis:
            (
                c.distinct_abnormal_lab_dates >= 1
                AND c.distinct_t2dm_dx_dates >= 1
            )
        ) AS inclusion_flag,

        -- Exclusion flags
        (c.first_t1dm_dx_date IS NOT NULL
         AND c.first_t1dm_dx_date <= c.index_date) AS has_t1dm_on_or_before_index,

        (c.first_gdm_secondary_date IS NOT NULL
         AND c.first_gdm_secondary_date <= c.index_date) AS has_gdm_secondary_on_or_before_index
    FROM candidate_with_index c
),

-- 6. Observation period constraint ---------------------------------------

phenotype_with_observation AS (
    SELECT
        pl.person_id,
        pl.index_date,
        pl.inclusion_flag,
        pl.has_t1dm_on_or_before_index,
        pl.has_gdm_secondary_on_or_before_index,
        op.observation_period_start_date,
        op.observation_period_end_date
    FROM phenotype_logic pl
    JOIN public.observation_period op
      ON pl.person_id = op.person_id
     AND pl.index_date BETWEEN op.observation_period_start_date
                           AND op.observation_period_end_date
)

-- 7. Final T2DM cohort ---------------------------------------------------

SELECT DISTINCT
    person_id,
    index_date
FROM phenotype_with_observation
WHERE
    -- Inclusion:
    inclusion_flag = TRUE

    AND

    -- Exclusions:
    NOT has_t1dm_on_or_before_index
    AND NOT has_gdm_secondary_on_or_before_index
;

