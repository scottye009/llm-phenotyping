WITH t2dm_icd_source AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD9CM'
      AND concept_code IN (
          '25000','25002','25010','25012','25020','25022','25030','25032',
          '25040','25042','25050','25052','25060','25062','25070','25072',
          '25080','25082','25090','25092'
      )

    UNION

    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD10CM'
      AND concept_code IN (
          'E11','E110','E1100','E1101','E111','E1110','E1111',
          'E112','E1121','E1122','E1129',
          'E113','E1131','E11311','E11319','E1132','E11321','E113211',
          'E113212','E113213','E113219','E11329','E113291','E113292',
          'E113293','E113299','E1133','E11331','E113311','E113312',
          'E113313','E113319','E11339','E113391','E113392','E113393',
          'E113399','E1134','E11341','E113411','E113412','E113413',
          'E113419','E11349','E113491','E113492','E113493','E113499',
          'E1135','E11351','E113511','E113512','E113513','E113519',
          'E113521','E113522','E113523','E113529','E113531','E113532',
          'E113533','E113539','E113541','E113542','E113543','E113549',
          'E113551','E113552','E113553','E113559','E113591','E113592',
          'E113593','E113599','E1136','E1137','E1137X1','E1137X2',
          'E1137X3','E1137X9','E1139',
          'E114','E1140','E1141','E1142','E1143','E1144','E1149',
          'E115','E1151','E1152','E1159',
          'E116','E11610','E11618','E11620','E11621','E11622','E11628',
          'E11630','E11638','E11641','E11649','E1165',
          'E1169','E118','E1181','E1182','E1183','E1184','E1185',
          'E1186','E1187','E1188','E1189',
          'E119'
      )
),

t2dm_standard_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM t2dm_icd_source s
    JOIN public.concept_relationship cr
      ON s.concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'

    UNION

    SELECT concept_id
    FROM t2dm_icd_source
),

t2dm_dx AS (
    SELECT DISTINCT
        co.person_id,
        co.condition_start_date AS event_date
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (
        SELECT concept_id FROM t2dm_standard_concepts
    )
),

exclusion_icd_source AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD9CM'
      AND (
          concept_code LIKE '25001%'
          OR concept_code LIKE '25003%'
          OR concept_code LIKE '6488%'
          OR concept_code LIKE '249%'
      )

    UNION

    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD10CM'
      AND (
          concept_code LIKE 'E10%'
          OR concept_code LIKE 'O24%'
          OR concept_code LIKE 'E08%'
          OR concept_code LIKE 'E09%'
          OR concept_code LIKE 'E13%'
      )
),

exclusion_standard_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM exclusion_icd_source s
    JOIN public.concept_relationship cr
      ON s.concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'

    UNION

    SELECT concept_id
    FROM exclusion_icd_source
),

exclusion_dx AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    WHERE co.condition_concept_id IN (
        SELECT concept_id FROM exclusion_standard_concepts
    )
),

