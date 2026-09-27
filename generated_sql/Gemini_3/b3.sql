-- filepath: 
-- 1. Support table for medication keywords
WITH med_patterns AS (
    SELECT pattern FROM (VALUES
        ('%metformin%'), ('%glucophage%'), ('%glipizide%'), ('%glucotrol%'),
        ('%glyburide%'), ('%micronase%'), ('%diabeta%'), ('%glimepiride%'), ('%amaryl%'),
        ('%sitagliptin%'), ('%januvia%'), ('%saxagliptin%'), ('%onglyza%'),
        ('%linagliptin%'), ('%tradjenta%'), ('%empagliflozin%'), ('%jardiance%'),
        ('%canagliflozin%'), ('%invokana%'), ('%dapagliflozin%'), ('%farxiga%'),
        ('%liraglutide%'), ('%victoza%'), ('%exenatide%'), ('%byetta%'), ('%ozempic%'),
        ('%pioglitazone%'), ('%actos%'), ('%rosiglitazone%'), ('%avandia%')
    ) AS t(pattern)
),

-- 2. Identify T2DM specific diagnoses
t2dm_dx AS (
    SELECT person_id, CAST(condition_start_date AS DATE) AS event_date
    FROM condition_occurrence
    WHERE condition_source_value ILIKE 'E11%' 
       OR regexp_matches(condition_source_value, '^250\.[0-9][02]') -- ICD-9 T2DM (x.x0 or x.x2)
       OR condition_source_concept_name ILIKE '%type 2 diabetes%'
       OR condition_source_concept_name ILIKE '%t2dm%'
),

-- 3. Identify T1DM specific diagnoses (for exclusion weighting)
t1dm_dx AS (
    SELECT person_id, CAST(condition_start_date AS DATE) AS event_date
    FROM condition_occurrence
    WHERE condition_source_value ILIKE 'E10%'
       OR regexp_matches(condition_source_value, '^250\.[0-9][13]') -- ICD-9 T1DM (x.x1 or x.x3)
       OR condition_source_concept_name ILIKE '%type 1 diabetes%'
       OR condition_source_concept_name ILIKE '%t1dm%'
),

-- 4. Identify T2DM related meds from reliable source concepts
t2dm_meds AS (
    SELECT DISTINCT person_id
    FROM drug_exposure
    WHERE EXISTS (
        SELECT 1 FROM med_patterns 
        WHERE drug_exposure.drug_source_value ILIKE med_patterns.pattern
    )
),

-- 5. Identify abnormal predictive labs (HbA1c >= 6.5)
t2dm_labs AS (
    SELECT DISTINCT person_id
    FROM measurement
    WHERE (
        measurement_source_value ILIKE '%a1c%' 
        OR measurement_source_value ILIKE '%glycated hemoglobin%'
    )
    AND value_as_number >= 6.5
),

-- 6. Aggregate patient diagnostic timelines
dx_counts AS (
    SELECT 
        person_id, 
        COUNT(DISTINCT event_date) AS t2dm_date_count
    FROM t2dm_dx
    GROUP BY person_id
),
t1_counts AS (
    SELECT 
        person_id, 
        COUNT(DISTINCT event_date) AS t1dm_date_count
    FROM t1dm_dx
    GROUP BY person_id
)

-- 7. Final Patient Assembly
SELECT DISTINCT d.person_id
FROM dx_counts d
LEFT JOIN t1_counts t1 ON d.person_id = t1.person_id
WHERE (
    -- Criterion A: At least 2 distinct T2DM diagnosis dates
    d.t2dm_date_count >= 2
    OR 
    -- Criterion B: 1 T2DM diagnosis date AND a supporting T2DM Med or Lab
    (d.t2dm_date_count >= 1 AND (
        EXISTS (SELECT 1 FROM t2dm_meds m WHERE m.person_id = d.person_id) OR 
        EXISTS (SELECT 1 FROM t2dm_labs l WHERE l.person_id = d.person_id)
    ))
)
-- Exclusion: Require that instances of T1DM don't outnumber T2DM dates
AND (t1.t1dm_date_count IS NULL OR t1.t1dm_date_count < d.t2dm_date_count);