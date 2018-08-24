-- 5 years, indexing at 01/06/2012

----------------
-- Population --
----------------

-- get the full clalit population
SELECT *
INTO ZebraCCSFLDFram2008Population
FROM m_clalit_members_ever;

-- get age and sex
EXEC dbo.sp_add_demography_columns
	@pstr_input_table_name = 'ZebraCCSFLDFram2008Population',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_date = '20120601',
	@pstr_age = 'age',
	@pstr_date_of_birth = 'dob',
	@pstr_date_of_death = 'dod',
	@pstr_gender = 'sex';

-- models only predict for persons of a certain age, delete those not of the proper age range
DELETE FROM ZebraCCSFLDFram2008Population WHERE age IS NULL OR age < 30 OR age > 74; -- 3661463

-- at least one year membership before
EXECUTE mechkar.dbo.sp_continuous_membership_column
	@pstr_table_name = 'ZebraCCSFLDFram2008Population',
	@pstr_start_date = '20110601',
	@pstr_end_date = '20120601',
	@pstr_id_col_name = 'teudat_zehut',
	@pstr_membership_col_name = 'sw_continuous_membership';

DELETE FROM ZebraCCSFLDFram2008Population WHERE sw_continuous_membership = 0;

-- exposure
EXEC sp_continuous_membership_survival_analysis
	@pstr_input_table_name = 'ZebraCCSFLDFram2008Population',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20120601',
	@pstr_end_date = '20170601',
	@pstr_membership_end_date ='exposure_end_date',
	@pstr_total_month_membership = 'exposure_month_count',
	@pstr_membership_type = 'exposure_termination_type';

DELETE FROM ZebraCCSFLDFram2008Population WHERE exposure_termination_type = 'No Membership'; -- 344076

----------------
-- Covariates --
----------------
-- 4 years before, 1 after

-- 3 labs(TC, LDL, HDL), which we'll get both last results for before the index date and first results for after the index date
EXEC mechkar.dbo.sp_get_lab_records
	@pstr_input_table_name = 'ZebraCCSFLDFram2008Population',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20080601',
	@pstr_end_date = '20120601',
	@pstr_lab_work_codes = '21500;21200;21400',
	@pstr_lab_work_names = 'LDL;TC;HDL',
	@pstr_last_value = 'last_v';

EXEC mechkar.dbo.sp_get_lab_records
	@pstr_input_table_name = 'ZebraCCSFLDFram2008Population',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20120601',
	@pstr_end_date = '20130601',
	@pstr_lab_work_codes = '21500;21200;21400',
	@pstr_lab_work_names = 'LDL;TC;HDL',
	@pstr_first_test_date_valid_numeric = 'first_date',
	@pstr_last_value = 'first_v';

-- 3 markers (SBP, DBP, smoking) - same trick
EXEC dbo.sp_add_clinical_covariates_columns
	@pstr_input_table_name = 'ZebraCCSFLDFram2008Population',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20080601',
	@pstr_end_date = '20120601',
	@pstr_sys_bp = 'SBP_last_v',
	@pstr_dias_bp = 'DBP_last_v',
	@pstr_smoking_status_code = 'smoking_last_v';

EXEC dbo.sp_add_clinical_covariates_columns
	@pstr_input_table_name = 'ZebraCCSFLDFram2008Population',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20120601',
	@pstr_end_date = '20130601',
	@pstr_bp_aggregation_type = 'first',
	@pstr_sys_bp = 'SBP_first_v',
	@pstr_dias_bp = 'DBP_first_v';

GO
-- smoking doesn't have a "first" value option, so we'll get it manually
ALTER TABLE ZebraCCSFLDFram2008Population ADD smoking_first_v TINYINT, smoking_first_date DATE;
GO

SELECT pop.teudat_zehut, MIN(mrk.date_start) AS min_date
INTO first_smoking
FROM DWH..mrk_fact_v AS mrk INNER JOIN ZebraCCSFLDFram2008Population AS pop
ON mrk.teudat_zehut = pop.teudat_zehut AND date_start >= '20120601'
AND mrk.kod_mrkr in (6, 8) AND mrk.mrkr_num_value1 <> (-1)
GROUP BY pop.teudat_zehut;

UPDATE pop
SET smoking_first_v = mrk.mrkr_num_value1, smoking_first_date = mrk.date_start
FROM ZebraCCSFLDFram2008Population AS pop
INNER JOIN DWH..mrk_fact_v AS mrk ON pop.teudat_zehut = mrk.teudat_zehut AND mrk.kod_mrkr in (6, 8) AND mrk.mrkr_num_value1 <> (-1)
INNER JOIN first_smoking ON mrk.date_start = first_smoking.min_date;

-- correcting for past smoking
SELECT pop.teudat_zehut
INTO past_smokers
FROM ZebraCCSFLDFram2008Population AS pop
INNER JOIN dwh..mrk_fact_v AS mrk ON pop.teudat_zehut = mrk.teudat_zehut AND
mrk.date_start < pop.smoking_first_date AND mrk.mrkr_num_value1 <> (-1) AND mrk.kod_mrkr IN (6,8)
WHERE pop.smoking_first_v = 1 AND mrk.mrkr_num_value1 > 1

UPDATE pop
SET smoking_first_v = 2 
FROM ZebraCCSFLDFram2008Population pop
JOIN past_smokers ON pop.teudat_zehut = past_smokers.teudat_zehut;

-- correcting for the change in smoking markers
UPDATE ZebraCCSFLDFram2008Population
SET smoking_first_v = IIF(smoking_first_v BETWEEN 4 AND 5, 3, smoking_first_v)
WHERE smoking_first_v IS NOT NULL;

DROP TABLE first_smoking;
DROP TABLE past_smokers;

-- DM Dx
ALTER TABLE ZebraCCSFLDFram2008Population ADD sw_diabetes_diag TINYINT, date_diabetes_diag DATE;
GO
UPDATE ZebraCCSFLDFram2008Population SET sw_diabetes_diag = 0, date_diabetes_diag = NULL;

