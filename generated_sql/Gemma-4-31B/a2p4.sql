/* 
  Phenotyping Algorithm for Type 2 Diabetes Mellitus (T2DM)
  Schema: OMOP CDM (Public)
*/

WITH 
-- 1. Define T2DM Diagnosis Concepts (ICD9, ICD10, SNOMED)
t2dm_diagnoses AS (
    SELECT concept_id 
    FROM concept 
    WHERE (vocabulary_id = 'ICD10CM' AND concept_code IN ('E11.9', 'E11.8', 'E11.65'))
       OR (vocabulary_id = 'ICD9CM' AND concept_code IN ('250.00', '250.01'))
       OR (concept_id = 443258) -- SNOMED for Type 2 Diabetes
),

-- 2. Define T2DM-Specific Medications (Generic and Brand)
t2dm_meds AS (
    SELECT concept_id 
    FROM concept 
    WHERE (concept_name LIKE '%Metformin%' OR concept_name LIKE '%Glucophage%')
       OR (concept_name LIKE '%Pioglitazone%' OR concept_name LIKE '%Actos%')
       OR (concept_name LIKE '%Sitagliptin%' OR concept_name LIKE '%Januvia%')
       OR (concept_name LIKE '%Empagliflozin%' OR concept_name LIKE '%Jardiance%')
       OR (concept_name LIKE '%Liraglutide%' OR concept_name LIKE '%Victoza%')
),

-- 3. Define Lab Tests for Hyperglycemia (HbA1c >= 6.5% or Fasting Glucose >= 126 mg/dL)
t2dm_labs AS (
    SELECT measurement_id, person_id 
    FROM measurement 
    WHERE (measurement_concept_id = 3004423 -- HbA1c
           AND value_as_number >= 6.5)
       OR (measurement_concept_id = 3004421 -- Fasting Glucose
           AND value_as_number >= 126)
),

-- 4. Define Exclusion Criteria (Type 1 Diabetes indicators)
t1dm_exclusion AS (
    SELECT DISTINCT person_id 
    FROM condition_occurrence 
    WHERE condition_concept_id IN (
        -- Concepts for T1DM, Diabetic Ketoacidosis (DKA)
        SELECT concept_id FROM concept 
        WHERE (vocabulary_id = 'ICD10CM' AND concept_code = 'E10.9')
           OR (concept_name LIKE '%Ketoacidosis%')
    )
),

-- 5. Apply the Combination Logic
t2dm_candidates AS (
    -- Logic: (2+ Diagnoses) OR (1 Diagnosis AND (Lab OR Med))
    SELECT p.person_id
    FROM person p
    JOIN condition_occurrence co ON p.person_id = co.person_id
    WHERE co.condition_concept_id IN (SELECT concept_id FROM t2dm_diagnoses)
    GROUP BY p.person_id
    HAVING COUNT(DISTINCT co.condition_occurrence_id) >= 2
    
    UNION
    
    SELECT co.person_id
    FROM condition_occurrence co
    WHERE co.condition_concept_id IN (SELECT concept_id FROM t2dm_diagnoses)
    AND (
        co.person_id IN (SELECT person_id FROM t2dm_labs) 
        OR 
        co.person_id IN (SELECT drug_exposure.person_id FROM drug_exposure WHERE drug_concept_id IN (SELECT concept_id FROM t2dm_meds))
    )
)

-- Final Algorithm Output
SELECT 
    c.person_id 
FROM t2dm_candidates c
LEFT JOIN t1dm_exclusion e ON c.person_id = e.person_id
WHERE e.person_id IS NULL; -- "NOT" T1DM