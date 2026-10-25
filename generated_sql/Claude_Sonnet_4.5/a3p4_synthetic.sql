-- T2DM phenotype for synthetic OMOP CDM (PostgreSQL / pgAdmin 4)

WITH
-- 1. Standard T2DM condition concepts from ICD-9-CM and ICD-10-CM source codes
t2dm_source_codes AS (
    SELECT c.concept_id AS source_concept_id
    FROM public.concept c
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (
            c.concept_code ~ '^250\.[0-9]2$'   -- ICD-9-CM T2DM (type 2 or unspecified, uncontrolled/controlled)
         OR c.concept_code ~ '^250\.[0-9]0$'   -- ICD-9-CM T2DM without complication
         OR c.concept_code ILIKE 'E11%'        -- ICD-10-CM type 2 diabetes
      )
),
t2dm_standard_concepts AS (
    -- Map source ICD codes to standard concepts, include descendants
    SELECT DISTINCT ca.descendant_concept_id AS concept_id
    FROM t2dm_source_codes s
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = s.source_concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
    JOIN public.concept_ancestor ca
      ON ca.ancestor_concept_id = cr.concept_id_2
    UNION
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM t2dm_source_codes s
    JOIN public.concept_relationship cr
      ON cr.concept_id_1 = s.source_concept_id
     AND cr.relationship_id = 'Maps to'
     AND cr.invalid_reason IS NULL
),
-- 2. Diagnosis evidence: distinct dates of T2DM conditions
dx_evidence AS (
    SELECT co.person_id,
           COUNT(DISTINCT co.condition_start_date) AS dx_dates
    FROM public.condition_occurrence co
    JOIN t2dm_standard_concepts t
      ON t.concept_id = co.condition_concept_id
    GROUP BY co.person_id
),
-- 3. Lab evidence: HbA1c >= 6.5 % or fasting glucose >= 126 mg/dL
lab_evidence AS (
    SELECT m.person_id,
           COUNT(DISTINCT m.measurement_date) AS lab_dates
    FROM public.measurement m
    WHERE (
            -- HbA1c (LOINC 4548-4, 17856-6, 41995-2), percent units
            (m.measurement_source_value IN ('4548-4', '17856-6', '41995-2')
             AND m.value_as_number >= 6.5
             AND (m.unit_source_value ILIKE '%percent%' OR m.unit_source_value ILIKE '%%%'
                  OR m.unit_source_value ILIKE '%pct%'))
         OR
            -- Fasting glucose (LOINC 1558-6, 1547-9), mg/dL
            (m.measurement_source_value IN ('1558-6', '1547-9')
             AND m.value_as_number >= 126
             AND m.value_as_number > 0
             AND (m.unit_source_value ILIKE '%mg/dL%' OR m.unit_source_value ILIKE '%mg/dl%'))
          )
    GROUP BY m.person_id
),
-- 4. Medication evidence: glucose-lowering agents (generic and brand names)
t2dm_drug_ingredients AS (
    SELECT c.concept_id
    FROM public.concept c
    WHERE c.vocabulary_id = 'RxNorm'
      AND c.concept_class_id = 'Ingredient'
      AND (
            c.concept_name ILIKE 'metformin%'        -- Glucophage
         OR c.concept_name ILIKE 'glipizide%'        -- Glucotrol
         OR c.concept_name ILIKE 'glyburide%'        -- Diabeta, Glynase
         OR c.concept_name ILIKE 'glimepiride%'      -- Amaryl
         OR c.concept_name ILIKE 'sitagliptin%'      -- Januvia
         OR c.concept_name ILIKE 'linagliptin%'      -- Tradjenta
         OR c.concept_name ILIKE 'saxagliptin%'      -- Onglyza
         OR c.concept_name ILIKE 'alogliptin%'       -- Nesina
         OR c.concept_name ILIKE 'empagliflozin%'    -- Jardiance
         OR c.concept_name ILIKE 'dapagliflozin%'    -- Farxiga
         OR c.concept_name ILIKE 'canagliflozin%'    -- Invokana
         OR c.concept_name ILIKE 'pioglitazone%'     -- Actos
         OR c.concept_name ILIKE 'liraglutide%'      -- Victoza
         OR c.concept_name ILIKE 'semaglutide%'      -- Ozempic, Rybelsus
         OR c.concept_name ILIKE 'dulaglutide%'      -- Trulicity
         OR c.concept_name ILIKE 'exenatide%'        -- Byetta, Bydureon
         OR c.concept_name ILIKE 'insulin%'          -- Humulin, Novolin, Lantus, Humalog, Novolog
      )
),
drug_evidence AS (
    SELECT de.person_id,
           COUNT(DISTINCT de.drug_exposure_start_date) AS drug_dates
    FROM public.drug_exposure de
    JOIN public.drug_strength ds
      ON ds.drug_concept_id = de.drug_concept_id
    JOIN t2dm_drug_ingredients di
      ON di.concept_id = ds.ingredient_concept_id
    GROUP BY de.person_id
),
-- 5. Combine criteria
phenotype AS (
    SELECT p.person_id
    FROM public.person p
    LEFT JOIN dx_evidence d   ON d.person_id = p.person_id
    LEFT JOIN lab_evidence l  ON l.person_id = p.person_id
    LEFT JOIN drug_evidence g ON g.person_id = p.person_id
    WHERE COALESCE(d.dx_dates, 0) >= 2
       OR (COALESCE(d.dx_dates, 0) >= 1 AND COALESCE(l.lab_dates, 0) >= 1)
       OR (COALESCE(d.dx_dates, 0) >= 1 AND COALESCE(g.drug_dates, 0) >= 1)
       OR COALESCE(l.lab_dates, 0) >= 2
)
SELECT DISTINCT person_id
FROM phenotype
ORDER BY person_id;