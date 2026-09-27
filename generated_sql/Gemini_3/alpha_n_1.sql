-- Final T2DM Phenotype Algorithm for PostgreSQL/pgAdmin4
WITH t2dm_concepts AS (
    -- Identifying T2DM via ICD9/10 mapped to SNOMED via Standardized Vocabularies
    SELECT concept_id FROM public.concept
    WHERE (concept_code LIKE 'E11%' AND vocabulary_id = 'ICD10CM')
       OR (concept_code IN ('250.00', '250.02', '250.10', '250.12') AND vocabulary_id = 'ICD9CM')
       OR concept_id IN (443264, 201820) -- Standard SNOMED codes for T2DM
),

t1dm_concepts AS (
    -- Exclusionary Type 1 concepts
    SELECT concept_id FROM public.concept
    WHERE (concept_code LIKE 'E10%' AND vocabulary_id = 'ICD10CM')
       OR (concept_code IN ('250.01', '250.03') AND vocabulary_id = 'ICD9CM')
),

t2dm_meds AS (
    -- Generic and Brand names (Metformin/Glucophage, Glipizide/Glucotrol, etc.)
    SELECT concept_id FROM public.concept
    WHERE lower(concept_name) ~* '(metformin|glucophage|glipizide|glucotrol|sitagliptin|januvia|empagliflozin|jardiance|liraglutide|victoza)'
      AND domain_id = 'Drug' AND standard_concept = 'S'
),

lab_evidence AS (
    -- Lab results: HbA1c >= 6.5
    SELECT person_id
    FROM public.measurement
    WHERE measurement_concept_id IN (3004410, 3005673) -- HbA1c codes
      AND value_as_number >= 6.5
)

SELECT DISTINCT p.person_id
FROM public.person p
JOIN public.condition_occurrence co ON p.person_id = co.person_id
LEFT JOIN public.drug_exposure de ON p.person_id = de.person_id
WHERE (
    -- INCLUSION CRITERIA
    co.condition_concept_id IN (SELECT concept_id FROM t2dm_concepts)
    OR de.drug_concept_id IN (SELECT concept_id FROM t2dm_meds)
    OR p.person_id IN (SELECT person_id FROM lab_evidence)
)
AND NOT EXISTS (
    -- EXCLUSION CRITERIA: Rule out T1DM dominance
    SELECT 1 FROM public.condition_occurrence co_ex
    WHERE co_ex.person_id = p.person_id
    AND co_ex.condition_concept_id IN (SELECT concept_id FROM t1dm_concepts)
)
-- Ensure clinical relevance by checking for a Visit Occurrence as per your diagram
AND EXISTS (
    SELECT 1 FROM public.visit_occurrence vo 
    WHERE vo.person_id = p.person_id
);
