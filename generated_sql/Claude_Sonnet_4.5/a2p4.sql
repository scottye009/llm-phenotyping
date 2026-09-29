-- ========================================================================
-- TYPE 2 DIABETES PHENOTYPING ALGORITHM
-- Based on OMOP CDM v5.4
-- Schema: public
-- ========================================================================

-- Step 1: Create a cohort of potential T2DM patients
WITH 

-- A. Patients with T2DM diagnosis codes
t2dm_diagnosis AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date AS index_date,
        'Diagnosis' AS criterion_type
    FROM public.condition_occurrence co
    INNER JOIN public.concept c ON co.condition_concept_id = c.concept_id
    INNER JOIN public.concept_ancestor ca ON c.concept_id = ca.descendant_concept_id
    WHERE ca.ancestor_concept_id IN (
        201826,    -- Type 2 diabetes mellitus (SNOMED)
        443238     -- Diabetes mellitus type 2 (SNOMED)
    )
    OR co.condition_source_value IN (
        -- ICD-9-CM codes
        '250.00', '250.02',  -- Diabetes mellitus without mention of complication, type II or unspecified
        '250.10', '250.12',  -- Diabetes with ketoacidosis, type II
        '250.20', '250.22',  -- Diabetes with hyperosmolarity, type II
        '250.30', '250.32',  -- Diabetes with other coma, type II
        '250.40', '250.42',  -- Diabetes with renal manifestations, type II
        '250.50', '250.52',  -- Diabetes with ophthalmic manifestations, type II
        '250.60', '250.62',  -- Diabetes with neurological manifestations, type II
        '250.70', '250.72',  -- Diabetes with peripheral circulatory disorders, type II
        '250.80', '250.82',  -- Diabetes with other specified manifestations, type II
        '250.90', '250.92',  -- Diabetes with unspecified complication, type II
        -- ICD-10-CM codes
        'E11.00', 'E11.01',  -- Type 2 DM with hyperosmolarity
        'E11.10', 'E11.11',  -- Type 2 DM with ketoacidosis
        'E11.21', 'E11.22', 'E11.29',  -- Type 2 DM with kidney complications
        'E11.311', 'E11.319', 'E11.32', 'E11.33', 'E11.34', 'E11.35', 'E11.36', 'E11.39',  -- Type 2 DM with eye complications
        'E11.40', 'E11.41', 'E11.42', 'E11.43', 'E11.44', 'E11.49',  -- Type 2 DM with neurological complications
        'E11.51', 'E11.52', 'E11.59',  -- Type 2 DM with circulatory complications
        'E11.610', 'E11.618', 'E11.620', 'E11.621', 'E11.622', 'E11.628', 'E11.630', 'E11.638', 'E11.641', 'E11.649', 'E11.65', 'E11.69',  -- Type 2 DM with other complications
        'E11.8', 'E11.9'  -- Type 2 DM with other/unspecified complications
    )
    AND co.person_id IN (
        SELECT person_id 
        FROM public.person 
        WHERE EXTRACT(YEAR FROM AGE(CURRENT_DATE, birth_datetime)) >= 18  -- Adults only
    )
),

-- B. Patients with abnormal glucose lab values
abnormal_labs AS (
    SELECT DISTINCT
        m.person_id,
        m.measurement_date AS index_date,
        'Laboratory' AS criterion_type
    FROM public.measurement m
    INNER JOIN public.concept c ON m.measurement_concept_id = c.concept_id
    WHERE (
        -- HbA1c >= 6.5%
        (c.concept_id IN (3004410, 3005673, 3007263) AND m.value_as_number >= 6.5)
        OR
        -- Fasting glucose >= 126 mg/dL
        (c.concept_id IN (3004501, 3016723) AND m.value_as_number >= 126)
        OR
        -- Random glucose >= 200 mg/dL
        (c.concept_id IN (3027018, 3034639) AND m.value_as_number >= 200)
    )
    AND m.measurement_date IS NOT NULL
),

-- Confirm abnormal labs with at least 2 occurrences or supporting evidence
confirmed_labs AS (
    SELECT 
        al.person_id,
        MIN(al.index_date) AS index_date,
        al.criterion_type
    FROM abnormal_labs al
    GROUP BY al.person_id, al.criterion_type
    HAVING COUNT(DISTINCT al.index_date) >= 2  -- At least 2 abnormal measurements
),

