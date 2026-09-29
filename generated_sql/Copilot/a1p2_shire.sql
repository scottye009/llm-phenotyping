
/* SHIRE / OMOP-lite rewrite of Copilot/alpha_2.sql
   - Remove concept joins (ICD/LOINC/RxNorm not available)
   - Use source fields & text matching
   - Output: person_id (as in original alpha_2 final)
*/

WITH
t2dm_dx AS (
  SELECT
    co.person_id,
    try_cast(co.condition_start_date AS DATE) AS dx_date
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'E11%'
    OR co.condition_source_value LIKE '250.%0'
    OR co.condition_source_value LIKE '250.%2'
),

t1dm_dx AS (
  SELECT DISTINCT co.person_id
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'E10%'
    OR co.condition_source_value LIKE '250.%1'
    OR co.condition_source_value LIKE '250.%3'
),

gest_dm_dx AS (
  SELECT DISTINCT co.person_id
  FROM memory.condition_occurrence co
  WHERE
    co.condition_source_value ILIKE 'O24%'
    OR co.condition_source_value ILIKE '648.8%'
    OR co.condition_source_value ILIKE 'P70.2%'
    OR co.condition_source_value ILIKE '249%'
    OR co.condition_source_value ILIKE 'E08%'
    OR co.condition_source_value ILIKE 'E09%'
    OR co.condition_source_value ILIKE 'E13%'
),

dm_meds AS (
  SELECT DISTINCT
    de.person_id,
    try_cast(COALESCE(de.drug_exposure_start_date, de.drug_exposure_start_datetime) AS DATE) AS med_date
  FROM memory.drug_exposure de
  WHERE
    (
      de.drug_source_value ILIKE '%metformin%'
      OR de.drug_source_value ILIKE '%glucophage%'
      OR de.drug_source_value ILIKE '%glumetza%'
      OR de.drug_source_value ILIKE '%fortamet%'
      OR de.drug_source_value ILIKE '%riomet%'
      OR de.drug_source_value ILIKE '%glipizide%'
      OR de.drug_source_value ILIKE '%glucotrol%'
      OR de.drug_source_value ILIKE '%glyburide%'
      OR de.drug_source_value ILIKE '%diabeta%'
      OR de.drug_source_value ILIKE '%micronase%'
      OR de.drug_source_value ILIKE '%glimepiride%'
      OR de.drug_source_value ILIKE '%amaryl%'
      OR de.drug_source_value ILIKE '%sitagliptin%'
      OR de.drug_source_value ILIKE '%januvia%'
      OR de.drug_source_value ILIKE '%saxagliptin%'
      OR de.drug_source_value ILIKE '%onglyza%'
      OR de.drug_source_value ILIKE '%linagliptin%'
      OR de.drug_source_value ILIKE '%tradjenta%'
      OR de.drug_source_value ILIKE '%alogliptin%'
      OR de.drug_source_value ILIKE '%nesina%'
      OR de.drug_source_value ILIKE '%exenatide%'
      OR de.drug_source_value ILIKE '%byetta%'
      OR de.drug_source_value ILIKE '%bydureon%'
      OR de.drug_source_value ILIKE '%liraglutide%'
      OR de.drug_source_value ILIKE '%victoza%'
      OR de.drug_source_value ILIKE '%dulaglutide%'
      OR de.drug_source_value ILIKE '%trulicity%'
      OR de.drug_source_value ILIKE '%semaglutide%'
      OR de.drug_source_value ILIKE '%ozempic%'
      OR de.drug_source_value ILIKE '%rybelsus%'
      OR de.drug_source_value ILIKE '%canagliflozin%'
      OR de.drug_source_value ILIKE '%invokana%'
      OR de.drug_source_value ILIKE '%dapagliflozin%'
      OR de.drug_source_value ILIKE '%farxiga%'
      OR de.drug_source_value ILIKE '%empagliflozin%'
      OR de.drug_source_value ILIKE '%jardiance%'
      OR de.drug_source_value ILIKE '%ertugliflozin%'
      OR de.drug_source_value ILIKE '%steglatro%'
      OR de.drug_source_value ILIKE '%insulin%'
    )
),

dm_labs_abnormal AS (
  SELECT DISTINCT
    m.person_id,
    try_cast(m.measurement_date AS DATE) AS lab_date
  FROM memory.measurement m
  WHERE
    m.value_as_number IS NOT NULL
    AND (
      (
        (m.measurement_source_value ILIKE '%hemoglobin a1c%'
         OR m.measurement_source_value ILIKE '%hba1c%'
         OR m.measurement_source_value ILIKE '%a1c%')
        AND m.value_as_number >= 6.5
      )
      OR
      (
        m.measurement_source_value ILIKE '%fast%'
        AND m.measurement_source_value ILIKE '%glucose%'
        AND m.value_as_number >= 126
      )
      OR
      (
        m.measurement_source_value ILIKE '%glucose%'
        AND m.value_as_number >= 200
      )
    )
),

patient_evidence AS (
  SELECT
    p.person_id,
    COUNT(DISTINCT t2.dx_date) AS n_t2dm_dx_dates,
    CASE WHEN EXISTS (SELECT 1 FROM dm_meds dm WHERE dm.person_id = p.person_id) THEN 1 ELSE 0 END AS has_dm_med,
    COUNT(DISTINCT dl.lab_date) AS n_abnormal_dm_labs,
    CASE WHEN EXISTS (SELECT 1 FROM t1dm_dx t1 WHERE t1.person_id = p.person_id) THEN 1 ELSE 0 END AS has_type1_dx,
    CASE WHEN EXISTS (SELECT 1 FROM gest_dm_dx g WHERE g.person_id = p.person_id) THEN 1 ELSE 0 END AS has_gest_or_secondary_dx
  FROM memory.person p
  LEFT JOIN t2dm_dx t2
    ON p.person_id = t2.person_id
  LEFT JOIN dm_labs_abnormal dl
    ON p.person_id = dl.person_id
  GROUP BY p.person_id
),

phenotype_logic AS (
  SELECT
    pe.*,
    CASE
      WHEN pe.n_t2dm_dx_dates >= 2 THEN 1
      WHEN pe.n_t2dm_dx_dates >= 1 AND pe.has_dm_med = 1 THEN 1
      ELSE 0
    END AS dx_t2dm_flag,
    CASE
      WHEN pe.n_abnormal_dm_labs >= 2 THEN 1
      ELSE 0
    END AS dm_lab_flag,
    CASE
      WHEN (pe.n_t2dm_dx_dates >= 2)
        OR (pe.n_t2dm_dx_dates >= 1 AND pe.has_dm_med = 1)
        OR (pe.n_abnormal_dm_labs >= 2 AND pe.has_dm_med = 1)
      THEN 1 ELSE 0
    END AS include_t2dm_flag,
    CASE
      WHEN (pe.has_type1_dx = 1 OR pe.has_gest_or_secondary_dx = 1)
           AND pe.n_t2dm_dx_dates = 0
      THEN 1 ELSE 0
    END AS exclude_non_t2dm_flag
  FROM patient_evidence pe
),

final_t2dm_cohort AS (
  SELECT person_id
  FROM phenotype_logic
  WHERE include_t2dm_flag = 1
    AND exclude_non_t2dm_flag = 0
)

SELECT *
FROM final_t2dm_cohort
;