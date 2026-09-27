/*==============================================================
  OMOP CDM v5.4 — Type 2 Diabetes Mellitus (T2DM) Phenotype
  Target DB: PostgreSQL (pgAdmin4), schema: public

  OUTPUT: person_id, index_date (earliest qualifying evidence date)
==============================================================*/

WITH
/*--------------------------
  1) Diagnosis concept sets (ICD9CM / ICD10CM)
--------------------------*/
t2dm_dx_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
    AND c.domain_id = 'Condition'
    AND (
      /* ICD-9-CM: 250.x0 or 250.x2 = Type II or unspecified type, not stated as uncontrolled/controlled detail handled by digits */
      (c.vocabulary_id = 'ICD9CM' AND (c.concept_code LIKE '250%0' OR c.concept_code LIKE '250%2'))
      /* ICD-10-CM: E11.* = Type 2 diabetes mellitus */
      OR (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E11%')
      /* Optional (less specific): E14.* unspecified diabetes — keep OFF unless you want broader capture */
      /* OR (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E14%') */
    )
),
t1dm_dx_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
    AND c.domain_id = 'Condition'
    AND (
      /* ICD-9-CM: 250.x1 or 250.x3 = Type I */
      (c.vocabulary_id = 'ICD9CM' AND (c.concept_code LIKE '250%1' OR c.concept_code LIKE '250%3'))
      /* ICD-10-CM: E10.* = Type 1 */
      OR (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E10%')
    )
),
gestational_dx_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id = 'ICD10CM'
    AND c.domain_id = 'Condition'
    AND c.concept_code LIKE 'O24%'
),
secondary_diabetes_dx_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id = 'ICD10CM'
    AND c.domain_id = 'Condition'
    AND (
      /* E08 = diabetes due to underlying condition; E09 = drug/chemical induced */
      c.concept_code LIKE 'E08%' OR c.concept_code LIKE 'E09%'
      /* Optional: E13 = other specified diabetes (often secondary/other); decide if you want to exclude */
      OR c.concept_code LIKE 'E13%'
    )
),

/*--------------------------
  2) Evidence tables: conditions
--------------------------*/
t2dm_dx AS (
  SELECT
    co.person_id,
    co.condition_start_date AS dx_date
  FROM public.condition_occurrence co
  WHERE co.condition_source_concept_id IN (SELECT concept_id FROM t2dm_dx_concepts)
),
t1dm_dx AS (
  SELECT DISTINCT co.person_id
  FROM public.condition_occurrence co
  WHERE co.condition_source_concept_id IN (SELECT concept_id FROM t1dm_dx_concepts)
),
gest_dx AS (
  SELECT DISTINCT co.person_id
  FROM public.condition_occurrence co
  WHERE co.condition_source_concept_id IN (SELECT concept_id FROM gestational_dx_concepts)
),
sec_dx AS (
  SELECT DISTINCT co.person_id
  FROM public.condition_occurrence co
  WHERE co.condition_source_concept_id IN (SELECT concept_id FROM secondary_diabetes_dx_concepts)
),

