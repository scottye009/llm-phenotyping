 --error
    SELECT patient_id
    FROM patient_data
    WHERE (
    -- Explicit diagnosis of type 2 diabetes
    ICD9CM_CODE IN ('250.0', '250.1', '250.2', '250.3') OR
    ICD10CM_CODE LIKE 'E11.%'
    )
    OR (
    -- Elevated glucose levels and use of antidiabetic medications
    (FASTING_GLUCOSE >= 126 OR HbA1c >= 6.5)
    AND 
    MEDICATION IN ('Metformin', 'Glucophage', 'Glyburide', 'Glucovance', 'Pioglitazone', 'Actos', 'Sitagliptin', 'Januvia', 'Liraglutide', 'Victoza', 'Canagliflozin', 'Invokana')
    )
    AS patients_with_type2_diabetes;