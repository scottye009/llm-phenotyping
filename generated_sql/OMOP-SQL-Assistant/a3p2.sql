-- Type 2 Diabetes Mellitus (T2DM) phenotype
-- Logic:
--   Include patients meeting ANY of:
--     A) >=2 T2DM diagnosis records on different dates
--     B) >=1 T2DM diagnosis + >=1 diabetes medication exposure
--     C) >=2 abnormal diabetes laboratory results
--   Exclude patients with evidence suggesting Type 1 diabetes only.
--
-- Returns:
--   person_id

WITH t2dm_dx AS (
    -- ICD-9-CM 250.x0 / 250.x2 = Type 2 DM
    -- ICD-10-CM E11*
    SELECT
        person_id,
        condition_start_date
    FROM condition_occurrence
    WHERE
        (
            regexp_matches(upper(coalesce(condition_source_value, '')),
                           '^250\\.[0-9][02]$')
            OR upper(coalesce(condition_source_value, '')) LIKE 'E11%'
        )
        OR (
            condition_source_concept_name IS NOT NULL
            AND (
                lower(condition_source_concept_name) LIKE '%type 2 diabetes%'
                OR lower(condition_source_concept_name) LIKE '%type ii diabetes%'
                OR lower(condition_source_concept_name) LIKE '%t2dm%'
            )
        )
),

t2dm_dx_patients AS (
    SELECT person_id
    FROM t2dm_dx
    GROUP BY person_id
    HAVING COUNT(DISTINCT condition_start_date) >= 2
),

type1_dx AS (
    -- ICD-9-CM 250.x1 / 250.x3 = Type 1 DM
    -- ICD-10-CM E10*
    SELECT DISTINCT person_id
    FROM condition_occurrence
    WHERE
        regexp_matches(upper(coalesce(condition_source_value, '')),
                       '^250\\.[0-9][13]$')
        OR upper(coalesce(condition_source_value, '')) LIKE 'E10%'
        OR (
            condition_source_concept_name IS NOT NULL
            AND (
                lower(condition_source_concept_name) LIKE '%type 1 diabetes%'
                OR lower(condition_source_concept_name) LIKE '%type i diabetes%'
                OR lower(condition_source_concept_name) LIKE '%t1dm%'
            )
        )
),

