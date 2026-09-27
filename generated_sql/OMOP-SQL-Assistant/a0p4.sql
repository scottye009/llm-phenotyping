/* T2DM phenotype = evidence of type 2 diabetes AND no stronger exclusion */

CASE
WHEN
(
    /* Diagnosis evidence */
    COUNT_DISTINCT_DATES(dx_code IN (
        -- ICD-10-CM Type 2 diabetes mellitus
        'E11%',
        -- ICD-9-CM Type II or unspecified diabetes, controlled/uncontrolled
        '250.%0', '250.%2'
    )) >= 2

    OR

    (
        COUNT_DISTINCT_DATES(dx_code IN ('E11%', '250.%0', '250.%2')) >= 1
        AND
        (
            /* Diabetes-range labs */
            lab('HbA1c') >= 6.5
            OR lab('fasting_glucose_mg_dl') >= 126
            OR lab('random_glucose_mg_dl') >= 200

            OR

            /* Non-insulin antidiabetic medication */
            drug_exposure IN (
                -- Biguanide
                'metformin', 'Glucophage', 'Fortamet', 'Glumetza', 'Riomet',

                -- Sulfonylureas
                'glipizide', 'Glucotrol',
                'glyburide', 'DiaBeta', 'Micronase', 'Glynase',
                'glimepiride', 'Amaryl',

                -- DPP-4 inhibitors
                'sitagliptin', 'Januvia',
                'saxagliptin', 'Onglyza',
                'linagliptin', 'Tradjenta',
                'alogliptin', 'Nesina',

                -- GLP-1 receptor agonists / dual incretins
                'exenatide', 'Byetta', 'Bydureon',
                'liraglutide', 'Victoza',
                'dulaglutide', 'Trulicity',
                'semaglutide', 'Ozempic', 'Rybelsus',
                'tirzepatide', 'Mounjaro',

                -- SGLT2 inhibitors
                'canagliflozin', 'Invokana',
                'dapagliflozin', 'Farxiga',
                'empagliflozin', 'Jardiance',
                'ertugliflozin', 'Steglatro',

                -- TZDs
                'pioglitazone', 'Actos',
                'rosiglitazone', 'Avandia',

                -- Alpha-glucosidase inhibitors
                'acarbose', 'Precose',
                'miglitol', 'Glyset',

                -- Meglitinides
                'repaglinide', 'Prandin',
                'nateglinide', 'Starlix'
            )
        )
    )
)
AND NOT
(
    /* Exclude likely non-T2DM */
    dx_code IN (
        -- Type 1 diabetes
        'E10%', '250.%1', '250.%3',

        -- Gestational diabetes / pregnancy-associated diabetes
        'O24.4%', 'O24.9%', '648.8%',

        -- Secondary diabetes
        'E08%', 'E09%', 'E13%', '249%',

        -- Neonatal diabetes
        'P70.2'
    )

    OR

    /* Strong type 1 pattern: insulin-only diabetes treatment */
    (
        drug_exposure IN ('insulin', 'Humalog', 'Novolog', 'Apidra',
                          'Lantus', 'Levemir', 'Tresiba', 'Toujeo',
                          'Humulin', 'Novolin')
        AND NOT drug_exposure IN (/* any non-insulin antidiabetic above */)
    )
)
THEN 1 ELSE 0
END AS t2dm_phenotype;--error