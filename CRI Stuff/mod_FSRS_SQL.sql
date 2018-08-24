----------------
-- Population --
----------------
--DROP TABLE StrokePopulationModFSRS;
GO

-- get full population
SELECT *
INTO StrokePopulationModFSRS
FROM m_clalit_members_ever;
-- 5781329

---------------
-- Inclusion --
---------------
-- age
EXEC dbo.sp_add_demography_columns
	@pstr_input_table_name = 'StrokePopulationModFSRS',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_date = '20070101',
	@pstr_gender = 'sex',
	@pstr_age = 'age';

GO

-- restrict ages
DELETE FROM StrokePopulationModFSRS WHERE age < 55 OR age > 84 OR age IS NULL; -- 842185

---------------
-- Exclusion --
---------------
EXECUTE mechkar.dbo.sp_get_diagnosis_records
	@pstr_input_table_name = 'StrokePopulationModFSRS',
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

DELETE FROM StrokePopulationModFSRS WHERE sw_old_stroke_diag = 1; -- 758038

---------------
-- Diagnoses --
---------------
-- AF
ALTER TABLE StrokePopulationModFSRS ADD sw_AF_diag TINYINT, date_AF_diag DATE;
GO
UPDATE StrokePopulationModFSRS SET sw_AF_diag = 0, date_AF_diag = NULL;
UPDATE pop SET sw_AF_diag = 1, date_AF_diag = index_diagnosis_date
FROM StrokePopulationModFSRS AS pop
INNER JOIN [CLALIT\asafba1].AF_cohort AS AF
ON pop.teudat_zehut = AF.teudat_zehut
AND AF.index_diagnosis_date <= '20070101'; -- 42529

-- LVH
EXECUTE mechkar.dbo.sp_get_diagnosis_records
	@pstr_input_table_name = 'StrokePopulationModFSRS',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_end_date = '20070101',
	@pstr_icd_diagnoses = '429.3%',
	@pstr_free_text_inclusion = '%cardiomegaly%;%ventricular%hypertrophy%',
	@psw_community = 1,
	@psw_admissions = 1,
	@psw_permanent = 1,
	@pstr_output_sw_column_name = 'sw_LVH_diag',
	@pstr_output_date_column_name = 'date_LVH_diag';
-- 4708

-- CHF (as part of CVD)
EXECUTE mechkar.dbo.sp_get_diagnosis_records
	@pstr_input_table_name = 'StrokePopulationModFSRS',
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
-- 37511

-- CHD (as part of CVD)
EXECUTE mechkar.dbo.sp_get_diagnosis_records 
	@pstr_input_table_name = 'StrokePopulationModFSRS',
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
-- 151725

-- PVD (as part of CVD)
EXECUTE mechkar.dbo.sp_get_diagnosis_records 
	@pstr_input_table_name = 'StrokePopulationModFSRS',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_end_date = '20070101',
	@pstr_icd_diagnoses = '443%;440.[23489]%;250.7%;444.2%', 
	@pstr_icpc_diagnoses = 'K92;',
	@pstr_chr_diagnoses = '126%',
	@pstr_free_text_inclusion = '%peripheral%vascular%;%PVD%;%claudication%;%buerger%;%thromboangiitis%obliterans%;', 
	@pstr_free_text_exclusion = '%neurogenic%;%spinal%;;%dissection%;%acute%;%vitreous%;%floater%;%eye%;%detachment%;%PVD%BE%;%BE%PVD%;%OD%PVD%;%PVD%OD%;%PVD%LE%;%LE%PVD%;%raynaud%', 
	@psw_community = 1,
	@psw_permanent = 1,
	@psw_chronic_all_diag = 1,
	@psw_admissions = 1,
	@pstr_professions = '0;1;2;3;4;10;11;12;13;14;15;21;22;23;26;27;28;29;31;32;33;35;41;49;50;51;52;53;54;55;56;57;58;59;62;63;65;66;67;68;69;70;71;72;73;75;76;77;78;79;80;81;83;84;85;86;87;88;89;90;91;92;93;94;95;96;97;98;99;101;102;103;104;105;106;107;108;110;116;117;118;119;120;121;122;123;124;125;126;127;999', -- no ophtalmologists!
	@pstr_output_sw_column_name = 'sw_PVD_diag',
	@pstr_output_date_column_name = 'date_PVD_diag';
-- 33205

