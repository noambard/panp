-- Qstroke
-- This one is a bit challenging. Many unusual variables

----------------
-- Population --
----------------
--DROP TABLE StrokePopulationQStroke;
GO

-- get full population
SELECT *
INTO StrokePopulationQStroke
FROM m_clalit_members_ever;
-- 5781329

---------------
-- Inclusion --
---------------
-- age
EXEC dbo.sp_add_demography_columns
	@pstr_input_table_name = 'StrokePopulationQStroke',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_date = '20070101',
	@pstr_gender = 'sex',
	@pstr_age = 'age',
	@pstr_ses_combined_1_to_20 = 'SES';

GO

-- restrict ages
DELETE FROM StrokePopulationQStroke WHERE age < 25 OR age > 84 OR age IS NULL; -- 2508894 left

---------------
-- Exclusion --
---------------
-- old stroke
EXECUTE mechkar.dbo.sp_get_diagnosis_records
	@pstr_input_table_name = 'StrokePopulationQStroke',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_end_date = '20070101',
	@pstr_icd_diagnoses = '43[0-8]%',
	@pstr_icpc_diagnoses ='K90',
	@pstr_chr_diagnoses = '95.2;124',
	@pstr_free_text_inclusion = '%cerebrovascular%accident%;%transient%ischemic%attack%;%intracerebral%hemorrhage%;%CVA%;%cerebelar%hemorrhage%;%cerebral%hemorrhage%;%cerebral%vasospasm%;%cerebrovascular%disease%;%stroke%;%cerebral%ischemia%;%subarachnoid%hemorrhage%;%ischemic%attack%transient%;%aneurysm%berry%ruptured%;%intracranial%hemorrhage%;%hemorrhage%brain%nontraumic%;',
	@pstr_free_text_exclusion ='%extradural%',
	@psw_community = 1,
	@psw_admissions = 1,
	@psw_permanent = 1,
	@psw_chronic_all_diag = 1,
	@pstr_output_sw_column_name = 'sw_old_stroke_diag';

DELETE FROM StrokePopulationQStroke WHERE sw_old_stroke_diag = 1; -- 2410703 left

-- previous anticoagulants
EXECUTE mechkar.dbo.sp_get_med_purch
	@pstr_input_table_name = 'StrokePopulationQStroke',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '19000101',
	@pstr_end_date = '20070101',
	@pstr_atc5_codes = 'B01AA03+B01AA07+B01AA02+B01AE07+B01AF01+B01AF02;',
	@pstr_med_group_names = 'old_anticoagulant',
	@pstr_sw_disp = 'sw_disp',
	@pstr_disp_num = 'num_disp',
	@pstr_first_disp_date = 'first_disp',
	@pstr_last_disp_date = 'last_disp',
	@pstr_sw_pres = 'sw_pres',
	@pstr_pres_num = 'num_pres',
	@pstr_first_pres_date = 'first_pres',
	@pstr_last_pres_date = 'last_pres';

DELETE FROM StrokePopulationQStroke WHERE num_disp_old_anticoagulant > 1; -- 38089 down

-----------------
-- Co-Variates --
-----------------
-- We give a 3 year pre-start date window
ALTER TABLE StrokePopulationQStroke ADD
SBP_first_v FLOAT,
SBP_first_date DATE,
chol_first_v FLOAT,
chol_first_date DATE,
HDL_first_v FLOAT,
HDL_first_date DATE,
BMI_first_v FLOAT,
BMI_first_date DATE,
smoking_first_v TINYINT,
smoking_first_date DATE;
GO

-- last before start date
EXEC dbo.sp_add_clinical_covariates_columns
	@pstr_input_table_name = 'StrokePopulationQStroke',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20040101',
	@pstr_end_date = '20070101',
	@pstr_sys_bp = 'SBP_last_v',
	@pstr_bmi_value = 'bmi_last_v',
	@pstr_smoking_status_code = 'smoking_last_v';

