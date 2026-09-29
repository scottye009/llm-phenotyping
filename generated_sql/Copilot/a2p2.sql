WITH

-- 1. T2DM diagnosis events (ICD9CM 250.x0, 250.x2; ICD10CM E11.x)
t2dm_dx AS (
    SELECT
        co.person_id,
        co.condition_start_date AS dx_date
    FROM public.condition_occurrence co
    WHERE
        (
            -- ICD-9-CM: 250.x0, 250.x2
            co.condition_source_value ~ '^250\.[0-9][02]$'
            OR
            -- ICD-10-CM: E11.*
            co.condition_source_value LIKE 'E11%'
        )
),

-- 2. Exclusion diagnoses: Type 1, gestational, secondary diabetes
exclusion_dx AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    WHERE
        (
            -- Type 1 diabetes: ICD-9-CM 250.x1, 250.x3; ICD-10-CM E10.*
            co.condition_source_value ~ '^250\.[0-9][13]$'
            OR co.condition_source_value LIKE 'E10%'
        )
        OR (
            -- Gestational diabetes: ICD-9-CM 648.0x, 648.8x; ICD-10-CM O24.4x
            co.condition_source_value LIKE '6480%'
            OR co.condition_source_value LIKE '6488%'
            OR co.condition_source_value LIKE 'O24.4%'
        )
        OR (
            -- Secondary diabetes (optional): ICD-9-CM 249.x; ICD-10-CM E08.x, E09.x, E13.x
            co.condition_source_value LIKE '249%'
            OR co.condition_source_value LIKE 'E08%'
            OR co.condition_source_value LIKE 'E09%'
            OR co.condition_source_value LIKE 'E13%'
        )
),

-- 3. T2DM medication exposures
t2dm_med AS (
    SELECT
        de.person_id,
        de.drug_exposure_start_date AS med_date
    FROM public.drug_exposure de
    WHERE
        (
            -- Biguanides: metformin (Glucophage, Fortamet, Glumetza, etc.)
            UPPER(de.drug_source_value) LIKE '%METFORMIN%'
            OR UPPER(de.drug_source_value) LIKE '%GLUCOPHAGE%'
            OR UPPER(de.drug_source_value) LIKE '%FORTAMET%'
            OR UPPER(de.drug_source_value) LIKE '%GLUMETZA%'
        )
        OR (
            -- Sulfonylureas: glipizide, glyburide, glimepiride
            UPPER(de.drug_source_value) LIKE '%GLIPIZIDE%'
            OR UPPER(de.drug_source_value) LIKE '%GLUCOTROL%'
            OR UPPER(de.drug_source_value) LIKE '%GLYBURIDE%'
            OR UPPER(de.drug_source_value) LIKE '%DIABETA%'
            OR UPPER(de.drug_source_value) LIKE '%MICRONASE%'
            OR UPPER(de.drug_source_value) LIKE '%GLIMEPIRIDE%'
            OR UPPER(de.drug_source_value) LIKE '%AMARYL%'
        )
        OR (
            -- Thiazolidinediones: pioglitazone, rosiglitazone
            UPPER(de.drug_source_value) LIKE '%PIOGLITAZONE%'
            OR UPPER(de.drug_source_value) LIKE '%ACTOS%'
            OR UPPER(de.drug_source_value) LIKE '%ROSIGLITAZONE%'
            OR UPPER(de.drug_source_value) LIKE '%AVANDIA%'
        )
        OR (
            -- DPP-4 inhibitors: sitagliptin, saxagliptin, linagliptin, alogliptin
            UPPER(de.drug_source_value) LIKE '%SITAGLIPTIN%'
            OR UPPER(de.drug_source_value) LIKE '%JANUVIA%'
            OR UPPER(de.drug_source_value) LIKE '%SAXAGLIPTIN%'
            OR UPPER(de.drug_source_value) LIKE '%ONGLYZA%'
            OR UPPER(de.drug_source_value) LIKE '%LINAGLIPTIN%'
            OR UPPER(de.drug_source_value) LIKE '%TRADJENTA%'
            OR UPPER(de.drug_source_value) LIKE '%ALOGLIPTIN%'
            OR UPPER(de.drug_source_value) LIKE '%NESINA%'
        )
        OR (
            -- GLP-1 receptor agonists: exenatide, liraglutide, dulaglutide, semaglutide, lixisenatide
            UPPER(de.drug_source_value) LIKE '%EXENATIDE%'
            OR UPPER(de.drug_source_value) LIKE '%BYETTA%'
            OR UPPER(de.drug_source_value) LIKE '%BYDUREON%'
            OR UPPER(de.drug_source_value) LIKE '%LIRAGLUTIDE%'
            OR UPPER(de.drug_source_value) LIKE '%VICTOZA%'
            OR UPPER(de.drug_source_value) LIKE '%DULAGLUTIDE%'
            OR UPPER(de.drug_source_value) LIKE '%TRULICITY%'
            OR UPPER(de.drug_source_value) LIKE '%SEMAGLUTIDE%'
            OR UPPER(de.drug_source_value) LIKE '%OZEMPIC%'
            OR UPPER(de.drug_source_value) LIKE '%RYBELSUS%'
            OR UPPER(de.drug_source_value) LIKE '%LIXISENATIDE%'
            OR UPPER(de.drug_source_value) LIKE '%ADLYXIN%'
        )
        OR (
            -- SGLT2 inhibitors: canagliflozin, dapagliflozin, empagliflozin, ertugliflozin
            UPPER(de.drug_source_value) LIKE '%CANAGLIFLOZIN%'
            OR UPPER(de.drug_source_value) LIKE '%INVOKANA%'
            OR UPPER(de.drug_source_value) LIKE '%DAPAGLIFLOZIN%'
            OR UPPER(de.drug_source_value) LIKE '%FARXIGA%'
            OR UPPER(de.drug_source_value) LIKE '%EMPAGLIFLOZIN%'
            OR UPPER(de.drug_source_value) LIKE '%JARDIANCE%'
            OR UPPER(de.drug_source_value) LIKE '%ERTUGLIFLOZIN%'
            OR UPPER(de.drug_source_value) LIKE '%STEGLATRO%'
        )
        OR (
            -- Insulins (supportive, not alone diagnostic)
            UPPER(de.drug_source_value) LIKE '%INSULIN%'
            OR UPPER(de.drug_source_value) LIKE '%LANTUS%'
            OR UPPER(de.drug_source_value) LIKE '%LEVEMIR%'
            OR UPPER(de.drug_source_value) LIKE '%TRESIBA%'
            OR UPPER(de.drug_source_value) LIKE '%HUMALOG%'
            OR UPPER(de.drug_source_value) LIKE '%NOVOLOG%'
        )
),

