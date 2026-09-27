SELECT person_id
FROM candidate_patients
WHERE
    age_at_index >= 18

    AND
    (
        (
            t2dm_dx_count >= 2
            AND t2dm_dx_distinct_dates >= 2
        )
        OR t2dm_inpatient_dx_count >= 1
        OR
        (
            t2dm_dx_count >= 1
            AND t2dm_med_count >= 1
        )
        OR
        (
            abnormal_diabetes_lab_count >= 1
            AND
            (
                t2dm_dx_count >= 1
                OR t2dm_med_count >= 1
            )
        )
    )

    AND NOT
    (
        type1_dx_count >= 2
        AND
        (
            type1_dx_count > t2dm_dx_count
            OR
            (
                insulin_count >= 1
                AND non_insulin_t2dm_med_count = 0
            )
        )
    )

    AND NOT gestational_diabetes_only
    AND NOT secondary_diabetes_only;--error