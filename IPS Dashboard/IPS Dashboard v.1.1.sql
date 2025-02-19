
---------- IPS Dashboard v.1.1 ----------

/* 
Steps:
- Declare reporting period
- Get all referrals to IPS services from the PreProc_Referral table
- Get activity information for all IPS referasl from the PreProc_Activity table - i.e. contacts with the service, access with the service
- Get outcomes information for all IPS referrals from the MHS004EmpStatus table - i.e. employment status
- Join this information together into a Master table - one row for each referral, for each month, with all their referral/activity/outcomes information
- Create measures using Master table data - i.e. caseload, number of new referals, number of employed people at discharge - at all monthly, geographical and demographic levels / combinations
- Pivot these measures into a suitable format for Tableau - creating an extract
*/

---------- Declare reporting period ----------

DECLARE @STARTRP INT
SET @STARTRP = 1417 -- 1417 = April 2018

DECLARE @ENDRP INT
SET @ENDRP = (SELECT UniqMonthID FROM [NHSE_Sandbox_MentalHealth].[dbo].[PreProc_Header] WHERE Der_MostRecentFlag = 'p') -- Der_MostRecentFlag = p (most recent month - primary data)

DECLARE @FYSTART INT
SET @FYSTART = (SELECT MAX(UniqMonthID) FROM [NHSE_Sandbox_MentalHealth].[dbo].[PreProc_Header] WHERE Der_FYStart = 'Y') -- Der_FYStart = Y (first month of the financial year); MAX here is most recent April / FY start date

---------- Create referrals temp table ----------

IF OBJECT_ID ('tempdb..#Referrals') IS NOT NULL
DROP TABLE #Referrals

SELECT
	r.Person_ID, 
	r.RecordNumber,
	r.UniqServReqID, 
	r.UniqMonthID,
	r.OrgIDProv, 
	CASE WHEN r.OrgIDProv = 'A8JX' THEN 'SOUTH YORKSHIRE HOUSING ASSOCIATION LIMITED' 
		ELSE o.Organisation_Name END AS ProvName, -- No org name for South Yorkshire so manually adding
	COALESCE(cc.New_Code, r.OrgIDCCGRes) AS OrgIDCCGRes, -- Use new CCG code - if no new code use original
	map.Organisation_Name AS CCGName,
	map.STP_Code,
	map.STP_Name,
	map.Region_Code,
	map.Region_Name,
	CASE WHEN r.SourceOfReferralMH IN ('A1','A2','A3','A4') THEN 'Primary Health Care' 
		WHEN r.SourceOfReferralMH IN ('B1','B2') THEN 'Self Referral' 
		WHEN r.SourceOfReferralMH IN ('I1','I2','P1','Q1','M9') THEN 'Secondary Health Care' 
		WHEN r.SourceOfReferralMH IN ('C1', 'C2', 'C3', 'D1', 'D2', 'E1', 'E2', 'E3', 'E4', 'E5', 'E6', 'F1', 'F2', 'F3', 'G1', 'G2', 'G3', 'G4', 'H1', 'H2', 'M1', 'M2', 'M3', 'M4', 'M5', 'M6', 'M7', 'N3') THEN 'Other' 
		ELSE 'Missing/Invalid' END AS SourceCat, -- Create/assign source of referral group
	CASE WHEN r.AgeServReferRecDate BETWEEN 16 AND 25 THEN '16to25' 
		WHEN r.AgeServReferRecDate BETWEEN 26 AND 35 THEN '26to35' 
		WHEN r.AgeServReferRecDate BETWEEN 36 AND 45 THEN '36to45' 
		WHEN r.AgeServReferRecDate BETWEEN 46 AND 55 THEN '46to55' 
		WHEN r.AgeServReferRecDate BETWEEN 56 AND 64 THEN '56to64' 
		WHEN r.AgeServReferRecDate < 16 OR r.AgeServReferRecDate > 64 THEN 'Other' 
		ELSE 'Missing/Invalid' END AS AgeCat, -- Create/assign age group
	CASE WHEN r.EthnicCategory = 'A' THEN 'White British' 
		WHEN r.EthnicCategory IN ('B', 'C') THEN 'White Other' 
		WHEN r.EthnicCategory IN ('D', 'E', 'F', 'G') THEN 'Mixed' 
		WHEN r.EthnicCategory IN ('H', 'J', 'K', 'L') THEN 'Asian' 
		WHEN r.EthnicCategory IN ('M', 'N', 'P') THEN 'Black' 
		WHEN r.EthnicCategory IN ('R', 'S') THEN 'Other' 
		ELSE 'Missing/Invalid' END AS EthnicityCat, -- Create/assign ethnicity group
	CASE WHEN r.Gender = '1' THEN 'Male' 
		WHEN r.Gender = '2' THEN 'Female' 
		WHEN (r.Gender = '9' AND r.UniqMonthID <= '1458') OR (r.Gender IN ('3', '4') AND r.UniqMonthID > '1458') THEN 'Other' 
		ELSE 'Missing/Invalid' END AS GenderCat, -- Create/assign gender group
	CASE WHEN d.IMD_Decile IN ('1', '2') THEN 'Quintile 1' 
		WHEN d.IMD_Decile IN ('3', '4') THEN 'Quintile 2' 
		WHEN d.IMD_Decile IN ('5', '6') THEN 'Quintile 3' 
		WHEN d.IMD_Decile IN ('7', '8') THEN 'Quintile 4' 
		WHEN d.IMD_Decile IN ('9', '10') THEN 'Quintile 5' 
		ELSE 'Missing/Invalid' END AS DeprivationQuintile, -- Create/assign deprivation (IMD) quintiles
	r.ServDischDate, 
	r.ReferralRequestReceivedDate, 
	r.ReportingPeriodEndDate AS ReportingPeriodEnd, 
	r.ReportingPeriodStartDate AS ReportingPeriodStart 
INTO #Referrals
FROM [NHSE_Sandbox_MentalHealth].[dbo].[PreProc_Referral] r -- Select referral info from r including referral received date and discharge date and referral demographics 
LEFT JOIN NHSE_Reference.dbo.tbl_Ref_ODS_Provider_Hierarchies o ON r.OrgIDProv = o.Organisation_Code -- Join to o to obtain organisation name for provider
LEFT JOIN NHSE_Reference.dbo.tbl_Ref_Other_ComCodeChanges cc ON r.OrgIDCCGRes = cc.Org_Code -- Join to cc to obtain new CCG codes
LEFT JOIN NHSE_Reference.dbo.tbl_Ref_ODS_Commissioner_Hierarchies map ON COALESCE(cc.New_Code, r.OrgIDCCGRes) = map.Organisation_Code -- Join to map to obtain provider to CCG / STP / region mappings
LEFT JOIN [NHSE_Reference].[dbo].[tbl_Ref_Other_Deprivation_By_LSOA] d ON r.LSOA2011 = d.LSOA_Code AND d.Effective_Snapshot_Date = '2019-12-31' -- Join to d to obtain IMD decile from LSOA code of residence
WHERE r.ReferralRequestReceivedDate >= '2016-01-01' AND r.UniqMonthID BETWEEN @STARTRP AND @ENDRP AND r.ServTeamTypeRefToMH = 'D05' AND (r.LADistrictAuth lIKE 'E%' OR r.LADistrictAuth IS NULL) -- Select only referrals to IPS received from 2016, in England to IPS, in the reporting period (from April 2018)

