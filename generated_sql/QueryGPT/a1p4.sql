-- ================================
-- TYPE 2 DIABETES PHENOTYPE (OMOP CDM)
-- Schema: public
-- ================================

WITH
-- --------------------------------
-- 0) Adults
-- --------------------------------
adults AS (
  SELECT p.person_id
  FROM public.person p
  WHERE (EXTRACT(YEAR FROM AGE(COALESCE(p.death_datetime, CURRENT_DATE), p.birth_datetime)) >= 18)
),

-- --------------------------------
-- 1) DIAGNOSIS CONCEPT SETS (ICD9CM/ICD10CM -> SNOMED)
-- --------------------------------
-- T2DM source ICD codes
t2dm_icd_source AS (
  SELECT c.concept_id AS source_concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('ICD10CM','ICD9CM')
    AND (
      -- ICD10CM E11.*
      (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E11%')
      OR
      -- ICD9CM 250.x0 or 250.x2 (T2DM)
      (c.vocabulary_id = 'ICD9CM'  AND (c.concept_code LIKE '250.%0' OR c.concept_code LIKE '250.%2'))
    )
    AND c.invalid_reason IS NULL
),
-- T1DM (exclusion)
t1dm_icd_source AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id IN ('ICD10CM','ICD9CM')
    AND (
      (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E10%')
      OR
      (c.vocabulary_id = 'ICD9CM'  AND (c.concept_code LIKE '250.%1' OR c.concept_code LIKE '250.%3'))
    )
    AND c.invalid_reason IS NULL
),
-- Gestational (exclusion)
gest_dm_icd_source AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id = 'ICD10CM'
    AND c.concept_code LIKE 'O24.4%'  -- gestational
    AND c.invalid_reason IS NULL
),
-- Secondary/other specified diabetes (exclusion)
secondary_dm_icd_source AS (
  SELECT c.concept_id
  FROM public.concept c
  WHERE c.vocabulary_id = 'ICD10CM'
    AND (c.concept_code LIKE 'E08%' OR c.concept_code LIKE 'E09%' OR c.concept_code LIKE 'E13%')
    AND c.invalid_reason IS NULL
),

-- Map ICD source codes to STANDARD SNOMED via 'Maps to', then include descendants (to be safe)
map_to_standard AS (
  SELECT s.source_concept_id, cr.concept_id_2 AS standard_concept_id
  FROM (
    SELECT source_concept_id FROM t2dm_icd_source
    UNION ALL
    SELECT concept_id FROM t1dm_icd_source
    UNION ALL
    SELECT concept_id FROM gest_dm_icd_source
    UNION ALL
    SELECT concept_id FROM secondary_dm_icd_source
  ) s
  JOIN public.concept_relationship cr
    ON cr.concept_id_1 = s.source_concept_id
   AND cr.relationship_id = 'Maps to'
   AND cr.invalid_reason IS NULL
  JOIN public.concept cs ON cs.concept_id = cr.concept_id_2
   AND cs.standard_concept = 'S'
   AND cs.invalid_reason IS NULL
),
-- Expand to descendants in SNOMED
dx_sets AS (
  SELECT 'T2DM' AS set_name, ca.descendant_concept_id AS concept_id
  FROM map_to_standard m
  JOIN t2dm_icd_source t ON t.source_concept_id = m.source_concept_id
  JOIN public.concept_ancestor ca ON ca.ancestor_concept_id = m.standard_concept_id

  UNION
  SELECT 'T1DM', ca.descendant_concept_id
  FROM map_to_standard m
  JOIN t1dm_icd_source t ON t.concept_id = m.source_concept_id
  JOIN public.concept_ancestor ca ON ca.ancestor_concept_id = m.standard_concept_id

  UNION
  SELECT 'GEST', ca.descendant_concept_id
  FROM map_to_standard m
  JOIN gest_dm_icd_source t ON t.concept_id = m.source_concept_id
  JOIN public.concept_ancestor ca ON ca.ancestor_concept_id = m.standard_concept_id

  UNION
  SELECT 'SECONDARY', ca.descendant_concept_id
  FROM map_to_standard m
  JOIN secondary_dm_icd_source t ON t.concept_id = m.source_concept_id
  JOIN public.concept_ancestor ca ON ca.ancestor_concept_id = m.standard_concept_id
),