UPDATE ZebraCCSFLDFram2008Population
SET sw_diabetes_diag = 1, date_diabetes_diag = diab.diab_date
FROM ZebraCCSFLDFram2008Population AS pop
INNER JOIN M_diabetes_registry AS diab
ON pop.teudat_zehut = diab.teudat_zehut
AND diab.diab_date < '20120601' AND diab_class = 2;

EXECUTE mechkar.dbo.sp_get_med_purch
	@pstr_input_table_name = 'ZebraCCSFLDFram2008Population',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '19000101',
	@pstr_end_date = '20120601',
	@pstr_atc5_codes = 'A10%',
	@pstr_med_group_names = 'DM',
	@pstr_sw_disp = 'sw_disp',
	@pstr_disp_num = 'num_disp',
	@pstr_first_disp_date = 'first_disp',
	@pstr_last_disp_date = 'last_disp',
	@pstr_sw_pres = 'sw_pres',
	@pstr_pres_num = 'num_pres',
	@pstr_first_pres_date = 'first_pres',
	@pstr_last_pres_date = 'last_pres';

ALTER TABLE ZebraCCSFLDFram2008Population ADD sw_final_DM TINYINT;

GO

UPDATE ZebraCCSFLDFram2008Population SET sw_final_DM = 0
UPDATE ZebraCCSFLDFram2008Population
SET sw_final_DM = 1
WHERE date_diabetes_diag <= '20120601' -- diag before index date
AND first_disp_DM <= '20120601' -- drugs before index date
AND num_disp_DM >= 3; -- at least two dispensings

-- HT Rx
EXECUTE mechkar.dbo.sp_get_med_purch
	@pstr_input_table_name = 'ZebraCCSFLDFram2008Population',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '19000101',
	@pstr_end_date = '20120601',
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

ALTER TABLE ZebraCCSFLDFram2008Population ADD sw_final_hypertension_Rx TINYINT;
GO

UPDATE ZebraCCSFLDFram2008Population SET sw_final_hypertension_Rx = 0;
UPDATE ZebraCCSFLDFram2008Population SET sw_final_hypertension_Rx = 1
WHERE first_disp_hypertension <= '20120601'
AND num_disp_hypertension >= 3;

--------------
-- Outcomes --
--------------

-- That's it for the covars, but that was actually the easy part...
-- This is a list of the outcomes, for each we'll detail the plan:
	-- Angina Pectoris (community + hospitalization) X
	-- MI (hospitalization) X
	-- Ischemic + Hemorrhagic Stroke (as per the stroke model) X
	-- TIA (as per the stroke model) X
	-- Intermittent Claudication (community + hospitalization) X
	-- Heart Failure (community + hospitalization) X
	-- Coronary Death (causes of mortality + death with a close coronary event) X
	-- All CVD Death (causes of mortality + death with a close event) X

-- obviously, we also need to exclude on "old X" for each model that uses X
-- so we'll start with old ones

-- old CHD
EXECUTE mechkar.dbo.sp_get_diagnosis_records 
	@pstr_input_table_name = 'ZebraCCSFLDFram2008Population',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_end_date = '20120601',
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
	@pstr_input_table_name = 'ZebraCCSFLDFram2008Population',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_end_date = '20120601',
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
	@pstr_input_table_name = 'ZebraCCSFLDFram2008Population',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_end_date = '20120601',
	@pstr_icd_diagnoses = '428%;I50%;I25.5',
	@pstr_chr_diagnoses = '112%',
	@pstr_free_text_inclusion = '%congestive%heart%;%heart%failure%;%systolic%dysfunction%;%diastolic%dysfunction%;%ventricular%failure%;%CHF%;%ventricular%d[yi]sfunction%;',
	@pstr_free_text_exclusion ='',
	@psw_community = 1,
	@psw_admissions = 1,
	@psw_permanent = 1,
	@psw_chronic_all_diag = 1,
	@pstr_output_sw_column_name = 'old_heart_failure';

-- old PVD
EXECUTE mechkar.dbo.sp_get_diagnosis_records 
	@pstr_input_table_name = 'ZebraCCSFLDFram2008Population',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_end_date = '20120601',
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
	@pstr_output_sw_column_name = 'old_PVD';

-- now the new ones
-- new MI
EXECUTE mechkar.dbo.sp_get_diagnosis_records 
	@pstr_input_table_name = 'ZebraCCSFLDFram2008Population',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20120601',
	@pstr_end_date = '20170601',
	@pstr_icd_diagnoses = '410%', 
	@psw_admissions = 1,
	@pn_hospital_diagnosis_type = 1,
	@pstr_output_sw_column_name = 'new_MI_sw',
	@pstr_output_date_column_name = 'new_MI_date',
	@pstr_departments = '10;11;12;13;14;21;22;23;26;27;28;39;31;32;33;41;52;53;55;56;57;58;61;62;63;65;70;71;73;84;85';

-- new CHD
EXECUTE mechkar.dbo.sp_get_diagnosis_records 
	@pstr_input_table_name = 'ZebraCCSFLDFram2008Population',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20120601',
	@pstr_end_date = '20170601',
	@pstr_icd_diagnoses = '41[01234]%;I2[012345]', 
	@pstr_icpc_diagnoses = 'K75;K76;', 
	@pstr_chr_diagnoses = '110.1;110.9;',
	@pstr_free_text_inclusion = '%angina%;%prectoris%;%heart%attack%;%myocardial%inf%;%ischemic%heart%;%ischaemic%heart%;%coronary%atherosclerosis%;%arterioscl%cardiovascular%;%post%coronary%bypass%;%coronary%insuf%;%atheroscl%cardiovasc%;%acute%coronary%;%cardial%ischemia%;%intermediate%coronary%;%dyspnea%effort%;infarction%myocardial%;%infarction%subendocardial%;%subendocardial%infarction%;', 
	@pstr_free_text_exclusion = '%fear%;%gynecologic%;%no%disease%;%us%examination%;%normal%;%breast%;%medical%examination%;%herp%angina%;%hearing%;', 
	@psw_community = 1,
	@psw_permanent = 1,
	@psw_chronic_all_diag = 1,
	@psw_admissions = 1,
	@pstr_output_sw_column_name = 'new_CHD_sw',
	@pstr_output_date_column_name = 'new_CHD_date';

