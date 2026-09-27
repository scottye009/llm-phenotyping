WITH t2dm_dx AS (
    SELECT
        co.person_id,
        co.condition_start_date AS index_date,
        co.condition_concept_id
    FROM condition_occurrence co
    JOIN concept c
        ON co.condition_concept_id = c.concept_id
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (
            c.concept_code LIKE '250.%0'
         OR c.concept_code LIKE '250.%2'
         OR c.concept_code LIKE 'E11%'
      )
),

confirmatory_t2dm_dx AS (
    SELECT DISTINCT
        a.person_id,
        a.index_date
    FROM t2dm_dx a
    JOIN t2dm_dx b
        ON a.person_id = b.person_id
       AND b.index_date > a.index_date
       AND b.index_date <= a.index_date + INTERVAL '365 days'
),

t2dm_meds AS (
    SELECT DISTINCT
        de.person_id,
        de.drug_exposure_start_date AS drug_date
    FROM drug_exposure de
    JOIN concept c
        ON de.drug_concept_id = c.concept_id
    WHERE LOWER(c.concept_name) LIKE ANY (ARRAY[
        '%metformin%',
        '%glucophage%', '%fortamet%', '%glumetza%', '%riomet%',
        '%glipizide%', '%glyburide%', '%glimepiride%',
        '%glucotrol%', '%diabeta%', '%micronase%', '%glynase%', '%amaryl%',
        '%sitagliptin%', '%saxagliptin%', '%linagliptin%', '%alogliptin%',
        '%januvia%', '%onglyza%', '%tradjenta%', '%nesina%',
        '%exenatide%', '%liraglutide%', '%dulaglutide%', '%semaglutide%',
        '%byetta%', '%bydureon%', '%victoza%', '%trulicity%', '%ozempic%', '%rybelsus%',
        '%canagliflozin%', '%dapagliflozin%', '%empagliflozin%', '%ertugliflozin%',
        '%invokana%', '%farxiga%', '%jardiance%', '%steglatro%',
        '%pioglitazone%', '%rosiglitazone%', '%actos%', '%avandia%',
        '%insulin%', '%lantus%', '%basaglar%', '%toujeo%', '%levemir%',
        '%tresiba%', '%humalog%', '%novolog%', '%apidra%'
    ])
),

abnormal_labs AS (
    SELECT DISTINCT
        m.person_id,
        m.measurement_date AS lab_date
    FROM measurement m
    JOIN concept c
        ON m.measurement_concept_id = c.concept_id
    WHERE (
            c.concept_code IN ('4548-4', '17856-6', '59261-8')
            AND m.value_as_number >= 6.5
          )
       OR (
            c.concept_code IN ('1558-6', '1557-8')
            AND m.value_as_number >= 126
          )
       OR (
            c.concept_code = '2345-7'
            AND m.value_as_number >= 200
          )
),

type1_dx AS (
    SELECT DISTINCT
        co.person_id
    FROM condition_occurrence co
    JOIN concept c
        ON co.condition_concept_id = c.concept_id
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (
            c.concept_code LIKE '250.%1'
         OR c.concept_code LIKE '250.%3'
         OR c.concept_code LIKE 'E10%'
      )
),

gestational_secondary_dx AS (
    SELECT DISTINCT
        co.person_id
    FROM condition_occurrence co
    JOIN concept c
        ON co.condition_concept_id = c.concept_id
    WHERE c.vocabulary_id IN ('ICD9CM', 'ICD10CM')
      AND (
            c.concept_code LIKE '648.8%'
         OR c.concept_code LIKE 'O24.4%'
         OR c.concept_code LIKE '249%'
         OR c.concept_code LIKE 'E08%'
         OR c.concept_code LIKE 'E09%'
         OR c.concept_code LIKE 'E13%'
      )
),

final_t2dm AS (
    SELECT DISTINCT
        dx.person_id,
        dx.index_date
    FROM t2dm_dx dx
    JOIN person p
        ON dx.person_id = p.person_id
    WHERE
        /* Adult at index */
        EXTRACT(YEAR FROM dx.index_date) - p.year_of_birth >= 18

        AND
        (
            /* Diagnosis confirmed by repeated T2DM diagnosis */
            EXISTS (
                SELECT 1
                FROM confirmatory_t2dm_dx cdx
                WHERE cdx.person_id = dx.person_id
                  AND cdx.index_date = dx.index_date
            )

            OR

            /* Diagnosis confirmed by diabetes medication */
            EXISTS (
                SELECT 1
                FROM t2dm_meds med
                WHERE med.person_id = dx.person_id
                  AND med.drug_date BETWEEN dx.index_date
                                      AND dx.index_date + INTERVAL '365 days'
            )

            OR

            /* Diagnosis confirmed by abnormal diabetes laboratory result */
            EXISTS (
                SELECT 1
                FROM abnormal_labs lab
                WHERE lab.person_id = dx.person_id
                  AND lab.lab_date BETWEEN dx.index_date
                                      AND dx.index_date + INTERVAL '365 days'
            )
        )

        AND NOT EXISTS (
            SELECT 1
            FROM type1_dx t1
            WHERE t1.person_id = dx.person_id
        )

        AND NOT EXISTS (
            SELECT 1
            FROM gestational_secondary_dx gs
            WHERE gs.person_id = dx.person_id
        )
)

SELECT
    person_id,
    MIN(index_date) AS t2dm_index_date
FROM final_t2dm
GROUP BY person_id;--0rows