-- T2DM phenotype for synthetic OMOP CDM (PostgreSQL / pgAdmin 4)

WITH t2dm_dx AS (
    -- T2DM diagnoses: SNOMED hierarchy or ICD10CM/ICD9CM source codes
    SELECT co.person_id, co.condition_start_date AS dx_date
    FROM public.condition_occurrence co
    LEFT JOIN public.concept sc ON sc.concept_id = co.condition_source_concept_id
    WHERE co.condition_concept_id IN (
            SELECT ca.descendant_concept_id
            FROM public.concept_ancestor ca
            WHERE ca.ancestor_concept_id = 201826)           -- Type 2 diabetes mellitus
       OR (sc.vocabulary_id = 'ICD10CM' AND sc.concept_code ILIKE 'E11%')
       OR (sc.vocabulary_id = 'ICD9CM'  AND sc.concept_code ~ '^250\.?[0-9][02]$')
),
dx_ge1 AS (
    SELECT person_id FROM t2dm_dx GROUP BY person_id
),
dx_ge2 AS (
    -- At least 2 distinct diagnosis dates
    SELECT person_id FROM t2dm_dx
    GROUP BY person_id
    HAVING COUNT(DISTINCT dx_date) >= 2
),
t1dm_dx AS (
    -- Type 1 diabetes exclusion
    SELECT co.person_id
    FROM public.condition_occurrence co
    LEFT JOIN public.concept sc ON sc.concept_id = co.condition_source_concept_id
    WHERE co.condition_concept_id IN (
            SELECT ca.descendant_concept_id
            FROM public.concept_ancestor ca
            WHERE ca.ancestor_concept_id = 201254)           -- Type 1 diabetes mellitus
       OR (sc.vocabulary_id = 'ICD10CM' AND sc.concept_code ILIKE 'E10%')
       OR (sc.vocabulary_id = 'ICD9CM'  AND sc.concept_code ~ '^250\.?[0-9][13]$')
),
lab_evidence AS (
    -- LOINC-coded labs with unit-aware glucose conversion (mmol/L -> mg/dL)
    SELECT m.person_id
    FROM public.measurement m
    WHERE m.value_as_number IS NOT NULL
      AND m.value_as_number > 0
      AND (
            (m.measurement_source_value IN ('4548-4', '17856-6', '4549-2')   -- HbA1c
             AND m.value_as_number BETWEEN 3 AND 20
             AND m.value_as_number >= 6.5)
         OR (m.measurement_source_value = '1558-6'                          -- Fasting glucose
             AND (CASE WHEN m.unit_source_value ILIKE '%mmol%'
                       THEN m.value_as_number * 18.016
                       ELSE m.value_as_number END) >= 126)
         OR (m.measurement_source_value IN ('2345-7', '2339-0')            -- Random glucose
             AND (CASE WHEN m.unit_source_value ILIKE '%mmol%'
                       THEN m.value_as_number * 18.016
                       ELSE m.value_as_number END) >= 200)
          )
),
med_evidence AS (
    -- Generic and brand antidiabetic drugs, matched on drug concept names
    SELECT de.person_id
    FROM public.drug_exposure de
    JOIN public.concept dc ON dc.concept_id = de.drug_concept_id
    WHERE dc.concept_name ~* '\m(metformin|glucophage|glumetza|fortamet|glipizide|glucotrol|glyburide|glibenclamide|diabeta|micronase|glimepiride|amaryl|sitagliptin|januvia|linagliptin|tradjenta|saxagliptin|onglyza|empagliflozin|jardiance|dapagliflozin|farxiga|canagliflozin|invokana|liraglutide|victoza|semaglutide|ozempic|dulaglutide|trulicity|pioglitazone|actos|insulin|humulin|novolin|lantus|levemir|humalog|novolog)\M'
)
SELECT DISTINCT p.person_id
FROM public.person p
WHERE NOT EXISTS (SELECT 1 FROM t1dm_dx t WHERE t.person_id = p.person_id)
  AND (
        EXISTS (SELECT 1 FROM dx_ge2 d2 WHERE d2.person_id = p.person_id)
     OR (
            EXISTS (SELECT 1 FROM dx_ge1 d1 WHERE d1.person_id = p.person_id)
        AND (
                EXISTS (SELECT 1 FROM lab_evidence l WHERE l.person_id = p.person_id)
             OR EXISTS (SELECT 1 FROM med_evidence md WHERE md.person_id = p.person_id)
            )
        )
      )
ORDER BY p.person_id;