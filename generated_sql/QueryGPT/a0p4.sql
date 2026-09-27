/* ============================================================
   TYPE 2 DIABETES MELLITUS PHENOTYPE
   OMOP CDM research cohort definition
   ============================================================ */

WITH
/* ------------------------------------------------------------
   1. Observation window
   Recommended: require sufficient observable history.
   ------------------------------------------------------------ */
eligible_population AS (
    SELECT
        p.person_id
    FROM person p
    JOIN observation_period op
      ON op.person_id = p.person_id
    WHERE DATEADD(
              day,
              -365,
              op.observation_period_end_date
          ) >= op.observation_period_start_date
),

/* ------------------------------------------------------------
   2. Diagnosis evidence
   Each concept-set table contains OMOP standard concept IDs
   and descendants resolved from ICD source-code mappings.

   cs_t2dm_condition:
       ICD9CM  250.x0 OR 250.x2
       NOT ICD9CM 250.10 OR 250.12
       OR ICD10CM E11.*

   cs_t1dm_condition:
       ICD9CM 250.x1 OR 250.x3
       OR ICD10CM E10.*

   cs_secondary_dm_condition:
       ICD10CM E08.* OR E09.* OR E13.*

   cs_gestational_dm_condition:
       ICD10CM O24.*
   ------------------------------------------------------------ */
dx AS (
    SELECT
        co.person_id,

        COUNT(DISTINCT CASE
            WHEN co.condition_concept_id IN (
                SELECT concept_id FROM cs_t2dm_condition
            )
            THEN co.condition_start_date
        END) AS t2dm_dx_date_count,

        COUNT(DISTINCT CASE
            WHEN co.condition_concept_id IN (
                SELECT concept_id FROM cs_t2dm_condition
            )
            AND co.condition_type_concept_id IN (
                SELECT concept_id FROM cs_clinician_entered_condition_type
            )
            THEN co.condition_start_date
        END) AS t2dm_clinician_dx_date_count,

        COUNT(DISTINCT CASE
            WHEN co.condition_concept_id IN (
                SELECT concept_id FROM cs_t1dm_condition
            )
            THEN co.condition_start_date
        END) AS t1dm_dx_date_count,

        COUNT(DISTINCT CASE
            WHEN co.condition_concept_id IN (
                SELECT concept_id FROM cs_secondary_dm_condition
            )
            THEN co.condition_start_date
        END) AS secondary_dm_dx_date_count,

        COUNT(DISTINCT CASE
            WHEN co.condition_concept_id IN (
                SELECT concept_id FROM cs_gestational_dm_condition
            )
            THEN co.condition_start_date
        END) AS gestational_dm_dx_date_count

    FROM condition_occurrence co
    GROUP BY co.person_id
),

/* ------------------------------------------------------------
   3. Medication evidence

   cs_non_insulin_dm_drug:
       standard RxNorm ingredient concepts and descendants:
       metformin (Glucophage, Glumetza, Fortamet, Riomet)
       glipizide (Glucotrol)
       glyburide (DiaBeta, Glynase, Micronase)
       glimepiride (Amaryl)
       repaglinide (Prandin)
       nateglinide (Starlix)
       pioglitazone (Actos)
       rosiglitazone (Avandia)
       acarbose (Precose)
       miglitol (Glyset)
       sitagliptin (Januvia)
       saxagliptin (Onglyza)
       linagliptin (Tradjenta)
       alogliptin (Nesina)
       canagliflozin (Invokana)
       dapagliflozin (Farxiga)
       empagliflozin (Jardiance)
       ertugliflozin (Steglatro)
       exenatide (Byetta, Bydureon)
       liraglutide (Victoza)
       dulaglutide (Trulicity)
       semaglutide (Ozempic, Rybelsus)
       lixisenatide (Adlyxin)
       tirzepatide (Mounjaro)
       colesevelam (Welchol)
       bromocriptine-QR (Cycloset)
       plus historical diabetes drugs

   cs_insulin_or_pramlintide_drug:
       insulin products OR pramlintide (Symlin)
   ------------------------------------------------------------ */
rx AS (
    SELECT
        de.person_id,

        MIN(CASE
            WHEN de.drug_concept_id IN (
                SELECT concept_id FROM cs_non_insulin_dm_drug
            )
            THEN de.drug_exposure_start_date
        END) AS first_non_insulin_dm_drug_date,

        MIN(CASE
            WHEN de.drug_concept_id IN (
                SELECT concept_id FROM cs_insulin_or_pramlintide_drug
            )
            THEN de.drug_exposure_start_date
        END) AS first_insulin_or_pramlintide_date

    FROM drug_exposure de
    GROUP BY de.person_id
),

/* ------------------------------------------------------------
   4. Laboratory evidence

   cs_hba1c_measurement:
       LOINC 4548-4 OR 17856-6 OR 4549-2 OR 17855-8
       OR locally validated equivalent concepts

   cs_fasting_glucose_measurement:
       LOINC 1558-6 OR locally validated equivalents

   cs_random_glucose_measurement:
       LOINC 2339-0 OR 2345-7 OR locally validated equivalents

   cs_two_hour_ogtt_measurement:
       validated 2-hour post-glucose-load concepts

   Normalize units before this CTE when required.
   ------------------------------------------------------------ */
