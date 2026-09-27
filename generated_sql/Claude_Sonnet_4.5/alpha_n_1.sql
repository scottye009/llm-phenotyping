-- =====================================================
-- TYPE 2 DIABETES PHENOTYPING ALGORITHM
-- Based on OMOP CDM v5.4
-- Schema: public
-- =====================================================

-- Step 1: Identify patients with T2DM diagnosis codes
WITH t2dm_diagnosis AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date,
        co.condition_concept_id,
        c.concept_name,
        'DIAGNOSIS' AS criterion_type
    FROM public.condition_occurrence co
    INNER JOIN public.concept c ON co.condition_concept_id = c.concept_id
    INNER JOIN public.concept_ancestor ca ON co.condition_concept_id = ca.descendant_concept_id
    WHERE (
        -- ICD-10-CM codes for Type 2 Diabetes
        co.condition_source_value LIKE 'E11%'  -- Type 2 diabetes mellitus
        
        -- ICD-9-CM codes for Type 2 Diabetes
        OR co.condition_source_value IN ('250.00', '250.02', '250.10', '250.12', 
                                          '250.20', '250.22', '250.30', '250.32',
                                          '250.40', '250.42', '250.50', '250.52',
                                          '250.60', '250.62', '250.70', '250.72',
                                          '250.80', '250.82', '250.90', '250.92')
        
        -- OMOP Standard Concepts for Type 2 Diabetes
        OR ca.ancestor_concept_id IN (
            201826,   -- Type 2 diabetes mellitus
            443238,   -- Diabetes mellitus type 2 uncontrolled
            443729,   -- Diabetes mellitus type 2 poor control
            442793,   -- Diabetes mellitus type 2 without complication
            40484648  -- Diabetes mellitus type 2 inadequate control
        )
    )
    AND co.condition_start_date IS NOT NULL
),

-- Step 2: Identify patients with T2DM-related laboratory values
t2dm_lab AS (
    SELECT DISTINCT
        m.person_id,
        m.measurement_date,
        m.measurement_concept_id,
        c.concept_name,
        m.value_as_number,
        m.unit_concept_id,
        'LABORATORY' AS criterion_type
    FROM public.measurement m
    INNER JOIN public.concept c ON m.measurement_concept_id = c.concept_id
    WHERE (
        -- HbA1c >= 6.5%
        (m.measurement_concept_id IN (3004410, 3003309, 3005673) -- HbA1c concepts
         AND m.value_as_number >= 6.5)
        
        -- Fasting glucose >= 126 mg/dL
        OR (m.measurement_concept_id IN (3004501, 3000483) -- Fasting glucose
            AND m.value_as_number >= 126
            AND m.unit_concept_id IN (8840, 9028)) -- mg/dL
        
        -- Random/casual glucose >= 200 mg/dL
        OR (m.measurement_concept_id IN (3027018, 3034426, 3051925) -- Glucose
            AND m.value_as_number >= 200
            AND m.unit_concept_id IN (8840, 9028))
    )
    AND m.measurement_date IS NOT NULL
),