-- C. Patients with T2DM medications
t2dm_medications AS (
    SELECT DISTINCT
        de.person_id,
        de.drug_exposure_start_date AS index_date,
        'Medication' AS criterion_type
    FROM public.drug_exposure de
    INNER JOIN public.concept c ON de.drug_concept_id = c.concept_id
    INNER JOIN public.concept_ancestor ca ON c.concept_id = ca.descendant_concept_id
    WHERE ca.ancestor_concept_id IN (
        21600712,  -- Metformin
        21604254,  -- Sulfonylureas
        21604847,  -- Thiazolidinediones
        21605150,  -- DPP-4 inhibitors
        21605212,  -- GLP-1 agonists
        21605225,  -- SGLT2 inhibitors
        21604175   -- Meglitinides
    )
    OR de.drug_source_value ILIKE ANY(ARRAY[
        -- Generic names
        '%metformin%', '%glyburide%', '%glipizide%', '%glimepiride%',
        '%pioglitazone%', '%rosiglitazone%',
        '%sitagliptin%', '%saxagliptin%', '%linagliptin%', '%alogliptin%',
        '%exenatide%', '%liraglutide%', '%dulaglutide%', '%semaglutide%',
        '%canagliflozin%', '%dapagliflozin%', '%empagliflozin%', '%ertugliflozin%',
        '%repaglinide%', '%nateglinide%',
        '%acarbose%', '%miglitol%',
        -- Brand names
        '%glucophage%', '%fortamet%', '%glumetza%', '%riomet%',
        '%diabeta%', '%glynase%', '%glucotrol%', '%amaryl%',
        '%actos%', '%avandia%',
        '%januvia%', '%onglyza%', '%tradjenta%', '%nesina%',
        '%byetta%', '%bydureon%', '%victoza%', '%trulicity%', '%ozempic%', '%rybelsus%',
        '%invokana%', '%farxiga%', '%jardiance%', '%steglatro%',
        '%prandin%', '%starlix%',
        '%precose%', '%glyset%'
    ])
    AND de.person_id IN (
        SELECT person_id 
        FROM public.person 
        WHERE EXTRACT(YEAR FROM AGE(CURRENT_DATE, birth_datetime)) >= 18
    )
),

-- Confirm medications with at least 30 days supply or multiple fills
confirmed_medications AS (
    SELECT 
        tm.person_id,
        MIN(tm.index_date) AS index_date,
        tm.criterion_type
    FROM t2dm_medications tm
    LEFT JOIN public.drug_exposure de ON tm.person_id = de.person_id 
        AND tm.index_date = de.drug_exposure_start_date
    GROUP BY tm.person_id, tm.criterion_type
    HAVING 
        COUNT(DISTINCT tm.index_date) >= 2  -- At least 2 prescriptions
        OR SUM(COALESCE(de.days_supply, 30)) >= 30  -- Or at least 30 days supply
),

-- D. Exclusion criteria - Type 1 Diabetes
type1_exclusion AS (
    SELECT DISTINCT
        co.person_id
    FROM public.condition_occurrence co
    INNER JOIN public.concept c ON co.condition_concept_id = c.concept_id
    INNER JOIN public.concept_ancestor ca ON c.concept_id = ca.descendant_concept_id
    WHERE ca.ancestor_concept_id IN (
        201254,    -- Type 1 diabetes mellitus (SNOMED)
        435216     -- Diabetes mellitus type 1 (SNOMED)
    )
    OR co.condition_source_value ILIKE ANY(ARRAY[
        '250.01', '250.03', '250.11', '250.13', '250.21', '250.23',
        '250.31', '250.33', '250.41', '250.43', '250.51', '250.53',
        '250.61', '250.63', '250.71', '250.73', '250.81', '250.83',
        '250.91', '250.93',  -- ICD-9-CM Type 1
        'E10.%'  -- ICD-10-CM Type 1
    ])
),

-- E. Exclusion criteria - Gestational diabetes only
gestational_exclusion AS (
    SELECT DISTINCT
        p.person_id
    FROM public.person p
    INNER JOIN public.condition_occurrence co ON p.person_id = co.person_id
    INNER JOIN public.concept c ON co.condition_concept_id = c.concept_id
    WHERE (
        c.concept_id IN (4058243, 4024659)  -- Gestational diabetes
        OR co.condition_source_value ILIKE ANY(ARRAY['648.8%', 'O24.4%', '648.0%'])
    )
    AND NOT EXISTS (
        SELECT 1 
        FROM public.condition_occurrence co2 
        WHERE co2.person_id = p.person_id 
        AND co2.condition_start_date > co.condition_start_date + INTERVAL '12 months'
        AND co2.condition_concept_id IN (
            SELECT descendant_concept_id 
            FROM public.concept_ancestor 
            WHERE ancestor_concept_id IN (201826, 443238)
        )
    )
),

