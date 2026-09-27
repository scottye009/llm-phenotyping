SELECT
  final.person_id,
  final.index_date
FROM (
  /* Restrict to persons whose index_date falls within an observation period */
  SELECT
    ci.person_id,
    ci.index_date
  FROM (
    /* Earliest qualifying index_date across rules A, B, C, D */
    SELECT
      u.person_id,
      MIN(u.index_date) AS index_date
    FROM (
      /* Rule A: >=2 T2DM diagnosis dates */
      SELECT
        dx.person_id,
        MIN(dx.dx_date) AS index_date
      FROM (
        SELECT
          co.person_id,
          co.condition_start_date::date AS dx_date
        FROM public.condition_occurrence co
        JOIN public.concept c
          ON c.concept_id = co.condition_source_concept_id
        WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
          AND (
            /* ICD10CM: E11.* (Type 2 diabetes mellitus) */
            (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E11%')
            /* ICD9CM: 250.xx with last digit 0 or 2 (Type II or unspecified) */
            OR (
              c.vocabulary_id = 'ICD9CM'
              AND c.concept_code LIKE '250.%'
              AND RIGHT(regexp_replace(c.concept_code, '[^0-9]', '', 'g'), 1) IN ('0','2')
            )
          )
      ) dx
      GROUP BY dx.person_id
      HAVING COUNT(DISTINCT dx.dx_date) >= 2

      UNION ALL

      /* Rule B: >=1 T2DM dx date AND >=1 non-insulin antihyperglycemic exposure */
      SELECT
        j.person_id,
        MIN(j.first_evidence_date) AS index_date
      FROM (
        SELECT
          d.person_id,
          LEAST(d.dx_date, m.drug_date) AS first_evidence_date
        FROM (
          SELECT
            co.person_id,
            co.condition_start_date::date AS dx_date
          FROM public.condition_occurrence co
          JOIN public.concept c
            ON c.concept_id = co.condition_source_concept_id
          WHERE c.vocabulary_id IN ('ICD9CM','ICD10CM')
            AND (
              (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E11%')
              OR (
                c.vocabulary_id = 'ICD9CM'
                AND c.concept_code LIKE '250.%'
                AND RIGHT(regexp_replace(c.concept_code, '[^0-9]', '', 'g'), 1) IN ('0','2')
              )
            )
        ) d
        JOIN (
          SELECT
            de.person_id,
            de.drug_exposure_start_date::date AS drug_date
          FROM public.drug_exposure de
          JOIN public.concept c
            ON c.concept_id = de.drug_concept_id
          WHERE c.domain_id = 'Drug'
            AND c.vocabulary_id IN ('RxNorm','RxNorm Extension')
            AND (
              /* Biguanide */
              c.concept_name ILIKE '%metformin%' OR c.concept_name ILIKE '%glucophage%' OR
              c.concept_name ILIKE '%fortamet%' OR c.concept_name ILIKE '%glumetza%' OR
              c.concept_name ILIKE '%riomet%'
              /* Sulfonylureas */
              OR c.concept_name ILIKE '%glipizide%' OR c.concept_name ILIKE '%glucotrol%' OR
                 c.concept_name ILIKE '%glucotrol xl%' OR
                 c.concept_name ILIKE '%glyburide%' OR c.concept_name ILIKE '%diabeta%' OR
                 c.concept_name ILIKE '%micronase%' OR c.concept_name ILIKE '%glynase%' OR
                 c.concept_name ILIKE '%glimepiride%' OR c.concept_name ILIKE '%amaryl%'
              /* Thiazolidinediones */
              OR c.concept_name ILIKE '%pioglitazone%' OR c.concept_name ILIKE '%actos%' OR
                 c.concept_name ILIKE '%rosiglitazone%' OR c.concept_name ILIKE '%avandia%'
              /* DPP-4 inhibitors */
              OR c.concept_name ILIKE '%sitagliptin%' OR c.concept_name ILIKE '%januvia%' OR
                 c.concept_name ILIKE '%saxagliptin%' OR c.concept_name ILIKE '%onglyza%' OR
                 c.concept_name ILIKE '%linagliptin%' OR c.concept_name ILIKE '%tradjenta%' OR
                 c.concept_name ILIKE '%alogliptin%' OR c.concept_name ILIKE '%nesina%'
              /* GLP-1 receptor agonists */
              OR c.concept_name ILIKE '%exenatide%' OR c.concept_name ILIKE '%byetta%' OR
                 c.concept_name ILIKE '%bydureon%' OR
                 c.concept_name ILIKE '%liraglutide%' OR c.concept_name ILIKE '%victoza%' OR
                 c.concept_name ILIKE '%dulaglutide%' OR c.concept_name ILIKE '%trulicity%' OR
                 c.concept_name ILIKE '%semaglutide%' OR c.concept_name ILIKE '%ozempic%' OR
                 c.concept_name ILIKE '%rybelsus%' OR
                 c.concept_name ILIKE '%lixisenatide%' OR c.concept_name ILIKE '%adlyxin%' OR
                 c.concept_name ILIKE '%tirzepatide%' OR c.concept_name ILIKE '%mounjaro%'
              /* SGLT2 inhibitors */
              OR c.concept_name ILIKE '%canagliflozin%' OR c.concept_name ILIKE '%invokana%' OR
                 c.concept_name ILIKE '%dapagliflozin%' OR c.concept_name ILIKE '%farxiga%' OR
                 c.concept_name ILIKE '%empagliflozin%' OR c.concept_name ILIKE '%jardiance%' OR
                 c.concept_name ILIKE '%ertugliflozin%' OR c.concept_name ILIKE '%steglatro%'
              /* Meglitinides */
              OR c.concept_name ILIKE '%repaglinide%' OR c.concept_name ILIKE '%prandin%' OR
                 c.concept_name ILIKE '%nateglinide%' OR c.concept_name ILIKE '%starlix%'
              /* Alpha-glucosidase inhibitors */
              OR c.concept_name ILIKE '%acarbose%' OR c.concept_name ILIKE '%precose%' OR
                 c.concept_name ILIKE '%miglitol%' OR c.concept_name ILIKE '%glyset%'
              /* Amylin analog */
              OR c.concept_name ILIKE '%pramlintide%' OR c.concept_name ILIKE '%symlin%'
              /* Common combination products (by brand) */
              OR c.concept_name ILIKE '%janumet%' OR c.concept_name ILIKE '%synjardy%' OR
                 c.concept_name ILIKE '%xigduo%' OR c.concept_name ILIKE '%glyxambi%' OR
                 c.concept_name ILIKE '%qtern%'
            )
        ) m
          ON m.person_id = d.person_id
      ) j
      GROUP BY j.person_id

      UNION ALL

      /* Rule C: >=2 abnormal diabetes lab dates */
      SELECT
        l.person_id,
        MIN(l.lab_date) AS index_date
      FROM (
        SELECT
          m.person_id,
          m.measurement_date::date AS lab_date
        FROM public.measurement m
        JOIN public.concept c
          ON c.concept_id = m.measurement_concept_id
        WHERE m.value_as_number IS NOT NULL
          AND c.vocabulary_id = 'LOINC'
          AND (
            /* HbA1c >= 6.5% */
            (c.concept_name ILIKE '%hemoglobin a1c%' AND m.value_as_number >= 6.5)
            /* Fasting plasma glucose >= 126 mg/dL */
            OR (c.concept_name ILIKE '%glucose%' AND c.concept_name ILIKE '%fasting%'
                AND m.value_as_number >= 126)
            /* Random/any plasma/blood glucose >= 200 mg/dL */
            OR (c.concept_name ILIKE '%glucose%' AND m.value_as_number >= 200)
            /* 2-hr OGTT glucose >= 200 mg/dL */
            OR (c.concept_name ILIKE '%oral glucose tolerance%' AND m.value_as_number >= 200)
            OR (c.concept_name ILIKE '%glucose%' AND c.concept_name ILIKE '%2 hour%'
                AND m.value_as_number >= 200)
          )
      ) l
      GROUP BY l.person_id
      HAVING COUNT(DISTINCT l.lab_date) >= 2

      UNION ALL

      /* Rule D: >=1 abnormal diabetes lab date AND >=1 non-insulin antihyperglycemic exposure */
      SELECT
        j.person_id,
        MIN(j.first_evidence_date) AS index_date
      FROM (
        SELECT
          l.person_id,
          LEAST(l.lab_date, m.drug_date) AS first_evidence_date
        FROM (
          SELECT
            m.person_id,
            m.measurement_date::date AS lab_date
          FROM public.measurement m
          JOIN public.concept c
            ON c.concept_id = m.measurement_concept_id
          WHERE m.value_as_number IS NOT NULL
            AND c.vocabulary_id = 'LOINC'
            AND (
              (c.concept_name ILIKE '%hemoglobin a1c%' AND m.value_as_number >= 6.5)
              OR (c.concept_name ILIKE '%glucose%' AND c.concept_name ILIKE '%fasting%'
                  AND m.value_as_number >= 126)
              OR (c.concept_name ILIKE '%glucose%' AND m.value_as_number >= 200)
              OR (c.concept_name ILIKE '%oral glucose tolerance%' AND m.value_as_number >= 200)
              OR (c.concept_name ILIKE '%glucose%' AND c.concept_name ILIKE '%2 hour%'
                  AND m.value_as_number >= 200)
            )
        ) l
        JOIN (
          SELECT
            de.person_id,
            de.drug_exposure_start_date::date AS drug_date
          FROM public.drug_exposure de
          JOIN public.concept c
            ON c.concept_id = de.drug_concept_id
          WHERE c.domain_id = 'Drug'
            AND c.vocabulary_id IN ('RxNorm','RxNorm Extension')
            AND (
              c.concept_name ILIKE '%metformin%' OR c.concept_name ILIKE '%glucophage%' OR
              c.concept_name ILIKE '%fortamet%' OR c.concept_name ILIKE '%glumetza%' OR
              c.concept_name ILIKE '%riomet%'
              OR c.concept_name ILIKE '%glipizide%' OR c.concept_name ILIKE '%glucotrol%' OR
                 c.concept_name ILIKE '%glucotrol xl%' OR
                 c.concept_name ILIKE '%glyburide%' OR c.concept_name ILIKE '%diabeta%' OR
                 c.concept_name ILIKE '%micronase%' OR c.concept_name ILIKE '%glynase%' OR
                 c.concept_name ILIKE '%glimepiride%' OR c.concept_name ILIKE '%amaryl%'
              OR c.concept_name ILIKE '%pioglitazone%' OR c.concept_name ILIKE '%actos%' OR
                 c.concept_name ILIKE '%rosiglitazone%' OR c.concept_name ILIKE '%avandia%'
              OR c.concept_name ILIKE '%sitagliptin%' OR c.concept_name ILIKE '%januvia%' OR
                 c.concept_name ILIKE '%saxagliptin%' OR c.concept_name ILIKE '%onglyza%' OR
                 c.concept_name ILIKE '%linagliptin%' OR c.concept_name ILIKE '%tradjenta%' OR
                 c.concept_name ILIKE '%alogliptin%' OR c.concept_name ILIKE '%nesina%'
              OR c.concept_name ILIKE '%exenatide%' OR c.concept_name ILIKE '%byetta%' OR
                 c.concept_name ILIKE '%bydureon%' OR
                 c.concept_name ILIKE '%liraglutide%' OR c.concept_name ILIKE '%victoza%' OR
                 c.concept_name ILIKE '%dulaglutide%' OR c.concept_name ILIKE '%trulicity%' OR
                 c.concept_name ILIKE '%semaglutide%' OR c.concept_name ILIKE '%ozempic%' OR
                 c.concept_name ILIKE '%rybelsus%' OR
                 c.concept_name ILIKE '%lixisenatide%' OR c.concept_name ILIKE '%adlyxin%' OR
                 c.concept_name ILIKE '%tirzepatide%' OR c.concept_name ILIKE '%mounjaro%'
              OR c.concept_name ILIKE '%canagliflozin%' OR c.concept_name ILIKE '%invokana%' OR
                 c.concept_name ILIKE '%dapagliflozin%' OR c.concept_name ILIKE '%farxiga%' OR
                 c.concept_name ILIKE '%empagliflozin%' OR c.concept_name ILIKE '%jardiance%' OR
                 c.concept_name ILIKE '%ertugliflozin%' OR c.concept_name ILIKE '%steglatro%'
              OR c.concept_name ILIKE '%repaglinide%' OR c.concept_name ILIKE '%prandin%' OR
                 c.concept_name ILIKE '%nateglinide%' OR c.concept_name ILIKE '%starlix%'
              OR c.concept_name ILIKE '%acarbose%' OR c.concept_name ILIKE '%precose%' OR
                 c.concept_name ILIKE '%miglitol%' OR c.concept_name ILIKE '%glyset%'
              OR c.concept_name ILIKE '%pramlintide%' OR c.concept_name ILIKE '%symlin%'
              OR c.concept_name ILIKE '%janumet%' OR c.concept_name ILIKE '%synjardy%' OR
                 c.concept_name ILIKE '%xigduo%' OR c.concept_name ILIKE '%glyxambi%' OR
                 c.concept_name ILIKE '%qtern%'
            )
        ) m
          ON m.person_id = l.person_id
      ) j
      GROUP BY j.person_id
    ) u
    GROUP BY u.person_id
  ) ci
  JOIN public.observation_period op
    ON op.person_id = ci.person_id
   AND ci.index_date BETWEEN op.observation_period_start_date
                         AND op.observation_period_end_date
) final
WHERE
  /* Exclude any Type 1, gestational, or secondary/other diabetes diagnoses */
  NOT EXISTS (
    SELECT 1
    FROM public.condition_occurrence co
    JOIN public.concept c
      ON c.concept_id = co.condition_source_concept_id
    WHERE co.person_id = final.person_id
      AND c.vocabulary_id IN ('ICD9CM','ICD10CM')
      AND (
        /* Type 1 diabetes */
        (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'E10%')
        OR (
          c.vocabulary_id = 'ICD9CM'
          AND c.concept_code LIKE '250.%'
          AND RIGHT(regexp_replace(c.concept_code, '[^0-9]', '', 'g'), 1) IN ('1','3')
        )
        /* Gestational / pregnancy-related diabetes */
        OR (c.vocabulary_id = 'ICD10CM' AND c.concept_code LIKE 'O24%')
        OR (c.vocabulary_id = 'ICD9CM' AND c.concept_code LIKE '648.8%')
        OR (c.vocabulary_id = 'ICD9CM' AND c.concept_code LIKE '6488%')
        /* Secondary / other specified diabetes */
        OR (c.vocabulary_id = 'ICD10CM' AND (c.concept_code LIKE 'E08%' OR c.concept_code LIKE 'E09%' OR c.concept_code LIKE 'E13%'))
        OR (c.vocabulary_id = 'IC9CM'  AND c.concept_code LIKE '249%')
      )
  )
ORDER BY final.person_id, final.index_date;


