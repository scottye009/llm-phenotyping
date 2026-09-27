WITH icd_t2dm_source AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (
            (vocabulary_id = 'ICD9CM' AND replace(concept_code, '.', '') IN (
                '25000','25002','25010','25012','25020','25022','25030','25032',
                '25040','25042','25050','25052','25060','25062','25070','25072',
                '25080','25082','25090','25092'
            ))
            OR
            (vocabulary_id = 'ICD10CM' AND replace(concept_code, '.', '') IN (
                'E1100','E1101','E1110','E1111','E1121','E1122','E1129',
                'E11311','E11319','E11321','E11329','E11331','E11339',
                'E11341','E11349','E11351','E11352','E11353','E11355',
                'E11359','E1136','E1137X1','E1137X2','E1137X3','E1137X9',
                'E1139','E1140','E1141','E1142','E1143','E1144','E1149',
                'E1151','E1152','E1159','E11610','E11618','E11620','E11621',
                'E11622','E11628','E11630','E11638','E11641','E11649','E1165',
                'E1169','E118','E119'
            ))
      )
),

mapped_t2dm_conditions AS (
    SELECT cr.concept_id_2 AS condition_concept_id
    FROM icd_t2dm_source s
    JOIN public.concept_relationship cr
      ON s.concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'

    UNION

    SELECT concept_id AS condition_concept_id
    FROM icd_t2dm_source
),

t2dm_diagnosis AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN mapped_t2dm_conditions m
      ON co.condition_concept_id = m.condition_concept_id
),

exclusion_dx_source AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (
            replace(concept_code, '.', '') ~ '^(25001|25003|E10)'
         OR replace(concept_code, '.', '') ~ '^(249|E08|E09|E13)'
         OR replace(concept_code, '.', '') ~ '^(6488|O24)'
      )
),

mapped_exclusion_conditions AS (
    SELECT cr.concept_id_2 AS condition_concept_id
    FROM exclusion_dx_source s
    JOIN public.concept_relationship cr
      ON s.concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'

    UNION

    SELECT concept_id AS condition_concept_id
    FROM exclusion_dx_source
),

exclusion_diagnosis AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN mapped_exclusion_conditions e
      ON co.condition_concept_id = e.condition_concept_id
),

t2dm_medication_concepts AS (
    SELECT concept_id
    FROM public.concept
    WHERE domain_id = 'Drug'
      AND standard_concept IN ('S', 'C')
      AND (
            concept_name ILIKE '%metformin%'
         OR concept_name ILIKE '%glucophage%'
         OR concept_name ILIKE '%glumetza%'
         OR concept_name ILIKE '%fortamet%'
         OR concept_name ILIKE '%riomet%'
         OR concept_name ILIKE '%glyburide%'
         OR concept_name ILIKE '%glibenclamide%'
         OR concept_name ILIKE '%diabeta%'
         OR concept_name ILIKE '%glynase%'
         OR concept_name ILIKE '%micronase%'
         OR concept_name ILIKE '%glipizide%'
         OR concept_name ILIKE '%glucotrol%'
         OR concept_name ILIKE '%glimepiride%'
         OR concept_name ILIKE '%amaryl%'
         OR concept_name ILIKE '%pioglitazone%'
         OR concept_name ILIKE '%actos%'
         OR concept_name ILIKE '%rosiglitazone%'
         OR concept_name ILIKE '%avandia%'
         OR concept_name ILIKE '%sitagliptin%'
         OR concept_name ILIKE '%januvia%'
         OR concept_name ILIKE '%saxagliptin%'
         OR concept_name ILIKE '%onglyza%'
         OR concept_name ILIKE '%linagliptin%'
         OR concept_name ILIKE '%tradjenta%'
         OR concept_name ILIKE '%alogliptin%'
         OR concept_name ILIKE '%nesina%'
         OR concept_name ILIKE '%empagliflozin%'
         OR concept_name ILIKE '%jardiance%'
         OR concept_name ILIKE '%dapagliflozin%'
         OR concept_name ILIKE '%farxiga%'
         OR concept_name ILIKE '%canagliflozin%'
         OR concept_name ILIKE '%invokana%'
         OR concept_name ILIKE '%ertugliflozin%'
         OR concept_name ILIKE '%steglatro%'
         OR concept_name ILIKE '%semaglutide%'
         OR concept_name ILIKE '%ozempic%'
         OR concept_name ILIKE '%rybelsus%'
         OR concept_name ILIKE '%wegovy%'
         OR concept_name ILIKE '%liraglutide%'
         OR concept_name ILIKE '%victoza%'
         OR concept_name ILIKE '%saxenda%'
         OR concept_name ILIKE '%dulaglutide%'
         OR concept_name ILIKE '%trulicity%'
         OR concept_name ILIKE '%exenatide%'
         OR concept_name ILIKE '%byetta%'
         OR concept_name ILIKE '%bydureon%'
         OR concept_name ILIKE '%tirzepatide%'
         OR concept_name ILIKE '%mounjaro%'
         OR concept_name ILIKE '%zepbound%'
         OR concept_name ILIKE '%repaglinide%'
         OR concept_name ILIKE '%prandin%'
         OR concept_name ILIKE '%nateglinide%'
         OR concept_name ILIKE '%starlix%'
         OR concept_name ILIKE '%acarbose%'
         OR concept_name ILIKE '%precose%'
         OR concept_name ILIKE '%miglitol%'
         OR concept_name ILIKE '%glyset%'
      )
),