-- DM
ALTER TABLE StrokePopulationModFSRS ADD sw_diabetes_diag TINYINT, date_diabetes_diag DATE;
GO
UPDATE StrokePopulationModFSRS SET sw_diabetes_diag = 0, date_diabetes_diag = NULL;
UPDATE StrokePopulationModFSRS
SET sw_diabetes_diag = 1, date_diabetes_diag = diab.diab_date
FROM StrokePopulationModFSRS AS pop
INNER JOIN M_diabetes_registry AS diab
ON pop.teudat_zehut = diab.teudat_zehut
AND diab.diab_date < '20070101' AND diab_class = 2;
-- 156510

-- HT
EXECUTE mechkar.dbo.sp_get_diagnosis_records
	@pstr_input_table_name = 'StrokePopulationModFSRS',
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

-----------
-- Drugs --
-----------
EXECUTE mechkar.dbo.sp_get_med_purch
	@pstr_input_table_name = 'StrokePopulationModFSRS',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '19000101',
	@pstr_end_date = '20070101',
	@pstr_atc5_codes = 'C09%+C07AB03+C07FB03+C07CB03+C07CB53+C07BB03+C07DB01+C07DB01+C07AB02+C07FX03+C07FB13+C07FB02+C07FX05+C07CB02+C07BB02+C07BB52+C08C%+C08G%+C03A%+C02AC01;A10%',
	@pstr_med_group_names = 'hypertension;DM',
	@pstr_sw_disp = 'sw_disp',
	@pstr_disp_num = 'num_disp',
	@pstr_first_disp_date = 'first_disp',
	@pstr_last_disp_date = 'last_disp',
	@pstr_sw_pres = 'sw_pres',
	@pstr_pres_num = 'num_pres',
	@pstr_first_pres_date = 'first_pres',
	@pstr_last_pres_date = 'last_pres';

-----------------
-- Co-Variates --
-----------------
-- We give a 3 year pre-start date window
ALTER TABLE StrokePopulationModFSRS ADD
SBP_first_v FLOAT,
SBP_first_date DATE,
smoking_first_v TINYINT,
smoking_first_date DATE;
GO

-- last before start date
EXEC dbo.sp_add_clinical_covariates_columns
	@pstr_input_table_name = 'StrokePopulationModFSRS',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20040101',
	@pstr_end_date = '20070101',
	@pstr_sys_bp = 'SBP_last_v',
	@pstr_smoking_status_code = 'smoking_last_v';

-- first after start date
-- BP
WITH first_bp AS (
SELECT pop.teudat_zehut, MIN(bp.measure_date) AS min_date
FROM m_bp_measurements AS bp INNER JOIN StrokePopulationModFSRS AS pop
ON bp.teudat_zehut = pop.teudat_zehut AND measure_date >= '20070101' AND measure_date <= '20170101'
GROUP BY pop.teudat_zehut)
UPDATE pop
SET SBP_first_v = bp.systolic, SBP_first_date = first_bp.min_date
FROM StrokePopulationModFSRS AS pop
INNER JOIN m_bp_measurements AS bp ON pop.teudat_zehut = bp.teudat_zehut
INNER JOIN first_bp ON bp.measure_date = first_bp.min_date;

-- Smoking
WITH first_smoking AS (
SELECT pop.teudat_zehut, MIN(mrk.date_start) AS min_date
FROM DWH..mrk_fact_v AS mrk INNER JOIN StrokePopulationModFSRS AS pop
ON mrk.teudat_zehut = pop.teudat_zehut AND date_start >= '20070101' AND date_start <= '20170101'
AND mrk.kod_mrkr in (6, 8) AND mrk.mrkr_num_value1 <> (-1)
GROUP BY pop.teudat_zehut)
UPDATE pop
SET smoking_first_v = mrk.mrkr_num_value1, smoking_first_date = mrk.date_start
FROM StrokePopulationModFSRS AS pop
INNER JOIN DWH..mrk_fact_v AS mrk ON pop.teudat_zehut = mrk.teudat_zehut AND mrk.kod_mrkr in (6, 8) AND mrk.mrkr_num_value1 <> (-1)
INNER JOIN first_smoking ON mrk.date_start = first_smoking.min_date;

-- correcting for past smoking
WITH past_smokers AS (
SELECT pop.teudat_zehut
FROM StrokePopulationModFSRS AS pop
INNER JOIN dwh..mrk_fact_v AS mrk ON pop.teudat_zehut = mrk.teudat_zehut AND
mrk.date_start < pop.smoking_first_date AND mrk.mrkr_num_value1 <> (-1) AND mrk.kod_mrkr IN (6,8)
WHERE pop.smoking_first_v = 1 AND mrk.mrkr_num_value1 > 1)
UPDATE pop
SET smoking_first_v = 2 
FROM StrokePopulationModFSRS pop
JOIN past_smokers ON pop.teudat_zehut = past_smokers.teudat_zehut;