----- Insert SNOMED referrals (repeat above but tweaked for TEWV & GMMH to instead idenfity referals to IPS services via SNOMED codes, as ServTeamTypeRefToMH = 'D05' is not available)

IF OBJECT_ID ('tempdb..#SNOMEDIPS ') IS NOT NULL
DROP TABLE #SNOMEDIPS 

SELECT 
	a.RecordNumber, 
	a.UniqServReqID
INTO #SNOMEDIPS 
FROM [NHSE_Sandbox_MentalHealth].dbo.PreProc_Interventions a 
LEFT JOIN [NHSE_Sandbox_MentalHealth].dbo.PreProc_Activity p ON a.RecordNumber = p.RecordNumber AND a.UniqCareContID = p.UniqCareContID
WHERE a.Der_SNoMEDProcCode IN ('1082621000000104', '772822000') AND a.OrgIDProv IN ('RX3', 'RXV') -- Select all interventions/activity data for TEWV referrals with IPS SNoMED codes
AND p.Der_DirectContactOrder IS NOT NULL -- and only bring in direct contacts that are F2F, video, telephone or other
GROUP BY a.RecordNumber, a.UniqServReqID

INSERT INTO #Referrals -- Insert SNOMED referrals below into #Referrals table created above

SELECT
r.Person_ID, 
	r.RecordNumber,
	r.UniqServReqID, 
	r.UniqMonthID,
	r.OrgIDProv, 
	CASE WHEN r.OrgIDProv = 'A8JX' THEN 'SOUTH YORKSHIRE HOUSING ASSOCIATION LIMITED' 
		ELSE o.Organisation_Name END AS ProvName,
	COALESCE(cc.New_Code, r.OrgIDCCGRes) AS OrgIDCCGRes,
	map.Organisation_Name AS CCGName,
	map.STP_Code,
	map.STP_Name,
	map.Region_Code,
	map.Region_Name,
	CASE WHEN r.SourceOfReferralMH IN ('A1','A2','A3','A4') THEN 'Primary Health Care' 
		WHEN r.SourceOfReferralMH IN ('B1','B2') THEN 'Self Referral' 
		WHEN r.SourceOfReferralMH IN ('I1','I2','P1','Q1','M9') THEN 'Secondary Health Care' 
		WHEN r.SourceOfReferralMH IN ('C1', 'C2', 'C3', 'D1', 'D2', 'E1', 'E2', 'E3', 'E4', 'E5', 'E6', 'F1', 'F2', 'F3', 'G1', 'G2', 'G3', 'G4', 'H1', 'H2', 'M1', 'M2', 'M3', 'M4', 'M5', 'M6', 'M7', 'N3') THEN 'Other' 
		ELSE 'Missing/Invalid' END AS SourceCat, 
	CASE WHEN r.AgeServReferRecDate BETWEEN 16 AND 25 THEN '16to25' 
		WHEN r.AgeServReferRecDate BETWEEN 26 AND 35 THEN '26to35' 
		WHEN r.AgeServReferRecDate BETWEEN 36 AND 45 THEN '36to45' 
		WHEN r.AgeServReferRecDate BETWEEN 46 AND 55 THEN '46to55' 
		WHEN r.AgeServReferRecDate BETWEEN 56 AND 64 THEN '56to64' 
		WHEN r.AgeServReferRecDate < 16 OR r.AgeServReferRecDate > 64 THEN 'Other' 
		ELSE 'Missing/Invalid' END AS AgeCat, 
	CASE WHEN r.EthnicCategory = 'A' THEN 'White British' 
		WHEN r.EthnicCategory IN ('B', 'C') THEN 'White Other' 
		WHEN r.EthnicCategory IN ('D', 'E', 'F', 'G') THEN 'Mixed' 
		WHEN r.EthnicCategory IN ('H', 'J', 'K', 'L') THEN 'Asian' 
		WHEN r.EthnicCategory IN ('M', 'N', 'P') THEN 'Black' 
		WHEN r.EthnicCategory IN ('R', 'S') THEN 'Other' 
		ELSE 'Missing/Invalid' END AS EthnicityCat, 
	CASE WHEN r.Gender = '1' THEN 'Male' 
		WHEN r.Gender = '2' THEN 'Female' 
		WHEN (r.Gender = '9' AND r.UniqMonthID <= '1458') OR (r.Gender IN ('3', '4') AND r.UniqMonthID > '1458') THEN 'Other' 
		ELSE 'Missing/Invalid' END AS GenderCat, 
	CASE WHEN d.IMD_Decile IN ('1', '2') THEN 'Quintile 1' 
		WHEN d.IMD_Decile IN ('3', '4') THEN 'Quintile 2' 
		WHEN d.IMD_Decile IN ('5', '6') THEN 'Quintile 3' 
		WHEN d.IMD_Decile IN ('7', '8') THEN 'Quintile 4' 
		WHEN d.IMD_Decile IN ('9', '10') THEN 'Quintile 5' 
		ELSE 'Missing/Invalid' END AS DeprivationQuintile, 
	r.ServDischDate, 
	r.ReferralRequestReceivedDate, 
	r.ReportingPeriodEndDate AS ReportingPeriodEnd, 
	r.ReportingPeriodStartDate AS ReportingPeriodStart
FROM [NHSE_Sandbox_MentalHealth].[dbo].[PreProc_Referral] r 
LEFT JOIN NHSE_Reference.dbo.tbl_Ref_ODS_Provider_Hierarchies o ON r.OrgIDProv = o.Organisation_Code
LEFT JOIN NHSE_Reference.dbo.tbl_Ref_Other_ComCodeChanges cc ON r.OrgIDCCGRes = cc.Org_Code
LEFT JOIN NHSE_Reference.dbo.tbl_Ref_ODS_Commissioner_Hierarchies map ON COALESCE(cc.New_Code, r.OrgIDCCGRes) = map.Organisation_Code
LEFT JOIN [NHSE_Reference].[dbo].[tbl_Ref_Other_Deprivation_By_LSOA] d ON r.LSOA2011 = d.LSOA_Code AND d.Effective_Snapshot_Date = '2019-12-31' 
INNER JOIN #SNOMEDIPS a ON a.RecordNumber = r.RecordNumber AND a.UniqServReqID = r.UniqServReqID -- Select all referrals that have a contact related to IPS at TEWV (this means all referrals for TEWV are those that have accessed the service i.e. had a first contact)
WHERE r.ReferralRequestReceivedDate >= '2016-01-01' AND r.UniqMonthID BETWEEN @STARTRP AND @ENDRP AND (r.LADistrictAuth lIKE 'E%' OR r.LADistrictAuth IS NULL)