-- Step 3: Identify patients with T2DM medications
t2dm_medications AS (
    SELECT DISTINCT
        de.person_id,
        de.drug_exposure_start_date,
        de.drug_concept_id,
        c.concept_name,
        de.drug_source_value,
        'MEDICATION' AS criterion_type
    FROM public.drug_exposure de
    INNER JOIN public.concept c ON de.drug_concept_id = c.concept_id
    INNER JOIN public.concept_ancestor ca ON de.drug_concept_id = ca.descendant_concept_id
    WHERE (
        -- Metformin (generic and brands)
        ca.ancestor_concept_id IN (1503297, 1502809) -- Metformin
        OR de.drug_source_value ILIKE ANY(ARRAY['%metformin%', '%glucophage%', '%fortamet%', '%glumetza%', '%riomet%'])
        
        -- Sulfonylureas
        OR ca.ancestor_concept_id IN (1502826, 1502855, 1502809, 1594973, 1560171)
        OR de.drug_source_value ILIKE ANY(ARRAY['%glyburide%', '%glipizide%', '%glimepiride%', '%diabeta%', '%glucotrol%', '%amaryl%'])
        
        -- DPP-4 Inhibitors
        OR ca.ancestor_concept_id IN (40166035, 40239216, 1580747, 43013884)
        OR de.drug_source_value ILIKE ANY(ARRAY['%sitagliptin%', '%saxagliptin%', '%linagliptin%', '%alogliptin%', '%januvia%', '%onglyza%', '%tradjenta%', '%nesina%'])
        
        -- GLP-1 Agonists
        OR ca.ancestor_concept_id IN (1583722, 40170911, 42479454, 45775487)
        OR de.drug_source_value ILIKE ANY(ARRAY['%exenatide%', '%liraglutide%', '%dulaglutide%', '%semaglutide%', '%byetta%', '%victoza%', '%trulicity%', '%ozempic%', '%rybelsus%'])
        
        -- SGLT2 Inhibitors
        OR ca.ancestor_concept_id IN (43526465, 45775965, 45775372, 45775409)
        OR de.drug_source_value ILIKE ANY(ARRAY['%canagliflozin%', '%dapagliflozin%', '%empagliflozin%', '%ertugliflozin%', '%invokana%', '%farxiga%', '%jardiance%', '%steglatro%'])
        
        -- Thiazolidinediones
        OR ca.ancestor_concept_id IN (1502905, 1547504)
        OR de.drug_source_value ILIKE ANY(ARRAY['%pioglitazone%', '%rosiglitazone%', '%actos%', '%avandia%'])
        
        -- Meglitinides
        OR ca.ancestor_concept_id IN (1516766, 1513102)
        OR de.drug_source_value ILIKE ANY(ARRAY['%repaglinide%', '%nateglinide%', '%prandin%', '%starlix%'])
        
        -- Insulin (basal only, excluding rapid-acting to avoid T1DM)
        OR ca.ancestor_concept_id IN (1550557, 1502905, 1502826) -- Insulin glargine, detemir, NPH
        OR de.drug_source_value ILIKE ANY(ARRAY['%insulin glargine%', '%insulin detemir%', '%insulin nph%', '%lantus%', '%levemir%', '%basaglar%', '%toujeo%', '%tresiba%'])
    )
    AND de.drug_exposure_start_date IS NOT NULL
    -- Exclude if ONLY on insulin without oral agents (potential T1DM)
    AND de.person_id IN (
        SELECT person_id 
        FROM public.drug_exposure de2
        INNER JOIN public.concept_ancestor ca2 ON de2.drug_concept_id = ca2.descendant_concept_id
        WHERE ca2.ancestor_concept_id IN (1503297, 1502826, 40166035, 43526465, 1502905) -- Oral agents
    )
),

-- Step 4: Exclusion - Type 1 Diabetes
exclusion_t1dm AS (
    SELECT DISTINCT
        co.person_id,
        'T1DM_EXCLUSION' AS exclusion_type
    FROM public.condition_occurrence co
    INNER JOIN public.concept_ancestor ca ON co.condition_concept_id = ca.descendant_concept_id
    WHERE (
        -- ICD-10-CM Type 1 Diabetes
        co.condition_source_value LIKE 'E10%'
        
        -- ICD-9-CM Type 1 Diabetes
        OR co.condition_source_value IN ('250.01', '250.03', '250.11', '250.13',
                                          '250.21', '250.23', '250.31', '250.33',
                                          '250.41', '250.43', '250.51', '250.53',
                                          '250.61', '250.63', '250.71', '250.73',
                                          '250.81', '250.83', '250.91', '250.93')
        
        -- OMOP Standard Concepts for Type 1 Diabetes
        OR ca.ancestor_concept_id IN (
            201254,   -- Type 1 diabetes mellitus
            435216,   -- Diabetes mellitus type 1 in obese
            40482883  -- Diabetes mellitus type 1 uncontrolled
        )
    )
),

-- Step 5: Exclusion - Gestational Diabetes
exclusion_gestational AS (
    SELECT DISTINCT
        co.person_id,
        'GESTATIONAL_EXCLUSION' AS exclusion_type
    FROM public.condition_occurrence co
    WHERE (
        -- ICD-10-CM Gestational Diabetes
        co.condition_source_value LIKE 'O24%'
        
        -- ICD-9-CM Gestational Diabetes
        OR co.condition_source_value IN ('648.8', '648.80', '648.81', '648.82', '648.83', '648.84')
        
        -- OMOP Standard Concepts
        OR co.condition_concept_id IN (
            4024659,  -- Gestational diabetes mellitus
            4322821,  -- Pre-existing type 2 diabetes in pregnancy
            4136529   -- Diabetes mellitus in pregnancy
        )
    )
    -- Only exclude if gestational DM occurred within 1 year of earliest T2DM evidence
),

