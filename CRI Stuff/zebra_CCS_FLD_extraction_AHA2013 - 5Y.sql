-- we'll do the usual 01/01/2012 trick with 3 years prior + 2 years ahead and impute the rest

----------------
-- Population --
----------------

-- get the full clalit population
SELECT *
INTO ZebraCCSFLDAHAPopulation5Y
FROM m_clalit_members_ever;

-- get age and sex
EXEC dbo.sp_add_demography_columns
	@pstr_input_table_name = 'ZebraCCSFLDAHAPopulation5Y',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_date = '20120101',
	@pstr_age = 'age',
	@pstr_date_of_birth = 'dob',
	@pstr_date_of_death = 'dod',
	@pstr_gender = 'sex';

-- models only predict for persons of a certain age, delete those not of the proper age range
DELETE FROM ZebraCCSFLDAHAPopulation5Y WHERE age IS NULL OR age < 40 OR age > 79; -- 4325275 deleted

-- exposure
EXEC sp_continuous_membership_survival_analysis
	@pstr_input_table_name = 'ZebraCCSFLDAHAPopulation5Y',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20120101',
	@pstr_end_date = '20170101',
	@pstr_membership_end_date ='exposure_end_date',
	@pstr_total_month_membership = 'exposure_month_count',
	@pstr_membership_type = 'exposure_termination_type';

DELETE FROM ZebraCCSFLDAHAPopulation5Y WHERE exposure_termination_type = 'No Membership'; -- 131344 deleted

----------------
-- Exclusions --
----------------
-- old CHD
EXECUTE mechkar.dbo.sp_get_diagnosis_records 
	@pstr_input_table_name = 'ZebraCCSFLDAHAPopulation5Y',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_end_date = '20120101',
	@pstr_icd_diagnoses = '41[01234]%;I2[012345]', 
	@pstr_icpc_diagnoses = 'K75;K76;', 
	@pstr_chr_diagnoses = '110.1;110.9;',
	@pstr_free_text_inclusion = '%angina%;%prectoris%;%heart%attack%;%myocardial%inf%;%ischemic%heart%;%ischaemic%heart%;%coronary%atherosclerosis%;%arterioscl%cardiovascular%;%post%coronary%bypass%;%coronary%insuf%;%atheroscl%cardiovasc%;%acute%coronary%;%cardial%ischemia%;%intermediate%coronary%;%dyspnea%effort%;infarction%myocardial%;%infarction%subendocardial%;%subendocardial%infarction%;', 
	@pstr_free_text_exclusion = '%fear%;%gynecologic%;%no%disease%;%us%examination%;%normal%;%breast%;%medical%examination%;%herp%angina%;%hearing%;', 
	@psw_community = 1,
	@psw_permanent = 1,
	@psw_chronic_all_diag = 1,
	@psw_admissions = 1,
	@pstr_output_sw_column_name = 'old_CHD';

-- old stroke
EXECUTE mechkar.dbo.sp_get_diagnosis_records
	@pstr_input_table_name = 'ZebraCCSFLDAHAPopulation5Y',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_end_date = '20120101',
	@pstr_icd_diagnoses = '43[0-8]%;I6[0-9]%',
	@pstr_icpc_diagnoses ='K90',
	@pstr_chr_diagnoses = '95.2;124',
	@pstr_free_text_inclusion = '%cerebrovascular%accident%;%transient%ischemic%attack%;%intracerebral%hemorrhage%;%CVA%;%cerebelar%hemorrhage%;%cerebral%hemorrhage%;%cerebral%vasospasm%;%cerebrovascular%disease%;%stroke%;%cerebral%ischemia%;%subarachnoid%hemorrhage%;%ischemic%attack%transient%;%aneurysm%berry%ruptured%;%intracranial%hemorrhage%;%hemorrhage%brain%nontraumic%;',
	@pstr_free_text_exclusion ='%extradural%',
	@psw_community = 1,
	@psw_admissions = 1,
	@psw_permanent = 1,
	@psw_chronic_all_diag = 1,
	@pstr_output_sw_column_name = 'old_stroke';