---------- Create activities temp table ----------

IF OBJECT_ID ('tempdb..#Activities') IS NOT NULL
DROP TABLE #Activities

SELECT
	a.RecordNumber, 
	a.UniqMonthID,
	a.Person_ID,
	a.UniqServReqID,
	MAX(a.Der_DirectContactOrder) AS ContactOrder, -- When ContactOrder is 0, referral has yet to access IPS (used for Caseload measure)
	SUM(CASE WHEN a.Der_DirectContactOrder = '1' THEN 1 ELSE 0 END) AS AccessFlag, -- Identify 1st ever contact (where direct contact order = 1) as access flag
	SUM(CASE WHEN a.Der_FYDirectContactOrder = '1' THEN 1 ELSE 0 END) AS FYAccessFlag, -- Identify 1st contact in FY year (where FY direct contact order = 1) as FY access flag
	MAX(CASE WHEN a.Der_DirectContactOrder = '1' THEN a.Der_ContactDate ELSE NULL END) AS AccessDate, -- Obtain date for first ever contact
	SUM(CASE WHEN (a.Der_DirectContactOrder IS NOT NULL AND a.ConsMediumUsed IN ('01', '02', '03', '04', '98') AND a.UniqMonthID <= '1458') OR (a.Der_DirectContactOrder IS NOT NULL AND a.ConsMediumUsed IN ('01', '02', '04', '98', '11') AND a.UniqMonthID > '1458') THEN 1 ELSE 0 END) AS TotalContacts, -- Calculate total contacts per referral per month
	SUM(CASE WHEN a.Der_DirectContactOrder IS NOT NULL AND a.ConsMediumUsed = '01' THEN 1 ELSE 0 END) AS TotalContactsF2F, -- Calculate total contacts per referral per month that were face to face contacts
	SUM(CASE WHEN a.Der_DirectContactOrder IS NOT NULL AND a.ConsMediumUsed IN ('02', '04') THEN 1 ELSE 0 END) AS TotalContactsTelephone, -- Calculate total contacts per referral per month that were via telephone or talk type
	SUM(CASE WHEN (a.Der_DirectContactOrder IS NOT NULL AND a.ConsMediumUsed = '03' AND a.UniqMonthID <= '1458') OR (a.Der_DirectContactOrder IS NOT NULL AND a.ConsMediumUsed = '11' AND a.UniqMonthID > '1458') THEN 1 ELSE 0 END) AS TotalContactsVideo, -- Calculate total contacts per referral per month that were via video
	SUM(CASE WHEN a.Der_DirectContactOrder IS NOT NULL AND a.ConsMediumUsed = '98' THEN 1 ELSE 0 END) AS TotalContactsOther -- Calculate total contacts per referral per month that were 'other' medium
INTO #Activities
FROM [NHSE_Sandbox_MentalHealth].dbo.PreProc_Activity a -- Select activitites info from PreProc Activity table...
INNER JOIN #Referrals r ON a.RecordNumber = r.RecordNumber AND a.UniqServReqID = r.UniqServReqID -- ... only for IPS referrals - those in the #Referrals table
WHERE a.OrgIDProv <> 'RX3' AND a.OrgIDProv <> 'RXV' -- Ignore TEWV / GMMS data as this is selected separately below
GROUP BY a.RecordNumber, a.UniqServReqID, a.Person_ID, a.UniqMonthID -- Get activites data in the format of one row per person per month, like those in #Referrals, using SUM and MAX in the Select

----- Insert SNOMED activities (repeat above but tweaked for TEWV & GMMH to instead idenfity activities to IPS services via SNOMED codes, as ServTeamTypeRefToMH = 'D05' is not available)

IF OBJECT_ID ('tempdb..#ActivitiesSNOMED') IS NOT NULL
DROP TABLE #ActivitiesSNOMED

