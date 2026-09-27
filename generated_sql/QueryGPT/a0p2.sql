--error
/*
Required concept_set_member.set_name values:

  T2DM_DX
  T1DM_DX
  GESTATIONAL_DM_DX
  SECONDARY_DM_DX
  CLASSIC_HYPERGLYCEMIA_SYMPTOM
  HYPERGLYCEMIC_CRISIS
  HBA1C
  FASTING_GLUCOSE
  TWO_HOUR_OGTT_GLUCOSE
  RANDOM_GLUCOSE
  NON_INSULIN_ANTIHYPERGLYCEMIC_DRUG
  INSULIN_DRUG

Recommended diagnosis source codes:
  ICD10CM T2DM: E11.*
  ICD9CM  T2DM: 250.x0 OR 250.x2
  ICD10CM T1DM: E10.*
  ICD9CM  T1DM: 250.x1 OR 250.x3
  ICD10CM gestational DM: O24.4*
  ICD9CM  gestational DM: 648.8*
  ICD10CM secondary DM: E08.* OR E09.* OR E13.*
  ICD9CM  secondary DM: 249.*
*/

WITH condition_flags AS (
    SELECT
        co.person_id,

        COUNT(DISTINCT CASE
            WHEN csm.set_name = 'T2DM_DX'
            THEN co.condition_start_date
        END) AS t2dm_dx_dates,

        COUNT(DISTINCT CASE
            WHEN csm.set_name = 'T1DM_DX'
            THEN co.condition_start_date
        END) AS t1dm_dx_dates,

        COUNT(DISTINCT CASE
            WHEN csm.set_name = 'GESTATIONAL_DM_DX'
            THEN co.condition_start_date
        END) AS gestational_dm_dates,

        COUNT(DISTINCT CASE
            WHEN csm.set_name = 'SECONDARY_DM_DX'
            THEN co.condition_start_date
        END) AS secondary_dm_dates,

        MAX(CASE
            WHEN csm.set_name = 'CLASSIC_HYPERGLYCEMIA_SYMPTOM'
            THEN 1 ELSE 0
        END) AS has_classic_symptom,

        MAX(CASE
            WHEN csm.set_name = 'HYPERGLYCEMIC_CRISIS'
            THEN 1 ELSE 0
        END) AS has_hyperglycemic_crisis

    FROM condition_occurrence co
    JOIN concept_set_member csm
      ON csm.concept_id = co.condition_concept_id
    GROUP BY co.person_id
),

normalized_measurements AS (
    SELECT
        m.person_id,
        m.measurement_date,
        csm.set_name,

        CASE
            WHEN csm.set_name = 'HBA1C'
                 AND u.concept_name IN ('percent', '%')
                THEN m.value_as_number

            WHEN csm.set_name = 'HBA1C'
                 AND u.concept_name IN ('millimole per mole', 'mmol/mol')
                THEN m.value_as_number / 10.929

            WHEN csm.set_name <> 'HBA1C'
                 AND u.concept_name IN ('milligram per deciliter', 'mg/dL')
                THEN m.value_as_number

            WHEN csm.set_name <> 'HBA1C'
                 AND u.concept_name IN ('millimole per liter', 'mmol/L')
                THEN m.value_as_number * 18.0

            ELSE NULL
        END AS normalized_value

    FROM measurement m
    JOIN concept_set_member csm
      ON csm.concept_id = m.measurement_concept_id
     AND csm.set_name IN (
            'HBA1C',
            'FASTING_GLUCOSE',
            'TWO_HOUR_OGTT_GLUCOSE',
            'RANDOM_GLUCOSE'
         )
    LEFT JOIN concept u
      ON u.concept_id = m.unit_concept_id
    WHERE m.value_as_number IS NOT NULL
),

abnormal_lab_events AS (
    SELECT
        person_id,
        measurement_date,
        set_name,
        normalized_value,

        CASE
            WHEN set_name = 'HBA1C'
                 AND normalized_value >= 6.5
                THEN 1

            WHEN set_name = 'FASTING_GLUCOSE'
                 AND normalized_value >= 126
                THEN 1

            WHEN set_name = 'TWO_HOUR_OGTT_GLUCOSE'
                 AND normalized_value >= 200
                THEN 1

            WHEN set_name = 'RANDOM_GLUCOSE'
                 AND normalized_value >= 200
                THEN 1

            ELSE 0
        END AS is_abnormal

    FROM normalized_measurements
),

