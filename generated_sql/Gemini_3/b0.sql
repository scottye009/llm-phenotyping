SELECT DISTINCT p.person_id
FROM person p
INNER JOIN (
    -- Inclusion logic: (2+ Outpatient DX OR 1 Inpatient DX) OR Labs OR Meds
    SELECT co.person_id
    FROM condition_occurrence co
    JOIN concept c ON co.condition_concept_id = c.concept_id
    WHERE (c.concept_code LIKE 'E11%' AND c.vocabulary_id = 'ICD10CM')
       OR (c.concept_code LIKE '250.%0' AND c.vocabulary_id = 'ICD9CM')
       OR (c.concept_code LIKE '250.%2' AND c.vocabulary_id = 'ICD9CM')
    GROUP BY co.person_id
    HAVING COUNT(DISTINCT co.condition_start_date) >= 2 
       OR SUM(CASE WHEN co.visit_occurrence_id IN (SELECT visit_occurrence_id FROM visit_occurrence WHERE visit_concept_id = 9201) THEN 1 ELSE 0 END) >= 1

    UNION

    SELECT m.person_id
    FROM measurement m
    WHERE (m.measurement_concept_id IN (3004410, 3005673, 4078571) AND m.value_as_number >= 6.5) -- HbA1c
       OR (m.measurement_concept_id IN (3000845, 3004501) AND m.value_as_number >= 126) -- Fasting Glucose

    UNION

    SELECT de.person_id
    FROM drug_exposure de
    JOIN concept dc ON de.drug_concept_id = dc.concept_id
    WHERE LOWER(dc.concept_name) LIKE '%metformin%' OR LOWER(dc.concept_name) LIKE '%glucophage%' OR LOWER(dc.concept_name) LIKE '%fortamet%' OR LOWER(dc.concept_name) LIKE '%glumetza%'
       OR LOWER(dc.concept_name) LIKE '%glipizide%' OR LOWER(dc.concept_name) LIKE '%glucotrol%'
       OR LOWER(dc.concept_name) LIKE '%glyburide%' OR LOWER(dc.concept_name) LIKE '%diabeta%' OR LOWER(dc.concept_name) LIKE '%glynase%'
       OR LOWER(dc.concept_name) LIKE '%glimepiride%' OR LOWER(dc.concept_name) LIKE '%amaryl%'
       OR LOWER(dc.concept_name) LIKE '%pioglitazone%' OR LOWER(dc.concept_name) LIKE '%actos%'
       OR LOWER(dc.concept_name) LIKE '%rosiglitazone%' OR LOWER(dc.concept_name) LIKE '%avandia%'
       OR LOWER(dc.concept_name) LIKE '%sitagliptin%' OR LOWER(dc.concept_name) LIKE '%januvia%'
       OR LOWER(dc.concept_name) LIKE '%saxagliptin%' OR LOWER(dc.concept_name) LIKE '%onglyza%'
       OR LOWER(dc.concept_name) LIKE '%linagliptin%' OR LOWER(dc.concept_name) LIKE '%tradjenta%'
       OR LOWER(dc.concept_name) LIKE '%empagliflozin%' OR LOWER(dc.concept_name) LIKE '%jardiance%'
       OR LOWER(dc.concept_name) LIKE '%dapagliflozin%' OR LOWER(dc.concept_name) LIKE '%farxiga%'
       OR LOWER(dc.concept_name) LIKE '%canagliflozin%' OR LOWER(dc.concept_name) LIKE '%invokana%'
       OR LOWER(dc.concept_name) LIKE '%liraglutide%' OR LOWER(dc.concept_name) LIKE '%victoza%'
       OR LOWER(dc.concept_name) LIKE '%semaglutide%' OR LOWER(dc.concept_name) LIKE '%ozempic%' OR LOWER(dc.concept_name) LIKE '%rybelsus%'
       OR LOWER(dc.concept_name) LIKE '%dulaglutide%' OR LOWER(dc.concept_name) LIKE '%trulicity%'
) inclusion ON p.person_id = inclusion.person_id
WHERE p.person_id NOT IN (
    -- Exclusions: T1DM, Gestational DM, Secondary DM
    SELECT person_id
    FROM condition_occurrence ex_co
    JOIN concept ex_c ON ex_co.condition_concept_id = ex_c.concept_id
    WHERE (ex_c.concept_code LIKE 'E10%' AND ex_c.vocabulary_id = 'ICD10CM')
       OR (ex_c.concept_code LIKE '250.%1' AND ex_c.vocabulary_id = 'ICD9CM')
       OR (ex_c.concept_code LIKE '250.%3' AND ex_c.vocabulary_id = 'ICD9CM')
       OR (ex_c.concept_code LIKE 'O24.4%' AND ex_c.vocabulary_id = 'ICD10CM')
       OR (ex_c.concept_code = '648.8' AND ex_c.vocabulary_id = 'ICD9CM')
       OR (ex_c.concept_code LIKE 'E08%' OR ex_c.concept_code LIKE 'E09%' OR ex_c.concept_code LIKE 'E13%')
);