--error
WITH person_adult AS (
    SELECT  p.person_id,
            p.year_of_birth,
            MIN(v.visit_start_date) AS first_visit_date
    FROM    person p
    JOIN    visit_occurrence v
        ON  v.person_id = p.person_id
    GROUP BY p.person_id, p.year_of_birth
),
adult AS (
    SELECT  person_id
    FROM    person_adult
    WHERE   DATEDIFF(year, year_of_birth, first_visit_date) >= 18
),

-- 1. Diagnosis concept sets (ICD9CM / ICD10CM mapped to OMOP standard concepts)

t2dm_dx AS (
    SELECT  c.person_id,
            c.condition_start_date,
            c.condition_occurrence_id
    FROM    condition_occurrence c
    JOIN    concept cc
        ON  c.condition_concept_id = cc.concept_id
    WHERE   cc.standard_concept = 'S'
      AND   cc.domain_id = 'Condition'
      AND (
                -- ICD9CM 250.x0, 250.x2 mapped to standard concepts
                (cc.vocabulary_id = 'ICD9CM'
                 AND cc.concept_code IN (
                     '25000','25002','25010','25012','25020','25022','25030','25032',
                     '25040','25042','25050','25052','25060','25062','25070','25072',
                     '25080','25082','25090','25092'
                 ))
            OR  -- ICD10CM E11.*
                (cc.vocabulary_id = 'ICD10CM'
                 AND cc.concept_code LIKE 'E11%')
          )
),

t1dm_dx AS (
    SELECT  c.person_id,
            c.condition_start_date
    FROM    condition_occurrence c
    JOIN    concept cc
        ON  c.condition_concept_id = cc.concept_id
    WHERE   cc.standard_concept = 'S'
      AND   cc.domain_id = 'Condition'
      AND (
                (cc.vocabulary_id = 'ICD9CM'
                 AND cc.concept_code IN (
                     '25001','25003','25011','25013','25021','25023','25031','25033',
                     '25041','25043','25051','25053','25061','25063','25071','25073',
                     '25081','25083','25091','25093'
                 ))
            OR  (cc.vocabulary_id = 'ICD10CM'
                 AND cc.concept_code LIKE 'E10%')
          )
),

gestational_dm_dx AS (
    SELECT  c.person_id,
            c.condition_start_date
    FROM    condition_occurrence c
    JOIN    concept cc
        ON  c.condition_concept_id = cc.concept_id
    WHERE   cc.standard_concept = 'S'
      AND   cc.domain_id = 'Condition'
      AND   cc.vocabulary_id = 'ICD10CM'
      AND   cc.concept_code LIKE 'O24.4%'
),

secondary_dm_dx AS (
    SELECT  c.person_id,
            c.condition_start_date
    FROM    condition_occurrence c
    JOIN    concept cc
        ON  c.condition_concept_id = cc.concept_id
    WHERE   cc.standard_concept = 'S'
      AND   cc.domain_id = 'Condition'
      AND   cc.vocabulary_id = 'ICD10CM'
      AND   cc.concept_code LIKE 'E0[89]%'  -- E08.*, E09.*
       OR  (cc.vocabulary_id = 'ICD10CM' AND cc.concept_code LIKE 'E13%')
),

prediabetes_dx AS (
    SELECT  c.person_id,
            c.condition_start_date
    FROM    condition_occurrence c
    JOIN    concept cc
        ON  c.condition_concept_id = cc.concept_id
    WHERE   cc.standard_concept = 'S'
      AND   cc.domain_id = 'Condition'
      AND (
                (cc.vocabulary_id = 'ICD9CM'
                 AND cc.concept_code IN ('79021','79022','79029'))
            OR  (cc.vocabulary_id = 'ICD10CM'
                 AND cc.concept_code = 'R73.03')
          )
),

pcos_dx AS (
    SELECT  c.person_id,
            c.condition_start_date
    FROM    condition_occurrence c
    JOIN    concept cc
        ON  c.condition_concept_id = cc.concept_id
    WHERE   cc.standard_concept = 'S'
      AND   cc.domain_id = 'Condition'
      AND (
                (cc.vocabulary_id = 'ICD10CM' AND cc.concept_code = 'E28.2')
            OR  (cc.vocabulary_id = 'ICD9CM' AND cc.concept_code = '2564')
          )
),

-- 2. Medication concept sets (RxNorm standard concepts)