-- 4. Abnormal diabetes labs
abnl_labs AS (
    SELECT
        m.person_id,
        m.measurement_date AS lab_date
    FROM public.measurement m
    WHERE
        (
            -- HbA1c ≥ 6.5%
            (
                UPPER(m.measurement_source_value) LIKE '%A1C%'
                OR UPPER(m.measurement_source_value) LIKE '%HBA1C%'
            )
            AND m.value_as_number IS NOT NULL
            AND m.value_as_number >= 6.5
        )
        OR (
            -- Fasting plasma glucose ≥ 126 mg/dL
            UPPER(m.measurement_source_value) LIKE '%FASTING GLUCOSE%'
            AND m.value_as_number IS NOT NULL
            AND m.value_as_number >= 126
        )
        OR (
            -- OGTT ≥ 200 mg/dL
            UPPER(m.measurement_source_value) LIKE '%OGTT%'
            AND m.value_as_number IS NOT NULL
            AND m.value_as_number >= 200
        )
        OR (
            -- Random glucose ≥ 200 mg/dL
            UPPER(m.measurement_source_value) LIKE '%GLUCOSE%'
            AND m.value_as_number IS NOT NULL
            AND m.value_as_number >= 200
        )
),

-- 5. Aggregate counts per person
dx_counts AS (
    SELECT
        person_id,
        COUNT(DISTINCT dx_date) AS dx_date_count,
        MIN(dx_date) AS first_dx_date
    FROM t2dm_dx
    GROUP BY person_id
),

med_counts AS (
    SELECT
        person_id,
        COUNT(DISTINCT med_date) AS med_date_count,
        MIN(med_date) AS first_med_date
    FROM t2dm_med
    GROUP BY person_id
),

lab_counts AS (
    SELECT
        person_id,
        COUNT(DISTINCT lab_date) AS lab_date_count,
        MIN(lab_date) AS first_lab_date
    FROM abnl_labs
    GROUP BY person_id
),

-- 6. Combine evidence and compute index date
combined_evidence AS (
    SELECT
        p.person_id,
        COALESCE(dx.dx_date_count, 0)  AS dx_date_count,
        COALESCE(med.med_date_count, 0) AS med_date_count,
        COALESCE(lab.lab_date_count, 0) AS lab_date_count,
        LEAST(
            COALESCE(dx.first_dx_date, '9999-12-31'::date),
            COALESCE(med.first_med_date, '9999-12-31'::date),
            COALESCE(lab.first_lab_date, '9999-12-31'::date)
        ) AS index_date
    FROM public.person p
    LEFT JOIN dx_counts  dx  ON p.person_id = dx.person_id
    LEFT JOIN med_counts med ON p.person_id = med.person_id
    LEFT JOIN lab_counts lab ON p.person_id = lab.person_id
),

-- 7. Age at index and observation period check
eligible_with_age_obs AS (
    SELECT
        ce.person_id,
        ce.dx_date_count,
        ce.med_date_count,
        ce.lab_date_count,
        ce.index_date,
        (EXTRACT(YEAR FROM ce.index_date) - p.year_of_birth) AS age_at_index
    FROM combined_evidence ce
    JOIN public.person p
        ON ce.person_id = p.person_id
    JOIN public.observation_period op
        ON op.person_id = p.person_id
       AND ce.index_date BETWEEN op.observation_period_start_date
                             AND op.observation_period_end_date
    WHERE
        ce.index_date < '9999-12-31'::date
),

-- 8. Apply inclusion logic (DX/LAB/MED combinations) AND age ≥ 18
candidate_cases AS (
    SELECT
        e.person_id,
        e.index_date,
        e.age_at_index
    FROM eligible_with_age_obs e
    WHERE
        (
            -- (DX_T2DM_COUNT ≥ 2)
            (e.dx_date_count >= 2)
            OR
            -- (DX_T2DM_COUNT ≥ 1 AND MED_T2DM_COUNT ≥ 1)
            (e.dx_date_count >= 1 AND e.med_date_count >= 1)
            OR
            -- (ABNL_LAB_COUNT ≥ 2)
            (e.lab_date_count >= 2)
            OR
            -- (ABNL_LAB_COUNT ≥ 1 AND MED_T2DM_COUNT ≥ 1)
            (e.lab_date_count >= 1 AND e.med_date_count >= 1)
        )
        AND e.age_at_index >= 18
),

-- 9. Remove exclusions (NOT Type 1 / Gestational / Secondary)
final_t2dm_cases AS (
    SELECT c.*
    FROM candidate_cases c
    LEFT JOIN exclusion_dx ex
        ON c.person_id = ex.person_id
    WHERE
        ex.person_id IS NULL
)

-- 10. Final cohort
SELECT
    person_id,
    index_date,
    age_at_index
FROM final_t2dm_cases;