-- non-MI AP is the difference between CHD and MI
ALTER TABLE ZebraCCSFLDFram2008Population ADD new_angina_pectoris_sw TINYINT, new_angina_pectoris_date DATE;
GO

UPDATE ZebraCCSFLDFram2008Population SET new_angina_pectoris_sw = 0, new_angina_pectoris_date = NULL;
UPDATE ZebraCCSFLDFram2008Population SET new_angina_pectoris_sw = new_CHD_sw, new_angina_pectoris_date = new_CHD_date
WHERE new_MI_sw = 0;

-- new heart failure
EXECUTE mechkar.dbo.sp_get_diagnosis_records
	@pstr_input_table_name = 'ZebraCCSFLDFram2008Population',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20120601',
	@pstr_end_date = '20170601',
	@pstr_icd_diagnoses = '428%;I50%;I25.5',
	@pstr_chr_diagnoses = '112%',
	@pstr_free_text_inclusion = '%congestive%heart%;%heart%failure%;%systolic%dysfunction%;%diastolic%dysfunction%;%ventricular%failure%;%CHF%;%ventricular%d[yi]sfunction%;',
	@pstr_free_text_exclusion ='',
	@psw_community = 1,
	@psw_admissions = 1,
	@psw_permanent = 1,
	@psw_chronic_all_diag = 1,
	@pstr_output_sw_column_name = 'new_HF_sw',
	@pstr_output_date_column_name = 'new_HF_date';

-- new PVD
EXECUTE mechkar.dbo.sp_get_diagnosis_records 
	@pstr_input_table_name = 'ZebraCCSFLDFram2008Population',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20120601',
	@pstr_end_date = '20170601',
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
	@pstr_output_sw_column_name = 'new_PVD_sw',
	@pstr_output_date_column_name = 'new_PVD_date';

-- new ICH
EXECUTE mechkar.dbo.sp_get_diagnosis_records
	@pstr_input_table_name = 'ZebraCCSFLDFram2008Population',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20120601',
	@pstr_end_date = '20170601',
	@pstr_output_sw_column_name = 'sw_ICH',
	@pstr_output_date_column_name = 'date_ICH',
	@pstr_icd_diagnoses = '431%;I61%',
	@psw_admissions = 1,
	@pn_hospital_diagnosis_type = 1,
	@pstr_departments = '10;11;12;13;14;21;22;23;26;27;28;39;31;32;33;41;52;53;55;56;57;58;61;62;63;65;70;71;73;84;85';

-- new CVA - Thrombotic
EXECUTE mechkar.dbo.sp_get_diagnosis_records
	@pstr_input_table_name = 'ZebraCCSFLDFram2008Population',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20120601',
	@pstr_end_date = '20170601',
	@pstr_output_sw_column_name = 'sw_CVA_T',
	@pstr_output_date_column_name = 'date_CVA_T',
	@pstr_icd_diagnoses = '433._1;434.01;434.91;I63.0%;I63.2%;I63.3%;I63.5%;I63.6%;I63.8%;I63.9%;',
	@psw_admissions = 1,
	@pn_hospital_diagnosis_type = 1,
	@pstr_departments = '10;11;12;13;14;21;22;23;26;27;28;39;31;32;33;41;52;53;55;56;57;58;61;62;63;65;70;71;73;84;85'; -- not rehab!!!

-- new CVA - Embolic
EXECUTE mechkar.dbo.sp_get_diagnosis_records
	@pstr_input_table_name = 'ZebraCCSFLDFram2008Population',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20120601',
	@pstr_end_date = '20170601',
	@pstr_output_sw_column_name = 'sw_CVA_E',
	@pstr_output_date_column_name = 'date_CVA_E',
	@pstr_icd_diagnoses = '434.11;I63.1%;I63.4%',
	@psw_admissions = 1,
	@pn_hospital_diagnosis_type = 1,
	@pstr_departments = '10;11;12;13;14;21;22;23;26;27;28;39;31;32;33;41;52;53;55;56;57;58;61;62;63;65;70;71;73;84;85'; -- not rehab!!!

-- new TIA
EXECUTE mechkar.dbo.sp_get_diagnosis_records
	@pstr_input_table_name = 'ZebraCCSFLDFram2008Population',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20120601',
	@pstr_end_date = '20170601',
	@pstr_output_sw_column_name = 'sw_TIA',
	@pstr_output_date_column_name = 'date_TIA',
	@pstr_icd_diagnoses = '435%;G45%',
	@psw_admissions = 1,
	@pn_hospital_diagnosis_type = 1,
	@pstr_departments = '10;11;12;13;14;21;22;23;26;27;28;39;31;32;33;41;52;53;55;56;57;58;61;62;63;65;70;71;73;84;85';

-- new CVA - Doubt
EXECUTE mechkar.dbo.sp_get_diagnosis_records
	@pstr_input_table_name = 'ZebraCCSFLDFram2008Population',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = '20120601',
	@pstr_end_date = '20170601',
	@pstr_output_sw_column_name = 'sw_CVA_D',
	@pstr_output_date_column_name = 'date_CVA_D',
	@pstr_icd_diagnoses = '436%;437%;434._0;997.02;I63.0%;I63.2%;I63.3%;I63.5%;I63.6%;I63.8%;I63.9%;',
	@psw_admissions = 1,
	@pn_hospital_diagnosis_type = 1,
	@pstr_departments = '10;11;12;13;14;21;22;23;26;27;28;39;31;32;33;41;52;53;55;56;57;58;61;62;63;65;70;71;73;84;85'; -- not rehab!!!

