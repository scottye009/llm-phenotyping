--error
/* ============================================================
   OMOP T2DM CASE PHENOTYPE
   Cohort type: prevalent adult T2DM cases
   ============================================================ */

WITH diagnosis_features AS (
    SELECT
        p.person_id,

        COUNT(DISTINCT CASE
            WHEN co.condition_concept_id IN (
                SELECT concept_id FROM cs_t2dm_dx
            )
            THEN co.condition_start_date
        END) AS t2dm_dx_date_count,

        COUNT(DISTINCT CASE
            WHEN co.condition_concept_id IN (
                SELECT concept_id FROM cs_t1dm_dx
            )
            THEN co.condition_start_date
        END) AS t1dm_dx_date_count,

        COUNT(DISTINCT CASE
            WHEN co.condition_concept_id IN (
                SELECT concept_id FROM cs_t2dm_dx
            )
            AND co.condition_type_concept_id IN (
                SELECT concept_id FROM cs_physician_entered_condition_type
            )
            AND co.condition_type_concept_id NOT IN (
                SELECT concept_id FROM cs_billing_only_condition_type
            )
            THEN co.condition_start_date
        END) AS t2dm_physician_dx_date_count,

        MAX(CASE
            WHEN co.condition_concept_id IN (
                SELECT concept_id FROM cs_secondary_dm_dx
            )
            THEN 1 ELSE 0
        END) AS has_secondary_dm_dx,

        MAX(CASE
            WHEN co.condition_concept_id IN (
                SELECT concept_id FROM cs_pregnancy_dm_dx
            )
            THEN 1 ELSE 0
        END) AS has_pregnancy_dm_dx

    FROM person p
    LEFT JOIN condition_occurrence co
        ON co.person_id = p.person_id
    GROUP BY p.person_id
),

drug_features AS (
    SELECT
        p.person_id,

        MIN(CASE
            WHEN de.drug_concept_id IN (
                SELECT concept_id FROM cs_t2dm_rx
            )
            THEN de.drug_exposure_start_date
        END) AS first_t2dm_rx_date,

        MIN(CASE
            WHEN de.drug_concept_id IN (
                SELECT concept_id FROM cs_t1dm_rx_marker
            )
            THEN de.drug_exposure_start_date
        END) AS first_t1dm_rx_marker_date

    FROM person p
    LEFT JOIN drug_exposure de
        ON de.person_id = p.person_id
    GROUP BY p.person_id
),

lab_events AS (
    SELECT
        m.person_id,
        m.measurement_date,

        CASE
            WHEN m.measurement_concept_id IN (
                SELECT concept_id FROM cs_hba1c_lab
            )
            AND m.value_as_number >= 6.5
            THEN 1

            WHEN m.measurement_concept_id IN (
                SELECT concept_id FROM cs_fasting_glucose_lab
            )
            AND m.value_as_number >= 126
            THEN 1

            WHEN m.measurement_concept_id IN (
                SELECT concept_id FROM cs_random_glucose_lab
            )
            AND m.value_as_number >= 200
            THEN 1

            WHEN m.measurement_concept_id IN (
                SELECT concept_id FROM cs_two_hour_ogtt_lab
            )
            AND m.value_as_number >= 200
            THEN 1

            ELSE 0
        END AS is_abnormal_diabetes_lab

    FROM measurement m
    WHERE m.value_as_number IS NOT NULL
),

lab_features AS (
    SELECT
        person_id,
        MAX(is_abnormal_diabetes_lab) AS has_abnormal_diabetes_lab,
        COUNT(DISTINCT CASE
            WHEN is_abnormal_diabetes_lab = 1
            THEN measurement_date
        END) AS abnormal_diabetes_lab_date_count
    FROM lab_events
    GROUP BY person_id
),

person_features AS (
    SELECT
        p.person_id,

        /* Use a proper date-of-birth expression in production. */
        EXTRACT(YEAR FROM CURRENT_DATE) - p.year_of_birth AS approximate_age,

        COALESCE(dx.t2dm_dx_date_count, 0) AS t2dm_dx_date_count,
        COALESCE(dx.t1dm_dx_date_count, 0) AS t1dm_dx_date_count,
        COALESCE(dx.t2dm_physician_dx_date_count, 0)
            AS t2dm_physician_dx_date_count,

        COALESCE(dx.has_secondary_dm_dx, 0) AS has_secondary_dm_dx,
        COALESCE(dx.has_pregnancy_dm_dx, 0) AS has_pregnancy_dm_dx,

        rx.first_t2dm_rx_date,
        rx.first_t1dm_rx_marker_date,

        COALESCE(lab.has_abnormal_diabetes_lab, 0)
            AS has_abnormal_diabetes_lab,

        COALESCE(lab.abnormal_diabetes_lab_date_count, 0)
            AS abnormal_diabetes_lab_date_count

    FROM person p
    LEFT JOIN diagnosis_features dx
        ON dx.person_id = p.person_id
    LEFT JOIN drug_features rx
        ON rx.person_id = p.person_id
    LEFT JOIN lab_features lab
        ON lab.person_id = p.person_id
)

SELECT
    person_id,
    CASE
        WHEN approximate_age >= 18

         AND NOT (t1dm_dx_date_count > 0)
         AND NOT (has_secondary_dm_dx = 1)
         AND NOT (has_pregnancy_dm_dx = 1)

         AND (
                /* PATH 1 */
                (
                    t2dm_dx_date_count > 0
                    AND first_t2dm_rx_date IS NOT NULL
                    AND first_t1dm_rx_marker_date IS NOT NULL
                    AND first_t2dm_rx_date < first_t1dm_rx_marker_date
                )

                OR

                /* PATH 2 */
                (
                    t2dm_dx_date_count > 0
                    AND first_t2dm_rx_date IS NOT NULL
                    AND first_t1dm_rx_marker_date IS NULL
                )

                OR

                /* PATH 3 */
                (
                    t2dm_dx_date_count > 0
                    AND first_t2dm_rx_date IS NULL
                    AND first_t1dm_rx_marker_date IS NULL
                    AND has_abnormal_diabetes_lab = 1
                )

                OR

                /* PATH 4 */
                (
                    t2dm_dx_date_count = 0
                    AND first_t2dm_rx_date IS NOT NULL
                    AND has_abnormal_diabetes_lab = 1
                )

                OR

                /* PATH 5 */
                (
                    t2dm_dx_date_count > 0
                    AND first_t1dm_rx_marker_date IS NOT NULL
                    AND first_t2dm_rx_date IS NULL
                    AND t2dm_physician_dx_date_count >= 2
                )
         )

        THEN 1
        ELSE 0
    END AS is_t2dm_case

FROM person_features;