-- old heart failure
EXECUTE mechkar.dbo.sp_get_diagnosis_records
	@pstr_input_table_name = 'ZebraCCSFLDAHAPopulation5Y',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_end_date = '20120101',
	@pstr_icd_diagnoses = '428%;I50%;I25.5',
	@pstr_chr_diagnoses = '112%',
	@pstr_free_text_inclusion = '%congestive%heart%;%heart%failure%;%systolic%dysfunction%;%diastolic%dysfunction%;%ventricular%failure%;%CHF%;%ventricular%d[yi]sfunction%;',
	@pstr_free_text_exclusion ='',
	@psw_community = 1,
	@psw_admissions = 1,
	@psw_permanent = 1,
	@psw_chronic_all_diag = 1,
	@pstr_output_sw_column_name = 'old_heart_failure';

-- old AF
ALTER TABLE ZebraCCSFLDAHAPopulation5Y ADD sw_AF_diag TINYINT, date_AF_diag DATE;
GO
UPDATE ZebraCCSFLDAHAPopulation5Y SET sw_AF_diag = 0, date_AF_diag = NULL;
UPDATE pop SET sw_AF_diag = 1, date_AF_diag = index_diagnosis_date
FROM ZebraCCSFLDAHAPopulation5Y AS pop
INNER JOIN [CLALIT\asafba1].AF_cohort AS AF
ON pop.teudat_zehut = AF.teudat_zehut
AND AF.index_diagnosis_date <= '20120101';

DELETE FROM ZebraCCSFLDAHAPopulation5Y WHERE old_CHD = 1 OR old_stroke = 1 OR old_heart_failure = 1 OR sw_AF_diag = 1; -- 245663 deleted

----------------
-- Covariates --
----------------
-- 3 labs(TC, LDL, HDL), which we'll get both last results for before the index date and first results for after the index date
EXEC mechkar.dbo.sp_get_lab_records
	@pstr_input_table_name = 'ZebraCCSFLDAHAPopulation5Y',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20100101',
	@pstr_end_date = '20120101',
	@pstr_lab_work_codes = '21200;21400',
	@pstr_lab_work_names = 'TC;HDL',
	@pstr_last_value = 'last_v';

EXEC mechkar.dbo.sp_get_lab_records
	@pstr_input_table_name = 'ZebraCCSFLDAHAPopulation5Y',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20120101',
	@pstr_end_date = '20140101',
	@pstr_lab_work_codes = '21200;21400',
	@pstr_lab_work_names = 'TC;HDL',
	@pstr_first_test_date_valid_numeric = 'first_date',
	@pstr_last_value = 'first_v';

-- 3 markers (SBP, DBP, smoking) - same trick
EXEC dbo.sp_add_clinical_covariates_columns
	@pstr_input_table_name = 'ZebraCCSFLDAHAPopulation5Y',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20100101',
	@pstr_end_date = '20120101',
	@pstr_sys_bp = 'SBP_last_v',
	@pstr_smoking_status_code = 'smoking_last_v';

-- since the procedure doesn't allow for date values unless I choose min/max, and I don't need min/max, I'll write the code myself

-- SBP
ALTER TABLE ZebraCCSFLDAHAPopulation5Y ADD SBP_first_v FLOAT, SBP_first_date DATE;
GO
WITH first_bp AS (
SELECT pop.teudat_zehut, MIN(bp.measure_date) AS min_date
FROM m_bp_measurements AS bp INNER JOIN ZebraCCSFLDAHAPopulation5Y AS pop
ON bp.teudat_zehut = pop.teudat_zehut AND measure_date >= '20120101' AND measure_date <= '20170101'
GROUP BY pop.teudat_zehut)
UPDATE pop
SET SBP_first_v = bp.systolic, SBP_first_date = first_bp.min_date
FROM ZebraCCSFLDAHAPopulation5Y AS pop
INNER JOIN m_bp_measurements AS bp ON pop.teudat_zehut = bp.teudat_zehut
INNER JOIN first_bp ON bp.measure_date = first_bp.min_date;