-- add check date, 2 months after the diag
ALTER TABLE ZebraCCSFLDFram2008Population ADD check_date date;
GO
UPDATE ZebraCCSFLDFram2008Population SET check_date = DATEADD(month, 2, date_CVA_D);

-- Community verification for CVA in doubt
EXECUTE mechkar.dbo.sp_get_diagnosis_records
	@pstr_input_table_name = 'ZebraCCSFLDFram2008Population',
	@pstr_ids_column_name = 'teudat_zehut',
	@pstr_start_date = 'date_CVA_D',
	@pstr_end_date = 'check_date',
	@pstr_icd_diagnoses = '430%;852%;431%;433_1;434_1;435%;436%',
	@pstr_icpc_diagnoses = 'K90',
	@pstr_free_text_inclusion='%intracerebral%hemorrhage%;%cerebro%vasc;%CVA%;%STROKE%;%TIA%;%transient%ischemic%attack%;%intra%cerebral%hemo%;transient%cerebral%ischemia%;%cerebrovascular%accident%;%SAH%;%subarachnoid%hemorrhage%;%hemorrhage%brain%nontraumatic%;',
	@pstr_free_text_exclusion = '%S/P%;%M/P%;%cognitive%;%old%;%resolved%;%susp%;%chronic%;%s/a%;%status%post%;%sp%;%excluded%;%בעבר%;%post%;%past%;%s-p%;%s\p%;%s.p%;%plaque%;%epidural%;%subdural%;',
	@psw_community = 1,
	@pstr_output_sw_column_name = 'sw_CVA_D_check';

UPDATE ZebraCCSFLDFram2008Population SET sw_CVA_D = 0, date_CVA_D = NULL WHERE sw_CVA_D_check = 0;

ALTER TABLE ZebraCCSFLDFram2008Population ADD sw_STROKE TINYINT, stroke_date DATE;
GO

UPDATE ZebraCCSFLDFram2008Population SET sw_STROKE = 1 WHERE sw_ICH = 1 OR sw_CVA_T = 1 OR sw_CVA_E = 1 OR sw_TIA = 1 OR sw_CVA_D = 1;
UPDATE ZebraCCSFLDFram2008Population SET stroke_date = new.min_date
	FROM ZebraCCSFLDFram2008Population
	INNER JOIN 
		(SELECT teudat_zehut, (SELECT MIN([date]) FROM (VALUES (date_ICH),(date_CVA_T), (date_CVA_E), (date_TIA), (date_CVA_D)) x ([date])) AS min_date
		FROM ZebraCCSFLDFram2008Population) AS new
	ON ZebraCCSFLDFram2008Population.teudat_zehut = new.teudat_zehut;

--------------------
-- Cause of Death --
--------------------
ALTER TABLE ZebraCCSFLDFram2008Population ADD coronary_death_MOI_sw TINYINT, coronary_death_MOI_date DATE;
GO