EXEC mechkar.dbo.sp_get_lab_records
	@pstr_input_table_name = 'StrokePopulationQStroke',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20040101',
	@pstr_end_date = '20070101',
	@pstr_lab_work_codes = '21200;21400',
	@pstr_lab_work_names = 'chol;HDL',
	@pstr_last_value = 'last_v';

-- first after start date
-- SBP
WITH first_bp AS (
SELECT pop.teudat_zehut, MIN(bp.measure_date) AS min_date
FROM m_bp_measurements AS bp INNER JOIN StrokePopulationQStroke AS pop
ON bp.teudat_zehut = pop.teudat_zehut AND measure_date >= '20070101' AND measure_date <= '20170101'
GROUP BY pop.teudat_zehut)
UPDATE pop
SET SBP_first_v = bp.systolic, SBP_first_date = first_bp.min_date
FROM StrokePopulationQStroke AS pop
INNER JOIN m_bp_measurements AS bp ON pop.teudat_zehut = bp.teudat_zehut
INNER JOIN first_bp ON bp.measure_date = first_bp.min_date;

-- BMI
WITH first_bmi AS (
SELECT pop.teudat_zehut, MIN(bmi.measure_date) AS min_date
FROM M_BMI_Adults AS bmi INNER JOIN StrokePopulationQStroke AS pop
ON bmi.teudat_zehut = pop.teudat_zehut AND measure_date >= '20070101' AND measure_date <= '20170101'
GROUP BY pop.teudat_zehut)
UPDATE pop
SET bmi_first_v = bmi.BMI, BMI_first_date = first_bmi.min_date
FROM StrokePopulationQStroke AS pop
INNER JOIN M_BMI_Adults AS bmi ON pop.teudat_zehut = bmi.teudat_zehut
INNER JOIN first_bmi ON bmi.measure_date = first_bmi.min_date;

-- Smoking
WITH first_smoking AS (
SELECT pop.teudat_zehut, MIN(mrk.date_start) AS min_date
FROM DWH..mrk_fact_v AS mrk INNER JOIN StrokePopulationQStroke AS pop
ON mrk.teudat_zehut = pop.teudat_zehut AND date_start >= '20070101' AND date_start <= '20170101'
AND mrk.kod_mrkr in (6, 8) AND mrk.mrkr_num_value1 <> (-1)
GROUP BY pop.teudat_zehut)
UPDATE pop
SET smoking_first_v = mrk.mrkr_num_value1, smoking_first_date = mrk.date_start
FROM StrokePopulationQStroke AS pop
INNER JOIN DWH..mrk_fact_v AS mrk ON pop.teudat_zehut = mrk.teudat_zehut AND mrk.kod_mrkr in (6, 8) AND mrk.mrkr_num_value1 <> (-1)
INNER JOIN first_smoking ON mrk.date_start = first_smoking.min_date;

-- correcting for past smoking
WITH past_smokers AS (
SELECT pop.teudat_zehut
FROM StrokePopulationQStroke AS pop
INNER JOIN dwh..mrk_fact_v AS mrk ON pop.teudat_zehut = mrk.teudat_zehut AND
mrk.date_start < pop.smoking_first_date AND mrk.mrkr_num_value1 <> (-1) AND mrk.kod_mrkr IN (6,8)
WHERE pop.smoking_first_v = 1 AND mrk.mrkr_num_value1 > 1)
UPDATE pop
SET smoking_first_v = 2 
FROM StrokePopulationQStroke pop
JOIN past_smokers ON pop.teudat_zehut = past_smokers.teudat_zehut;

-- correcting for the change in smoking markers
UPDATE StrokePopulationQStroke
SET smoking_first_v = IIF(smoking_first_v BETWEEN 4 AND 5, 3, smoking_first_v)
WHERE smoking_first_v IS NOT NULL;

EXEC mechkar.dbo.sp_get_lab_records
	@pstr_input_table_name = 'StrokePopulationQStroke',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20070101',
	@pstr_end_date = '20170101',
	@pstr_lab_work_codes = '21200;21400',
	@pstr_lab_work_names = 'chol;HDL',
	@pstr_first_test_date_valid_numeric = 'first_date',
	@pstr_first_value = 'first_v';

