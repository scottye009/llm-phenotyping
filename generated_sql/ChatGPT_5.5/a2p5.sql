WITH t2dm_icd_source_concepts AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (
            -- ICD-9-CM type 2 diabetes: 250.xx with 5th digit 0 or 2
            (vocabulary_id = 'ICD9CM' AND concept_code ~ '^250\.?[0-9][0-9][02]$')

            OR

            -- ICD-10-CM type 2 diabetes: E11.*
            (vocabulary_id = 'ICD10CM' AND concept_code ~ '^E11(\.|$)')
          )
),

t2dm_condition_concepts AS (
    SELECT concept_id AS condition_concept_id
    FROM t2dm_icd_source_concepts

    UNION

    SELECT cr.concept_id_2 AS condition_concept_id
    FROM t2dm_icd_source_concepts s
    JOIN public.concept_relationship cr
      ON s.concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'
),

t2dm_diagnosis AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (
        SELECT condition_concept_id
        FROM t2dm_condition_concepts
    )
),

abnormal_diabetes_labs AS (
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN public.concept c
      ON m.measurement_concept_id = c.concept_id
    WHERE m.value_as_number IS NOT NULL
      AND (
            (
                lower(c.concept_name) LIKE '%hemoglobin a1c%'
                AND m.value_as_number >= 6.5
            )
            OR
            (
                lower(c.concept_name) LIKE '%fasting glucose%'
                AND m.value_as_number >= 126
            )
            OR
            (
                lower(c.concept_name) LIKE '%glucose%'
                AND m.value_as_number >= 200
            )
          )
),

antidiabetic_seed_drugs AS (
    SELECT concept_id
    FROM public.concept
    WHERE domain_id = 'Drug'
      AND (
            lower(concept_name) ~
            'metformin|glucophage|fortamet|glumetza|riomet|glipizide|glucotrol|glyburide|diaBeta|glynase|glimepiride|amaryl|pioglitazone|actos|rosiglitazone|avandia|sitagliptin|januvia|saxagliptin|onglyza|linagliptin|tradjenta|alogliptin|nesina|exenatide|byetta|bydureon|liraglutide|victoza|dulaglutide|trulicity|semaglutide|ozempic|rybelsus|mounjaro|tirzepatide|canagliflozin|invokana|dapagliflozin|farxiga|empagliflozin|jardiance|ertugliflozin|steglatro|acarbose|precose|miglitol|glyset|repaglinide|prandin|nateglinide|starlix'

            OR EXISTS (
                SELECT 1
                FROM public.concept_synonym cs
                WHERE cs.concept_id = public.concept.concept_id
                  AND lower(cs.concept_synonym_name) ~
                  'metformin|glucophage|fortamet|glumetza|riomet|glipizide|glucotrol|glyburide|diaBeta|glynase|glimepiride|amaryl|pioglitazone|actos|rosiglitazone|avandia|sitagliptin|januvia|saxagliptin|onglyza|linagliptin|tradjenta|alogliptin|nesina|exenatide|byetta|bydureon|liraglutide|victoza|dulaglutide|trulicity|semaglutide|ozempic|rybelsus|mounjaro|tirzepatide|canagliflozin|invokana|dapagliflozin|farxiga|empagliflozin|jardiance|ertugliflozin|steglatro|acarbose|precose|miglitol|glyset|repaglinide|prandin|nateglinide|starlix'
            )
          )
),

antidiabetic_drug_concepts AS (
    SELECT concept_id AS drug_concept_id
    FROM antidiabetic_seed_drugs

    UNION

    SELECT ca.descendant_concept_id AS drug_concept_id
    FROM public.concept_ancestor ca
    JOIN antidiabetic_seed_drugs s
      ON ca.ancestor_concept_id = s.concept_id
),

antidiabetic_medication AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    WHERE de.drug_concept_id IN (
        SELECT drug_concept_id
        FROM antidiabetic_drug_concepts
    )
),

exclusion_icd_source_concepts AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (
            -- Type 1 diabetes
            (vocabulary_id = 'ICD9CM' AND concept_code ~ '^250\.?[0-9][0-9][13]$')
            OR (vocabulary_id = 'ICD10CM' AND concept_code ~ '^E10(\.|$)')

            OR

            -- Secondary diabetes
            (vocabulary_id = 'ICD9CM' AND concept_code ~ '^249')
            OR (vocabulary_id = 'ICD10CM' AND concept_code ~ '^E0[89](\.|$)')
            OR (vocabulary_id = 'ICD10CM' AND concept_code ~ '^E13(\.|$)')

            OR

            -- Gestational diabetes
            (vocabulary_id = 'ICD9CM' AND concept_code ~ '^648\.?8')
            OR (vocabulary_id = 'ICD10CM' AND concept_code ~ '^O24\.4')
          )
),

exclusion_condition_concepts AS (
    SELECT concept_id AS condition_concept_id
    FROM exclusion_icd_source_concepts

    UNION

    SELECT cr.concept_id_2 AS condition_concept_id
    FROM exclusion_icd_source_concepts s
    JOIN public.concept_relationship cr
      ON s.concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'
),

exclusion_diagnosis AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (
        SELECT condition_concept_id
        FROM exclusion_condition_concepts
    )
),

final_t2dm_phenotype AS (
    SELECT DISTINCT p.person_id
    FROM public.person p
    LEFT JOIN t2dm_diagnosis dx
      ON p.person_id = dx.person_id
    LEFT JOIN abnormal_diabetes_labs lab
      ON p.person_id = lab.person_id
    LEFT JOIN antidiabetic_medication med
      ON p.person_id = med.person_id
    LEFT JOIN exclusion_diagnosis ex
      ON p.person_id = ex.person_id
    WHERE
        (
            dx.person_id IS NOT NULL
            OR
            (
                lab.person_id IS NOT NULL
                AND med.person_id IS NOT NULL
            )
        )
        AND NOT (
            dx.person_id IS NULL
            AND ex.person_id IS NOT NULL
        )
)

SELECT person_id
FROM final_t2dm_phenotype;