UPDATE pop SET coronary_death_MOI_sw = 1, coronary_death_MOI_date = TRY_CONVERT(date, ["death_dt"], 103)
FROM ZebraCCSFLDFram2008Population AS pop
INNER JOIN [Mechkar].[CLALIT\MosheHo].[clalit_cause_death1] AS MOI
ON pop.teudat_zehut = LEFT(MOI.["full_TZ"], LEN(MOI.["full_TZ"]) - 1)
WHERE ["death_dt"] <> '' AND
(["siba1"] LIKE 'I11%' OR ["siba1"] LIKE 'I13%' OR ["siba1"] LIKE 'I21%' OR ["siba1"] LIKE 'I24%' OR ["siba1"] LIKE 'I25%' OR ["siba1"] LIKE 'I20%' OR ["siba1"] LIKE 'I44%' OR ["siba1"] LIKE 'I47%' OR ["siba1"] LIKE 'I50%' OR ["siba1"] LIKE 'I51%') AND (["siba1"] NOT LIKE 'I456%' AND ["siba1"] NOT LIKE 'I514%')
OR (["siba2"] LIKE 'I11%' OR ["siba2"] LIKE 'I13%' OR ["siba2"] LIKE 'I21%' OR ["siba2"] LIKE 'I24%' OR ["siba2"] LIKE 'I25%' OR ["siba2"] LIKE 'I20%' OR ["siba2"] LIKE 'I44%' OR ["siba2"] LIKE 'I47%' OR ["siba2"] LIKE 'I50%' OR ["siba2"] LIKE 'I51%') AND (["siba2"] NOT LIKE 'I456%' AND ["siba2"] NOT LIKE 'I514%')
OR (["siba3"] LIKE 'I11%' OR ["siba3"] LIKE 'I13%' OR ["siba3"] LIKE 'I21%' OR ["siba3"] LIKE 'I24%' OR ["siba3"] LIKE 'I25%' OR ["siba3"] LIKE 'I20%' OR ["siba3"] LIKE 'I44%' OR ["siba3"] LIKE 'I47%' OR ["siba3"] LIKE 'I50%' OR ["siba3"] LIKE 'I51%') AND (["siba3"] NOT LIKE 'I456%' AND ["siba3"] NOT LIKE 'I514%')
OR (["siba4"] LIKE 'I11%' OR ["siba4"] LIKE 'I13%' OR ["siba4"] LIKE 'I21%' OR ["siba4"] LIKE 'I24%' OR ["siba4"] LIKE 'I25%' OR ["siba4"] LIKE 'I20%' OR ["siba4"] LIKE 'I44%' OR ["siba4"] LIKE 'I47%' OR ["siba4"] LIKE 'I50%' OR ["siba4"] LIKE 'I51%') AND (["siba4"] NOT LIKE 'I456%' AND ["siba4"] NOT LIKE 'I514%')
OR (["siba5"] LIKE 'I11%' OR ["siba5"] LIKE 'I13%' OR ["siba5"] LIKE 'I21%' OR ["siba5"] LIKE 'I24%' OR ["siba5"] LIKE 'I25%' OR ["siba5"] LIKE 'I20%' OR ["siba5"] LIKE 'I44%' OR ["siba5"] LIKE 'I47%' OR ["siba5"] LIKE 'I50%' OR ["siba5"] LIKE 'I51%') AND (["siba5"] NOT LIKE 'I456%' AND ["siba5"] NOT LIKE 'I514%')
OR (["siba6"] LIKE 'I11%' OR ["siba6"] LIKE 'I13%' OR ["siba6"] LIKE 'I21%' OR ["siba6"] LIKE 'I24%' OR ["siba6"] LIKE 'I25%' OR ["siba6"] LIKE 'I20%' OR ["siba6"] LIKE 'I44%' OR ["siba6"] LIKE 'I47%' OR ["siba6"] LIKE 'I50%' OR ["siba6"] LIKE 'I51%') AND (["siba6"] NOT LIKE 'I456%' AND ["siba6"] NOT LIKE 'I514%')
OR (["siba7"] LIKE 'I11%' OR ["siba7"] LIKE 'I13%' OR ["siba7"] LIKE 'I21%' OR ["siba7"] LIKE 'I24%' OR ["siba7"] LIKE 'I25%' OR ["siba7"] LIKE 'I20%' OR ["siba7"] LIKE 'I44%' OR ["siba7"] LIKE 'I47%' OR ["siba7"] LIKE 'I50%' OR ["siba7"] LIKE 'I51%') AND (["siba7"] NOT LIKE 'I456%' AND ["siba7"] NOT LIKE 'I514%')
OR (["siba8"] LIKE 'I11%' OR ["siba8"] LIKE 'I13%' OR ["siba8"] LIKE 'I21%' OR ["siba8"] LIKE 'I24%' OR ["siba8"] LIKE 'I25%' OR ["siba8"] LIKE 'I20%' OR ["siba8"] LIKE 'I44%' OR ["siba8"] LIKE 'I47%' OR ["siba8"] LIKE 'I50%' OR ["siba8"] LIKE 'I51%') AND (["siba8"] NOT LIKE 'I456%' AND ["siba8"] NOT LIKE 'I514%')
OR (["siba9"] LIKE 'I11%' OR ["siba9"] LIKE 'I13%' OR ["siba9"] LIKE 'I21%' OR ["siba9"] LIKE 'I24%' OR ["siba9"] LIKE 'I25%' OR ["siba9"] LIKE 'I20%' OR ["siba9"] LIKE 'I44%' OR ["siba9"] LIKE 'I47%' OR ["siba9"] LIKE 'I50%' OR ["siba9"] LIKE 'I51%') AND (["siba9"] NOT LIKE 'I456%' AND ["siba9"] NOT LIKE 'I514%')
OR (["siba10"] LIKE 'I11%' OR ["siba10"] LIKE 'I13%' OR ["siba10"] LIKE 'I21%' OR ["siba10"] LIKE 'I24%' OR ["siba10"] LIKE 'I25%' OR ["siba10"] LIKE 'I20%' OR ["siba10"] LIKE 'I44%' OR ["siba10"] LIKE 'I47%' OR ["siba10"] LIKE 'I50%' OR ["siba10"] LIKE 'I51%') AND (["siba10"] NOT LIKE 'I456%' AND ["siba10"] NOT LIKE 'I514%')
OR (["siba11"] LIKE 'I11%' OR ["siba11"] LIKE 'I13%' OR ["siba11"] LIKE 'I21%' OR ["siba11"] LIKE 'I24%' OR ["siba11"] LIKE 'I25%' OR ["siba11"] LIKE 'I20%' OR ["siba11"] LIKE 'I44%' OR ["siba11"] LIKE 'I47%' OR ["siba11"] LIKE 'I50%' OR ["siba11"] LIKE 'I51%') AND (["siba11"] NOT LIKE 'I456%' AND ["siba11"] NOT LIKE 'I514%')
OR (["siba12"] LIKE 'I11%' OR ["siba12"] LIKE 'I13%' OR ["siba12"] LIKE 'I21%' OR ["siba12"] LIKE 'I24%' OR ["siba12"] LIKE 'I25%' OR ["siba12"] LIKE 'I20%' OR ["siba12"] LIKE 'I44%' OR ["siba12"] LIKE 'I47%' OR ["siba12"] LIKE 'I50%' OR ["siba12"] LIKE 'I51%') AND (["siba12"] NOT LIKE 'I456%' AND ["siba12"] NOT LIKE 'I514%')
OR (["siba13"] LIKE 'I11%' OR ["siba13"] LIKE 'I13%' OR ["siba13"] LIKE 'I21%' OR ["siba13"] LIKE 'I24%' OR ["siba13"] LIKE 'I25%' OR ["siba13"] LIKE 'I20%' OR ["siba13"] LIKE 'I44%' OR ["siba13"] LIKE 'I47%' OR ["siba13"] LIKE 'I50%' OR ["siba13"] LIKE 'I51%') AND (["siba13"] NOT LIKE 'I456%' AND ["siba13"] NOT LIKE 'I514%')
OR (["siba14"] LIKE 'I11%' OR ["siba14"] LIKE 'I13%' OR ["siba14"] LIKE 'I21%' OR ["siba14"] LIKE 'I24%' OR ["siba14"] LIKE 'I25%' OR ["siba14"] LIKE 'I20%' OR ["siba14"] LIKE 'I44%' OR ["siba14"] LIKE 'I47%' OR ["siba14"] LIKE 'I50%' OR ["siba14"] LIKE 'I51%') AND (["siba14"] NOT LIKE 'I456%' AND ["siba14"] NOT LIKE 'I514%')
OR (["siba20"] LIKE 'I11%' OR ["siba20"] LIKE 'I13%' OR ["siba20"] LIKE 'I21%' OR ["siba20"] LIKE 'I24%' OR ["siba20"] LIKE 'I25%' OR ["siba20"] LIKE 'I20%' OR ["siba20"] LIKE 'I44%' OR ["siba20"] LIKE 'I47%' OR ["siba20"] LIKE 'I50%' OR ["siba20"] LIKE 'I51%') AND (["siba20"] NOT LIKE 'I456%' AND ["siba20"] NOT LIKE 'I514%')
OR (["siba21"] LIKE 'I11%' OR ["siba21"] LIKE 'I13%' OR ["siba21"] LIKE 'I21%' OR ["siba21"] LIKE 'I24%' OR ["siba21"] LIKE 'I25%' OR ["siba21"] LIKE 'I20%' OR ["siba21"] LIKE 'I44%' OR ["siba21"] LIKE 'I47%' OR ["siba21"] LIKE 'I50%' OR ["siba21"] LIKE 'I51%') AND (["siba21"] NOT LIKE 'I456%' AND ["siba21"] NOT LIKE 'I514%')
OR (["siba22"] LIKE 'I11%' OR ["siba22"] LIKE 'I13%' OR ["siba22"] LIKE 'I21%' OR ["siba22"] LIKE 'I24%' OR ["siba22"] LIKE 'I25%' OR ["siba22"] LIKE 'I20%' OR ["siba22"] LIKE 'I44%' OR ["siba22"] LIKE 'I47%' OR ["siba22"] LIKE 'I50%' OR ["siba22"] LIKE 'I51%') AND (["siba22"] NOT LIKE 'I456%' AND ["siba22"] NOT LIKE 'I514%')
OR (["siba23"] LIKE 'I11%' OR ["siba23"] LIKE 'I13%' OR ["siba23"] LIKE 'I21%' OR ["siba23"] LIKE 'I24%' OR ["siba23"] LIKE 'I25%' OR ["siba23"] LIKE 'I20%' OR ["siba23"] LIKE 'I44%' OR ["siba23"] LIKE 'I47%' OR ["siba23"] LIKE 'I50%' OR ["siba23"] LIKE 'I51%') AND (["siba23"] NOT LIKE 'I456%' AND ["siba23"] NOT LIKE 'I514%')
OR (["siba24"] LIKE 'I11%' OR ["siba24"] LIKE 'I13%' OR ["siba24"] LIKE 'I21%' OR ["siba24"] LIKE 'I24%' OR ["siba24"] LIKE 'I25%' OR ["siba24"] LIKE 'I20%' OR ["siba24"] LIKE 'I44%' OR ["siba24"] LIKE 'I47%' OR ["siba24"] LIKE 'I50%' OR ["siba24"] LIKE 'I51%') AND (["siba24"] NOT LIKE 'I456%' AND ["siba24"] NOT LIKE 'I514%')
OR (["siba25"] LIKE 'I11%' OR ["siba25"] LIKE 'I13%' OR ["siba25"] LIKE 'I21%' OR ["siba25"] LIKE 'I24%' OR ["siba25"] LIKE 'I25%' OR ["siba25"] LIKE 'I20%' OR ["siba25"] LIKE 'I44%' OR ["siba25"] LIKE 'I47%' OR ["siba25"] LIKE 'I50%' OR ["siba25"] LIKE 'I51%') AND (["siba25"] NOT LIKE 'I456%' AND ["siba25"] NOT LIKE 'I514%')
OR (["siba26"] LIKE 'I11%' OR ["siba26"] LIKE 'I13%' OR ["siba26"] LIKE 'I21%' OR ["siba26"] LIKE 'I24%' OR ["siba26"] LIKE 'I25%' OR ["siba26"] LIKE 'I20%' OR ["siba26"] LIKE 'I44%' OR ["siba26"] LIKE 'I47%' OR ["siba26"] LIKE 'I50%' OR ["siba26"] LIKE 'I51%') AND (["siba26"] NOT LIKE 'I456%' AND ["siba26"] NOT LIKE 'I514%')
OR (["siba27"] LIKE 'I11%' OR ["siba27"] LIKE 'I13%' OR ["siba27"] LIKE 'I21%' OR ["siba27"] LIKE 'I24%' OR ["siba27"] LIKE 'I25%' OR ["siba27"] LIKE 'I20%' OR ["siba27"] LIKE 'I44%' OR ["siba27"] LIKE 'I47%' OR ["siba27"] LIKE 'I50%' OR ["siba27"] LIKE 'I51%') AND (["siba27"] NOT LIKE 'I456%' AND ["siba27"] NOT LIKE 'I514%')
OR (["siba28"] LIKE 'I11%' OR ["siba28"] LIKE 'I13%' OR ["siba28"] LIKE 'I21%' OR ["siba28"] LIKE 'I24%' OR ["siba28"] LIKE 'I25%' OR ["siba28"] LIKE 'I20%' OR ["siba28"] LIKE 'I44%' OR ["siba28"] LIKE 'I47%' OR ["siba28"] LIKE 'I50%' OR ["siba28"] LIKE 'I51%') AND (["siba28"] NOT LIKE 'I456%' AND ["siba28"] NOT LIKE 'I514%')
OR (["siba29"] LIKE 'I11%' OR ["siba29"] LIKE 'I13%' OR ["siba29"] LIKE 'I21%' OR ["siba29"] LIKE 'I24%' OR ["siba29"] LIKE 'I25%' OR ["siba29"] LIKE 'I20%' OR ["siba29"] LIKE 'I44%' OR ["siba29"] LIKE 'I47%' OR ["siba29"] LIKE 'I50%' OR ["siba29"] LIKE 'I51%') AND (["siba29"] NOT LIKE 'I456%' AND ["siba29"] NOT LIKE 'I514%')
OR (["siba30"] LIKE 'I11%' OR ["siba30"] LIKE 'I13%' OR ["siba30"] LIKE 'I21%' OR ["siba30"] LIKE 'I24%' OR ["siba30"] LIKE 'I25%' OR ["siba30"] LIKE 'I20%' OR ["siba30"] LIKE 'I44%' OR ["siba30"] LIKE 'I47%' OR ["siba30"] LIKE 'I50%' OR ["siba30"] LIKE 'I51%') AND (["siba30"] NOT LIKE 'I456%' AND ["siba30"] NOT LIKE 'I514%')
OR (["siba31"] LIKE 'I11%' OR ["siba31"] LIKE 'I13%' OR ["siba31"] LIKE 'I21%' OR ["siba31"] LIKE 'I24%' OR ["siba31"] LIKE 'I25%' OR ["siba31"] LIKE 'I20%' OR ["siba31"] LIKE 'I44%' OR ["siba31"] LIKE 'I47%' OR ["siba31"] LIKE 'I50%' OR ["siba31"] LIKE 'I51%') AND (["siba31"] NOT LIKE 'I456%' AND ["siba31"] NOT LIKE 'I514%')