SELECT COUNT(*) FROM StrokePopulationQStroke WHERE BMI_first_v IS NULL AND BMI_last_v IS NULL

---------------
-- Diagnoses --
---------------
-- AF
ALTER TABLE StrokePopulationQStroke ADD sw_AF_diag TINYINT, date_AF_diag DATE;
GO
UPDATE StrokePopulationQStroke SET sw_AF_diag = 0, date_AF_diag = NULL;
UPDATE pop SET sw_AF_diag = 1, date_AF_diag = index_diagnosis_date
FROM StrokePopulationQStroke AS pop
INNER JOIN [CLALIT\asafba1].AF_cohort AS AF
ON pop.teudat_zehut = AF.teudat_zehut
AND AF.index_diagnosis_date <= '20070101'; -- 42529

-- CHF
EXECUTE mechkar.dbo.sp_get_diagnosis_records
	@pstr_input_table_name = 'StrokePopulationQStroke',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_end_date = '20070101',
	@pstr_icd_diagnoses = '428%;I50%;I25.5',
	@pstr_chr_diagnoses = '112%',
	@pstr_free_text_inclusion = '%congestive%heart%;%heart%failure%;%systolic%dysfunction%;%diastolic%dysfunction%;%ventricular%failure%;%CHF%;%ventricular%d[yi]sfunction%;',
	@pstr_free_text_exclusion ='',
	@psw_community = 1,
	@psw_admissions = 1,
	@psw_permanent = 1,
	@psw_chronic_all_diag = 1,
	@pstr_output_sw_column_name = 'sw_CHF_diag',
	@pstr_output_date_column_name = 'date_CHF_diag';
-- 

-- CHD
EXECUTE mechkar.dbo.sp_get_diagnosis_records 
	@pstr_input_table_name = 'StrokePopulationQStroke',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_end_date = '20070101',
	@pstr_icd_diagnoses = '41[01234]%;I2[012345]', 
	@pstr_icpc_diagnoses = 'K75;K76;', 
	@pstr_chr_diagnoses = '110.1;110.9;',
	@pstr_free_text_inclusion = '%angina%;%prectoris%;%heart%attack%;%myocardial%inf%;%ischemic%heart%;%ischaemic%heart%;%coronary%atherosclerosis%;%arterioscl%cardiovascular%;%post%coronary%bypass%;%coronary%insuf%;%atheroscl%cardiovasc%;%acute%coronary%;%cardial%ischemia%;%intermediate%coronary%;%dyspnea%effort%;infarction%myocardial%;%infarction%subendocardial%;%subendocardial%infarction%;', 
	@pstr_free_text_exclusion = '%fear%;%gynecologic%;%no%disease%;%us%examination%;%normal%;%breast%;%medical%examination%;%herp%angina%;%hearing%;', 
	@psw_community = 1,
	@psw_permanent = 1,
	@psw_chronic_all_diag = 1,
	@psw_admissions = 1,
	@pstr_output_sw_column_name = 'sw_CHD_diag',
	@pstr_output_date_column_name = 'date_CHD_diag';
-- 

-- DM T. 1
ALTER TABLE StrokePopulationQStroke ADD sw_diabetes_1 TINYINT, date_diabetes_1 DATE;
GO
UPDATE StrokePopulationQStroke SET sw_diabetes_1 = 0, date_diabetes_1 = NULL;
UPDATE StrokePopulationQStroke
SET sw_diabetes_1 = 1, date_diabetes_1 = diab.diab_date
FROM StrokePopulationQStroke AS pop
INNER JOIN Mechkar.[CLALIT\TomasKa].diab_pop10 AS diab
ON pop.teudat_zehut = diab.teudat_zehut
AND diab.diab_date < '20070101' AND diab_class = 1;
-- 