non_insulin_dm_drugs AS (
    SELECT  d.person_id,
            d.drug_exposure_start_date,
            d.drug_exposure_id
    FROM    drug_exposure d
    JOIN    concept dc
        ON  d.drug_concept_id = dc.concept_id
    WHERE   dc.standard_concept = 'S'
      AND   dc.domain_id = 'Drug'
      AND   dc.vocabulary_id = 'RxNorm'
      AND (
                -- Metformin (Glucophage, etc.)
                dc.concept_name LIKE '%metformin%'
            OR  dc.concept_name LIKE '%Glucophage%'
            OR  dc.concept_name LIKE '%Fortamet%'
            OR  dc.concept_name LIKE '%Glumetza%'
            OR  dc.concept_name LIKE '%Riomet%'
                -- Sulfonylureas
            OR  dc.concept_name LIKE '%glipizide%'
            OR  dc.concept_name LIKE '%glyburide%'
            OR  dc.concept_name LIKE '%glimepiride%'
                -- TZDs
            OR  dc.concept_name LIKE '%pioglitazone%'
            OR  dc.concept_name LIKE '%rosiglitazone%'
                -- DPP-4 inhibitors
            OR  dc.concept_name LIKE '%sitagliptin%'
            OR  dc.concept_name LIKE '%saxagliptin%'
            OR  dc.concept_name LIKE '%linagliptin%'
            OR  dc.concept_name LIKE '%alogliptin%'
                -- GLP-1 RAs
            OR  dc.concept_name LIKE '%exenatide%'
            OR  dc.concept_name LIKE '%liraglutide%'
            OR  dc.concept_name LIKE '%dulaglutide%'
            OR  dc.concept_name LIKE '%semaglutide%'
            OR  dc.concept_name LIKE '%lixisenatide%'
                -- SGLT2 inhibitors
            OR  dc.concept_name LIKE '%canagliflozin%'
            OR  dc.concept_name LIKE '%dapagliflozin%'
            OR  dc.concept_name LIKE '%empagliflozin%'
            OR  dc.concept_name LIKE '%ertugliflozin%'
          )
),

insulin_drugs AS (
    SELECT  d.person_id,
            d.drug_exposure_start_date,
            d.drug_exposure_id
    FROM    drug_exposure d
    JOIN    concept dc
        ON  d.drug_concept_id = dc.concept_id
    WHERE   dc.standard_concept = 'S'
      AND   dc.domain_id = 'Drug'
      AND   dc.vocabulary_id = 'RxNorm'
      AND (
                dc.concept_name LIKE '%insulin%'
            OR  dc.concept_name LIKE '%glargine%'
            OR  dc.concept_name LIKE '%detemir%'
            OR  dc.concept_name LIKE '%degludec%'
            OR  dc.concept_name LIKE '%lispro%'
            OR  dc.concept_name LIKE '%aspart%'
            OR  dc.concept_name LIKE '%glulisine%'
          )
),

-- 3. Laboratory evidence (HbA1c, FPG, RPG)

dm_labs AS (
    SELECT  m.person_id,
            m.measurement_date,
            m.value_as_number,
            mc.concept_code,
            mc.vocabulary_id
    FROM    measurement m
    JOIN    concept mc
        ON  m.measurement_concept_id = mc.concept_id
    WHERE   mc.standard_concept = 'S'
      AND   mc.domain_id = 'Measurement'
      AND (
                -- HbA1c LOINC codes
                (mc.vocabulary_id = 'LOINC'
                 AND mc.concept_code IN ('4548-4','17856-6','41995-2','59261-8'))
            OR  -- Fasting plasma glucose
                (mc.vocabulary_id = 'LOINC'
                 AND mc.concept_code IN ('1558-6','14771-0'))
            OR  -- Random plasma glucose
                (mc.vocabulary_id = 'LOINC'
                 AND mc.concept_code = '2345-7')
          )
),

dm_labs_positive AS (
    SELECT  person_id,
            MIN(measurement_date) AS first_dm_lab_date
    FROM (
        SELECT  person_id,
                measurement_date
        FROM    dm_labs
        WHERE   (
                    -- HbA1c >= 6.5%
                    (concept_code IN ('4548-4','17856-6','41995-2','59261-8')
                     AND value_as_number >= 6.5)
                OR  -- FPG >= 126 mg/dL
                    (concept_code IN ('1558-6','14771-0')
                     AND value_as_number >= 126)
                OR  -- RPG >= 200 mg/dL
                    (concept_code = '2345-7'
                     AND value_as_number >= 200)
               )
    ) x
    GROUP BY person_id
),

-- 4. Aggregate counts and flags

t2dm_dx_summary AS (
    SELECT  person_id,
            COUNT(DISTINCT condition_start_date) AS t2dm_dx_dates,
            MIN(condition_start_date) AS first_t2dm_dx_date
    FROM    t2dm_dx
    GROUP BY person_id
),

t1dm_dx_summary AS (
    SELECT  person_id,
            COUNT(*) AS t1dm_dx_count
    FROM    t1dm_dx
    GROUP BY person_id
),

gestational_dm_summary AS (
    SELECT  person_id,
            COUNT(*) AS gest_dm_count
    FROM    gestational_dm_dx
    GROUP BY person_id
),

secondary_dm_summary AS (
    SELECT  person_id,
            COUNT(*) AS secondary_dm_count
    FROM    secondary_dm_dx
    GROUP BY person_id
),

prediabetes_summary AS (
    SELECT  person_id,
            COUNT(*) AS prediabetes_count
    FROM    prediabetes_dx
    GROUP BY person_id
),