-------------------
-- Smoking Logic --
-------------------
ALTER TABLE ZebraCCSFLDFram2008Population ADD LDL_final_v FLOAT, TC_final_v FLOAT, HDL_final_v FLOAT, SBP_final_v FLOAT, DBP_final_v FLOAT, smoking_final_v INT;
GO

-- smoking has some unique behaviour
UPDATE ZebraCCSFLDFram2008Population SET smoking_final_v = smoking_last_v;
UPDATE ZebraCCSFLDFram2008Population SET smoking_final_v = 1 WHERE smoking_first_v = 1;
UPDATE ZebraCCSFLDFram2008Population SET smoking_final_v = 2 WHERE smoking_first_v IN (2,3);
UPDATE ZebraCCSFLDFram2008Population SET smoking_final_v = 2 WHERE smoking_final_v = 3;

----------------
-- Seperating --
----------------
DROP TABLE ZebraCCSFLDPopulationFraminghamCVD;
GO

-- we have three models here, and each needs to be in its own table and only then do we get an event_date, exposure figures and survival stats
SELECT teudat_zehut, dob, dod, sex, age, exposure_end_date, exposure_month_count, exposure_termination_type,
TC_first_v, TC_last_v, TC_final_v, HDL_first_v, HDL_last_v, HDL_final_v, SBP_last_v, SBP_first_v, SBP_final_v, smoking_final_v, sw_final_DM,
sw_final_hypertension_Rx,
new_MI_sw, new_MI_date, new_angina_pectoris_sw, new_angina_pectoris_date, coronary_death_MOI_sw, coronary_death_MOI_date, sw_stroke, stroke_date,
new_PVD_sw, new_PVD_date, new_HF_sw, new_HF_date,
old_CHD, old_stroke, old_PVD, old_heart_failure
INTO ZebraCCSFLDPopulationFraminghamCVD
FROM ZebraCCSFLDFram2008Population
WHERE age BETWEEN 30 AND 74;