-- DM T. 2
ALTER TABLE StrokePopulationQStroke ADD sw_diabetes_2 TINYINT, date_diabetes_2 DATE;
GO
UPDATE StrokePopulationQStroke SET sw_diabetes_2 = 0, date_diabetes_2 = NULL;
UPDATE StrokePopulationQStroke
SET sw_diabetes_2 = 1, date_diabetes_2 = diab.diab_date
FROM StrokePopulationQStroke AS pop
INNER JOIN Mechkar.[CLALIT\TomasKa].diab_pop10 AS diab
ON pop.teudat_zehut = diab.teudat_zehut
AND diab.diab_date < '20070101' AND diab_class = 2;

-- HT
EXECUTE mechkar.dbo.sp_get_diagnosis_records
	@pstr_input_table_name = 'StrokePopulationQStroke',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_end_date = '20070101',
	@pstr_icd_diagnoses = '40[12345]%;I1[01235]%',
	@pstr_icpc_diagnoses = 'K85;K86;K87',
	@pstr_chr_diagnoses = '120%',
	@pstr_free_text_inclusion = '%hypertension%;%hypertensive%;%hypert%with%;%nephrosclerosis%;%hypert%;%essential%hypert%;%hypertesion%;%hypertention%',
	@pstr_free_text_exclusion ='%low%;%w/o%;%pulmonary%;%pulmoanry%;%ocular%;%portal%;%holter%;%no%hypert%;%no%retino%;%pre%hyper%;%borderline%;%prostat%;%hyperthy%;%hypertrig%;%ventricular%;%tonsil%;%hypertroph%;%hypertg%;%hyperton%;%cranial%;%endomet%;%adenoid%;',
	@psw_community = 1,
	@psw_admissions = 1,
	@psw_permanent = 1,
	@psw_chronic_all_diag = 1,
	@pstr_output_sw_column_name = 'sw_hypertension_diag',
	@pstr_output_date_column_name = 'date_hypertension_diag';
-- 399068

-- RA
EXECUTE mechkar.dbo.sp_get_diagnosis_records
	@pstr_input_table_name = 'StrokePopulationQStroke',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_end_date = '20070101',
	@pstr_icd_diagnoses = '714.0%;714.2%',
	@pstr_icpc_diagnoses = 'L88%',
	@pstr_chr_diagnoses = '231%',
	@pstr_free_text_inclusion = '%rheumatoid%arthritis%;%arthritis%atrophic%',
	@pstr_free_text_exclusion ='',
	@psw_community = 1,
	@psw_admissions = 1,
	@psw_permanent = 1,
	@psw_chronic_all_diag = 1,
	@pstr_output_sw_column_name = 'sw_RA_diag',
	@pstr_output_date_column_name = 'date_RA_diag';

-- CKD
EXECUTE mechkar.dbo.sp_get_diagnosis_records
	@pstr_input_table_name = 'StrokePopulationQStroke',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_end_date = '20070101',
	@pstr_icd_diagnoses = '585%',
	@pstr_chr_diagnoses = '177%',
	@pstr_free_text_inclusion = '%chronic%kidney%;%chronic%renal%;%renal%failure%chronic%;%uremia%;',
	@pstr_free_text_exclusion ='',
	@psw_community = 1,
	@psw_admissions = 1,
	@psw_permanent = 1,
	@psw_chronic_all_diag = 1,
	@pstr_output_sw_column_name = 'sw_CKD_diag',
	@pstr_output_date_column_name = 'date_CKD_diag';

-- valve
EXECUTE mechkar.dbo.sp_get_diagnosis_records
	@pstr_input_table_name = 'StrokePopulationQStroke',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_end_date = '20070101',
	@pstr_icd_diagnoses = '424.0%;424.1%;424.2%;424.3%;394%;395%;396%;397%;093.2%;746.0%;746.1%;746.2%;746.3%;746.4%;746.5%;746.6%;',
	@pstr_icpc_diagnoses = 'K83%',
	@pstr_chr_diagnoses = '111%',
	@pstr_free_text_inclusion = '%valv%;%stenosis%;%regurgitation%;%incompetence%;%insufficiency%;%ebstein%;%tricuspid%atresia%;%pulmonary%atresia%',
	@pstr_free_text_exclusion ='',
	@psw_community = 1,
	@psw_admissions = 1,
	@psw_permanent = 1,
	@psw_chronic_all_diag = 1,
	@pstr_output_sw_column_name = 'sw_valvular_disease_diag',
	@pstr_output_date_column_name = 'date_valvular_disease_diag';