t2dm_med_concepts AS (
    SELECT concept_id
    FROM public.concept
    WHERE domain_id = 'Drug'
      AND (
          LOWER(concept_name) LIKE '%metformin%'
          OR LOWER(concept_name) LIKE '%glucophage%'
          OR LOWER(concept_name) LIKE '%glumetza%'
          OR LOWER(concept_name) LIKE '%fortamet%'
          OR LOWER(concept_name) LIKE '%riomet%'

          OR LOWER(concept_name) LIKE '%glipizide%'
          OR LOWER(concept_name) LIKE '%glucotrol%'
          OR LOWER(concept_name) LIKE '%glyburide%'
          OR LOWER(concept_name) LIKE '%diabeta%'
          OR LOWER(concept_name) LIKE '%glynase%'
          OR LOWER(concept_name) LIKE '%micronase%'
          OR LOWER(concept_name) LIKE '%glimepiride%'
          OR LOWER(concept_name) LIKE '%amaryl%'

          OR LOWER(concept_name) LIKE '%pioglitazone%'
          OR LOWER(concept_name) LIKE '%actos%'
          OR LOWER(concept_name) LIKE '%rosiglitazone%'
          OR LOWER(concept_name) LIKE '%avandia%'

          OR LOWER(concept_name) LIKE '%sitagliptin%'
          OR LOWER(concept_name) LIKE '%januvia%'
          OR LOWER(concept_name) LIKE '%saxagliptin%'
          OR LOWER(concept_name) LIKE '%onglyza%'
          OR LOWER(concept_name) LIKE '%linagliptin%'
          OR LOWER(concept_name) LIKE '%tradjenta%'
          OR LOWER(concept_name) LIKE '%alogliptin%'
          OR LOWER(concept_name) LIKE '%nesina%'

          OR LOWER(concept_name) LIKE '%liraglutide%'
          OR LOWER(concept_name) LIKE '%victoza%'
          OR LOWER(concept_name) LIKE '%semaglutide%'
          OR LOWER(concept_name) LIKE '%ozempic%'
          OR LOWER(concept_name) LIKE '%rybelsus%'
          OR LOWER(concept_name) LIKE '%dulaglutide%'
          OR LOWER(concept_name) LIKE '%trulicity%'
          OR LOWER(concept_name) LIKE '%exenatide%'
          OR LOWER(concept_name) LIKE '%byetta%'
          OR LOWER(concept_name) LIKE '%bydureon%'
          OR LOWER(concept_name) LIKE '%tirzepatide%'
          OR LOWER(concept_name) LIKE '%mounjaro%'

          OR LOWER(concept_name) LIKE '%empagliflozin%'
          OR LOWER(concept_name) LIKE '%jardiance%'
          OR LOWER(concept_name) LIKE '%canagliflozin%'
          OR LOWER(concept_name) LIKE '%invokana%'
          OR LOWER(concept_name) LIKE '%dapagliflozin%'
          OR LOWER(concept_name) LIKE '%farxiga%'
          OR LOWER(concept_name) LIKE '%ertugliflozin%'
          OR LOWER(concept_name) LIKE '%steglatro%'
      )
),

t2dm_med AS (
    SELECT DISTINCT
        de.person_id,
        de.drug_exposure_start_date AS event_date
    FROM public.drug_exposure de
    WHERE de.drug_concept_id IN (
        SELECT concept_id FROM t2dm_med_concepts
    )
),

diabetes_lab AS (
    SELECT DISTINCT
        m.person_id,
        m.measurement_date AS event_date
    FROM public.measurement m
    JOIN public.concept c
      ON m.measurement_concept_id = c.concept_id
    WHERE m.value_as_number IS NOT NULL
      AND (
          (
              LOWER(c.concept_name) LIKE '%hemoglobin a1c%'
              AND m.value_as_number >= 6.5
          )
          OR (
              LOWER(c.concept_name) LIKE '%hba1c%'
              AND m.value_as_number >= 6.5
          )
          OR (
              LOWER(c.concept_name) LIKE '%fasting glucose%'
              AND m.value_as_number >= 126
          )
          OR (
              LOWER(c.concept_name) LIKE '%glucose%'
              AND LOWER(c.concept_name) NOT LIKE '%fasting%'
              AND m.value_as_number >= 200
          )
          OR (
              LOWER(c.concept_name) LIKE '%oral glucose tolerance%'
              AND m.value_as_number >= 200
          )
      )
),

dx_counts AS (
    SELECT
        person_id,
        COUNT(DISTINCT event_date) AS t2dm_dx_dates
    FROM t2dm_dx
    GROUP BY person_id
),

phenotype_candidates AS (
    SELECT DISTINCT d.person_id
    FROM t2dm_dx d
    JOIN t2dm_med med
      ON d.person_id = med.person_id

    UNION

    SELECT DISTINCT d.person_id
    FROM t2dm_dx d
    JOIN diabetes_lab lab
      ON d.person_id = lab.person_id

    UNION

    SELECT DISTINCT med.person_id
    FROM t2dm_med med
    JOIN diabetes_lab lab
      ON med.person_id = lab.person_id

    UNION

    SELECT person_id
    FROM dx_counts
    WHERE t2dm_dx_dates >= 2
)

SELECT DISTINCT
    p.person_id
FROM public.person p
JOIN phenotype_candidates pc
  ON p.person_id = pc.person_id
WHERE NOT EXISTS (
    SELECT 1
    FROM exclusion_dx ex
    WHERE ex.person_id = p.person_id
)
ORDER BY p.person_id;