---------------
-- CVD Logic --
---------------
-- Plan:
-- 1. exclude old events
-- 2. set a compound event switch and date
-- 3. finalize the covars that use the future with the event_date (2 years, but less than the event_date)
-- 4. go to R and impute
SELECT TOP 1 * FROM ZebraCCSFLDPopulationFraminghamCVD

-- exclude
DELETE FROM ZebraCCSFLDPopulationFraminghamCVD WHERE old_CHD = 1 OR old_stroke = 1 OR old_PVD = 1 OR old_heart_failure = 1;

-- event switch and date
ALTER TABLE ZebraCCSFLDPopulationFraminghamCVD ADD sw_outcome TINYINT, outcome_date DATE;
GO
UPDATE ZebraCCSFLDPopulationFraminghamCVD SET sw_outcome = 0, outcome_date = NULL;

UPDATE ZebraCCSFLDPopulationFraminghamCVD SET sw_outcome = 1 WHERE
new_MI_sw = 1 OR new_angina_pectoris_sw = 1 OR coronary_death_MOI_sw = 1 OR sw_stroke = 1 OR new_PVD_sw = 1 OR new_HF_sw = 1;

UPDATE ZebraCCSFLDPopulationFraminghamCVD SET outcome_date = new.min_date
	FROM ZebraCCSFLDPopulationFraminghamCVD
	INNER JOIN 
		(SELECT teudat_zehut, (SELECT MIN([date]) FROM (VALUES (new_MI_date),(new_angina_pectoris_date), (coronary_death_MOI_date), (stroke_date), (new_PVD_date),
		(new_HF_date)) x ([date])) AS min_date
		FROM ZebraCCSFLDPopulationFraminghamCVD) AS new
	ON ZebraCCSFLDPopulationFraminghamCVD.teudat_zehut = new.teudat_zehut;

-- now we set the final columns
ALTER TABLE ZebraCCSFLDPopulationFraminghamCVD ADD exposure_time INT, event_date DATE, event_type TINYINT, exposure_years INT;
GO

UPDATE ZebraCCSFLDPopulationFraminghamCVD SET event_type = sw_outcome;
UPDATE ZebraCCSFLDPopulationFraminghamCVD SET event_date = IIF(event_type = 1, outcome_date, exposure_end_date);

UPDATE ZebraCCSFLDPopulationFraminghamCVD SET exposure_time = DATEDIFF(day, '20120601', event_date)/30;
UPDATE ZebraCCSFLDPopulationFraminghamCVD SET exposure_years = DATEDIFF(day, '20120601', event_date)/365.25;

-- competing risk columns might also aid us in the future
ALTER TABLE ZebraCCSFLDPopulationFraminghamCVD ADD comp_risk_type TINYINT, comp_risk_date DATE, comp_risk_exposure INT;
GO