---------------
-- Family Hx --
---------------
ALTER TABLE StrokePopulationQStroke ADD family_hx_freetext_sw TINYINT, family_hx_freetext_date DATE;
GO
UPDATE StrokePopulationQStroke SET family_hx_freetext_sw = 0, family_hx_freetext_date = NULL;

WITH free_text AS (
SELECT teudat_zehut,teur_avchana_src ,MIN(date_bikur) first_visit,'cvd' AS diag
  FROM [clalit\ilango3].fh_free_text
  WHERE FREETEXT(teur_avchana_src,'parent mother maternal father paternal grandmother grandfather sister brother cousin uncle aunt nephew fh f.h "family history" משפחה אבא אמא סבתא סבא אחות אח דוד דודה אחיין ') 
  AND FREETEXT(teur_avchana_src,'cabg mi coronary acs ihd pci ptca uap "heart attack" anginal angina "coronary syndrome" ischemia "coronary thrombosis" "myocardial infarction" CARDI')
  GROUP BY teudat_zehut,teur_avchana_src
)
UPDATE StrokePopulationQStroke SET family_hx_freetext_sw = 1, family_hx_freetext_date = first_visit
FROM StrokePopulationQStroke AS pop
INNER JOIN free_text
ON pop.teudat_zehut = free_text.teudat_zehut;

EXECUTE mechkar.dbo.sp_get_diagnosis_records
	@pstr_input_table_name = 'StrokePopulationQStroke',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_end_date = '20070101',
	@pstr_icd_diagnoses = 'V173%',
	@pstr_free_text_inclusion = '%family%history%',
	@pstr_free_text_exclusion ='',
	@psw_community = 1,
	@psw_admissions = 1,
	@psw_permanent = 1,
	@pstr_output_sw_column_name = 'sw_family_hx_diag',
	@pstr_output_date_column_name = 'date_family_hx_diag'
	--@pstr_rawdata_output_table_name = 'family_hx_raw',
	--@pstr_deleted_records_dt_text_validation_table_name = 'family_hx_del';

SELECT sw_family_hx_diag, COUNT(*) FROM StrokePopulationQStroke GROUP BY sw_family_hx_diag
-----------
-- Drugs --
-----------
EXECUTE mechkar.dbo.sp_get_med_purch
	@pstr_input_table_name = 'StrokePopulationQStroke',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '19000101',
	@pstr_end_date = '20070101',
	@pstr_atc5_codes = 'C09%+C07AB03+C07FB03+C07CB03+C07CB53+C07BB03+C07DB01+C07DB01+C07AB02+C07FX03+C07FB13+C07FB02+C07FX05+C07CB02+C07BB02+C07BB52+C08C%+C08G%+C03A%+C02AC01',
	@pstr_med_group_names = 'hypertension',
	@pstr_sw_disp = 'sw_disp',
	@pstr_disp_num = 'num_disp',
	@pstr_first_disp_date = 'first_disp',
	@pstr_last_disp_date = 'last_disp',
	@pstr_sw_pres = 'sw_pres',
	@pstr_pres_num = 'num_pres',
	@pstr_first_pres_date = 'first_pres',
	@pstr_last_pres_date = 'last_pres';

--------------
-- Exposure --
--------------
-- Now we get the exposure time
EXEC sp_continuous_membership_survival_analysis
	@pstr_input_table_name = 'StrokePopulationQStroke',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20070101',
	@pstr_end_date = '20170101',
	@pstr_membership_end_date ='exposure_end_date',
	@pstr_total_month_membership = 'exposure_month_count',
	@pstr_membership_type = 'exposure_termination_type';