/*--------------------------
  3) Medication concepts: non-insulin anti-hyperglycemics (RxNorm)
     Use BOTH generic and brand names (strings), resolve via concept_name ILIKE.
--------------------------*/
antidiabetic_name_list AS (
  SELECT drug_name FROM (VALUES
    /* Biguanide */
    ('metformin'), ('glucophage'), ('fortamet'), ('glumetza'), ('riomet'),
    /* Sulfonylureas */
    ('glipizide'), ('glucotrol'), ('glucotrol xl'),
    ('glyburide'), ('diabeta'), ('micronase'), ('glynase'),
    ('glimepiride'), ('amaryl'),
    /* Thiazolidinediones */
    ('pioglitazone'), ('actos'),
    ('rosiglitazone'), ('avandia'),
    /* DPP-4 inhibitors */
    ('sitagliptin'), ('januvia'),
    ('saxagliptin'), ('onglyza'),
    ('linagliptin'), ('tradjenta'),
    ('alogliptin'), ('nesina'),
    /* GLP-1 receptor agonists */
    ('exenatide'), ('byetta'), ('bydureon'),
    ('liraglutide'), ('victoza'),
    ('dulaglutide'), ('trulicity'),
    ('semaglutide'), ('ozempic'), ('rybelsus'),
    ('lixisenatide'), ('adlyxin'),
    ('tirzepatide'), ('mounjaro'),
    /* SGLT2 inhibitors */
    ('canagliflozin'), ('invokana'),
    ('dapagliflozin'), ('farxiga'),
    ('empagliflozin'), ('jardiance'),
    ('ertugliflozin'), ('steglatro'),
    /* Meglitinides */
    ('repaglinide'), ('prandin'),
    ('nateglinide'), ('starlix'),
    /* Alpha-glucosidase inhibitors */
    ('acarbose'), ('precose'),
    ('miglitol'), ('glyset'),
    /* Amylin analog */
    ('pramlintide'), ('symlin'),
    /* Combination products (common) */
    ('janumet'), ('jardiance'), ('synjardy'), ('xigduo'), ('glyxambi'), ('qtern'), ('ste glujan') /* ok if not found */
  ) v(drug_name)
),
antidiabetic_drug_concepts AS (
  SELECT DISTINCT c.concept_id
  FROM public.concept c
  JOIN antidiabetic_name_list nl
    ON c.domain_id = 'Drug'
   AND c.standard_concept = 'S'
   AND c.vocabulary_id IN ('RxNorm','RxNorm Extension')
   AND c.concept_name ILIKE ('%' || nl.drug_name || '%')
),
antidiabetic_drug AS (
  SELECT
    de.person_id,
    de.drug_exposure_start_date AS drug_date
  FROM public.drug_exposure de
  WHERE de.drug_concept_id IN (SELECT concept_id FROM antidiabetic_drug_concepts)
),

/*--------------------------
  4) Lab concepts (LOINC via Measurement)
     Thresholds consistent with diagnostic criteria:
       - HbA1c >= 6.5 %
       - Fasting plasma glucose >= 126 mg/dL
       - Random plasma glucose >= 200 mg/dL
       - 2-hr OGTT glucose >= 200 mg/dL
--------------------------*/
a1c_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.domain_id = 'Measurement'
    AND c.vocabulary_id = 'LOINC'
    AND c.concept_name ILIKE '%hemoglobin a1c%'
),
fasting_glucose_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.domain_id = 'Measurement'
    AND c.vocabulary_id = 'LOINC'
    AND (
      c.concept_name ILIKE '%glucose%fasting%'
      OR c.concept_name ILIKE '%fasting%glucose%'
    )
),
random_glucose_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.domain_id = 'Measurement'
    AND c.vocabulary_id = 'LOINC'
    AND (
      c.concept_name ILIKE '%glucose%random%'
      OR (c.concept_name ILIKE '%glucose%' AND c.concept_name ILIKE '%plasma%')
    )
),
ogtt_2hr_concepts AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.domain_id = 'Measurement'
    AND c.vocabulary_id = 'LOINC'
    AND (
      c.concept_name ILIKE '%glucose%2 hour%'
      OR c.concept_name ILIKE '%glucose%2h%'
      OR c.concept_name ILIKE '%oral glucose tolerance%'
    )
),
abnormal_diabetes_labs AS (
  SELECT
    m.person_id,
    m.measurement_date AS lab_date
  FROM public.measurement m
  WHERE m.value_as_number IS NOT NULL
    AND (
      /* HbA1c >= 6.5% */
      (m.measurement_concept_id IN (SELECT concept_id FROM a1c_concepts) AND m.value_as_number >= 6.5)

      /* Fasting plasma glucose >= 126 mg/dL */
      OR (m.measurement_concept_id IN (SELECT concept_id FROM fasting_glucose_concepts) AND m.value_as_number >= 126)

      /* Random plasma glucose >= 200 mg/dL (symptoms not enforced here) */
      OR (m.measurement_concept_id IN (SELECT concept_id FROM random_glucose_concepts) AND m.value_as_number >= 200)

      /* 2-hr OGTT glucose >= 200 mg/dL */
      OR (m.measurement_concept_id IN (SELECT concept_id FROM ogtt_2hr_concepts) AND m.value_as_number >= 200)
    )
),

