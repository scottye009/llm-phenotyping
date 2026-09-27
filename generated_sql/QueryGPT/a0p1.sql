-- Phenotype: Type 2 Diabetes Mellitus

--error
T2DM_CASE =
(
    (
        T2DM_DIAGNOSIS_COUNT >= 2
        OR
        (
            T2DM_DIAGNOSIS_COUNT >= 1
            AND
            (
                T2DM_MED = TRUE
                OR DIABETES_LAB = TRUE
            )
        )
        OR
        (
            T2DM_MED_NON_INSULIN = TRUE
            AND DIABETES_LAB = TRUE
        )
    )
    AND NOT GESTATIONAL_DIABETES
    AND NOT SECONDARY_DIABETES
    AND NOT
    (
        T1DM_DIAGNOSIS_COUNT > T2DM_DIAGNOSIS_COUNT
        AND T2DM_MED_NON_INSULIN = FALSE
    )
);