DELETE FROM StrokePopulationQStroke WHERE exposure_termination_type = 'no membership'; -- 331097 removed
DELETE FROM StrokePopulationQStroke WHERE exposure_month_count IS NULL; -- 2481 removed

SELECT exposure_month_count, COUNT(*) AS n FROM StrokePopulationQStroke GROUP BY exposure_month_count ORDER BY exposure_month_count ASC

------------
-- Events --
------------
-- CVA - Ischemic
EXECUTE mechkar.dbo.sp_get_diagnosis_records
	@pstr_input_table_name = 'StrokePopulationQStroke',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20070101',
	@pstr_end_date = '20170101',
	@pstr_output_sw_column_name = 'sw_CVA',
	@pstr_output_date_column_name = 'date_CVA',
	@pstr_icd_diagnoses = '433;433._;433._1;434%;362.3[1-3];362.4%;',
	@psw_admissions = 1,
	@pn_hospital_diagnosis_type = 1,
	@pstr_departments = '10;11;12;13;14;21;22;23;26;27;28;39;31;32;33;41;52;53;55;56;57;58;61;62;63;65;70;71;73;84;85'; -- not rehab

-- CVA - unknown
EXECUTE mechkar.dbo.sp_get_diagnosis_records
	@pstr_input_table_name = 'StrokePopulationQStroke',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20070101',
	@pstr_end_date = '20170101',
	@pstr_output_sw_column_name = 'sw_stroke_unknown',
	@pstr_output_date_column_name = 'date_stroke_unknown',
	@pstr_icd_diagnoses = '436%',
	@psw_admissions = 1,
	@pn_hospital_diagnosis_type = 1,
	@pstr_departments = '10;11;12;13;14;21;22;23;26;27;28;39;31;32;33;41;52;53;55;56;57;58;61;62;63;65;70;71;73;84;85'; -- not rehab

-- TIA
EXECUTE mechkar.dbo.sp_get_diagnosis_records
	@pstr_input_table_name = 'StrokePopulationQStroke',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20070101',
	@pstr_end_date = '20170101',
	@pstr_output_sw_column_name = 'sw_TIA',
	@pstr_output_date_column_name = 'date_TIA',
	@pstr_icd_diagnoses = '435%',
	@pstr_free_text_inclusion = '%transient%ischemic%attack%;%ischemic%attack%transient%;%transient%cerebral%ischemia%;%vertebral%artery%syndrome%;%ischemic%attack%transient%',
	@pstr_free_text_exclusion = '',
	@psw_admissions = 1,
	@psw_community = 1,
	@psw_permanent = 1,
	@pn_hospital_diagnosis_type = 1,
	@pstr_professions = '32',
	@pstr_departments = '10;11;12;13;14;21;22;23;26;27;28;39;31;32;33;41;52;53;55;56;57;58;61;62;63;65;70;71;73;84;85'; -- not rehab

-------------------------
-- Event Consolidation --
-------------------------
-- Consolidate to a single outcome measure and date
ALTER TABLE StrokePopulationQStroke ADD sw_stroke TINYINT, stroke_date DATE;
GO
UPDATE StrokePopulationQStroke SET sw_stroke = 0, stroke_date = NULL;
UPDATE StrokePopulationQStroke SET sw_stroke = 1 WHERE sw_TIA = 1 OR sw_CVA = 1 OR sw_stroke_unknown = 1;
UPDATE StrokePopulationQStroke SET stroke_date = new.min_date
	FROM StrokePopulationQStroke
	INNER JOIN 
		(SELECT teudat_zehut, (SELECT MIN([date]) FROM (VALUES (date_TIA),(date_CVA),(date_stroke_unknown)) x ([date])) AS min_date
		FROM StrokePopulationQStroke) AS new
	ON StrokePopulationQStroke.teudat_zehut = new.teudat_zehut;
-- 