/*--------------------------
  5) Person-level feature aggregation
--------------------------*/
features AS (
  SELECT
    p.person_id,

    /* counts of distinct evidence dates */
    COALESCE((SELECT COUNT(DISTINCT dx_date) FROM t2dm_dx d WHERE d.person_id = p.person_id), 0) AS n_t2_dx_dates,
    COALESCE((SELECT COUNT(DISTINCT drug_date) FROM antidiabetic_drug a WHERE a.person_id = p.person_id), 0) AS n_antidiab_drug_dates,
    COALESCE((SELECT COUNT(DISTINCT lab_date) FROM abnormal_diabetes_labs l WHERE l.person_id = p.person_id), 0) AS n_abnl_lab_dates,

    /* earliest evidence dates (for index) */
    (SELECT MIN(dx_date)   FROM t2dm_dx d WHERE d.person_id = p.person_id) AS first_t2_dx_date,
    (SELECT MIN(drug_date) FROM antidiabetic_drug a WHERE a.person_id = p.person_id) AS first_drug_date,
    (SELECT MIN(lab_date)  FROM abnormal_diabetes_labs l WHERE l.person_id = p.person_id) AS first_lab_date

  FROM public.person p
),

/*--------------------------
  6) Apply phenotype logic using AND / OR / NOT
--------------------------*/
classified AS (
  SELECT
    f.person_id,

    /* index date = earliest qualifying evidence among dx/drug/lab used in any rule */
    LEAST(
      COALESCE(f.first_t2_dx_date, DATE '9999-12-31'),
      COALESCE(f.first_drug_date,  DATE '9999-12-31'),
      COALESCE(f.first_lab_date,   DATE '9999-12-31')
    ) AS index_date

  FROM features f
  WHERE
    /* -------- Inclusion: (Rule A OR Rule B OR Rule C OR Rule D) -------- */
    (
      /* Rule A: >=2 T2DM diagnosis dates */
      (f.n_t2_dx_dates >= 2)

      OR
      /* Rule B: >=1 T2DM diagnosis AND >=1 antidiabetic medication */
      (f.n_t2_dx_dates >= 1 AND f.n_antidiab_drug_dates >= 1)

      OR
      /* Rule C: >=1 T2DM diagnosis AND >=1 abnormal diabetes lab */
      (f.n_t2_dx_dates >= 1 AND f.n_abnl_lab_dates >= 1)

      OR
      /* Rule D: >=2 abnormal labs AND >=1 antidiabetic medication (captures “lab+med” without coded dx) */
      (f.n_abnl_lab_dates >= 2 AND f.n_antidiab_drug_dates >= 1)
    )

    /* -------- Exclusion: NOT (Type 1 OR Gestational OR Secondary diabetes) -------- */
    AND NOT EXISTS (SELECT 1 FROM t1dm_dx  x WHERE x.person_id = f.person_id)
    AND NOT EXISTS (SELECT 1 FROM gest_dx g WHERE g.person_id = f.person_id)
    AND NOT EXISTS (SELECT 1 FROM sec_dx  s WHERE s.person_id = f.person_id)
)

SELECT
  c.person_id,
  c.index_date
FROM classified c
WHERE c.index_date <> DATE '9999-12-31'
ORDER BY c.index_date, c.person_id;