abnormal_labs AS (
    SELECT
        m.person_id,
        CAST(m.measurement_date AS DATE) AS abnormal_lab_date
    FROM measurement m
    WHERE
           (
               m.measurement_concept_id IN (
                   SELECT concept_id FROM cs_hba1c_measurement
               )
               AND m.value_as_number >= 6.5
           )
        OR (
               m.measurement_concept_id IN (
                   SELECT concept_id FROM cs_fasting_glucose_measurement
               )
               AND m.value_as_number >= 126
           )
        OR (
               m.measurement_concept_id IN (
                   SELECT concept_id FROM cs_random_glucose_measurement
               )
               AND m.value_as_number >= 200
           )
        OR (
               m.measurement_concept_id IN (
                   SELECT concept_id FROM cs_two_hour_ogtt_measurement
               )
               AND m.value_as_number >= 200
           )
),

lab_summary AS (
    SELECT
        person_id,
        COUNT(DISTINCT abnormal_lab_date) AS abnormal_lab_date_count
    FROM abnormal_labs
    GROUP BY person_id
),

/* ------------------------------------------------------------
   5. Classic hyperglycemia symptoms
   cs_classic_hyperglycemia_symptom includes standard OMOP
   concepts and descendants for:
       polyuria OR polydipsia OR unexplained weight loss
       OR hyperglycemic crisis
   ------------------------------------------------------------ */
symptomatic_random_glucose AS (
    SELECT DISTINCT
        m.person_id
    FROM measurement m
    WHERE
        m.measurement_concept_id IN (
            SELECT concept_id FROM cs_random_glucose_measurement
        )
        AND m.value_as_number >= 200
        AND EXISTS (
            SELECT 1
            FROM condition_occurrence symptom
            WHERE symptom.person_id = m.person_id
              AND symptom.condition_concept_id IN (
                  SELECT concept_id
                  FROM cs_classic_hyperglycemia_symptom
              )
              AND symptom.condition_start_date
                  BETWEEN DATEADD(day, -30, m.measurement_date)
                      AND DATEADD(day,  30, m.measurement_date)
        )
),

/* ------------------------------------------------------------
   6. Assemble derived flags
   ------------------------------------------------------------ */
flags AS (
    SELECT
        ep.person_id,

        COALESCE(dx.t2dm_dx_date_count, 0)
            AS t2dm_dx_date_count,

        COALESCE(dx.t2dm_clinician_dx_date_count, 0)
            AS t2dm_clinician_dx_date_count,

        COALESCE(dx.t1dm_dx_date_count, 0)
            AS t1dm_dx_date_count,

        rx.first_non_insulin_dm_drug_date,
        rx.first_insulin_or_pramlintide_date,

        CASE
            WHEN COALESCE(ls.abnormal_lab_date_count, 0) >= 1
            THEN 1 ELSE 0
        END AS has_any_abnormal_diabetes_lab,

        CASE
            WHEN COALESCE(ls.abnormal_lab_date_count, 0) >= 2
              OR srg.person_id IS NOT NULL
            THEN 1 ELSE 0
        END AS has_confirmed_diabetes_lab,

        CASE
            WHEN srg.person_id IS NOT NULL
            THEN 1 ELSE 0
        END AS has_symptomatic_random_glucose,

        CASE
            WHEN COALESCE(dx.gestational_dm_dx_date_count, 0) > 0
             AND COALESCE(dx.t2dm_dx_date_count, 0) = 0
            THEN 1 ELSE 0
        END AS has_gestational_only_diabetes,

        CASE
            WHEN COALESCE(dx.secondary_dm_dx_date_count, 0) > 0
             AND COALESCE(dx.t2dm_dx_date_count, 0) = 0
            THEN 1 ELSE 0
        END AS has_secondary_only_diabetes

    FROM eligible_population ep
    LEFT JOIN dx
      ON dx.person_id = ep.person_id
    LEFT JOIN rx
      ON rx.person_id = ep.person_id
    LEFT JOIN lab_summary ls
      ON ls.person_id = ep.person_id
    LEFT JOIN symptomatic_random_glucose srg
      ON srg.person_id = ep.person_id
),

classified AS (
    SELECT
        f.*,

        CASE
            WHEN f.t1dm_dx_date_count >= 2
             AND (
                    f.first_non_insulin_dm_drug_date IS NULL
                 OR f.first_insulin_or_pramlintide_date
                    <= f.first_non_insulin_dm_drug_date
             )
             AND f.t2dm_clinician_dx_date_count < 2
            THEN 1 ELSE 0
        END AS has_strong_t1dm_pattern

    FROM flags f
)

/* ------------------------------------------------------------
   7. Final T2DM phenotype
   ------------------------------------------------------------ */
SELECT
    person_id,
    'T2DM_CASE' AS phenotype_status
FROM classified
WHERE
    (
           /* PATH A: repeated T2DM diagnoses */
           t2dm_dx_date_count >= 2

        OR /* PATH B: diagnosis AND abnormal laboratory result */
           (
               t2dm_dx_date_count >= 1
               AND has_any_abnormal_diabetes_lab = 1
           )

        OR /* PATH C: diagnosis AND non-insulin diabetes drug */
           (
               t2dm_dx_date_count >= 1
               AND first_non_insulin_dm_drug_date IS NOT NULL
           )

        OR /* PATH D: medication AND confirmed laboratory evidence */
           (
               first_non_insulin_dm_drug_date IS NOT NULL
               AND has_confirmed_diabetes_lab = 1
           )

        OR /* PATH E: symptomatic hyperglycemia */
           (
               has_symptomatic_random_glucose = 1
           )
    )
    AND NOT (
        has_gestational_only_diabetes = 1
    )
    AND NOT (
        has_secondary_only_diabetes = 1
    )
    AND NOT (
        has_strong_t1dm_pattern = 1
    );

    --error