-- smoking doesn't have a "first" value option, so we'll get it manually
ALTER TABLE ZebraCCSFLDAHAPopulation5Y ADD smoking_first_v TINYINT, smoking_first_date DATE;
GO

SELECT pop.teudat_zehut, MIN(mrk.date_start) AS min_date
INTO first_smoking
FROM DWH..mrk_fact_v AS mrk INNER JOIN ZebraCCSFLDAHAPopulation5Y AS pop
ON mrk.teudat_zehut = pop.teudat_zehut AND date_start >= '20120101'
AND mrk.kod_mrkr in (6, 8) AND mrk.mrkr_num_value1 <> (-1)
GROUP BY pop.teudat_zehut;

UPDATE pop
SET smoking_first_v = mrk.mrkr_num_value1, smoking_first_date = mrk.date_start
FROM ZebraCCSFLDAHAPopulation5Y AS pop
INNER JOIN DWH..mrk_fact_v AS mrk ON pop.teudat_zehut = mrk.teudat_zehut AND mrk.kod_mrkr in (6, 8) AND mrk.mrkr_num_value1 <> (-1)
INNER JOIN first_smoking ON mrk.date_start = first_smoking.min_date;

-- correcting for past smoking
SELECT pop.teudat_zehut
INTO past_smokers
FROM ZebraCCSFLDAHAPopulation5Y AS pop
INNER JOIN dwh..mrk_fact_v AS mrk ON pop.teudat_zehut = mrk.teudat_zehut AND
mrk.date_start < pop.smoking_first_date AND mrk.mrkr_num_value1 <> (-1) AND mrk.kod_mrkr IN (6,8)
WHERE pop.smoking_first_v = 1 AND mrk.mrkr_num_value1 > 1

UPDATE pop
SET smoking_first_v = 2 
FROM ZebraCCSFLDAHAPopulation5Y pop
JOIN past_smokers ON pop.teudat_zehut = past_smokers.teudat_zehut;

-- correcting for the change in smoking markers
UPDATE ZebraCCSFLDAHAPopulation5Y
SET smoking_first_v = IIF(smoking_first_v BETWEEN 4 AND 5, 3, smoking_first_v)
WHERE smoking_first_v IS NOT NULL;

-- DM Dx
ALTER TABLE ZebraCCSFLDAHAPopulation5Y ADD sw_diabetes_diag TINYINT, date_diabetes_diag DATE;
GO
UPDATE ZebraCCSFLDAHAPopulation5Y SET sw_diabetes_diag = 0, date_diabetes_diag = NULL;

UPDATE ZebraCCSFLDAHAPopulation5Y
SET sw_diabetes_diag = 1, date_diabetes_diag = diab.diab_date
FROM ZebraCCSFLDAHAPopulation5Y AS pop
INNER JOIN M_diabetes_registry AS diab
ON pop.teudat_zehut = diab.teudat_zehut
AND diab.diab_date < '20120101';

-- HT Rx
EXECUTE mechkar.dbo.sp_get_med_purch
	@pstr_input_table_name = 'ZebraCCSFLDAHAPopulation5Y',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '19000101',
	@pstr_end_date = '20120101',
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
-- Outcomes --
--------------
-- new MI
EXECUTE mechkar.dbo.sp_get_diagnosis_records 
	@pstr_input_table_name = 'ZebraCCSFLDAHAPopulation5Y',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20120101',
	@pstr_end_date = '20170101',
	@pstr_icd_diagnoses = '410%', 
	@psw_admissions = 1,
	@pn_hospital_diagnosis_type = 1,
	@pstr_output_sw_column_name = 'new_MI_sw',
	@pstr_output_date_column_name = 'new_MI_date',
	@pstr_departments = '10;11;12;13;14;21;22;23;26;27;28;39;31;32;33;41;52;53;55;56;57;58;61;62;63;65;70;71;73;84;85';