SELECT
	a.RecordNumber,
	a.UniqMonthID,
	a.Person_ID,
	a.UniqServReqID,
	ROW_NUMBER()OVER(PARTITION BY a.Person_ID, a.UniqServReqID ORDER BY a.Der_ContactDate ASC) AS AccessFlag, -- Use row number to order contacts (as we don't have Der_FacetoFaceContact) - will be turned into an access flag in the master where AccessFlag = 1 (first contact)
	ROW_NUMBER()OVER(PARTITION BY a.Person_ID, a.UniqServReqID, a.Der_FY ORDER BY a.Der_ContactDate ASC) AS FYAccessFlag, -- Use row number to order contacts (as we don't have Der_FacetoFaceContact) - will be turned into an access flag in the master where AccessFlag = 1
	a.Der_ContactDate,
	a.ConsMediumUsed,
	i.Der_SNoMEDProcCode,
	a.Der_DirectContactOrder
INTO #ActivitiesSNOMED
FROM [NHSE_Sandbox_MentalHealth].dbo.PreProc_Activity a -- Select activities info from PreProc Activity table...
INNER JOIN [NHSE_Sandbox_MentalHealth].dbo.PreProc_Interventions i ON a.RecordNumber = i.RecordNumber AND a.UniqCareContID = i.UniqCareContID AND i.Der_SNoMEDProcCode IN ('1082621000000104', '772822000')
WHERE a.OrgIDProv IN ('RX3', 'RXV') -- ... only for IPS activities at TEWV using SNoMED code
AND a.Der_DirectContactOrder IS NOT NULL -- and only bring in direct contacts that are F2F, video, telephone or other

INSERT INTO #Activities -- Insert SNOMED activities info below into #Activities table created above

SELECT
	a.RecordNumber,
	a.UniqMonthID,
	a.Person_ID,
	a.UniqServReqID,
	1 AS ContactOrder, -- All TEWV referrals have accessed IPS as we only know about those that have a contact (so all will be in caseload, just give a value of 1 so they are counted in the caseload)
	MIN(a.AccessFlag) AS AccessFlag, -- As we don't have Der_DirectContactOrder, identify first contact as access flag
	MIN(a.FYAccessFlag) AS FYAccessFlag, -- As we don't have Der_FYDirectContactOrder, identify first contact of the financial year as FY access flag
	MIN(a.Der_ContactDate) AS AccessDate, -- For now, all contacts have their date listed - will be turned into the access date in the master where AccessFlag = 1 
	SUM(CASE WHEN (a.Der_SNoMEDProcCode IS NOT NULL AND a.ConsMediumUsed IN ('01', '02', '03', '04', '98') AND a.UniqMonthID <= '1458') OR (a.Der_SNoMEDProcCode IS NOT NULL AND a.ConsMediumUsed IN ('01', '02', '04', '98', '11')  AND a.UniqMonthID > '1458') THEN 1 ELSE 0 END) AS TotalContacts,
	SUM(CASE WHEN a.Der_SNoMEDProcCode IS NOT NULL AND a.ConsMediumUsed = '01' THEN 1 ELSE 0 END) AS TotalContactsF2F, -- Use presence of SNOMED code instead
	SUM(CASE WHEN a.Der_SNoMEDProcCode IS NOT NULL AND a.ConsMediumUsed IN ('02', '04') THEN 1 ELSE 0 END) AS TotalContactsTelephone,
	SUM(CASE WHEN (a.Der_SNoMEDProcCode IS NOT NULL AND a.ConsMediumUsed = '03' AND a.UniqMonthID <= '1458') OR (a.Der_SNoMEDProcCode IS NOT NULL AND a.ConsMediumUsed = '11' AND a.UniqMonthID > '1457')THEN 1 ELSE 0 END) AS TotalContactsVideo,
	SUM(CASE WHEN a.Der_SNoMEDProcCode IS NOT NULL AND a.ConsMediumUsed = '98' THEN 1 ELSE 0 END) AS TotalContactsOther -- Calculate total contacts per referral per month that were 'other' medium
FROM #ActivitiesSNOMED a
GROUP BY a.RecordNumber, a.UniqServReqID, a.Person_ID, a.UniqMonthID

---------- Create activiites per referral temp table

IF OBJECT_ID ('tempdb..#ActPerRef') IS NOT NULL
DROP TABLE #ActPerRef

SELECT
	a.Person_ID,
	a.UniqServReqID,
	SUM(CASE WHEN a.Der_DirectContactOrder IS NOT NULL THEN 1 ELSE 0 END) AS TotalContactsPerReferral, -- Same process as above (calculate total contacts) but group by means it's for each referal rather than referral / month
	MAX(CASE WHEN a.Der_DirectContactOrder = '1' THEN a.Der_ContactDate ELSE NULL END) AS AccessDatePerReferal -- Same process as above (obtain date for first contact) but group by means it's for each referal rather than referral / month
INTO #ActPerRef
FROM [NHSE_Sandbox_MentalHealth].dbo.PreProc_Activity a -- Select activity info from PreProc Activity table
INNER JOIN #Referrals r ON a.RecordNumber = r.RecordNumber AND a.UniqServReqID = r.UniqServReqID -- Only select activity info for referrals in the referral table
WHERE a.OrgIDProv <> 'RX3' AND a.OrgIDProv <> 'RXV' -- Ignore TEWV provider as data is selected separately below
GROUP BY a.UniqServReqID, a.Person_ID -- Group by ONLY referral, ignoring month

----- Insert SNOMED activities per referral (repeat above but tweaked for TEWV & GMMH to instead idenfity activities to IPS services via SNOMED codes, as ServTeamTypeRefToMH = 'D05' is not available)

INSERT INTO #ActPerRef

SELECT
	i.Person_ID,
	i.UniqServReqID,
	SUM(CASE WHEN i.Der_SNoMEDProcCode IS NOT NULL THEN 1 ELSE 0 END) AS TotalContactsPerReferral, -- Calcuate total contacts for each referral
	MIN(i.Der_ContactDate) AS AccessDatePerReferral -- Find the date of the first contact for each referral
FROM [NHSE_Sandbox_MentalHealth].dbo.PreProc_Interventions i
INNER JOIN (SELECT DISTINCT r.Person_ID, r.UniqServReqID FROM [NHSE_Sandbox_MentalHealth].dbo.PreProc_Referral r GROUP BY r.Person_ID, r.UniqServReqID) r ON i.Person_ID = r.Person_ID AND i.UniqServReqID = r.UniqServReqID -- Select distinct referrals at TEWV who have IPS activities
LEFT JOIN [NHSE_Sandbox_MentalHealth].dbo.PreProc_Activity a ON a.RecordNumber = i.RecordNumber AND a.UniqCareContID = i.UniqCareContID
WHERE i.Der_SNoMEDProcCode IN ('1082621000000104', '772822000') AND i.OrgIDProv IN ('RX3', 'RXV')
AND a.Der_DirectContactOrder IS NOT NULL -- and only bring in direct contacts that are F2F, video, telephone or other
GROUP BY i.UniqServReqID, i.Person_ID

---------- Create outcomes temp table ----------

IF OBJECT_ID ('tempdb..#OutcomesStep1') IS NOT NULL
DROP TABLE #OutcomesStep1

SELECT
	e1.RecordNumber,
	e1.EmployStatus, -- Employment status
	e1.WeekHoursWorked, -- Weekly hours worked
	e1.EmployStatusStartDate AS EmployStatusStartDate, -- Start date of employment field (new)
	ROW_NUMBER()OVER(PARTITION BY e1.RecordNumber ORDER BY e1.EmployStatusRecDate ASC) AS FirstRecording, -- To highlight first status if there are more than 1 in month, for employed at referal
	ROW_NUMBER()OVER(PARTITION BY e1.RecordNumber ORDER BY e1.EmployStatusRecDate DESC) AS LastRecording -- To highlight last status if there are more than 1 in a month, for employed at discharge
INTO #OutcomesStep1
FROM [NHSE_MHSDS].[dbo].[MHS004EmpStatus] e1 -- Select employment status and weekly hours worked from e1 - this is processed data
INNER JOIN #Referrals r ON e1.RecordNumber = r.RecordNumber AND e1.UniqMonthID = r.UniqMonthID -- Only select employment information for referrals in the #Referrals table
INNER JOIN [NHSE_MH_PrePublication].[Test].[MHSDS_SubmissionFlags] s ON e1.NHSEUniqSubmissionID = s.NHSEUniqSubmissionID AND s.Der_IsLatest = 'Y' -- Identify if it is the latest data or if there have been any new submissions (which are included in the Pre Publication tables)

INSERT INTO #OutcomesStep1

SELECT
	e2.RecordNumber,
	e2.EmployStatus,
	e2.WeekHoursWorked,
	e2.EmployStatusStartDate AS EmployStatusStartDate,
	ROW_NUMBER()OVER(PARTITION BY e2.RecordNumber ORDER BY e2.EmployStatusRecDate ASC) AS FirstRecording,
	ROW_NUMBER()OVER(PARTITION BY e2.RecordNumber ORDER BY e2.EmployStatusRecDate DESC) AS LastRecording
FROM [NHSE_MH_PrePublication].[test].[MHS004EmpStatus] e2 -- Repeat above (selecting employment status and weekly hours worked) but using e2 - this is unprocessed data
INNER JOIN #Referrals r ON e2.RecordNumber = r.RecordNumber AND e2.UniqMonthID = r.UniqMonthID
INNER JOIN [NHSE_MH_PrePublication].[Test].[MHSDS_SubmissionFlags] s ON e2.NHSEUniqSubmissionID = s.NHSEUniqSubmissionID AND s.Der_IsLatest = 'Y' -- identify that this data is a new submission or submission

IF OBJECT_ID ('tempdb..#Outcomes') IS NOT NULL
DROP TABLE #Outcomes

SELECT
	o.RecordNumber,
	MAX(CASE WHEN o.FirstRecording = 1 THEN o.EmployStatus ELSE NULL END) AS EmployStatusFirst, -- Select the first employment status (used for employed at referral)
	MAX(CASE WHEN o.LastRecording = 1 THEN o.EmployStatus ELSE NULL END) AS EmployStatusLast, -- Select the last employment status (used for employed at discharge)
	MAX(CASE WHEN o.LastRecording = 1 THEN o.WeekHoursWorked ELSE NULL END) AS WeekHoursWorkedLast, -- Select the last week hours worked (used for hours worked at discharge)
	MAX(CASE WHEN o.LastRecording = 1 THEN o.EmployStatusStartDate ELSE NULL END) AS EmployStatusStartDateLast -- Select the start date of the last employment status (used only in proportion missing - for now)
INTO #Outcomes
FROM #OutcomesStep1 o
GROUP BY o.RecordNumber

---------- Join temp tables in a Master table ----------

IF OBJECT_ID ('tempdb..#Master') IS NOT NULL
DROP TABLE #Master

SELECT	
	r.RecordNumber,
	r.Person_ID,
	r.UniqServReqID,
	r.UniqMonthID,
	RIGHT(p.UniqCareProfTeamID,(LEN(p.UniqCareProfTeamID) - LEN(p.OrgIDProv))) AS  CareProfTeamLocalId, -- Obtain team ID (not Uniq Team ID)
	r.OrgIDProv,
	r.ProvName,
	r.OrgIDCCGRes,
	r.CCGName,
	r.STP_Code,
	r.STP_Name,
	r.Region_Code,
	r.Region_Name,
	r.ReportingPeriodStart,
	r.ReportingPeriodEnd,
	r.GenderCat, 
	r.AgeCat, 
	r.EthnicityCat, 
	r.SourceCat, 
	r.DeprivationQuintile, 
	r.ReferralRequestReceivedDate, 
	r.ServDischDate,
	a.ContactOrder,
	(CASE WHEN a.AccessFlag = 1 THEN 1 ELSE 0 END) AS AccessFlag, -- Ensure AccessFlag is using the first ever contact, for TEWV
	(CASE WHEN a.FYAccessFlag = 1 THEN 1 ELSE 0 END) AS FYAccessFlag, -- Ensure FYAccessFlag is using the first contact in the FY, for TEWV 
	(CASE WHEN a.AccessFlag = 1 THEN a.AccessDate ELSE NULL END) AS AccessDate, -- Ensure AccessDate is only recorded for first ever contact, for TEWV
	ap.AccessDatePerReferal,
	ISNULL (a.TotalContacts, 0) AS TotalContacts, -- Convert any NULLs to 0 to enable calculations in the next #Agg table
	ISNULL (ap.TotalContactsPerReferral, 0) AS TotalContactsPerReferral,
	ISNULL (a.TotalContactsF2F, 0) AS TotalContactsF2F,
	ISNULL (a.TotalContactsTelephone, 0) AS TotalContactsTelephone, 
	ISNULL (a.TotalContactsVideo, 0) AS TotalContactsVideo, 
	ISNULL (a.TotalContactsOther, 0) AS TotalContactsOther,
	ISNULL (o.EmployStatusFirst, 0) AS EmployStatusFirst,
	ISNULL (o.EmployStatusLast, 0) AS EmployStatusLast,
	ISNULL (o.WeekHoursWorkedLast, 0) AS WeekHoursWorkedLast,
	o.EmployStatusStartDateLast,
	o.EmployStatusLast AS EmployStatusLastWithNulls, -- Leave a version of employment status where NULLs have not been converted to 0s to allow the employment status data quality measure calculated below to use assign 'Missing/Invalid' to NULL values
	o.WeekHoursWorkedLast AS WeekHoursWorkedLastWithNulls, -- Leave a version of weekly hours worked where NULLS have not been converted for a similar data quality measure
	o.EmployStatusStartDateLast AS EmployStatusStartDateLastWithNulls -- Leave a version where NULLS have not been converted for a similar data quality measure
INTO #Master
FROM #Referrals r --- Select referrals (r) and join all relevant columns a, o and ap temp tables constructed above
LEFT JOIN #Activities a ON a.RecordNumber = r.RecordNumber AND a.UniqServReqID = r.UniqServReqID -- Activites per referral per month combinaton
LEFT JOIN #Outcomes o ON o.RecordNumber = r.RecordNumber -- Outcomes per person per month
LEFT JOIN #ActPerRef ap ON ap.Person_ID = r.Person_ID AND ap.UniqServReqID = r.UniqServReqID -- Activities per referral per person
LEFT JOIN [NHSE_Sandbox_MentalHealth].[dbo].[PreProc_Referral] p ON p.RecordNumber = r.RecordNumber AND p.UniqServReqID = r.UniqServReqID -- Add in local team identifier for each referral
 
---------- Create measures ----------

IF OBJECT_ID ('tempdb..#Agg') IS NOT NULL
DROP TABLE #Agg

SELECT 
	r.UniqMonthID, -- The fields used in the group by
	r.CareProfTeamLocalId,
	r.OrgIDProv,
	r.ProvName,
	r.OrgIDCCGRes,
	r.CCGName,
	r.STP_Code,
	r.STP_Name,
	r.Region_Code,
	r.Region_Name,
	r.ReportingPeriodEnd,
	r.GenderCat, 
	r.AgeCat, 
	r.EthnicityCat, 
	r.SourceCat, 
	r.DeprivationQuintile, 

-- Referral received in the month (1=YES, new referral this month)
SUM(CASE WHEN r.ReferralRequestReceivedDate BETWEEN r.ReportingPeriodStart AND r.ReportingPeriodEnd THEN 1 ELSE 0 END) AS NewReferrals, 

-- Referral discharged in the month (1=YES, discharged this month)
SUM(CASE WHEN r.ServDischDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedReferrals,

-- An open referral not yet discharged (1=YES, an open referral this month) 
SUM(CASE WHEN r.ServDischDate IS NULL THEN 1 ELSE 0 END) AS OpenReferrals, 

-- A referral in the caseload - an open referral not yet discharged with at least 1 direct contact (1=YES, in the caseload this month) 
SUM(CASE WHEN r.ServDischDate IS NULL AND r.AccessDatePerReferal IS NOT NULL AND r.AccessDatePerReferal <= r.ReportingPeriodEnd THEN 1 ELSE 0 END) AS Caseload,

-- Time in days from referral / access date to discharge date
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND DATEDIFF(DD, r.ReferralRequestReceivedDate, r.ServDischDate) > 180 THEN 1 ELSE 0 END) AS LengthOfReferralOver180, 
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND DATEDIFF(DD, r.ReferralRequestReceivedDate, r.ServDischDate) BETWEEN 91 AND 180 THEN 1 ELSE 0 END) AS LengthOfReferral91To180,
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND DATEDIFF(DD, r.ReferralRequestReceivedDate, r.ServDischDate) BETWEEN 0 AND 90 THEN 1 ELSE 0 END) AS LengthOfReferral0To90,
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND DATEDIFF(DD, r.AccessDatePerReferal, r.ServDischDate) > 180 THEN 1 ELSE 0 END) AS TimeInCaseloadOver180,
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND DATEDIFF(DD, r.AccessDatePerReferal, r.ServDischDate) BETWEEN 91 AND 180 THEN 1 ELSE 0 END) AS TimeInCaseload91To180,
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND DATEDIFF(DD, r.AccessDatePerReferal, r.ServDischDate) BETWEEN 0 AND 90 THEN 1 ELSE 0 END) AS TimeInCaseload0To90,
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND r.AccessDatePerReferal IS NOT NULL THEN 1 ELSE 0 END) AS ClosedReferralsWhoAccessedDenom,

