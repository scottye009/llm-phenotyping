/* Type 2 Diabetes Mellitus phenotype — OMOP CDM v5.4 */

/* Step 1: Critical criteria
   A. T2DM diagnosis codes
   B. Diabetes-range labs
   C. Antihyperglycemic medication exposure
   D. Exclude likely Type 1 DM, gestational diabetes, secondary diabetes
*/

/* ICD diagnosis concepts */
T2DM_DX AS (
  -- ICD9CM: 250.x0, 250.x2
  -- ICD10CM: E11.*
  SELECT concept_id
  FROM concept
  WHERE vocabulary_id IN ('ICD9CM', 'ICD10CM')
    AND (
      concept_code LIKE '250.%0'
      OR concept_code LIKE '250.%2'
      OR concept_code LIKE 'E11%'
    )
),

EXCLUDE_DX AS (
  -- Type 1 diabetes: ICD9CM 250.x1, 250.x3; ICD10CM E10.*
  -- Gestational diabetes: ICD9CM 648.8x; ICD10CM O24.4*
  -- Secondary diabetes: ICD10CM E08.*, E09.*, E13.*
  SELECT concept_id
  FROM concept
  WHERE vocabulary_id IN ('ICD9CM', 'ICD10CM')
    AND (
      concept_code LIKE '250.%1'
      OR concept_code LIKE '250.%3'
      OR concept_code LIKE 'E10%'
      OR concept_code LIKE '648.8%'
      OR concept_code LIKE 'O24.4%'
      OR concept_code LIKE 'E08%'
      OR concept_code LIKE 'E09%'
      OR concept_code LIKE 'E13%'
    )
),

T2DM_LABS AS (
  /* Diabetes-range labs:
     HbA1c >= 6.5%
     fasting glucose >= 126 mg/dL
     random glucose >= 200 mg/dL
     oral glucose tolerance test 2-hour glucose >= 200 mg/dL
  */
  SELECT person_id, measurement_date
  FROM measurement
  WHERE (
        measurement_concept_id IN (
          /* HbA1c, fasting glucose, random glucose, OGTT glucose OMOP concepts */
          SELECT concept_id
          FROM concept
          WHERE vocabulary_id IN ('LOINC')
            AND concept_code IN (
              '4548-4',   -- Hemoglobin A1c/Hemoglobin.total
              '1558-6',   -- Fasting glucose
              '2345-7',   -- Glucose [Mass/volume] in Serum or Plasma
              '20436-2'   -- Glucose 2 hour post dose
            )
        )
      )
    AND (
         value_as_number >= 6.5
         OR value_as_number >= 126
         OR value_as_number >= 200
    )
),

T2DM_MED AS (
  /* Non-insulin antihyperglycemic medications.
     Generic and brand examples included.
  */
  SELECT person_id, drug_exposure_start_date
  FROM drug_exposure de
  JOIN concept c
    ON de.drug_concept_id = c.concept_id
  WHERE LOWER(c.concept_name) SIMILAR TO
    '%(metformin|glucophage|glumetza|fortamet|
       glipizide|glucotrol|
       glyburide|diabeta|glynase|micronase|
       glimepiride|amaryl|
       pioglitazone|actos|
       rosiglitazone|avandia|
       sitagliptin|januvia|
       saxagliptin|onglyza|
       linagliptin|tradjenta|
       alogliptin|nesina|
       empagliflozin|jardiance|
       dapagliflozin|farxiga|
       canagliflozin|invokana|
       ertugliflozin|steglatro|
       liraglutide|victoza|
       semaglutide|ozempic|rybelsus|
       dulaglutide|trulicity|
       exenatide|byetta|bydureon|
       tirzepatide|mounjaro|
       acarbose|precose|
       miglitol|glyset|
       repaglinide|prandin|
       nateglinide|starlix)%'
),

T2DM_CASES AS (
  SELECT person_id
  FROM person p
  WHERE
    (
      /* Inclusion: diagnosis OR lab OR medication evidence */
      EXISTS (
        SELECT 1
        FROM condition_occurrence co
        JOIN T2DM_DX dx
          ON co.condition_source_concept_id = dx.concept_id
        WHERE co.person_id = p.person_id
        GROUP BY co.person_id
        HAVING COUNT(*) >= 2
      )

      OR EXISTS (
        SELECT 1
        FROM T2DM_LABS l
        WHERE l.person_id = p.person_id
        GROUP BY l.person_id
        HAVING COUNT(*) >= 2
      )

      OR EXISTS (
        SELECT 1
        FROM T2DM_MED m
        WHERE m.person_id = p.person_id
      )
    )

    AND NOT EXISTS (
      /* Exclusion: likely Type 1, gestational, secondary diabetes */
      SELECT 1
      FROM condition_occurrence co
      JOIN EXCLUDE_DX ex
        ON co.condition_source_concept_id = ex.concept_id
      WHERE co.person_id = p.person_id
    )
)

/* Final phenotype */
SELECT DISTINCT person_id
FROM T2DM_CASES;--error