-- ischemic CVA (w/o TIA)
EXECUTE mechkar.dbo.sp_get_diagnosis_records
	@pstr_input_table_name = 'ZebraCCSFLDAHAPopulation5Y',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20120101',
	@pstr_end_date = '20170101',
	@pstr_output_sw_column_name = 'sw_stroke_ischemic',
	@pstr_output_date_column_name = 'date_stroke_ischemic',
	@pstr_icd_diagnoses = '433;433._;433._1;434%;362.3[1-3];362.4%;',
	@psw_admissions = 1,
	@pn_hospital_diagnosis_type = 1,
	@pstr_departments = '10;11;12;13;14;21;22;23;26;27;28;39;31;32;33;41;52;53;55;56;57;58;61;62;63;65;70;71;73;84;85'; -- not rehab

-- hemorrhagic CVA
EXECUTE mechkar.dbo.sp_get_diagnosis_records
	@pstr_input_table_name = 'ZebraCCSFLDAHAPopulation5Y',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20120101',
	@pstr_end_date = '20170101',
	@pstr_output_sw_column_name = 'sw_stroke_hemorrhagic',
	@pstr_output_date_column_name = 'date_stroke_hemorrhagic',
	@pstr_icd_diagnoses = '431%;',
	@psw_admissions = 1,
	@pn_hospital_diagnosis_type = 1,
	@pstr_departments = '10;11;12;13;14;21;22;23;26;27;28;39;31;32;33;41;52;53;55;56;57;58;61;62;63;65;70;71;73;84;85'; -- not rehab

-- unknown CVA
EXECUTE mechkar.dbo.sp_get_diagnosis_records
	@pstr_input_table_name = 'ZebraCCSFLDAHAPopulation5Y',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20120101',
	@pstr_end_date = '20170101',
	@pstr_output_sw_column_name = 'sw_stroke_unknown',
	@pstr_output_date_column_name = 'date_stroke_unknown',
	@pstr_icd_diagnoses = '436%',
	@psw_admissions = 1,
	@pn_hospital_diagnosis_type = 1,
	@pstr_departments = '10;11;12;13;14;21;22;23;26;27;28;39;31;32;33;41;52;53;55;56;57;58;61;62;63;65;70;71;73;84;85'; -- not rehab

-- the death outcomes are actually the hardest part
-- we'll use the MOI table, considering just the main reason.
ALTER TABLE ZebraCCSFLDAHAPopulation5Y ADD CVD_death_sw TINYINT, CVD_death_date DATE;
GO
UPDATE ZebraCCSFLDAHAPopulation5Y SET CVD_death_sw = 0, CVD_death_date = NULL;
UPDATE ZebraCCSFLDAHAPopulation5Y SET CVD_death_sw = 1, CVD_death_date = TRY_CONVERT(date, ["death_dt"], 103)
FROM ZebraCCSFLDAHAPopulation5Y AS pop
INNER JOIN [Mechkar].[CLALIT\MosheHo].[clalit_cause_death1] AS MOI
ON pop.teudat_zehut = LEFT(MOI.["full_TZ"], LEN(MOI.["full_TZ"]) - 1)
WHERE ["death_dt"] <> '' AND
(["siba31"] LIKE 'I10%' OR ["siba31"] LIKE 'I11%' OR ["siba31"] LIKE 'I12%' OR ["siba31"] LIKE 'I13%' OR ["siba31"] LIKE 'I15%' OR ["siba31"] LIKE 'I21%' OR ["siba31"] LIKE 'I24%' OR ["siba31"] LIKE 'I25%' OR ["siba31"] LIKE 'I20%' OR ["siba31"] LIKE 'I44%' OR ["siba31"] LIKE 'I47%' OR ["siba31"] LIKE 'I50%' OR ["siba31"] LIKE 'I51%' OR ["siba31"] LIKE 'I60%' OR ["siba31"] LIKE 'I61%' OR ["siba31"] LIKE 'I62%' OR ["siba31"] LIKE 'I63%' OR ["siba31"] LIKE 'G45%' OR ["siba31"] LIKE 'I67%' OR ["siba31"] LIKE 'I69%' OR ["siba31"] LIKE 'I70%' OR ["siba31"] LIKE 'I71%' OR ["siba31"] LIKE 'I72%' OR ["siba31"] LIKE 'I73%' OR ["siba31"] LIKE 'R99%') AND (["siba31"] NOT LIKE 'I456%' AND ["siba31"] NOT LIKE 'I514%' AND ["siba31"] NOT LIKE 'I609%' AND ["siba31"] NOT LIKE 'I6200%' AND ["siba31"] NOT LIKE 'I671%' AND ["siba31"] NOT LIKE 'I677%' AND ["siba31"] NOT LIKE 'I675%');