non_insulin_dm_summary AS (
    SELECT  person_id,
            COUNT(*) AS non_insulin_dm_rx_count,
            MIN(drug_exposure_start_date) AS first_non_insulin_dm_rx_date
    FROM    non_insulin_dm_drugs
    GROUP BY person_id
),

insulin_summary AS (
    SELECT  person_id,
            COUNT(*) AS insulin_rx_count,
            MIN(drug_exposure_start_date) AS first_insulin_rx_date
    FROM    insulin_drugs
    GROUP BY person_id
),

pcos_summary AS (
    SELECT  person_id,
            COUNT(*) AS pcos_count
    FROM    pcos_dx
    GROUP BY person_id
),

-- 5. Build inclusion candidates

candidates AS (
    SELECT  a.person_id,

            COALESCE(t2.t2dm_dx_dates, 0)              AS t2dm_dx_dates,
            COALESCE(t2.first_t2dm_dx_date, NULL)      AS first_t2dm_dx_date,

            COALESCE(nid.non_insulin_dm_rx_count, 0)   AS non_insulin_dm_rx_count,
            COALESCE(nid.first_non_insulin_dm_rx_date, NULL) AS first_non_insulin_dm_rx_date,

            COALESCE(dl.first_dm_lab_date, NULL)       AS first_dm_lab_date,

            COALESCE(t1.t1dm_dx_count, 0)              AS t1dm_dx_count,
            COALESCE(gd.gest_dm_count, 0)              AS gest_dm_count,
            COALESCE(sd.secondary_dm_count, 0)         AS secondary_dm_count,
            COALESCE(pd.prediabetes_count, 0)          AS prediabetes_count,
            COALESCE(pc.pcos_count, 0)                 AS pcos_count,

            COALESCE(ins.insulin_rx_count, 0)          AS insulin_rx_count

    FROM    adult a
    LEFT JOIN t2dm_dx_summary       t2   ON a.person_id = t2.person_id
    LEFT JOIN non_insulin_dm_summary nid  ON a.person_id = nid.person_id
    LEFT JOIN dm_labs_positive      dl   ON a.person_id = dl.person_id
    LEFT JOIN t1dm_dx_summary       t1   ON a.person_id = t1.person_id
    LEFT JOIN gestational_dm_summary gd  ON a.person_id = gd.person_id
    LEFT JOIN secondary_dm_summary  sd   ON a.person_id = sd.person_id
    LEFT JOIN prediabetes_summary   pd   ON a.person_id = pd.person_id
    LEFT JOIN pcos_summary          pc   ON a.person_id = pc.person_id
    LEFT JOIN insulin_summary       ins  ON a.person_id = ins.person_id
),

-- 6. Apply inclusion logic

included_raw AS (
    SELECT  person_id,
            CASE
                WHEN t2dm_dx_dates >= 2 THEN 'DX_ONLY'
                WHEN t2dm_dx_dates >= 1
                     AND (non_insulin_dm_rx_count >= 1 OR first_dm_lab_date IS NOT NULL)
                     THEN 'DX_PLUS_RX_OR_LAB'
                WHEN t2dm_dx_dates = 0
                     AND non_insulin_dm_rx_count >= 1
                     AND first_dm_lab_date IS NOT NULL
                     THEN 'RX_PLUS_LAB'
                ELSE NULL
            END AS inclusion_path
    FROM    candidates
),

included AS (
    SELECT  c.*
    FROM    candidates c
    JOIN    included_raw ir
        ON  c.person_id = ir.person_id
    WHERE   ir.inclusion_path IS NOT NULL
),

-- 7. Apply exclusion logic

final_cohort AS (
    SELECT  i.person_id,
            -- Define index date as earliest of T2DM dx, non-insulin DM med, or positive DM lab
            MIN(
                COALESCE(i.first_t2dm_dx_date,
                         i.first_non_insulin_dm_rx_date,
                         i.first_dm_lab_date)
            ) AS index_date
    FROM    included i
    WHERE   -- Exclude T1DM-only (no T2DM dx, but T1DM dx present)
            NOT (
                    i.t2dm_dx_dates = 0
                AND i.t1dm_dx_count > 0
                )

      AND   -- Exclude gestational-only
            NOT (
                    i.t2dm_dx_dates = 0
                AND i.gest_dm_count > 0
                )

      AND   -- Exclude secondary DM-only
            NOT (
                    i.t2dm_dx_dates = 0
                AND i.secondary_dm_count > 0
                )

      AND   -- Exclude prediabetes-only (no T2DM dx, no DM-range labs, no non-insulin DM meds)
            NOT (
                    i.t2dm_dx_dates = 0
                AND i.first_dm_lab_date IS NULL
                AND i.non_insulin_dm_rx_count = 0
                AND i.prediabetes_count > 0
                )

      AND   -- Exclude PCOS + metformin only (no T2DM dx, no DM-range labs)
            NOT (
                    i.t2dm_dx_dates = 0
                AND i.first_dm_lab_date IS NULL
                AND i.non_insulin_dm_rx_count > 0
                AND i.pcos_count > 0
                )

    GROUP BY i.person_id
)

SELECT *
FROM   final_cohort;
