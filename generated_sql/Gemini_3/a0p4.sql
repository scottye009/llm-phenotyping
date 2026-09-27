/* 
   Phenotype: Type 2 Diabetes Mellitus (T2DM)
   Logic: (Diagnosis OR (Labs AND Meds)) AND NOT (Exclusions)
*/

WITH T2DM_Diagnosis AS (
    SELECT person_id 
    FROM condition_occurrence 
    WHERE condition_concept_id IN (SELECT concept_id FROM concept WHERE concept_id = 201826 OR (concept_code LIKE 'E11%' AND vocabulary_id = 'ICD10CM') OR (concept_code LIKE '250.0%' AND vocabulary_id = 'ICD9CM'))
),

T2DM_Labs AS (
    SELECT person_id 
    FROM measurement 
    WHERE (measurement_concept_id IN (3004327, 3007263) AND value_as_number >= 6.5) -- HbA1c
       OR (measurement_concept_id IN (3004501, 3015632) AND value_as_number >= 126) -- Fasting Glucose
),

T2DM_Meds AS (
    SELECT person_id 
    FROM drug_exposure 
    WHERE drug_concept_id IN (
        -- Biguanides: Metformin (Glucophage, Fortamet)
        1503297, 43526465, 
        -- Sulfonylureas: Glipizide (Glucotrol), Glyburide (Diabeta, Glynase), Glimepiride (Amaryl)
        1551860, 1560171, 1547504,
        -- TZDs: Pioglitazone (Actos), Rosiglitazone (Avandia)
        1525215, 1594973,
        -- DPP-4: Sitagliptin (Januvia), Saxagliptin (Onglyza), Linagliptin (Tradjenta)
        1580747, 1583722, 40166035,
        -- SGLT2: Empagliflozin (Jardiance), Canagliflozin (Invokana), Dapagliflozin (Farxiga)
        44231629, 43526424, 44231617,
        -- GLP-1: Liraglutide (Victoza), Semaglutide (Ozempic/Rybelsus), Dulaglutide (Trulicity)
        43292412, 45774435, 45892847
    )
),

Exclusions AS (
    SELECT person_id 
    FROM condition_occurrence 
    WHERE condition_concept_id IN (SELECT concept_id FROM concept WHERE concept_id = 201254 OR (concept_code LIKE 'E10%' AND vocabulary_id = 'ICD10CM') OR (concept_code LIKE '250.%1' AND vocabulary_id = 'ICD9CM')) -- Type 1
       OR condition_concept_id IN (SELECT concept_id FROM concept WHERE (concept_code LIKE 'O24.4%' AND vocabulary_id = 'ICD10CM') OR (concept_code = '648.8' AND vocabulary_id = 'ICD9CM')) -- Gestational
       OR condition_concept_id IN (SELECT concept_id FROM concept WHERE (concept_code LIKE 'E08%' OR concept_code LIKE 'E09%' OR concept_code LIKE 'E13%')) -- Secondary
)

SELECT DISTINCT 
    p.person_id
FROM person p
JOIN (
    -- Inclusion Logic: Diagnosis OR (Labs AND Meds)
    SELECT person_id FROM T2DM_Diagnosis
    UNION
    SELECT l.person_id 
    FROM T2DM_Labs l 
    JOIN T2DM_Meds m ON l.person_id = m.person_id
) as inclusion ON p.person_id = inclusion.person_id
LEFT JOIN Exclusions e ON p.person_id = e.person_id
WHERE e.person_id IS NULL;