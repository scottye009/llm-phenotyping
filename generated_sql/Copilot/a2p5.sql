
WITH

-- 1. Concept sets --------------------------------------------------------

t2dm_dx_concepts AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.concept_id IN (123456, 789012) -- Replace with actual T2DM diagnosis concept_ids
),

t1dm_dx_concepts AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.concept_id IN (234567, 890123) -- Replace with actual T1DM diagnosis concept_ids
),

gestational_dm_dx_concepts AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.concept_id IN (345678) -- Replace with gestational diabetes concept_ids
),

other_dm_dx_concepts AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.concept_id IN (456789) -- Replace with secondary/other diabetes concept_ids
),

hba1c_meas_concepts AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.concept_id IN (567890) -- Replace with HbA1c measurement concept_ids
),

fpg_meas_concepts AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.concept_id IN (678901) -- Replace with fasting plasma glucose concept_ids
),

ogtt_meas_concepts AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.concept_id IN (789012) -- Replace with 2h OGTT glucose concept_ids
),

random_glucose_meas_concepts AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.concept_id IN (890123) -- Replace with random plasma glucose concept_ids
),

non_insulin_antihyperglycemic_drug_concepts AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.concept_id IN (901234, 912345) -- Replace with non-insulin drug concept_ids
),

insulin_drug_concepts AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.concept_id IN (923456) -- Replace with insulin drug concept_ids
),

-- 2. Diagnosis evidence --------------------------------------------------

t2dm_dx AS (
    SELECT person_id, condition_start_date
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (SELECT concept_id FROM t2dm_dx_concepts)
),

t1dm_dx AS (
    SELECT person_id, condition_start_date
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (SELECT concept_id FROM t1dm_dx_concepts)
),

gestational_dm_dx AS (
    SELECT person_id, condition_start_date
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (SELECT concept_id FROM gestational_dm_dx_concepts)
),

other_dm_dx AS (
    SELECT person_id, condition_start_date
    FROM public.condition_occurrence
    WHERE condition_concept_id IN (SELECT concept_id FROM other_dm_dx_concepts)
),

-- 3. Lab evidence --------------------------------------------------------

abnormal_glucose_labs AS (
    SELECT person_id, measurement_date
    FROM public.measurement
    WHERE (
        measurement_concept_id IN (SELECT concept_id FROM hba1c_meas_concepts)
        AND value_as_number >= 6.5
    ) OR (
        measurement_concept_id IN (SELECT concept_id FROM fpg_meas_concepts)
        AND value_as_number >= 126
    ) OR (
        measurement_concept_id IN (SELECT concept_id FROM ogtt_meas_concepts)
        AND value_as_number >= 200
    ) OR (
        measurement_concept_id IN (SELECT concept_id FROM random_glucose_meas_concepts)
        AND value_as_number >= 200
    )
),

abnormal_glucose_labs_agg AS (
    SELECT person_id,
           COUNT(DISTINCT measurement_date) AS abnormal_lab_dates
    FROM abnormal_glucose_labs
    GROUP BY person_id
),

-- 4. Medication evidence -------------------------------------------------

non_insulin_exposure AS (
    SELECT person_id, drug_exposure_start_date
    FROM public.drug_exposure
    WHERE drug_concept_id IN (SELECT concept_id FROM non_insulin_antihyperglycemic_drug_concepts)
),

non_insulin_exposure_agg AS (
    SELECT person_id,
           COUNT(DISTINCT drug_exposure_start_date) AS non_insulin_exposure_dates
    FROM non_insulin_exposure
    GROUP BY person_id
),

insulin_exposure AS (
    SELECT person_id, drug_exposure_start_date
    FROM public.drug_exposure
    WHERE drug_concept_id IN (SELECT concept_id FROM insulin_drug_concepts)
),

insulin_exposure_agg AS (
    SELECT person_id,
           COUNT(DISTINCT drug_exposure_start_date) AS insulin_exposure_dates
    FROM insulin_exposure
    GROUP BY person_id
),