---------------------
-- Finalizing Vars --
---------------------
-- for HT, we want at least 2 dispensings overall, the last in the last 6 months
ALTER TABLE ZebraCCSFLDAHAPopulation5Y ADD sw_final_hypertension_Rx TINYINT;
GO
UPDATE ZebraCCSFLDAHAPopulation5Y SET sw_final_hypertension_Rx = 0;
UPDATE ZebraCCSFLDAHAPopulation5Y SET sw_final_hypertension_Rx = 1
WHERE last_disp_hypertension >= '20110601'
AND num_disp_hypertension >= 2;

-- for smoking we only need now or not now, so 1 and 2 are 1, 3 is 2, and 1 ever is also 1. the rest are missing
ALTER TABLE ZebraCCSFLDAHAPopulation5Y ADD smoking_final_v TINYINT;
GO
UPDATE ZebraCCSFLDAHAPopulation5Y SET smoking_final_v = smoking_last_v;
UPDATE ZebraCCSFLDAHAPopulation5Y SET smoking_final_v = smoking_first_v WHERE smoking_last_v IS NULL AND DATEDIFF(day, '20120101', smoking_first_date) <= 730
AND smoking_first_date < event_date;
UPDATE ZebraCCSFLDAHAPopulation5Y SET smoking_final_v = 1 WHERE smoking_first_v = 1;

UPDATE ZebraCCSFLDAHAPopulation5Y SET smoking_final_v = 1 WHERE smoking_final_v IN (1,2);
UPDATE ZebraCCSFLDAHAPopulation5Y SET smoking_final_v = 2 WHERE smoking_final_v = 3;

ALTER TABLE ZebraCCSFLDAHAPopulation5Y ADD SBP_final_v FLOAT;
GO
UPDATE ZebraCCSFLDAHAPopulation5Y SET sbp_final_v = sbp_last_v;
UPDATE ZebraCCSFLDAHAPopulation5Y SET sbp_final_v = sbp_first_v WHERE sbp_last_v IS NULL AND DATEDIFF(day, '20120101', sbp_first_date) <= 730
AND sbp_first_date < event_date;

ALTER TABLE ZebraCCSFLDAHAPopulation5Y ADD HDL_final_v FLOAT;
GO
UPDATE ZebraCCSFLDAHAPopulation5Y SET HDL_final_v = HDL_last_v;
UPDATE ZebraCCSFLDAHAPopulation5Y SET HDL_final_v = HDL_first_v WHERE HDL_last_v IS NULL AND DATEDIFF(day, '20120101', HDL_first_date) <= 730
AND HDL_first_date < event_date;