-- Concrete diagnosis events
dx_t2 AS (
  SELECT co.person_id, DATE(co.condition_start_date) AS dx_date
  FROM public.condition_occurrence co
  JOIN dx_sets d ON d.concept_id = co.condition_concept_id
  WHERE d.set_name = 'T2DM'
),
dx_t1 AS (
  SELECT co.person_id, DATE(co.condition_start_date) AS dx_date
  FROM public.condition_occurrence co
  JOIN dx_sets d ON d.concept_id = co.condition_concept_id
  WHERE d.set_name = 'T1DM'
),
dx_gest AS (
  SELECT co.person_id, DATE(co.condition_start_date) AS dx_date
  FROM public.condition_occurrence co
  JOIN dx_sets d ON d.concept_id = co.condition_concept_id
  WHERE d.set_name = 'GEST'
),
dx_secondary AS (
  SELECT co.person_id, DATE(co.condition_start_date) AS dx_date
  FROM public.condition_occurrence co
  JOIN dx_sets d ON d.concept_id = co.condition_concept_id
  WHERE d.set_name = 'SECONDARY'
),

-- --------------------------------
-- 2) MEDICATION CONCEPT SETS (RxNorm Ingredients & Brand Names -> descendants)
-- --------------------------------
-- Seed list: add/adjust as needed.
seed_drug_names AS (
  SELECT unnest(ARRAY[
    -- Biguanide
    'metformin', 'Glucophage', 'Glumetza', 'Fortamet', 'Riomet',
    -- Sulfonylureas
    'glipizide','Glucotrol','glyburide','Diabeta','Micronase','glimepiride','Amaryl',
    -- TZDs
    'pioglitazone','Actos','rosiglitazone','Avandia',
    -- DPP-4
    'sitagliptin','Januvia','saxagliptin','Onglyza','linagliptin','Tradjenta','alogliptin','Nesina',
    -- GLP-1 / GIP
    'exenatide','Byetta','Bydureon','liraglutide','Victoza','dulaglutide','Trulicity',
    'semaglutide','Ozempic','Rybelsus','tirzepatide','Mounjaro',
    -- SGLT2
    'canagliflozin','Invokana','dapagliflozin','Farxiga','empagliflozin','Jardiance','ertugliflozin','Steglatro',
    -- Insulin (brands vary; include generic class word to seed)
    'insulin'
  ]) AS name
),
seed_drug_concepts AS (
  SELECT DISTINCT c.concept_id
  FROM seed_drug_names s
  JOIN public.concept c
    ON c.vocabulary_id = 'RxNorm'
   AND c.invalid_reason IS NULL
   AND (
      c.concept_class_id IN ('Ingredient','Brand Name','Clinical Drug','Branded Drug')
      OR c.concept_name ILIKE '%insulin%'
   )
   AND (
      c.concept_name ILIKE s.name || '%'
      OR '%' || s.name || '%' ILIKE '%' || c.concept_name || '%'  -- loose match
      OR c.concept_name ILIKE '%' || s.name || '%'
   )
),
drug_descendants AS (
  SELECT DISTINCT ca.descendant_concept_id AS concept_id
  FROM seed_drug_concepts s
  JOIN public.concept_ancestor ca
    ON ca.ancestor_concept_id = s.concept_id
),
rx_t2 AS (
  SELECT de.person_id, DATE(de.drug_exposure_start_date) AS rx_date
  FROM public.drug_exposure de
  JOIN drug_descendants d ON d.concept_id = de.drug_concept_id
),

