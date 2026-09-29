-- replace ICD concept IDs with their mapped standard concept IDs

SELECT DISTINCT p.person_id
FROM public.person p
JOIN public.condition_occurrence co ON p.person_id = co.person_id
WHERE 
-- INCLUSION: Must have at least one T2DM Diagnosis code
co.condition_concept_id IN (
    SELECT cr.concept_id_2
    FROM public.concept c
    JOIN public.concept_relationship cr
        ON c.concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'
      AND (
          (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E11%')
          OR (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~ '^250\.[0-9][0,2]$')
      )
)
-- REFINEMENT: Ensure the case is robust (2+ dates OR Meds OR Lab)
AND (
    -- Criteria A: Two or more T2DM diagnoses on different days
    (SELECT COUNT(DISTINCT co2.condition_start_date) 
     FROM public.condition_occurrence co2 
     WHERE co2.person_id = p.person_id 
     AND co2.condition_concept_id IN (
         SELECT cr.concept_id_2
         FROM public.concept c
         JOIN public.concept_relationship cr
             ON c.concept_id = cr.concept_id_1
         WHERE cr.relationship_id = 'Maps to'
           AND (
               (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E11%')
               OR (c.vocabulary_id = 'ICD9CM' AND c.concept_code ~ '^250\.[0-9][0,2]$')
           )
     )) >= 2
    
    OR
    
    -- Criteria B: T2DM specific medication exposure
    EXISTS (
        SELECT 1 FROM public.drug_exposure de
        JOIN public.concept c ON de.drug_concept_id = c.concept_id
        WHERE de.person_id = p.person_id
        AND (
            LOWER(c.concept_name) LIKE '%metformin%' OR LOWER(c.concept_name) LIKE '%glucophage%' OR
            LOWER(c.concept_name) LIKE '%glipizide%' OR LOWER(c.concept_name) LIKE '%glucotrol%' OR
            LOWER(c.concept_name) LIKE '%glyburide%' OR LOWER(c.concept_name) LIKE '%micronase%' OR
            LOWER(c.concept_name) LIKE '%glimepiride%' OR LOWER(c.concept_name) LIKE '%amaryl%' OR
            LOWER(c.concept_name) LIKE '%pioglitazone%' OR LOWER(c.concept_name) LIKE '%actos%' OR
            LOWER(c.concept_name) LIKE '%rosiglitazone%' OR LOWER(c.concept_name) LIKE '%avandia%' OR
            LOWER(c.concept_name) LIKE '%sitagliptin%' OR LOWER(c.concept_name) LIKE '%januvia%' OR
            LOWER(c.concept_name) LIKE '%saxagliptin%' OR LOWER(c.concept_name) LIKE '%onglyza%' OR
            LOWER(c.concept_name) LIKE '%linagliptin%' OR LOWER(c.concept_name) LIKE '%tradjenta%' OR
            LOWER(c.concept_name) LIKE '%empagliflozin%' OR LOWER(c.concept_name) LIKE '%jardiance%' OR
            LOWER(c.concept_name) LIKE '%dapagliflozin%' OR LOWER(c.concept_name) LIKE '%farxiga%' OR
            LOWER(c.concept_name) LIKE '%canagliflozin%' OR LOWER(c.concept_name) LIKE '%invokana%' OR
            LOWER(c.concept_name) LIKE '%liraglutide%' OR LOWER(c.concept_name) LIKE '%victoza%' OR
            LOWER(c.concept_name) LIKE '%semaglutide%' OR LOWER(c.concept_name) LIKE '%ozempic%' OR LOWER(c.concept_name) LIKE '%rybelsus%' OR
            LOWER(c.concept_name) LIKE '%exenatide%' OR LOWER(c.concept_name) LIKE '%byetta%' OR LOWER(c.concept_name) LIKE '%bydureon%' OR
            LOWER(c.concept_name) LIKE '%dulaglutide%' OR LOWER(c.concept_name) LIKE '%trulicity%'
        )
    )
    
    OR
    
    -- Criteria C: Abnormal HbA1c lab result (>= 6.5%)
    EXISTS (
        SELECT 1 FROM public.measurement m
        WHERE m.person_id = p.person_id
        AND m.measurement_concept_id IN (3004410, 3007263, 40758583, 3005673)
        AND m.value_as_number >= 6.5
    )
)
-- EXCLUSIONS: Remove Type 1 and Gestational Diabetes
AND NOT EXISTS (
    SELECT 1
    FROM public.condition_occurrence co_ex
    WHERE co_ex.person_id = p.person_id
      AND co_ex.condition_concept_id IN (
          SELECT cr.concept_id_2
          FROM public.concept c_ex
          JOIN public.concept_relationship cr
              ON c_ex.concept_id = cr.concept_id_1
          WHERE cr.relationship_id = 'Maps to'
            AND (
                -- Type 1 Diabetes
                (c_ex.vocabulary_id = 'ICD10CM' AND c_ex.concept_code LIKE 'E10%') OR
                (c_ex.vocabulary_id = 'ICD9CM' AND c_ex.concept_code ~ '^250\.[0-9][1,3]$') OR
                -- Gestational Diabetes
                (c_ex.vocabulary_id = 'ICD10CM' AND (c_ex.concept_code LIKE 'O24.4%' OR c_ex.concept_code LIKE 'O24.9%')) OR
                (c_ex.vocabulary_id = 'ICD9CM' AND c_ex.concept_code LIKE '648.0%')
            )
      )
);