-- correcting for the change in smoking markers
UPDATE StrokePopulationModFSRS
SET smoking_first_v = IIF(smoking_first_v BETWEEN 4 AND 5, 3, smoking_first_v)
WHERE smoking_first_v IS NOT NULL;

--------------
-- Exposure --
--------------
-- Now we get the exposure time
EXEC sp_continuous_membership_survival_analysis
	@pstr_input_table_name = 'StrokePopulationModFSRS',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20070101',
	@pstr_end_date = '20170101',
	@pstr_membership_end_date ='exposure_end_date',
	@pstr_total_month_membership = 'exposure_month_count',
	@pstr_membership_type = 'exposure_termination_type';

DELETE FROM StrokePopulationModFSRS WHERE exposure_termination_type = 'no membership'; -- 706032
DELETE FROM StrokePopulationModFSRS WHERE exposure_month_count IS NULL; -- 329

SELECT exposure_month_count, COUNT(*) AS n FROM StrokePopulationModFSRS GROUP BY exposure_month_count ORDER BY exposure_month_count ASC

------------
-- Events --
------------
-- ICH
EXECUTE mechkar.dbo.sp_get_diagnosis_records
	@pstr_input_table_name = 'StrokePopulationModFSRS',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20070101',
	@pstr_end_date = '20170101',
	@pstr_output_sw_column_name = 'sw_ICH',
	@pstr_output_date_column_name = 'date_ICH',
	@pstr_icd_diagnoses = '431%',
	@psw_admissions = 1,
	@pn_hospital_diagnosis_type = 1,
	@pstr_departments = '10;11;12;13;14;21;22;23;26;27;28;39;31;32;33;41;52;53;55;56;57;58;61;62;63;65;70;71;73;84;85'; -- not rehab

-- CVA - Ischemic
EXECUTE mechkar.dbo.sp_get_diagnosis_records
	@pstr_input_table_name = 'StrokePopulationModFSRS',
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
	@pstr_input_table_name = 'StrokePopulationModFSRS',
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
	@pstr_input_table_name = 'StrokePopulationModFSRS',
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

-- SAH
EXECUTE mechkar.dbo.sp_get_diagnosis_records
	@pstr_input_table_name = 'StrokePopulationModFSRS',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20070101',
	@pstr_end_date = '20170101',
	@pstr_output_sw_column_name = 'sw_SAH',
	@pstr_output_date_column_name = 'date_SAH',
	@pstr_icd_diagnoses = '430%',
	@psw_admissions = 1,
	@pn_hospital_diagnosis_type = 1,
	@pstr_departments = '10;11;12;13;14;21;22;23;26;27;28;39;31;32;33;41;52;53;55;56;57;58;61;62;63;65;70;71;73;84;85'; -- not rehab

-------------------------
-- Event Consolidation --
-------------------------
-- Consolidate to a single outcome measure and date
ALTER TABLE StrokePopulationModFSRS ADD sw_stroke TINYINT, stroke_date DATE;
GO
UPDATE StrokePopulationModFSRS SET sw_stroke = 0, stroke_date = NULL;
UPDATE StrokePopulationModFSRS SET sw_stroke = 1 WHERE sw_SAH = 1 OR sw_TIA = 1 OR sw_ICH = 1 OR sw_CVA = 1 OR sw_stroke_unknown = 1;
UPDATE StrokePopulationModFSRS SET stroke_date = new.min_date
	FROM StrokePopulationModFSRS
	INNER JOIN 
		(SELECT teudat_zehut, (SELECT MIN([date]) FROM (VALUES (date_SAH),(date_TIA),(date_ICH),(date_CVA),(date_stroke_unknown)) x ([date])) AS min_date
		FROM StrokePopulationModFSRS) AS new
	ON StrokePopulationModFSRS.teudat_zehut = new.teudat_zehut;
-- 

-- For cases when membership was terminated by death, and the terminated date is 31 days or less earlier than the stroke date,
-- we'll change the stroke date to be the dod
UPDATE StrokePopulationModFSRS SET stroke_date = exposure_end_date
WHERE DATEDIFF(day, exposure_end_date, stroke_date) BETWEEN 0 AND 31
AND exposure_termination_type = 'Terminated By Death'; -- 2287

-- now we set the final columns
ALTER TABLE StrokePopulationModFSRS ADD exposure_time INT, event_date DATE, event_type VARCHAR(10);
GO