--UPDATE ZebraCCSFLDPopulationFraminghamCVD SET comp_risk_type =
--	CASE
--		WHEN sw_outcome = 1 THEN 1
--		WHEN exposure_termination_type = 'Terminated By Death' THEN 2
--		ELSE 0
--	END

--UPDATE ZebraCCSFLDPopulationFraminghamCVD SET comp_risk_date = IIF(comp_risk_type = 1, outcome_date, exposure_end_date);

--UPDATE ZebraCCSFLDPopulationFraminghamCVD SET comp_risk_exposure = DATEDIFF(day, '20120601', comp_risk_date)/30;

-- They have to have at least a month of follow up
DELETE FROM ZebraCCSFLDPopulationFraminghamCVD WHERE exposure_time = 0;

-- finalize future based covars
UPDATE ZebraCCSFLDPopulationFraminghamCVD SET TC_final_v = TC_last_v
UPDATE ZebraCCSFLDPopulationFraminghamCVD SET TC_final_v = TC_first_v WHERE TC_last_v IS NULL
-- AND TC_first_date < event_date;

UPDATE ZebraCCSFLDPopulationFraminghamCVD SET HDL_final_v = HDL_last_v
UPDATE ZebraCCSFLDPopulationFraminghamCVD SET HDL_final_v = HDL_first_v WHERE HDL_last_v IS NULL
-- AND HDL_first_date < event_date;

UPDATE ZebraCCSFLDPopulationFraminghamCVD SET SBP_final_v = SBP_last_v
UPDATE ZebraCCSFLDPopulationFraminghamCVD SET SBP_final_v = SBP_first_v WHERE SBP_last_v IS NULL
-- AND SBP_first_date < event_date;

----------------
-- Zebra Vars --
----------------
-- 4 years before, 1 year after
ALTER TABLE ZebraCCSFLDPopulationFraminghamCVD ADD FLD_date DATE, FLD_score FLOAT, CCS_date DATE, CCS_score FLOAT;
GO
UPDATE ZebraCCSFLDPopulationFraminghamCVD SET FLD_date = NULL, FLD_score = NULL, CCS_date = NULL, CCS_score = NULL;

WITH closest_FLD AS (
SELECT pop.teudat_zehut, MIN(ABS(DATEDIFF(day, '20120601', zebra.date))) AS closest_date
FROM ZebraCCSFLDPopulationFraminghamCVD AS pop
INNER JOIN zebra_ccs_and_fld_data_cleaned AS zebra
ON pop.teudat_zehut = zebra.teudat_zehut
AND type = 'FLD'
AND zebra.date BETWEEN '20080601' AND '20130601'
GROUP BY pop.teudat_zehut
)
UPDATE pop SET FLD_score = zebra_fld.score, FLD_date = zebra_fld.date
--SELECT *
FROM ZebraCCSFLDPopulationFraminghamCVD AS pop
INNER JOIN zebra_ccs_and_fld_data_cleaned AS zebra_fld
ON pop.teudat_zehut = zebra_fld.teudat_zehut AND zebra_fld.type = 'fld'
INNER JOIN closest_FLD
ON closest_FLD.teudat_zehut = pop.teudat_zehut AND ABS(DATEDIFF(day, '20120601', zebra_fld.date)) = closest_FLD.closest_date;
--WHERE pop.teudat_zehut = 2679181

WITH closest_CCS AS (
SELECT pop.teudat_zehut, MIN(ABS(DATEDIFF(day, '20120601', zebra.date))) AS closest_date
FROM ZebraCCSFLDPopulationFraminghamCVD AS pop
INNER JOIN zebra_ccs_and_fld_data_cleaned AS zebra
ON pop.teudat_zehut = zebra.teudat_zehut
AND type = 'CCS'
AND zebra.date BETWEEN '20080601' AND '20130601'
GROUP BY pop.teudat_zehut)
UPDATE pop SET CCS_score = zebra_ccs.score, CCS_date = zebra_ccs.date
--SELECT *
FROM ZebraCCSFLDPopulationFraminghamCVD AS pop
INNER JOIN zebra_ccs_and_fld_data_cleaned AS zebra_ccs
ON pop.teudat_zehut = zebra_ccs.teudat_zehut AND zebra_ccs.type = 'ccs'
INNER JOIN closest_CCS
ON closest_CCS.teudat_zehut = pop.teudat_zehut AND ABS(DATEDIFF(day, '20120601', zebra_ccs.date)) = closest_CCS.closest_date;

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
DROP TABLE ZebraCCSFLDPopulationFraminghamCVDFinal;
DROP TABLE ZebraCCSFLDPopulationFraminghamCVDFinalReduced;

SELECT teudat_zehut, exposure_time, exposure_years, event_type, event_date,
--comp_risk_exposure, comp_risk_type, comp_risk_date, -- survival analysis basics
age, sex, -- demographics covars
TC_final_v, HDL_final_v, SBP_final_v, smoking_final_v, sw_final_DM, sw_final_hypertension_Rx, -- clinical covars
FLD_score, CCS_score -- zebras
INTO ZebraCCSFLDPopulationFraminghamCVDFinal
FROM ZebraCCSFLDPopulationFraminghamCVD;

SELECT teudat_zehut, exposure_time, exposure_years, event_type, event_date,
--comp_risk_exposure, comp_risk_type, comp_risk_date, -- survival analysis basics
age, sex, -- demographics covars
TC_final_v, HDL_final_v, SBP_final_v, smoking_final_v, sw_final_DM, sw_final_hypertension_Rx, -- clinical covars
FLD_score, CCS_score -- zebras
INTO ZebraCCSFLDPopulationFraminghamCVDFinalReduced
FROM ZebraCCSFLDPopulationFraminghamCVD
WHERE CCS_score IS NOT NULL AND FLD_score IS NOT NULL;

SELECT COUNT(*) FROM ZebraCCSFLDPopulationFraminghamCVDFinal; -- 1590229
SELECT COUNT(*) FROM ZebraCCSFLDPopulationFraminghamCVDFinalReduced; -- 12316