ALTER TABLE ZebraCCSFLDAHAPopulation5Y ADD TC_final_v FLOAT;
GO
UPDATE ZebraCCSFLDAHAPopulation5Y SET TC_final_v = TC_last_v;
UPDATE ZebraCCSFLDAHAPopulation5Y SET TC_final_v = TC_first_v WHERE TC_last_v IS NULL AND DATEDIFF(day, '20120101', TC_first_date) <= 730
AND TC_first_date < event_date;

-- and one to make the column names nice and monotone
ALTER TABLE ZebraCCSFLDAHAPopulation5Y ADD sw_final_DM FLOAT;
GO
UPDATE ZebraCCSFLDAHAPopulation5Y SET sw_final_DM = sw_diabetes_diag;

---------------------------
-- Dealing with Outliers --
---------------------------
UPDATE ZebraCCSFLDAHAPopulation5Y SET sbp_final_v = NULL WHERE sbp_final_v >= 230;
UPDATE ZebraCCSFLDAHAPopulation5Y SET HDL_final_v = NULL WHERE HDL_final_v > 150 OR HDL_final_v < 6;
UPDATE ZebraCCSFLDAHAPopulation5Y SET TC_final_v = NULL WHERE TC_final_v > 700 OR TC_final_v < 20;

--------------------------
-- Consolidate Outcomes --
--------------------------
-- The idea:
-- we're flattening survival analysis, so:
-- A case is anyone who had an event and reached the end or had an event and died
-- A control is anyone who reached the end or died w/o having an event
-- Anyone lost to follow up, event or no, is excluded

ALTER TABLE ZebraCCSFLDAHAPopulation5Y ADD sw_event TINYINT, event_date DATE;
GO
UPDATE ZebraCCSFLDAHAPopulation5Y SET sw_event = 0, event_date = NULL;
UPDATE ZebraCCSFLDAHAPopulation5Y SET sw_event = 1 WHERE sw_stroke_ischemic = 1 OR sw_stroke_hemorrhagic = 1 OR sw_stroke_unknown = 1 OR new_MI_sw = 1 OR CVD_death_sw = 1;
UPDATE ZebraCCSFLDAHAPopulation5Y SET event_date = new.min_date
	FROM ZebraCCSFLDAHAPopulation5Y
	INNER JOIN 
		(SELECT teudat_zehut, (SELECT MIN([date]) FROM (VALUES (date_stroke_ischemic), (date_stroke_hemorrhagic), (date_stroke_unknown), (new_MI_date), (CVD_death_date)) x ([date])) AS min_date
		FROM ZebraCCSFLDAHAPopulation5Y) AS new
	ON ZebraCCSFLDAHAPopulation5Y.teudat_zehut = new.teudat_zehut;

-- final exposure columns
ALTER TABLE ZebraCCSFLDAHAPopulation5Y ADD exposure_time INT, compound_end_date DATE;
GO
UPDATE ZebraCCSFLDAHAPopulation5Y SET compound_end_date = IIF(sw_event = 1, event_date, exposure_end_date);
UPDATE ZebraCCSFLDAHAPopulation5Y SET exposure_time = DATEDIFF(day, '20120101', compound_end_date)/30;

-- They have to have at least a month of follow up
DELETE FROM ZebraCCSFLDAHAPopulation5Y WHERE exposure_time = 0; -- 982 deleted

-----------------------
-- Add Zebra Columns --
-----------------------
ALTER TABLE ZebraCCSFLDAHAPopulation5Y ADD FLD_date DATE, FLD_score FLOAT, CCS_date DATE, CCS_score FLOAT;
GO
UPDATE ZebraCCSFLDAHAPopulation5Y SET FLD_date = NULL, FLD_score = NULL, CCS_date = NULL, CCS_score = NULL;

