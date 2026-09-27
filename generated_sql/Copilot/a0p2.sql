--error
WITH person_base AS (
    SELECT
        p.person_id,
        EXTRACT(YEAR FROM CURRENT_DATE) - p.year_of_birth AS age
    FROM person p
),

-- 1. T2DM diagnosis evidence (ICD9/10 source or SNOMED standard)
t2dm_dx AS (
    SELECT
        c.person_id,
        MIN(c.condition_start_date) AS first_t2dm_dx_date,
        COUNT(DISTINCT c.condition_start_date) AS t2dm_dx_distinct_dates
    FROM condition_occurrence c
    WHERE
        (
            c.condition_source_concept_id IN ( /* T2DM_ICD9_SET, T2DM_ICD10_SET */ )
            OR c.condition_concept_id IN ( /* T2DM_SNOMED_SET */ )
        )
    GROUP BY c.person_id
),

-- 2. Exclusion diagnoses: type 1, gestational, secondary diabetes
excl_type1 AS (
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE
        condition_source_concept_id IN ( /* TYPE1_ICD9_SET, TYPE1_ICD10_SET */ )
        OR condition_concept_id IN ( /* TYPE1_SNOMED_SET */ )
),

excl_gdm AS (
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE
        condition_source_concept_id IN ( /* GDM_ICD9_SET, GDM_ICD10_SET */ )
        OR condition_concept_id IN ( /* GDM_SNOMED_SET */ )
),

excl_secondary AS (
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE
        condition_source_concept_id IN ( /* SECONDARY_DM_ICD9_SET, SECONDARY_DM_ICD10_SET */ )
        OR condition_concept_id IN ( /* SECONDARY_DM_SNOMED_SET */ )
),

-- 3. Diabetes medications (non-insulin + optional insulin)
dm_meds AS (
    SELECT
        d.person_id,
        MIN(d.drug_exposure_start_date) AS first_dm_med_date,
        COUNT(DISTINCT d.drug_exposure_start_date) AS dm_med_dates
    FROM drug_exposure d
    WHERE
        d.drug_concept_id IN ( /* T2DM_ORAL_OR_INJECTABLE_NON_INSULIN_SET, optionally DIABETES_INSULIN_SET */ )
    GROUP BY d.person_id
),

-- 4. Abnormal diabetes labs
abnl_labs AS (
    SELECT
        m.person_id,
        MIN(m.measurement_date) AS first_abnl_lab_date,
        COUNT(DISTINCT m.measurement_date) AS abnl_lab_dates
    FROM measurement m
    JOIN concept mc ON m.measurement_concept_id = mc.concept_id
    WHERE
        (
            -- HbA1c ≥ 6.5%
            m.measurement_concept_id IN ( /* HBA1C_MEASUREMENT_SET */ )
            AND m.value_as_number >= 6.5
            AND m.unit_concept_id IN ( /* PERCENT_UNIT_SET */ )
        )
        OR (
            -- Fasting plasma glucose ≥ 126 mg/dL
            m.measurement_concept_id IN ( /* FASTING_GLUCOSE_MEASUREMENT_SET */ )
            AND m.value_as_number >= 126
            AND m.unit_concept_id IN ( /* MG_DL_UNIT_SET */ )
        )
        OR (
            -- 2h OGTT glucose ≥ 200 mg/dL
            m.measurement_concept_id IN ( /* OGTT_2H_GLUCOSE_MEASUREMENT_SET */ )
            AND m.value_as_number >= 200
            AND m.unit_concept_id IN ( /* MG_DL_UNIT_SET */ )
        )
    GROUP BY m.person_id
),

-- 5. Optional: visit filter (at least one qualifying visit)
qualifying_visits AS (
    SELECT DISTINCT v.person_id
    FROM visit_occurrence v
    WHERE v.visit_concept_id IN ( /* INPATIENT_VISIT_SET, OUTPATIENT_VISIT_SET */ )
),

-- 6. Combine inclusion logic
inclusion AS (
    SELECT
        pb.person_id,
        pb.age,
        COALESCE(dx.t2dm_dx_distinct_dates, 0) AS t2dm_dx_dates,
        COALESCE(dm.dm_med_dates, 0) AS dm_med_dates,
        COALESCE(lab.abnl_lab_dates, 0) AS abnl_lab_dates,
        LEAST(
            COALESCE(dx.first_t2dm_dx_date, DATE '9999-12-31'),
            COALESCE(dm.first_dm_med_date, DATE '9999-12-31'),
            COALESCE(lab.first_abnl_lab_date, DATE '9999-12-31')
        ) AS index_date
    FROM person_base pb
    LEFT JOIN t2dm_dx dx ON pb.person_id = dx.person_id
    LEFT JOIN dm_meds dm ON pb.person_id = dm.person_id
    LEFT JOIN abnl_labs lab ON pb.person_id = lab.person_id
    LEFT JOIN qualifying_visits qv ON pb.person_id = qv.person_id
    WHERE
        pb.age >= 18
        AND qv.person_id IS NOT NULL
        AND (
            -- Rule 1: ≥ 2 T2DM diagnosis dates
            COALESCE(dx.t2dm_dx_distinct_dates, 0) >= 2

            OR

            -- Rule 2: ≥ 1 T2DM diagnosis AND ≥ 1 diabetes medication date
            (
                COALESCE(dx.t2dm_dx_distinct_dates, 0) >= 1
                AND COALESCE(dm.dm_med_dates, 0) >= 1
            )

            OR

            -- Rule 3: ≥ 2 abnormal lab dates
            COALESCE(lab.abnl_lab_dates, 0) >= 2

            OR

            -- Rule 4: ≥ 1 abnormal lab date AND ≥ 1 diabetes medication date
            (
                COALESCE(lab.abnl_lab_dates, 0) >= 1
                AND COALESCE(dm.dm_med_dates, 0) >= 1
            )
        )
),

-- 7. Apply exclusions
final_t2dm_cohort AS (
    SELECT i.*
    FROM inclusion i
    LEFT JOIN excl_type1 e1 ON i.person_id = e1.person_id
    LEFT JOIN excl_gdm eg ON i.person_id = eg.person_id
    LEFT JOIN excl_secondary es ON i.person_id = es.person_id
    WHERE
        e1.person_id IS NULL   -- NOT type 1
        AND eg.person_id IS NULL   -- NOT gestational
        AND es.person_id IS NULL   -- NOT secondary diabetes
        -- AND NOT STRONG_TYPE1_PATTERN (if implemented as another CTE)
)

SELECT *
FROM final_t2dm_cohort;