-- For cases when membership was terminated by death, and the terminated date is 31 days or less earlier than the stroke date,
-- we'll change the stroke date to be the dod
UPDATE StrokePopulationQStroke SET stroke_date = exposure_end_date
WHERE DATEDIFF(day, exposure_end_date, stroke_date) BETWEEN 0 AND 31
AND exposure_termination_type = 'Terminated By Death'; -- 1384

-- now we set the final columns
ALTER TABLE StrokePopulationQStroke ADD exposure_time INT, event_date DATE, event_type VARCHAR(10);
GO

UPDATE StrokePopulationQStroke SET event_type =
	CASE
		WHEN stroke_date <= exposure_end_date THEN 'stroke'
		ELSE 'censored'
	END
UPDATE StrokePopulationQStroke SET event_date = IIF(exposure_end_date < stroke_date OR stroke_date IS NULL, exposure_end_date, stroke_date);

UPDATE StrokePopulationQStroke SET exposure_time = DATEDIFF(day, '20070101', event_date)/30;

-----------------------------------
-- Dealing with future variables --
-----------------------------------
-- smoking has some unique behaviour
ALTER TABLE StrokePopulationQStroke ADD smoking_final_v TINYINT;
GO
UPDATE StrokePopulationQStroke SET smoking_final_v = smoking_last_v;
UPDATE StrokePopulationQStroke SET smoking_final_v = smoking_first_v WHERE smoking_last_v IS NULL --AND DATEDIFF(day, '20070101', smoking_first_date) <= 730
AND smoking_first_date < event_date;
UPDATE StrokePopulationQStroke SET smoking_final_v = 1 WHERE smoking_first_v = 1;

-- the others we'll take from <=2 years in the future
ALTER TABLE StrokePopulationQStroke ADD chol_final_v FLOAT;
GO
UPDATE StrokePopulationQStroke SET chol_final_v = chol_last_v
UPDATE StrokePopulationQStroke SET chol_final_v = chol_first_v WHERE chol_last_v IS NULL --AND DATEDIFF(day, '20070101', chol_first_date) <= 730
AND chol_first_date < event_date;

ALTER TABLE StrokePopulationQStroke ADD hdl_final_v FLOAT;
GO
UPDATE StrokePopulationQStroke SET hdl_final_v = hdl_last_v
UPDATE StrokePopulationQStroke SET hdl_final_v = hdl_first_v WHERE hdl_last_v IS NULL --AND DATEDIFF(day, '20070101', hdl_first_date) <= 730
AND hdl_first_date < event_date;

ALTER TABLE StrokePopulationQStroke ADD bmi_final_v FLOAT;
GO
UPDATE StrokePopulationQStroke SET bmi_final_v = bmi_last_v
UPDATE StrokePopulationQStroke SET bmi_final_v = bmi_first_v WHERE bmi_last_v IS NULL --AND DATEDIFF(day, '20070101', bmi_first_date) <= 730
AND bmi_first_date < event_date;

ALTER TABLE StrokePopulationQStroke ADD sbp_final_v FLOAT;
GO
UPDATE StrokePopulationQStroke SET sbp_final_v = sbp_last_v
UPDATE StrokePopulationQStroke SET sbp_final_v = sbp_first_v WHERE sbp_last_v IS NULL --AND DATEDIFF(day, '20070101', sbp_first_date) <= 730
AND sbp_first_date < event_date;

---------------------------
-- Dealing with outliers --
---------------------------
-- specifically unknown sex we'll delete
DELETE FROM StrokePopulationQStroke WHERE sex = 'U'; -- 0

-- the rest we'll null, so the imputation takes care of them
UPDATE StrokePopulationQStroke SET sbp_final_v = NULL WHERE sbp_final_v >= 230;
UPDATE StrokePopulationQStroke SET HDL_final_v = NULL WHERE HDL_final_v >= 90;
UPDATE StrokePopulationQStroke SET bmi_final_v = NULL WHERE bmi_final_v >= 60;