-- F. Exclusion criteria - Secondary diabetes
secondary_exclusion AS (
    SELECT DISTINCT
        co.person_id
    FROM public.condition_occurrence co
    WHERE co.condition_source_value ILIKE ANY(ARRAY[
        '249.%',  -- Secondary diabetes ICD-9
        'E08.%',  -- Diabetes due to underlying condition ICD-10
        'E09.%'   -- Drug or chemical induced diabetes ICD-10
    ])
),

-- G. Combine all inclusion criteria
all_inclusions AS (
    SELECT person_id, index_date, criterion_type FROM t2dm_diagnosis
    UNION
    SELECT person_id, index_date, criterion_type FROM confirmed_labs
    UNION
    SELECT person_id, index_date, criterion_type FROM confirmed_medications
),

-- H. Apply exclusions and create final cohort
t2dm_cohort AS (
    SELECT DISTINCT
        ai.person_id,
        MIN(ai.index_date) AS earliest_index_date,
        STRING_AGG(DISTINCT ai.criterion_type, ', ' ORDER BY ai.criterion_type) AS criteria_met,
        COUNT(DISTINCT ai.criterion_type) AS num_criteria_met
    FROM all_inclusions ai
    WHERE ai.person_id NOT IN (SELECT person_id FROM type1_exclusion)
    AND ai.person_id NOT IN (SELECT person_id FROM gestational_exclusion)
    AND ai.person_id NOT IN (SELECT person_id FROM secondary_exclusion)
    GROUP BY ai.person_id
)

-- Final output: Type 2 Diabetes cohort
SELECT 
    tc.person_id,
    p.gender_concept_id,
    p.year_of_birth,
    EXTRACT(YEAR FROM AGE(tc.earliest_index_date, 
        MAKE_DATE(p.year_of_birth, COALESCE(p.month_of_birth, 1), COALESCE(p.day_of_birth, 1)))) AS age_at_diagnosis,
    tc.earliest_index_date,
    tc.criteria_met,
    tc.num_criteria_met,
    CASE 
        WHEN EXISTS (SELECT 1 FROM t2dm_diagnosis td WHERE td.person_id = tc.person_id) THEN 'Yes'
        ELSE 'No'
    END AS has_diagnosis_code,
    CASE 
        WHEN EXISTS (SELECT 1 FROM confirmed_labs cl WHERE cl.person_id = tc.person_id) THEN 'Yes'
        ELSE 'No'
    END AS has_abnormal_labs,
    CASE 
        WHEN EXISTS (SELECT 1 FROM confirmed_medications cm WHERE cm.person_id = tc.person_id) THEN 'Yes'
        ELSE 'No'
    END AS has_t2dm_medication
FROM t2dm_cohort tc
INNER JOIN public.person p ON tc.person_id = p.person_id
ORDER BY tc.person_id;

-- Optional: Create summary statistics
SELECT 
    COUNT(DISTINCT person_id) AS total_t2dm_patients,
    ROUND(AVG(age_at_diagnosis), 1) AS avg_age_at_diagnosis,
    ROUND(AVG(num_criteria_met), 2) AS avg_criteria_met,
    SUM(CASE WHEN has_diagnosis_code = 'Yes' THEN 1 ELSE 0 END) AS patients_with_dx_code,
    SUM(CASE WHEN has_abnormal_labs = 'Yes' THEN 1 ELSE 0 END) AS patients_with_labs,
    SUM(CASE WHEN has_t2dm_medication = 'Yes' THEN 1 ELSE 0 END) AS patients_with_meds
FROM (
    SELECT 
        tc.person_id,
        EXTRACT(YEAR FROM AGE(tc.earliest_index_date, 
            MAKE_DATE(p.year_of_birth, COALESCE(p.month_of_birth, 1), COALESCE(p.day_of_birth, 1)))) AS age_at_diagnosis,
        tc.num_criteria_met,
        CASE WHEN EXISTS (SELECT 1 FROM t2dm_diagnosis td WHERE td.person_id = tc.person_id) THEN 'Yes' ELSE 'No' END AS has_diagnosis_code,
        CASE WHEN EXISTS (SELECT 1 FROM confirmed_labs cl WHERE cl.person_id = tc.person_id) THEN 'Yes' ELSE 'No' END AS has_abnormal_labs,
        CASE WHEN EXISTS (SELECT 1 FROM confirmed_medications cm WHERE cm.person_id = tc.person_id) THEN 'Yes' ELSE 'No' END AS has_t2dm_medication
    FROM t2dm_cohort tc
    INNER JOIN public.person p ON tc.person_id = p.person_id
) summary;

