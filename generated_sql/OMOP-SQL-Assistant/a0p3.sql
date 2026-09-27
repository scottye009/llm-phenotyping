SELECT person_id
FROM omop_person_level_features
WHERE age_at_index >= 18

AND (
        /* Diagnosis-based T2DM */
        t2dm_dx_distinct_dates >= 2
        OR t2dm_inpatient_or_ed_count >= 1

        OR

        /* Lab-based diabetes */
        abnormal_diabetes_lab_distinct_dates >= 2

        OR

        /* Medication-supported T2DM */
        (
            non_insulin_antidiabetic_med_count >= 1
            AND (
                t2dm_dx_distinct_dates >= 1
                OR abnormal_diabetes_lab_distinct_dates >= 1
            )
        )
    )

AND NOT (
        gestational_diabetes_dx_count >= 1
        OR secondary_diabetes_dx_count >= 1
    )

AND NOT (
        t1dm_dx_distinct_dates > t2dm_dx_distinct_dates
        AND insulin_med_count >= 1
        AND non_insulin_antidiabetic_med_count = 0
    );--error