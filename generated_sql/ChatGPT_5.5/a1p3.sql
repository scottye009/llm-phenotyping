WITH t2dm_icd_source AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD9CM'
      AND concept_code IN (
          '25000','25002','25010','25012','25020','25022',
          '25030','25032','25040','25042','25050','25052',
          '25060','25062','25070','25072','25080','25082',
          '25090','25092'
      )

    UNION

    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD10CM'
      AND concept_code IN (
          'E11','E110','E1100','E1101','E111','E1110','E1111',
          'E112','E1121','E1122','E1129',
          'E113','E1131','E11311','E11319','E1132','E11321',
          'E113211','E113212','E113213','E113219','E11329',
          'E113291','E113292','E113293','E113299',
          'E1133','E11331','E113311','E113312','E113313','E113319',
          'E11339','E113391','E113392','E113393','E113399',
          'E1134','E11341','E113411','E113412','E113413','E113419',
          'E11349','E113491','E113492','E113493','E113499',
          'E1135','E11351','E113511','E113512','E113513','E113519',
          'E11352','E113521','E113522','E113523','E113529',
          'E11353','E113531','E113532','E113533','E113539',
          'E11354','E113541','E113542','E113543','E113549',
          'E11355','E113551','E113552','E113553','E113559',
          'E11359','E113591','E113592','E113593','E113599',
          'E1136','E1137','E1139',
          'E114','E1140','E1141','E1142','E1143','E1144','E1149',
          'E115','E1151','E1152',
          'E116','E11610','E11618','E11620','E11621','E11622','E11628',
          'E11630','E11638','E1164','E1165','E1169',
          'E118','E1181','E1182','E11821','E11822','E1183','E1184','E1185','E1186','E1187','E1189',
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
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN t2dm_standard_concepts t
      ON co.condition_concept_id = t.concept_id
),

t1dm_icd_source AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD9CM'
      AND concept_code IN (
          '25001','25003','25011','25013','25021','25023',
          '25031','25033','25041','25043','25051','25053',
          '25061','25063','25071','25073','25081','25083',
          '25091','25093'
      )

    UNION

    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD10CM'
      AND concept_code IN (
          'E10','E100','E101','E102','E103','E104','E105','E106','E108','E109',
          'E1000','E1001','E1010','E1011',
          'E1021','E1022','E1029',
          'E1031','E10311','E10319','E1032','E10321','E103211','E103212','E103213','E103219',
          'E10329','E103291','E103292','E103293','E103299',
          'E1033','E10331','E103311','E103312','E103313','E103319',
          'E10339','E103391','E103392','E103393','E103399',
          'E1034','E10341','E103411','E103412','E103413','E103419',
          'E10349','E103491','E103492','E103493','E103499',
          'E1035','E10351','E103511','E103512','E103513','E103519',
          'E10352','E103521','E103522','E103523','E103529',
          'E10353','E103531','E103532','E103533','E103539',
          'E10354','E103541','E103542','E103543','E103549',
          'E10355','E103551','E103552','E103553','E103559',
          'E10359','E103591','E103592','E103593','E103599',
          'E1036','E1037','E1039',
          'E1040','E1041','E1042','E1043','E1044','E1049',
          'E1051','E1052',
          'E10610','E10618','E10620','E10621','E10622','E10628',
          'E10630','E10638','E1064','E1065','E1069',
          'E108','E1081','E1082','E10821','E10822','E1083','E1084','E1085','E1086','E1089',
          'E109'
      )
),

t1dm_standard_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM t1dm_icd_source s
    JOIN public.concept_relationship cr
      ON s.concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'

    UNION

    SELECT concept_id
    FROM t1dm_icd_source
),

t1dm_dx AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN t1dm_standard_concepts t
      ON co.condition_concept_id = t.concept_id
),

gestational_diabetes_icd_source AS (
    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD9CM'
      AND concept_code IN ('64880','64881','64882','64883','64884')

    UNION

    SELECT concept_id
    FROM public.concept
    WHERE vocabulary_id = 'ICD10CM'
      AND concept_code IN (
          'O244','O2441','O24410','O24414','O24415','O24419',
          'O2442','O24420','O24424','O24425','O24429',
          'O2443','O24430','O24434','O24435','O24439',
          'O2449','O24410'
      )
),

gestational_diabetes_standard_concepts AS (
    SELECT DISTINCT cr.concept_id_2 AS concept_id
    FROM gestational_diabetes_icd_source s
    JOIN public.concept_relationship cr
      ON s.concept_id = cr.concept_id_1
    WHERE cr.relationship_id = 'Maps to'

    UNION

    SELECT concept_id
    FROM gestational_diabetes_icd_source
),

gestational_diabetes_dx AS (
    SELECT DISTINCT co.person_id
    FROM public.condition_occurrence co
    JOIN gestational_diabetes_standard_concepts g
      ON co.condition_concept_id = g.concept_id
),

diabetes_labs AS (
    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN public.concept c
      ON m.measurement_concept_id = c.concept_id
    WHERE (
            LOWER(c.concept_name) LIKE '%hemoglobin a1c%'
         OR LOWER(c.concept_name) LIKE '%hba1c%'
         OR LOWER(c.concept_name) LIKE '%glycated hemoglobin%'
          )
      AND m.value_as_number >= 6.5

    UNION

    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN public.concept c
      ON m.measurement_concept_id = c.concept_id
    WHERE (
            LOWER(c.concept_name) LIKE '%glucose%'
        AND (
               LOWER(c.concept_name) LIKE '%fasting%'
            OR LOWER(c.concept_name) LIKE '%fasted%'
        )
          )
      AND m.value_as_number >= 126

    UNION

    SELECT DISTINCT m.person_id
    FROM public.measurement m
    JOIN public.concept c
      ON m.measurement_concept_id = c.concept_id
    WHERE LOWER(c.concept_name) LIKE '%glucose%'
      AND m.value_as_number >= 200
),

