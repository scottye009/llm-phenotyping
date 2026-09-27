SELECT DISTINCT p.person_id
FROM public.person p
WHERE 
/* 1. PRIMARY INCLUSION: Must have at least one T2DM Diagnosis */
p.person_id IN (
    SELECT co.person_id
    FROM public.condition_occurrence co
    JOIN public.concept c ON co.condition_source_concept_id = c.concept_id
    WHERE (c.concept_code LIKE 'E11%' AND c.vocabulary_id = 'ICD10CM')
       OR (c.concept_code IN ('250.00', '250.02', '250.10', '250.12', '250.20', '250.22') AND c.vocabulary_id = 'ICD9CM')
)

/* 2. SPECIFICITY FILTER: Must meet one of the following three sub-criteria */
AND (
    -- Sub-criterion A: At least 2 separate days with T2DM diagnosis
    p.person_id IN (
        SELECT person_id 
        FROM public.condition_occurrence
        WHERE condition_source_concept_id IN (
            SELECT concept_id FROM public.concept 
            WHERE (concept_code LIKE 'E11%' AND vocabulary_id = 'ICD10CM')
               OR (concept_code LIKE '250.0%' AND vocabulary_id = 'ICD9CM')
        )
        GROUP BY person_id 
        HAVING COUNT(DISTINCT condition_start_date) >= 2
    )
    OR
    -- Sub-criterion B: 1+ T2DM Diagnosis AND 1+ T2DM Medication
    p.person_id IN (
        SELECT person_id FROM public.drug_exposure
        WHERE drug_concept_id IN (
            SELECT concept_id FROM public.concept
            WHERE (
                LOWER(concept_name) ~* '(metformin|glucophage|glipizide|glucotrol|glyburide|diabeta|micronase|glimepiride|amaryl|sitagliptin|januvia|saxagliptin|onglyza|linagliptin|tradjenta|empagliflozin|jardiance|dapagliflozin|farxiga|canagliflozin|invokana|liraglutide|victoza|semaglutide|ozempic|rybelsus|pioglitazone|actos)'
            )
            AND domain_id = 'Drug'
        )
    )
    OR
    -- Sub-criterion C: 1+ T2DM Diagnosis AND Lab evidence (A1c >= 6.5 or Glucose >= 126)
    p.person_id IN (
        SELECT person_id FROM public.measurement
        WHERE (measurement_concept_id IN (3004410, 3005673, 40758583) AND value_as_number >= 6.5) -- HbA1c
           OR (measurement_concept_id IN (3003280, 3000671, 3004501) AND value_as_number >= 126) -- Fasting Glucose
    )
)

/* 3. EXCLUSION: Exclude Type 1 Diabetes unless T2DM diagnoses outnumber T1DM diagnoses */
AND p.person_id NOT IN (
    SELECT t1.person_id
    FROM (
        SELECT person_id, COUNT(*) as t1_count 
        FROM public.condition_occurrence 
        WHERE condition_source_concept_id IN (
            SELECT concept_id FROM public.concept 
            WHERE (concept_code LIKE 'E10%' AND vocabulary_id = 'ICD10CM')
               OR (concept_code IN ('250.01', '250.03') AND vocabulary_id = 'ICD9CM')
        )
        GROUP BY person_id
    ) t1
    LEFT JOIN (
        SELECT person_id, COUNT(*) as t2_count 
        FROM public.condition_occurrence 
        WHERE condition_source_concept_id IN (
            SELECT concept_id FROM public.concept 
            WHERE (concept_code LIKE 'E11%' AND vocabulary_id = 'ICD10CM')
               OR (concept_code LIKE '250.0%' AND vocabulary_id = 'ICD9CM')
        )
        GROUP BY person_id
    ) t2 ON t1.person_id = t2.person_id
    WHERE t1.t1_count > COALESCE(t2.t2_count, 0)
);