-- Step 6: Exclusion - Secondary Diabetes
exclusion_secondary AS (
    SELECT DISTINCT
        co.person_id,
        'SECONDARY_EXCLUSION' AS exclusion_type
    FROM public.condition_occurrence co
    WHERE (
        -- ICD-10-CM Secondary Diabetes
        co.condition_source_value LIKE 'E08%' OR co.condition_source_value LIKE 'E09%'
        
        -- OMOP Standard Concepts for drug-induced or secondary diabetes
        OR co.condition_concept_id IN (
            4058243,  -- Drug-induced diabetes mellitus
            4096804,  -- Steroid-induced diabetes
            4058243   -- Secondary diabetes mellitus
        )
    )
),

-- Step 7: Combine all T2DM evidence
all_t2dm_evidence AS (
    SELECT person_id, condition_start_date AS event_date, criterion_type FROM t2dm_diagnosis
    UNION ALL
    SELECT person_id, measurement_date AS event_date, criterion_type FROM t2dm_lab
    UNION ALL
    SELECT person_id, drug_exposure_start_date AS event_date, criterion_type FROM t2dm_medications
),

-- Step 8: Calculate evidence strength per person
evidence_summary AS (
    SELECT 
        person_id,
        MIN(event_date) AS first_t2dm_date,
        MAX(event_date) AS last_t2dm_date,
        COUNT(DISTINCT criterion_type) AS num_criterion_types,
        COUNT(DISTINCT event_date) AS num_occurrences,
        STRING_AGG(DISTINCT criterion_type, ', ') AS criterion_types
    FROM all_t2dm_evidence
    GROUP BY person_id
    HAVING COUNT(DISTINCT criterion_type) >= 2  -- At least 2 different types of evidence
       AND COUNT(DISTINCT event_date) >= 2      -- At least 2 separate occurrences
),

-- Step 9: Apply observation period requirement
valid_observation AS (
    SELECT 
        es.*,
        op.observation_period_start_date,
        op.observation_period_end_date,
        EXTRACT(DAY FROM (op.observation_period_end_date - op.observation_period_start_date)) AS obs_days
    FROM evidence_summary es
    INNER JOIN public.observation_period op ON es.person_id = op.person_id
    WHERE es.first_t2dm_date >= op.observation_period_start_date
      AND es.first_t2dm_date <= op.observation_period_end_date
      AND EXTRACT(DAY FROM (op.observation_period_end_date - op.observation_period_start_date)) >= 365  -- At least 1 year observation
),

-- Step 10: Final T2DM Cohort (with exclusions applied)
final_t2dm_cohort AS (
    SELECT 
        vo.person_id,
        vo.first_t2dm_date AS index_date,
        vo.last_t2dm_date,
        vo.num_criterion_types,
        vo.num_occurrences,
        vo.criterion_types,
        vo.obs_days,
        p.gender_concept_id,
        p.year_of_birth,
        EXTRACT(YEAR FROM vo.first_t2dm_date) - p.year_of_birth AS age_at_diagnosis,
        CASE 
            WHEN e1.person_id IS NOT NULL THEN 1 ELSE 0 
        END AS has_t1dm_exclusion,
        CASE 
            WHEN e2.person_id IS NOT NULL THEN 1 ELSE 0 
        END AS has_gestational_exclusion,
        CASE 
            WHEN e3.person_id IS NOT NULL THEN 1 ELSE 0 
        END AS has_secondary_exclusion
    FROM valid_observation vo
    INNER JOIN public.person p ON vo.person_id = p.person_id
    LEFT JOIN exclusion_t1dm e1 ON vo.person_id = e1.person_id
    LEFT JOIN exclusion_gestational e2 ON vo.person_id = e2.person_id
    LEFT JOIN exclusion_secondary e3 ON vo.person_id = e3.person_id
    WHERE e1.person_id IS NULL  -- NOT Type 1 Diabetes
      AND e2.person_id IS NULL  -- NOT Gestational Diabetes
      AND e3.person_id IS NULL  -- NOT Secondary Diabetes
      AND (EXTRACT(YEAR FROM vo.first_t2dm_date) - p.year_of_birth) >= 18  -- Age >= 18 at diagnosis
)

-- Final Output: T2DM Cohort
SELECT 
    person_id,
    index_date,
    last_t2dm_date,
    age_at_diagnosis,
    gender_concept_id,
    num_criterion_types,
    num_occurrences,
    criterion_types,
    obs_days AS observation_days
FROM final_t2dm_cohort
ORDER BY person_id;

-- Optional: Create a persistent cohort table
/*
CREATE TABLE public.cohort AS
SELECT 
    ROW_NUMBER() OVER (ORDER BY person_id) AS cohort_definition_id,
    person_id,
    index_date AS cohort_start_date,
    last_t2dm_date AS cohort_end_date
FROM final_t2dm_cohort;
*/