WITH closest_FLD AS (
SELECT pop.teudat_zehut, MIN(ABS(DATEDIFF(day, '20120101', zebra.date))) AS closest_date
FROM ZebraCCSFLDAHAPopulation5Y AS pop
INNER JOIN zebra_ccs_and_fld_data_cleaned AS zebra
ON pop.teudat_zehut = zebra.teudat_zehut
AND type = 'FLD'
AND zebra.date BETWEEN '20100101' AND '20140101'
GROUP BY pop.teudat_zehut
)
UPDATE pop SET FLD_score = zebra_fld.score, FLD_date = zebra_fld.date
--SELECT *
FROM ZebraCCSFLDAHAPopulation5Y AS pop
INNER JOIN zebra_ccs_and_fld_data_cleaned AS zebra_fld
ON pop.teudat_zehut = zebra_fld.teudat_zehut AND zebra_fld.type = 'fld'
INNER JOIN closest_FLD
ON closest_FLD.teudat_zehut = pop.teudat_zehut AND ABS(DATEDIFF(day, '20120101', zebra_fld.date)) = closest_FLD.closest_date;
--WHERE pop.teudat_zehut = 2679181

WITH closest_CCS AS (
SELECT pop.teudat_zehut, MIN(ABS(DATEDIFF(day, '20120101', zebra.date))) AS closest_date
FROM ZebraCCSFLDAHAPopulation5Y AS pop
INNER JOIN zebra_ccs_and_fld_data_cleaned AS zebra
ON pop.teudat_zehut = zebra.teudat_zehut
AND type = 'CCS'
AND zebra.date BETWEEN '20100101' AND '20140101'
GROUP BY pop.teudat_zehut)
UPDATE pop SET CCS_score = zebra_ccs.score, CCS_date = zebra_ccs.date
--SELECT *
FROM ZebraCCSFLDAHAPopulation5Y AS pop
INNER JOIN zebra_ccs_and_fld_data_cleaned AS zebra_ccs
ON pop.teudat_zehut = zebra_ccs.teudat_zehut AND zebra_ccs.type = 'ccs'
INNER JOIN closest_CCS
ON closest_CCS.teudat_zehut = pop.teudat_zehut AND ABS(DATEDIFF(day, '20120101', zebra_ccs.date)) = closest_CCS.closest_date;

-- we'll use the old one here for more results
--WITH closest_CCS AS (
--SELECT pop.teudat_zehut, MIN(ABS(DATEDIFF(day, '20120101', zebra.date))) AS closest_date
--FROM ZebraCCSFLDAHAPopulation5Y AS pop
--INNER JOIN zebra_ccs_data_new_cleaned AS zebra
--ON pop.teudat_zehut = zebra.teudat_zehut
--AND type = 'CCS'
--AND zebra.date BETWEEN '20100101' AND '20090101'
--GROUP BY pop.teudat_zehut)
--UPDATE pop SET CCS_score = zebra_ccs.score, CCS_date = zebra_ccs.date
----SELECT *
--FROM ZebraCCSFLDAHAPopulation5Y AS pop
--INNER JOIN zebra_ccs_data_new_cleaned AS zebra_ccs
--ON pop.teudat_zehut = zebra_ccs.teudat_zehut AND zebra_ccs.type = 'ccs'
--INNER JOIN closest_CCS
--ON closest_CCS.teudat_zehut = pop.teudat_zehut AND ABS(DATEDIFF(day, '20120101', zebra_ccs.date)) = closest_CCS.closest_date;

--------------
-- Finalize --
--------------
-- ready the final table
DROP TABLE ZebraCCSFLDAHAPopulation5YFinal;
GO
SELECT teudat_zehut, exposure_time, exposure_termination_type, sw_event, -- survival analysis basics
age, sex, -- demographics covars
TC_final_v, HDL_final_v, SBP_final_v, smoking_final_v, -- clinical covars
sw_final_DM, sw_final_hypertension_Rx, -- diagnoses
CCS_score, FLD_score -- zebra vars
INTO ZebraCCSFLDAHAPopulation5YFinal
FROM ZebraCCSFLDAHAPopulation5Y;

SELECT COUNT(*) FROM ZebraCCSFLDAHAPopulation5YFinal; -- 1105942
-- now to R for imputation and the rest