lab_flags AS (
    SELECT
        person_id,

        COUNT(DISTINCT CASE
            WHEN is_abnormal = 1
            THEN measurement_date
        END) AS abnormal_lab_dates,

        MAX(CASE
            WHEN set_name = 'RANDOM_GLUCOSE'
             AND normalized_value >= 200
            THEN 1 ELSE 0
        END) AS has_random_glucose_ge_200

    FROM abnormal_lab_events
    GROUP BY person_id
),

drug_flags AS (
    SELECT
        de.person_id,

        MAX(CASE
            WHEN csm.set_name = 'NON_INSULIN_ANTIHYPERGLYCEMIC_DRUG'
            THEN 1 ELSE 0
        END) AS has_non_insulin_antihyperglycemic,

        MAX(CASE
            WHEN csm.set_name = 'INSULIN_DRUG'
            THEN 1 ELSE 0
        END) AS has_insulin

    FROM drug_exposure de
    JOIN concept_set_member csm
      ON csm.concept_id = de.drug_concept_id
     AND csm.set_name IN (
            'NON_INSULIN_ANTIHYPERGLYCEMIC_DRUG',
            'INSULIN_DRUG'
         )
    GROUP BY de.person_id
),

patient_flags AS (
    SELECT
        p.person_id,

        COALESCE(cf.t2dm_dx_dates, 0) AS t2dm_dx_dates,
        COALESCE(cf.t1dm_dx_dates, 0) AS t1dm_dx_dates,
        COALESCE(cf.gestational_dm_dates, 0) AS gestational_dm_dates,
        COALESCE(cf.secondary_dm_dates, 0) AS secondary_dm_dates,
        COALESCE(cf.has_classic_symptom, 0) AS has_classic_symptom,
        COALESCE(cf.has_hyperglycemic_crisis, 0) AS has_hyperglycemic_crisis,

        COALESCE(lf.abnormal_lab_dates, 0) AS abnormal_lab_dates,
        COALESCE(lf.has_random_glucose_ge_200, 0) AS has_random_glucose_ge_200,

        COALESCE(df.has_non_insulin_antihyperglycemic, 0)
            AS has_non_insulin_antihyperglycemic,

        COALESCE(df.has_insulin, 0) AS has_insulin

    FROM person p
    LEFT JOIN condition_flags cf
      ON cf.person_id = p.person_id
    LEFT JOIN lab_flags lf
      ON lf.person_id = p.person_id
    LEFT JOIN drug_flags df
      ON df.person_id = p.person_id
),

classified AS (
    SELECT
        person_id,

        CASE
            WHEN
                NOT (
                    gestational_dm_dates >= 1
                    AND t2dm_dx_dates = 0
                    AND abnormal_lab_dates = 0
                )

                AND NOT (
                    secondary_dm_dates >= 1
                    AND t2dm_dx_dates = 0
                )

                AND NOT (
                    t1dm_dx_dates >= 2
                    AND t1dm_dx_dates > t2dm_dx_dates
                    AND has_non_insulin_antihyperglycemic = 0
                )

                AND (
                    t2dm_dx_dates >= 2

                    OR (
                        t2dm_dx_dates >= 1
                        AND (
                            abnormal_lab_dates >= 2
                            OR has_non_insulin_antihyperglycemic = 1
                        )
                    )

                    OR (
                        has_non_insulin_antihyperglycemic = 1
                        AND abnormal_lab_dates >= 2
                    )

                    OR (
                        has_random_glucose_ge_200 = 1
                        AND (
                            has_classic_symptom = 1
                            OR has_hyperglycemic_crisis = 1
                        )
                        AND (
                            t2dm_dx_dates >= 1
                            OR has_non_insulin_antihyperglycemic = 1
                        )
                    )
                )

            THEN 'T2DM_CASE'
            ELSE 'NOT_T2DM_CASE'
        END AS phenotype_status

    FROM patient_flags
)

SELECT
    person_id,
    phenotype_status
FROM classified
WHERE phenotype_status = 'T2DM_CASE';