dm_medications AS (
    -- Common generic and brand names for T2DM therapies
    SELECT DISTINCT person_id
    FROM drug_exposure d
    WHERE
        lower(coalesce(d.drug_source_value, '')) LIKE '%metformin%'
        OR lower(coalesce(d.drug_source_value, '')) LIKE '%glucophage%'
        OR lower(coalesce(d.drug_source_value, '')) LIKE '%glumetza%'
        OR lower(coalesce(d.drug_source_value, '')) LIKE '%fortamet%'

        OR lower(coalesce(d.drug_source_value, '')) LIKE '%glyburide%'
        OR lower(coalesce(d.drug_source_value, '')) LIKE '%glibenclamide%'
        OR lower(coalesce(d.drug_source_value, '')) LIKE '%diabeta%'
        OR lower(coalesce(d.drug_source_value, '')) LIKE '%glynase%'

        OR lower(coalesce(d.drug_source_value, '')) LIKE '%glipizide%'
        OR lower(coalesce(d.drug_source_value, '')) LIKE '%glucotrol%'

        OR lower(coalesce(d.drug_source_value, '')) LIKE '%glimepiride%'
        OR lower(coalesce(d.drug_source_value, '')) LIKE '%amaryl%'

        OR lower(coalesce(d.drug_source_value, '')) LIKE '%pioglitazone%'
        OR lower(coalesce(d.drug_source_value, '')) LIKE '%actos%'

        OR lower(coalesce(d.drug_source_value, '')) LIKE '%rosiglitazone%'
        OR lower(coalesce(d.drug_source_value, '')) LIKE '%avandia%'

        OR lower(coalesce(d.drug_source_value, '')) LIKE '%sitagliptin%'
        OR lower(coalesce(d.drug_source_value, '')) LIKE '%januvia%'

        OR lower(coalesce(d.drug_source_value, '')) LIKE '%saxagliptin%'
        OR lower(coalesce(d.drug_source_value, '')) LIKE '%onglyza%'

        OR lower(coalesce(d.drug_source_value, '')) LIKE '%linagliptin%'
        OR lower(coalesce(d.drug_source_value, '')) LIKE '%tradjenta%'

        OR lower(coalesce(d.drug_source_value, '')) LIKE '%alogliptin%'
        OR lower(coalesce(d.drug_source_value, '')) LIKE '%nesina%'

        OR lower(coalesce(d.drug_source_value, '')) LIKE '%empagliflozin%'
        OR lower(coalesce(d.drug_source_value, '')) LIKE '%jardiance%'

        OR lower(coalesce(d.drug_source_value, '')) LIKE '%dapagliflozin%'
        OR lower(coalesce(d.drug_source_value, '')) LIKE '%farxiga%'

        OR lower(coalesce(d.drug_source_value, '')) LIKE '%canagliflozin%'
        OR lower(coalesce(d.drug_source_value, '')) LIKE '%invokana%'

        OR lower(coalesce(d.drug_source_value, '')) LIKE '%ertugliflozin%'
        OR lower(coalesce(d.drug_source_value, '')) LIKE '%steglatro%'

        OR lower(coalesce(d.drug_source_value, '')) LIKE '%liraglutide%'
        OR lower(coalesce(d.drug_source_value, '')) LIKE '%victoza%'

        OR lower(coalesce(d.drug_source_value, '')) LIKE '%semaglutide%'
        OR lower(coalesce(d.drug_source_value, '')) LIKE '%ozempic%'

        OR lower(coalesce(d.drug_source_value, '')) LIKE '%dulaglutide%'
        OR lower(coalesce(d.drug_source_value, '')) LIKE '%trulicity%'

        OR lower(coalesce(d.drug_source_value, '')) LIKE '%exenatide%'
        OR lower(coalesce(d.drug_source_value, '')) LIKE '%byetta%'
        OR lower(coalesce(d.drug_source_value, '')) LIKE '%bydureon%'

        OR lower(coalesce(d.drug_source_value, '')) LIKE '%tirzepatide%'
        OR lower(coalesce(d.drug_source_value, '')) LIKE '%mounjaro%'

        OR lower(coalesce(d.drug_source_value, '')) LIKE '%acarbose%'
        OR lower(coalesce(d.drug_source_value, '')) LIKE '%precose%'

        OR lower(coalesce(d.drug_source_value, '')) LIKE '%miglitol%'
        OR lower(coalesce(d.drug_source_value, '')) LIKE '%glyset%'

        OR lower(coalesce(d.drug_source_value, '')) LIKE '%repaglinide%'
        OR lower(coalesce(d.drug_source_value, '')) LIKE '%prandin%'

        OR lower(coalesce(d.drug_source_value, '')) LIKE '%nateglinide%'
        OR lower(coalesce(d.drug_source_value, '')) LIKE '%starlix%'
),

abnormal_dm_labs AS (
    -- Diabetes-defining laboratory results
    SELECT person_id
    FROM measurement
    WHERE value_as_number IS NOT NULL
      AND (
            (
                lower(coalesce(measurement_source_value,'')) LIKE '%a1c%'
                OR lower(coalesce(measurement_source_value,'')) LIKE '%hba1c%'
                OR lower(coalesce(measurement_source_value,'')) LIKE '%hemoglobin a1c%'
                OR lower(coalesce(measurement_source_value,'')) LIKE '%glycohemoglobin%'
            )
            AND value_as_number >= 6.5
          )
       OR (
            (
                lower(coalesce(measurement_source_value,'')) LIKE '%fasting glucose%'
                OR lower(coalesce(measurement_source_value,'')) LIKE '%fpg%'
                OR lower(coalesce(measurement_source_value,'')) LIKE '%glucose fasting%'
            )
            AND value_as_number >= 126
          )
       OR (
            (
                lower(coalesce(measurement_source_value,'')) LIKE '%glucose%'
                OR lower(coalesce(measurement_source_value,'')) LIKE '%plasma glucose%'
            )
            AND value_as_number >= 200
          )
    GROUP BY person_id
    HAVING COUNT(*) >= 2
),

dx_plus_med AS (
    SELECT DISTINCT d.person_id
    FROM t2dm_dx d
    INNER JOIN dm_medications m
        ON d.person_id = m.person_id
)

SELECT DISTINCT person_id
FROM (
    SELECT person_id FROM t2dm_dx_patients
    UNION
    SELECT person_id FROM dx_plus_med
    UNION
    SELECT person_id FROM abnormal_dm_labs
) cases
WHERE person_id NOT IN (
    SELECT person_id
    FROM type1_dx
);