-- Referral accessed care for the first time ever in the month, 1st ever contact (1=YES, new access this month)
SUM(r.AccessFlag) AS AccessedFirstTimeEver, 
SUM(r.FYAccessFlag) AS AccessedInFinancialYear, -- or first contact of the financial year

-- Time in days between referral and access date
SUM(CASE WHEN r.AccessFlag = '1' AND DATEDIFF(DD, r.ReferralRequestReceivedDate, r.AccessDate) <= 7 THEN 1 ELSE 0 END) AS SeenIn7,
SUM(CASE WHEN r.AccessFlag = '1' AND DATEDIFF(DD, r.ReferralRequestReceivedDate, r.AccessDate) BETWEEN 8 AND 30 THEN 1 ELSE 0 END) AS SeenIn8To30, 
SUM(CASE WHEN r.AccessFlag = '1' AND DATEDIFF(DD, r.ReferralRequestReceivedDate, r.AccessDate) > 30 THEN 1 ELSE 0 END) AS SeenInOver30,

-- Total contacts within the month, split by contact medium
SUM(r.TotalContacts) AS TotalContacts, 
SUM(r.TotalContactsF2F) AS TotalContactsF2F,
SUM(r.TotalContactsTelephone) AS TotalContactsTelephone,
SUM(r.TotalContactsVideo) AS TotalContactsVideo,
SUM(r.TotalContactsOther) AS TotalContactsOther,