-- zeroing the nulls
UPDATE StrokePopulationQStroke SET sw_AF_diag = 0 WHERE sw_AF_diag IS NULL;
UPDATE StrokePopulationQStroke SET sw_CHF_diag = 0 WHERE sw_CHF_diag IS NULL;
UPDATE StrokePopulationQStroke SET sw_CHD_diag = 0 WHERE sw_CHD_diag IS NULL;
UPDATE StrokePopulationQStroke SET sw_diabetes_1 = 0 WHERE sw_diabetes_1 IS NULL;
UPDATE StrokePopulationQStroke SET sw_diabetes_2 = 0 WHERE sw_diabetes_2 IS NULL;
UPDATE StrokePopulationQStroke SET sw_hypertension_diag = 0 WHERE sw_hypertension_diag IS NULL;
UPDATE StrokePopulationQStroke SET sw_family_hx_diag = 0 WHERE sw_family_hx_diag IS NULL;
UPDATE StrokePopulationQStroke SET sw_RA_diag = 0 WHERE sw_RA_diag IS NULL;
UPDATE StrokePopulationQStroke SET sw_CKD_diag = 0 WHERE sw_CKD_diag IS NULL;
UPDATE StrokePopulationQStroke SET sw_valvular_disease_diag = 0 WHERE sw_valvular_disease_diag IS NULL;

-----------------------------------
-- Applying study specific logic --
-----------------------------------
ALTER TABLE StrokePopulationQStroke ADD sw_final_smoking TINYINT, tchol_hdl_ratio FLOAT,
sw_final_SES TINYINT, sw_final_hypertension TINYINT, towsend_depr INT, sw_final_family_hx TINYINT;
GO

UPDATE StrokePopulationQStroke SET sw_final_smoking = 0, tchol_hdl_ratio = 0,
sw_final_SES = 0, sw_final_hypertension = 0, sw_final_family_hx = 0;

-- we use moderate smoker for current smoker, similar to Noa
UPDATE StrokePopulationQStroke SET sw_final_smoking =
CASE
	WHEN smoking_final_v = 1 THEN 1
	WHEN smoking_final_v = 2 THEN 2
	WHEN smoking_final_v = 3 THEN 4
END

UPDATE StrokePopulationQStroke SET tchol_hdl_ratio = CAST(chol_final_v AS FLOAT) / CAST(HDL_final_v AS FLOAT)

-- towsend is -7 to 11 with high being bad, but SES is 1 to 20 with high being good
UPDATE StrokePopulationQStroke SET towsend_depr = ROUND(CAST((20 - SES) AS FLOAT)* 19/21 - 7, 0)

UPDATE StrokePopulationQStroke
SET sw_final_hypertension = 1
WHERE date_hypertension_diag <= '20070101' -- diag before index date
AND first_disp_hypertension <= '20070101' -- drugs before index date
AND last_disp_hypertension >= '20060601'
AND num_disp_hypertension >= 3; -- at least two dispensings

UPDATE StrokePopulationQStroke
SET sw_final_family_hx = 1
WHERE sw_family_hx_diag = 1 OR 
(family_hx_freetext_sw = 1 AND family_hx_freetext_date < event_date);

----------------------
-- Prep Final Table --
----------------------
DROP TABLE StrokePopulationQStrokeFinal;

SELECT exposure_time AS time, event_type AS status, -- survival analysis basics
	sex, age, 0 AS ethnicity, -- demographics
	smoking_final_v, sbp_final_v, tchol_hdl_ratio, bmi_final_v, towsend_depr, -- covariates
	sw_AF_diag, sw_final_family_hx, sw_final_hypertension, sw_RA_diag, sw_CKD_diag,
	sw_diabetes_1, sw_diabetes_2, sw_CHF_diag, sw_CHD_diag, sw_valvular_disease_diag -- diagnoses
	INTO StrokePopulationQStrokeFinal
	FROM StrokePopulationQStroke;
-- 2039033

----------------
-- And now... --
----------------
-- we go to R, impute missing variables, calculate the risk score as per the article and score it