-- --------------------------------
-- 3) LAB CONCEPT SETS (LOINC)
-- --------------------------------
-- Build LOINC sets by code and name pattern to be robust. Add more LOINCs as needed.
loinc_seed AS (
  SELECT * FROM (VALUES
    -- HbA1c common LOINCs
    ('4548-4'), ('17856-6'), ('41995-2'), ('59261-8'),
    -- Glucose (fasting/random/OGTT) - representative seeds; expand as needed
    ('1558-6'),  -- Glucose [Moles/volume] in Serum/Plasma—Fasting
    ('2345-7'),  -- Glucose [Mass/volume] in Serum/Plasma
    ('14771-0'), -- Glucose [Moles/volume] in Blood—2 hours post 75 g glucose
    ('12607-8')  -- Glucose [Mass/volume] in Serum/Plasma—2 hours post 75 g glucose
  ) AS t(code)
),
lab_concepts AS (
  SELECT DISTINCT c.concept_id,
         CASE
           WHEN c.concept_name ILIKE '%hemoglobin a1c%' THEN 'A1C'
           WHEN c.concept_name ILIKE '%glucose%' AND c.concept_name ILIKE '%fast%' THEN 'FPG'
           WHEN c.concept_name ILIKE '%glucose%' AND c.concept_name ILIKE '%2 hour%' THEN 'OGTT'
           WHEN c.concept_name ILIKE '%glucose%' THEN 'RPG'
         END AS lab_type
  FROM public.concept c
  WHERE c.vocabulary_id = 'LOINC'
    AND c.invalid_reason IS NULL
    AND (
      c.concept_code IN (SELECT code FROM loinc_seed)
      OR c.concept_name ILIKE '%Hemoglobin A1c%'
      OR (c.concept_name ILIKE '%Glucose%' AND c.concept_class_id IN ('Laboratory Test'))
    )
),
-- Measurement events
labs AS (
  SELECT m.person_id,
         DATE(m.measurement_date) AS lab_date,
         m.value_as_number,
         lc.lab_type,
         m.unit_concept_id,
         m.unit_source_value
  FROM public.measurement m
  JOIN lab_concepts lc ON lc.concept_id = m.measurement_concept_id
  WHERE m.value_as_number IS NOT NULL
),
-- Apply thresholds (assumes standard units: A1C in %, glucose in mg/dL; adjust if your ETL differs)
abnl_a1c AS (
  SELECT person_id, lab_date
  FROM labs
  WHERE lab_type = 'A1C' AND value_as_number >= 6.5
),
abnl_fpg AS (
  SELECT person_id, lab_date
  FROM labs
  WHERE lab_type = 'FPG' AND value_as_number >= 126
),
abnl_ogtt AS (
  SELECT person_id, lab_date
  FROM labs
  WHERE lab_type = 'OGTT' AND value_as_number >= 200
),
abnl_rpg AS (
  SELECT person_id, lab_date
  FROM labs
  WHERE lab_type = 'RPG' AND value_as_number >= 200
),
abnl_any AS (
  SELECT * FROM abnl_a1c
  UNION ALL SELECT * FROM abnl_fpg
  UNION ALL SELECT * FROM abnl_ogtt
  UNION ALL SELECT * FROM abnl_rpg
),

-- --------------------------------
-- 4) Build inclusion evidence blocks
-- --------------------------------
inc_A_two_dx AS (
  SELECT person_id, MIN(dx_date) AS index_date
  FROM (
    SELECT DISTINCT person_id, dx_date FROM dx_t2
  ) s
  GROUP BY person_id
  HAVING COUNT(*) FILTER (WHERE dx_date IS NOT NULL) >= 2
),
inc_B_dx_plus_rx AS (
  SELECT d.person_id, MIN(LEAST(d.dx_date, r.rx_date)) AS index_date
  FROM dx_t2 d
  JOIN rx_t2 r ON r.person_id = d.person_id
  GROUP BY d.person_id
),
inc_C_two_labs AS (
  SELECT person_id, MIN(lab_date) AS index_date
  FROM (
    SELECT DISTINCT person_id, lab_date FROM abnl_any
  ) a
  GROUP BY person_id
  HAVING COUNT(*) >= 2
),
inc_D_lab_plus_rx AS (
  SELECT a.person_id, MIN(LEAST(a.lab_date, r.rx_date)) AS index_date
  FROM abnl_any a
  JOIN rx_t2 r ON r.person_id = a.person_id
  GROUP BY a.person_id
),

-- Union of inclusions
incl_union AS (
  SELECT * FROM inc_A_two_dx
  UNION ALL SELECT * FROM inc_B_dx_plus_rx
  UNION ALL SELECT * FROM inc_C_two_labs
  UNION ALL SELECT * FROM inc_D_lab_plus_rx
),
incl_by_person AS (
  SELECT person_id, MIN(index_date) AS index_date
  FROM incl_union
  GROUP BY person_id
),

-- --------------------------------
-- 5) Exclusions
-- --------------------------------
exc_any AS (
  SELECT DISTINCT person_id
  FROM (
    SELECT person_id FROM dx_t1
    UNION SELECT person_id FROM dx_gest
    UNION SELECT person_id FROM dx_secondary
  ) x
)

-- --------------------------------
-- 6) FINAL COHORT
-- --------------------------------
SELECT i.person_id,
       i.index_date
FROM incl_by_person i
JOIN adults a ON a.person_id = i.person_id
LEFT JOIN exc_any e ON e.person_id = i.person_id
WHERE e.person_id IS NULL
ORDER BY i.person_id;