-- Employment status at time of discharge
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND r.EmployStatusLast = '01' THEN 1 ELSE 0 END) AS EmployedAtDischarge, 
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND r.EmployStatusLast IN ('02', '03', '04', '05', '06', '07', '08') THEN 1 ELSE 0 END) AS NotEmployedAtDischarge, 
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND r.EmployStatusLast IN ('0', 'ZZ') THEN 1 ELSE 0 END) AS UnknownEmployedAtDischarge, 

-- Hours worked by those employed at discharge
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND r.EmployStatusLast = '01' AND r.WeekHoursWorkedLast = '01' THEN 1 ELSE 0 END) AS EmployedAtDischarge30Hours, 
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND r.EmployStatusLast = '01' AND r.WeekHoursWorkedLast = '02' THEN 1 ELSE 0 END) AS EmployedAtDischarge16to29Hours,
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND r.EmployStatusLast = '01' AND r.WeekHoursWorkedLast IN ('03','04') THEN 1 ELSE 0 END) AS EmployedAtDischarge15OrLess,
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND r.EmployStatusLast = '01' AND r.WeekHoursWorkedLast NOT IN ('01', '02', '03','04') THEN 1 ELSE 0 END) AS EmployedAtDischargeHoursMissing,

-- Length of time using service (since access) by those employed at discharge
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND r.EmployStatusLast = '01' AND DATEDIFF(DD, r.AccessDatePerReferal, r.ServDischDate) > 180 THEN 1 ELSE 0 END) AS EmployedAtDischargeSeenForOver180, 
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND r.EmployStatusLast = '01' AND DATEDIFF(DD, r.AccessDatePerReferal, r.ServDischDate) BETWEEN 91 AND 180 THEN 1 ELSE 0 END) AS EmployedAtDischargeSeenFor91To180,
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND r.EmployStatusLast = '01' AND DATEDIFF(DD, r.AccessDatePerReferal, r.ServDischDate) BETWEEN 0 AND 90 THEN 1 ELSE 0 END) AS EmployedAtDischargeSeenFor0To90,
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND r.EmployStatusLast = '01' AND r.AccessDatePerReferal IS NULL THEN 1 ELSE 0 END) AS EmployedAtDischargeNeverSeen,

-- Number of contacts whilst using the service by those employed at discharge
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND r.EmployStatusLast = '01' AND r.TotalContactsPerReferral >10 THEN 1 ELSE 0 END) AS EmployedAtDischargeSeenOver10Times, 
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND r.EmployStatusLast = '01' AND r.TotalContactsPerReferral BETWEEN 6 AND 10 THEN 1 ELSE 0 END) AS EmployedAtDischargeSeen6To10Times,
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND r.EmployStatusLast = '01' AND r.TotalContactsPerReferral BETWEEN 1 AND 5 THEN 1 ELSE 0 END) AS EmployedAtDischargeSeen1To5Times,
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND r.EmployStatusLast = '01' AND r.TotalContactsPerReferral = 0 THEN 1 ELSE 0 END) AS EmployedAtDischargeSeen0Times,

-- Employment status at time of referral
SUM(CASE WHEN r.ReferralRequestReceivedDate BETWEEN r.ReportingPeriodStart AND r.ReportingPeriodEnd AND r.EmployStatusFirst = '01' THEN 1 ELSE 0 END) AS EmployedAtReferral, 
SUM(CASE WHEN r.ReferralRequestReceivedDate BETWEEN r.ReportingPeriodStart AND r.ReportingPeriodEnd AND r.EmployStatusFirst IN ('02', '03', '04', '05', '06', '07', '08') THEN 1 ELSE 0 END) AS NotEmployedAtReferral,
SUM(CASE WHEN r.ReferralRequestReceivedDate BETWEEN r.ReportingPeriodStart AND r.ReportingPeriodEnd AND r.EmployStatusFirst IN ('0', 'ZZ') THEN 1 ELSE 0 END) AS UnknownEmployedAtReferral,