t2dm_medication AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN public.concept_ancestor ca
      ON de.drug_concept_id = ca.descendant_concept_id
    JOIN t2dm_medication_concepts mc
      ON ca.ancestor_concept_id = mc.concept_id
),

diabetes_labs AS (
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN public.concept c
      ON m.measurement_concept_id = c.concept_id
    WHERE m.value_as_number IS NOT NULL
      AND (
            (
                c.concept_name ILIKE '%hemoglobin a1c%'
                AND m.value_as_number >= 6.5
            )
         OR (
                (
                    c.concept_name ILIKE '%glucose%'
                    AND (
                        c.concept_name ILIKE '%fasting%'
                        OR c.concept_name ILIKE '%glucose [mass/volume] in serum or plasma%'
                    )
                )
                AND m.value_as_number >= 126
            )
         OR (
                c.concept_name ILIKE '%glucose%'
                AND c.concept_name ILIKE '%2 hour%'
                AND m.value_as_number >= 200
            )
         OR (
                c.concept_name ILIKE '%glucose%'
                AND c.concept_name ILIKE '%random%'
                AND m.value_as_number >= 200
            )
      )
),

candidate_t2dm AS (
    SELECT person_id, 'diagnosis' AS evidence_type FROM t2dm_diagnosis
    UNION ALL
    SELECT person_id, 'medication' AS evidence_type FROM t2dm_medication
    UNION ALL
    SELECT person_id, 'lab' AS evidence_type FROM diabetes_labs
),

phenotype_logic AS (
    SELECT
        person_id,
        MAX(CASE WHEN evidence_type = 'diagnosis' THEN 1 ELSE 0 END) AS has_t2dm_diagnosis,
        MAX(CASE WHEN evidence_type = 'medication' THEN 1 ELSE 0 END) AS has_t2dm_medication,
        MAX(CASE WHEN evidence_type = 'lab' THEN 1 ELSE 0 END) AS has_diabetes_lab
    FROM candidate_t2dm
    GROUP BY person_id
)

SELECT DISTINCT
    p.person_id
FROM public.person p
JOIN phenotype_logic pl
  ON p.person_id = pl.person_id
LEFT JOIN exclusion_diagnosis ex
  ON p.person_id = ex.person_id
WHERE
    (
        pl.has_t2dm_diagnosis = 1
        OR (
            pl.has_t2dm_medication = 1
            AND pl.has_diabetes_lab = 1
        )
    )
    AND NOT (
        ex.person_id IS NOT NULL
        AND pl.has_t2dm_diagnosis = 0
    );