non_insulin_diabetes_drug_concepts AS (
    SELECT DISTINCT concept_id
    FROM public.concept
    WHERE domain_id = 'Drug'
      AND (
             LOWER(concept_name) LIKE '%metformin%'
          OR LOWER(concept_name) LIKE '%glucophage%'

          OR LOWER(concept_name) LIKE '%glipizide%'
          OR LOWER(concept_name) LIKE '%glucotrol%'

          OR LOWER(concept_name) LIKE '%glyburide%'
          OR LOWER(concept_name) LIKE '%diaBeta%'
          OR LOWER(concept_name) LIKE '%micronase%'

          OR LOWER(concept_name) LIKE '%glimepiride%'
          OR LOWER(concept_name) LIKE '%amaryl%'

          OR LOWER(concept_name) LIKE '%sitagliptin%'
          OR LOWER(concept_name) LIKE '%januvia%'

          OR LOWER(concept_name) LIKE '%saxagliptin%'
          OR LOWER(concept_name) LIKE '%onglyza%'

          OR LOWER(concept_name) LIKE '%linagliptin%'
          OR LOWER(concept_name) LIKE '%tradjenta%'

          OR LOWER(concept_name) LIKE '%semaglutide%'
          OR LOWER(concept_name) LIKE '%ozempic%'
          OR LOWER(concept_name) LIKE '%rybelsus%'
          OR LOWER(concept_name) LIKE '%wegovy%'

          OR LOWER(concept_name) LIKE '%liraglutide%'
          OR LOWER(concept_name) LIKE '%victoza%'
          OR LOWER(concept_name) LIKE '%saxenda%'

          OR LOWER(concept_name) LIKE '%dulaglutide%'
          OR LOWER(concept_name) LIKE '%trulicity%'

          OR LOWER(concept_name) LIKE '%exenatide%'
          OR LOWER(concept_name) LIKE '%byetta%'
          OR LOWER(concept_name) LIKE '%bydureon%'

          OR LOWER(concept_name) LIKE '%empagliflozin%'
          OR LOWER(concept_name) LIKE '%jardiance%'

          OR LOWER(concept_name) LIKE '%dapagliflozin%'
          OR LOWER(concept_name) LIKE '%farxiga%'

          OR LOWER(concept_name) LIKE '%canagliflozin%'
          OR LOWER(concept_name) LIKE '%invokana%'

          OR LOWER(concept_name) LIKE '%ertugliflozin%'
          OR LOWER(concept_name) LIKE '%steglatro%'

          OR LOWER(concept_name) LIKE '%pioglitazone%'
          OR LOWER(concept_name) LIKE '%actos%'

          OR LOWER(concept_name) LIKE '%rosiglitazone%'
          OR LOWER(concept_name) LIKE '%avandia%'
      )
),

non_insulin_diabetes_drug_exposure AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN public.concept_ancestor ca
      ON de.drug_concept_id = ca.descendant_concept_id
    JOIN non_insulin_diabetes_drug_concepts dc
      ON ca.ancestor_concept_id = dc.concept_id
),

insulin_drug_concepts AS (
    SELECT DISTINCT concept_id
    FROM public.concept
    WHERE domain_id = 'Drug'
      AND (
             LOWER(concept_name) LIKE '%insulin%'
          OR LOWER(concept_name) LIKE '%lantus%'
          OR LOWER(concept_name) LIKE '%basaglar%'
          OR LOWER(concept_name) LIKE '%levemir%'
          OR LOWER(concept_name) LIKE '%tresiba%'
          OR LOWER(concept_name) LIKE '%humalog%'
          OR LOWER(concept_name) LIKE '%novolog%'
          OR LOWER(concept_name) LIKE '%apidra%'
          OR LOWER(concept_name) LIKE '%humulin%'
          OR LOWER(concept_name) LIKE '%novolin%'
      )
),

insulin_drug_exposure AS (
    SELECT DISTINCT de.person_id
    FROM public.drug_exposure de
    JOIN public.concept_ancestor ca
      ON de.drug_concept_id = ca.descendant_concept_id
    JOIN insulin_drug_concepts ic
      ON ca.ancestor_concept_id = ic.concept_id
),

candidate_t2dm AS (
    SELECT person_id
    FROM t2dm_dx

    UNION

    SELECT person_id
    FROM diabetes_labs

    UNION

    SELECT person_id
    FROM non_insulin_diabetes_drug_exposure

    UNION

    SELECT i.person_id
    FROM insulin_drug_exposure i
    WHERE i.person_id IN (
        SELECT person_id FROM t2dm_dx
        UNION
        SELECT person_id FROM non_insulin_diabetes_drug_exposure
    )
),

final_t2dm_phenotype AS (
    SELECT DISTINCT c.person_id
    FROM candidate_t2dm c
    WHERE c.person_id NOT IN (
        SELECT person_id FROM gestational_diabetes_dx
    )
      AND NOT (
          c.person_id IN (SELECT person_id FROM t1dm_dx)
          AND c.person_id NOT IN (SELECT person_id FROM t2dm_dx)
          AND c.person_id NOT IN (SELECT person_id FROM non_insulin_diabetes_drug_exposure)
      )
)

SELECT DISTINCT
    p.person_id
FROM public.person p
JOIN final_t2dm_phenotype f
  ON p.person_id = f.person_id
ORDER BY p.person_id;