-- Total missing / not missing for selected fields - for data quality pie charts
SUM(CASE WHEN r.SourceCat = 'Missing/Invalid' THEN 1 ELSE 0 END) AS SourceCatMissing, 
SUM(CASE WHEN r.SourceCat <> 'Missing/Invalid' THEN 1 ELSE 0 END) AS SourceCatNotMissing,
SUM(CASE WHEN r.AgeCat = 'Missing/Invalid' THEN 1 ELSE 0 END) AS AgeCatMissing,
SUM(CASE WHEN r.AgeCat <> 'Missing/Invalid' THEN 1 ELSE 0 END) AS AgeCatNotMissing,
SUM(CASE WHEN r.EthnicityCat = 'Missing/Invalid' THEN 1 ELSE 0 END) AS EthnicityCatMissing,
SUM(CASE WHEN r.EthnicityCat <> 'Missing/Invalid' THEN 1 ELSE 0 END) AS EthnicityCatNotMissing,
SUM(CASE WHEN r.GenderCat = 'Missing/Invalid' THEN 1 ELSE 0 END) AS GenderCatMissing,
SUM(CASE WHEN r.GenderCat <> 'Missing/Invalid' THEN 1 ELSE 0 END) AS GenderCatNotMissing,
SUM(CASE WHEN r.DeprivationQuintile = 'Missing/Invalid' THEN 1 ELSE 0 END) AS DeprivationQuintileMissing,
SUM(CASE WHEN r.DeprivationQuintile <> 'Missing/Invalid' THEN 1 ELSE 0 END) AS DeprivationQuintileNotMissing,
SUM(CASE WHEN r.EmployStatusLastWithNulls IS NULL OR r.EmployStatusLastWithNulls = 'ZZ' THEN 1 ELSE 0 END) AS EmployStatusMissing,
SUM(CASE WHEN r.EmployStatusLastWithNulls IS NOT NULL AND r.EmployStatusLastWithNulls <> 'ZZ' THEN 1 ELSE 0 END) AS EmployStatusNotMissing,
COUNT(*) AS AllDemom, -- An all open or closed referrals denom for data quality pie charts (except weekly hours worked) 
SUM(CASE WHEN (r.WeekHoursWorkedLastWithNulls IS NULL OR r.WeekHoursWorkedLastWithNulls IN ('97', '99')) AND r.EmployStatusLast = '01' THEN 1 ELSE 0 END) AS WeekHoursWorkedMissing,
SUM(CASE WHEN r.WeekHoursWorkedLastWithNulls IS NOT NULL AND r.WeekHoursWorkedLastWithNulls NOT IN ('97', '99') AND r.EmployStatusLast = '01' THEN 1 ELSE 0 END) AS WeekHoursWorkedNotMissing,
SUM(CASE WHEN r.EmployStatusLast = '01' THEN 1 ELSE 0 END) AS AllEmpDenom, -- An all employed denom for weekly hours worked and/or start time pie chart
SUM(CASE WHEN r.EmployStatusStartDateLastWithNulls IS NULL AND r.EmployStatusLast = '01' THEN 1 ELSE 0 END) AS EmployStatusStartDateLastMissing,
SUM(CASE WHEN r.EmployStatusStartDateLastWithNulls IS NOT NULL AND r.EmployStatusLast = '01' THEN 1 ELSE 0 END) AS EmployStatusStartDateLastNotMissing

INTO #Agg
FROM #Master r
GROUP BY r.UniqMonthID, r.ReportingPeriodEnd, r.CareProfTeamLocalId, r.OrgIDProv, r.ProvName, r.OrgIDCCGRes, r.CCGName, r.STP_Code, r.STP_Name, r.Region_Code, r.Region_Name, r.GenderCat, r.AgeCat, r.EthnicityCat, r.SourceCat, r.DeprivationQuintile -- Measures calculated for every combination of referral, month, geography, gender, age, ethnicity, source of referral and deprivation quintile

---------- Final list of measures ----------

IF OBJECT_ID ('tempdb..#AggFinal') IS NOT NULL
DROP TABLE #AggFinal

SELECT  
	a.UniqMonthID,
	a.CareProfTeamLocalId,
	a.OrgIDProv,
	a.ProvName,
	a.OrgIDCCGRes,
	a.CCGName,
	a.STP_Code,
	a.STP_Name,
	a.Region_Code,
	a.Region_Name,
	a.ReportingPeriodEnd,
	a.GenderCat, 
	a.AgeCat, 
	a.EthnicityCat, 
	a.SourceCat, 
	a.DeprivationQuintile, 
	a.NewReferrals, 
	a.ClosedReferrals, 
	a.OpenReferrals,
	a.Caseload,
	a.LengthOfReferral0To90, 
	a.LengthOfReferral91To180,
	a.LengthOfReferralOver180,
	a.TimeInCaseload0To90,
	a.TimeInCaseload91To180,
	a.TimeInCaseloadOver180,
	a.AccessedFirstTimeEver,
	a.AccessedInFinancialYear,
	a.SeenIn7,
	a.SeenIn8To30, 
	a.SeenInOver30,
	a.TotalContacts, 
	a.TotalContactsF2F,
	a.TotalContactsTelephone,
	a.TotalContactsVideo,
	a.TotalContactsOther,
	a.EmployedAtDischarge,
	a.NotEmployedAtDischarge,
	a.UnknownEmployedAtDischarge,
	a.EmployedAtDischarge30Hours, 
	a.EmployedAtDischarge16to29Hours,
	a.EmployedAtDischarge15OrLess,
	a.EmployedAtDischargeHoursMissing,
	a.EmployedAtDischargeSeenForOver180,
	a.EmployedAtDischargeSeenFor91To180,
	a.EmployedAtDischargeSeenFor0To90,
	a.EmployedAtDischargeNeverSeen,
	a.EmployedAtDischargeSeenOver10Times, 
	a.EmployedAtDischargeSeen6To10Times,
	a.EmployedAtDischargeSeen1To5Times,
	a.EmployedAtDischargeSeen0Times,
	a.EmployedAtReferral,
	a.NotEmployedAtReferral,
	a.UnknownEmployedAtReferral,
	a.SourceCatMissing,
	a.SourceCatNotMissing,
	a.AgeCatMissing,
	a.AgeCatNotMissing,
	a.EthnicityCatMissing,
	a.EthnicityCatNotMissing,
	a.GenderCatMissing,
	a.GenderCatNotMissing,
	a.DeprivationQuintileMissing,
	a.DeprivationQuintileNotMissing,
	a.EmployStatusMissing,
	a.EmployStatusNotMissing,
	a.WeekHoursWorkedMissing,
	a.WeekHoursWorkedNotMissing,
	a.EmployStatusStartDateLastMissing,
	a.EmployStatusStartDateLastNotMissing,
	a.AllDemom, -- Creates 4 denominators that are needed to calculate proportions in Tableau
	a.AllEmpDenom, 
	a.ClosedReferralsWhoAccessedDenom,
	a.OpenReferrals AS OpenReferralsDenom, -- Create duplicates for 6 measures that are needed as denominators to calculate proportions in Tableau
	a.AccessedFirstTimeEver AS AccessedFirstTimeEverDenom,
	a.TotalContacts AS TotalContactsDenom,
	a.ClosedReferrals AS ClosedReferralsDenom,
	a.NewReferrals AS NewReferralsDenom,
	a.EmployedAtDischarge AS EmployedAtDischargeDenom