-- 5. Aggregate diagnosis evidence ---------------------------------------

t2dm_dx_agg AS (
    SELECT person_id,
           COUNT(DISTINCT condition_start_date) AS t2dm_dx_dates
    FROM t2dm_dx
    GROUP BY person_id
),

t1dm_dx_agg AS (
    SELECT person_id,
           COUNT(DISTINCT condition_start_date) AS t1dm_dx_dates
    FROM t1dm_dx
    GROUP BY person_id
),

gestational_dm_dx_agg AS (
    SELECT person_id,
           COUNT(DISTINCT condition_start_date) AS gestational_dm_dx_dates
    FROM gestational_dm_dx
    GROUP BY person_id
),

other_dm_dx_agg AS (
    SELECT person_id,
           COUNT(DISTINCT condition_start_date) AS other_dm_dx_dates
    FROM other_dm_dx
    GROUP BY person_id
),

-- 6. Positive evidence flags --------------------------------------------

positive_evidence AS (
    SELECT p.person_id,
           CASE WHEN t2.t2dm_dx_dates >= 2 THEN 1 ELSE 0 END AS cond_a_dx2,
           CASE WHEN t2.t2dm_dx_dates >= 1 AND (ni.non_insulin_exposure_dates >= 1 OR i.insulin_exposure_dates >= 1)
                THEN 1 ELSE 0 END AS cond_b_dx_plus_med,
           CASE WHEN labs.abnormal_lab_dates >= 2 THEN 1 ELSE 0 END AS cond_c_labs2,
           CASE WHEN ni.non_insulin_exposure_dates >= 2 AND (t2.t2dm_dx_dates >= 1 OR labs.abnormal_lab_dates >= 1)
                THEN 1 ELSE 0 END AS cond_d_meds2_plus_dx_or_lab
    FROM public.person p
    LEFT JOIN t2dm_dx_agg t2 ON p.person_id = t2.person_id
    LEFT JOIN abnormal_glucose_labs_agg labs ON p.person_id = labs.person_id
    LEFT JOIN non_insulin_exposure_agg ni ON p.person_id = ni.person_id
    LEFT JOIN insulin_exposure_agg i ON p.person_id = i.person_id
),

-- 7. Exclusion flags -----------------------------------------------------

exclusions AS (
    SELECT p.person_id,
           COALESCE(t1.t1dm_dx_dates, 0) AS t1dm_dx_dates,
           COALESCE(g.gestational_dm_dx_dates, 0) AS gestational_dm_dx_dates,
           COALESCE(o.other_dm_dx_dates, 0) AS other_dm_dx_dates,
           COALESCE(t2.t2dm_dx_dates, 0) AS t2dm_dx_dates
    FROM public.person p
    LEFT JOIN t1dm_dx_agg t1 ON p.person_id = t1.person_id
    LEFT JOIN gestational_dm_dx_agg g ON p.person_id = g.person_id
    LEFT JOIN other_dm_dx_agg o ON p.person_id = o.person_id
    LEFT JOIN t2dm_dx_agg t2 ON p.person_id = t2.person_id
),

-- 8. Final cohort --------------------------------------------------------

t2dm_cohort AS (
    SELECT pe.person_id
    FROM positive_evidence pe
    JOIN exclusions ex ON pe.person_id = ex.person_id
    WHERE (
        pe.cond_a_dx2 = 1 OR
        pe.cond_b_dx_plus_med = 1 OR
        pe.cond_c_labs2 = 1 OR
        pe.cond_d_meds2_plus_dx_or_lab = 1
    )
    AND NOT (
        ex.t1dm_dx_dates >= 2 AND ex.t2dm_dx_dates = 0
    )
    AND ex.gestational_dm_dx_dates = 0
    AND ex.other_dm_dx_dates = 0
)

SELECT *
FROM t2dm_cohort;