UPDATE StrokePopulationModFSRS SET event_type =
	CASE
		WHEN stroke_date <= exposure_end_date THEN 'stroke'
		ELSE 'censored'
	END
UPDATE StrokePopulationModFSRS SET event_date = IIF(exposure_end_date < stroke_date OR stroke_date IS NULL, exposure_end_date, stroke_date);

UPDATE StrokePopulationModFSRS SET exposure_time = DATEDIFF(day, '20070101', event_date)/30;

------------------------------
-- ANDing diagnoses and drugs
------------------------------
ALTER TABLE StrokePopulationModFSRS ADD sw_final_DM TINYINT, sw_final_hypertension TINYINT,
sw_final_CVD TINYINT, sw_final_AF TINYINT, sw_final_LVH TINYINT;
GO
UPDATE StrokePopulationModFSRS SET sw_final_DM = 0, sw_final_hypertension = 0,
sw_final_CVD = 0, sw_final_AF = 0, sw_final_LVH = 0;

UPDATE StrokePopulationModFSRS
SET sw_final_DM = 1
WHERE date_diabetes_diag <= '20070101' -- diag before index date
AND first_disp_DM <= '20070101' -- drugs before index date
AND num_disp_DM >= 3; -- at least two dispensings

UPDATE StrokePopulationModFSRS
SET sw_final_hypertension = 1
WHERE date_hypertension_diag <= '20070101' -- diag before index date
AND first_disp_hypertension <= '20070101' -- drugs before index date
AND num_disp_hypertension >= 3; -- at least two dispensings

UPDATE StrokePopulationModFSRS
SET sw_final_CVD = 1
WHERE sw_CHF_diag = 1 OR sw_CHD_diag = 1 OR sw_PVD_diag = 1;

UPDATE StrokePopulationModFSRS
SET sw_final_AF = sw_AF_diag;

UPDATE StrokePopulationModFSRS
SET sw_final_LVH = sw_LVH_diag;

SELECT TOP 1 * FROM StrokePopulationModFSRS
------------------------------------
-- Sanity checks and last repairs --
------------------------------------
-- smoking has some unique behaviour
ALTER TABLE StrokePopulationModFSRS ADD smoking_final_v TINYINT;
GO

UPDATE StrokePopulationModFSRS SET smoking_final_v = smoking_last_v;
UPDATE StrokePopulationModFSRS SET smoking_final_v = smoking_first_v WHERE smoking_last_v IS NULL AND DATEDIFF(day, '20070101', smoking_first_date) <= 730
AND smoking_first_date < event_date;
UPDATE StrokePopulationModFSRS SET smoking_final_v = 1 WHERE smoking_first_v = 1;

-- flat means active smoker vs. not active smoker
ALTER TABLE StrokePopulationModFSRS ADD smoking_final_v_flat TINYINT;
GO
UPDATE StrokePopulationModFSRS SET smoking_final_v_flat =
 CASE
	WHEN smoking_final_v = 1 OR smoking_final_v = 3 THEN 1
	WHEN smoking_final_v = 2 THEN 2
	ELSE NULL
 END;

-- the others we'll take from <=2 years in the future
ALTER TABLE StrokePopulationModFSRS ADD sbp_final_v FLOAT;
GO
UPDATE StrokePopulationModFSRS SET sbp_final_v = sbp_last_v
UPDATE StrokePopulationModFSRS SET sbp_final_v = sbp_first_v WHERE sbp_last_v IS NULL AND DATEDIFF(day, '20070101', sbp_first_date) <= 730
AND sbp_first_date < event_date;

---------------------------
-- Dealing with outliers --
---------------------------
-- specifically unknown sex we'll delete
DELETE FROM StrokePopulationModFSRS WHERE sex = 'U'; -- 0

-- the rest we'll null, so the imputation takes care of them
UPDATE StrokePopulationModFSRS SET sbp_final_v = NULL WHERE sbp_final_v >= 230;

----------------------
-- Prep Final Table --
----------------------
DROP TABLE StrokePopulationModFSRSFinal;

SELECT exposure_time AS time, event_type AS status, -- survival analysis basics
	sex, age, -- demographics
	smoking_final_v_flat, sbp_final_v, -- covariates
	sw_final_DM, sw_final_hypertension, sw_final_CVD, sw_final_AF, sw_final_LVH -- diagnoses
	INTO StrokePopulationModFSRSFinal
	FROM StrokePopulationModFSRS;
	-- 705703

----------------
-- And now... --
----------------
-- we go to R, impute missing variables, calculate the risk score as per the article and score it