INTO #AggFinal
FROM #Agg a

---------- Pivot final table into long format and refresh 'Dashboard_IPS_rebuild'

DROP TABLE NHSE_Sandbox_MentalHealth.dbo.Dashboard_IPS_rebuild
 
SELECT 
	a.UniqMonthID,
	a.CareProfTeamLocalId,
	a.OrgIDProv,
	a.ProvName,
	a.OrgIDCCGRes,
	a.CCGName,
	a.STP_Code,
	a.STP_Name,
	a.Region_Code,
	a.Region_Name,
	a.ReportingPeriodEnd,
	a.GenderCat, 
	a.AgeCat, 
	a.EthnicityCat, 
	a.SourceCat, 
	a.DeprivationQuintile, 
	MeasureName, -- MeasureName now includes all measures calculated above / included in the unpivot below - there will be a row for each measure, for each of the fields we grouped by above from the UNPIVOT [month / demography (age, gender, deprivation quintile, ethnicity) & source of referral / Team ID (mapped to provider, CCG, STP and region)]
	MeasureValue, -- MeasureValue will change depending on the MeasureName
	CASE WHEN MeasureName IN ('SourceCatMissing', 'SourceCatNotMissing', 'AgeCatMissing', 'AgeCatNotMissing', 'EthnicityCatMissing', 'EthnicityCatNotMissing', 'GenderCatMissing', 'GenderCatNotMissing', 'DeprivationQuintileMissing', 'DeprivationQuintileNotMissing', 'EmployStatusMissing', 'EmployStatusNotMissing') THEN a.AllDemom
		WHEN MeasureName IN ('WeekHoursWorkedMissing', 'WeekHoursWorkedNotMissing', 'EmployStatusStartDateLastMissing', 'EmployStatusStartDateLastNotMissing') THEN AllEmpDenom
		WHEN MeasureName = 'Caseload' THEN OpenReferralsDenom
		WHEN MeasureName IN ('SeenIn7', 'SeenIn8To30', 'SeenInOver30') THEN AccessedFirstTimeEverDenom
		WHEN MeasureName IN ('TotalContactsF2F', 'TotalContactsTelephone', 'TotalContactsVideo', 'TotalContactsOther') THEN a.TotalContactsDenom
		WHEN MeasureName IN ('EmployedAtDischarge', 'NotEmployedAtDischarge', 'UnknownEmployedAtDischarge', 'LengthOfReferralOver180', 'LengthOfReferral91To180', 'LengthOfReferral0To90') THEN a.ClosedReferralsDenom
		WHEN MeasureName IN ('TimeInCaseloadOver180', 'TimeInCaseload91To180', 'TimeInCaseload0To90') THEN a.ClosedReferralsWhoAccessedDenom
		WHEN MeasureName IN ('EmployedAtDischarge30Hours', 'EmployedAtDischarge16to29Hours', 'EmployedAtDischarge15OrLess', 'EmployedAtDischargeHoursMissing', 'EmployedAtDischargeSeenForOver180', 'EmployedAtDischargeSeenFor91To180', 'EmployedAtDischargeSeenFor0To90', 'EmployedAtDischargeNeverSeen', 'EmployedAtDischargeSeenOver10Times', 'EmployedAtDischargeSeen6To10Times', 'EmployedAtDischargeSeen1To5Times', 'EmployedAtDischargeSeen0Times') THEN a.EmployedAtDischargeDenom
		WHEN MeasureName IN ('EmployedAtReferral', 'NotEmployedAtReferral', 'UnknownEmployedAtReferral') THEN a.NewReferralsDenom
		ELSE NULL END AS Denominator -- The relevant denominator (changes depending on the measure name) is provided alongside the measure value, and both are used to calculate proportions in Tableau

INTO NHSE_Sandbox_MentalHealth.dbo.Dashboard_IPS_rebuild
FROM #AggFinal a

UNPIVOT (MeasureValue FOR MeasureName IN ( -- Creating 2 new fields: MeasureName where the data items are the list of measures below, and MeasureValue
	a.NewReferrals, 
	a.ClosedReferrals, 
	a.OpenReferrals,
	a.Caseload,
	a.LengthOfReferralOver180, 
	a.LengthOfReferral91To180,
	a.LengthOfReferral0To90,
	a.TimeInCaseloadOver180,
	a.TimeInCaseload91To180,
	a.TimeInCaseload0To90,
	a.AccessedFirstTimeEver,
	a.AccessedInFinancialYear,
	a.SeenIn7,
	a.SeenIn8To30,
	a.SeenInOver30,
	a.TotalContacts, 
	a.TotalContactsF2F,
	a.TotalContactsTelephone,
	a.TotalContactsVideo,
	a.TotalContactsOther,
	a.EmployedAtDischarge,
	a.NotEmployedAtDischarge,
	a.UnknownEmployedAtDischarge,
	a.EmployedAtDischarge30Hours, 
	a.EmployedAtDischarge16to29Hours,
	a.EmployedAtDischarge15OrLess,
	a.EmployedAtDischargeHoursMissing,
	a.EmployedAtDischargeSeenForOver180,
	a.EmployedAtDischargeSeenFor91To180,
	a.EmployedAtDischargeSeenFor0To90,
	a.EmployedAtDischargeNeverSeen,
	a.EmployedAtDischargeSeenOver10Times, 
	a.EmployedAtDischargeSeen6To10Times,
	a.EmployedAtDischargeSeen1To5Times,
	a.EmployedAtDischargeSeen0Times,
	a.EmployedAtReferral,
	a.NotEmployedAtReferral,
	a.UnknownEmployedAtReferral,
	a.SourceCatMissing,
	a.SourceCatNotMissing,
	a.AgeCatMissing,
	a.AgeCatNotMissing,
	a.EthnicityCatMissing,
	a.EthnicityCatNotMissing,
	a.GenderCatMissing,
	a.GenderCatNotMissing,
	a.DeprivationQuintileMissing,
	a.DeprivationQuintileNotMissing,
	a.EmployStatusMissing,
	a.EmployStatusNotMissing,
	a.WeekHoursWorkedMissing,
	a.WeekHoursWorkedNotMissing,
	a.EmployStatusStartDateLastMissing, 
	a.EmployStatusStartDateLastNotMissing)) a
