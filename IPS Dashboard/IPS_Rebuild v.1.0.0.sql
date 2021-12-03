
---------- Set up steps - declare reporting period and financial year ----------

DECLARE @STARTRP INT
SET @STARTRP = 1417 -- 1417 = April 2018

DECLARE @ENDRP INT
SET @ENDRP = (SELECT UniqMonthID FROM [NHSE_Sandbox_MentalHealth].[dbo].[PreProc_Header] WHERE Der_MostRecentFlag = 'p') -- Der_MostRecentFlag = p (most recent month - primary)

DECLARE @FYSTART INT
SET @FYSTART = (SELECT MAX(UniqMonthID) FROM [NHSE_Sandbox_MentalHealth].[dbo].[PreProc_Header] WHERE Der_FYStart = 'Y') -- Der_FYStart = Y (first month of the financial year); MAX here is most recent April / FY start date

------------ Create temp tables / master ----------

---- Create referrals temp table

IF OBJECT_ID ('tempdb..#Referrals') IS NOT NULL
DROP TABLE #Referrals

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
		WHEN r.SourceOfReferralMH IN ('I1','I2','P1') THEN 'Secondary Health Care' 
		WHEN r.SourceOfReferralMH IN ('C1', 'C2', 'C3', 'D1', 'D2', 'E1', 'E2', 'E3', 'E4', 'E5', 'E6', 'F1', 'F2', 'F3', 'G1', 'G2', 'G3', 'G4', 'H1', 'H2', 'M1', 'M2', 'M3', 'M4', 'M5', 'M6', 'M7', 'N3') THEN 'Other' 
		ELSE 'Missing/Invalid' END AS SourceCat, -- Create/assign source of referral group
	CASE WHEN r.AgeServReferRecDate BETWEEN 16 AND 25 THEN '16to25' 
		WHEN r.AgeServReferRecDate BETWEEN 26 AND 35 THEN '26to35' 
		WHEN r.AgeServReferRecDate BETWEEN 36 AND 45 THEN '36to45' 
		WHEN r.AgeServReferRecDate BETWEEN 46 AND 55 THEN '46to55' 
		WHEN r.AgeServReferRecDate BETWEEN 56 AND 64 THEN '56to64' 
		WHEN r.AgeServReferRecDate < 16 OR r.AgeServReferRecDate > 64 THEN 'Other' 
		ELSE 'Missing/Invalid' END AS AgeCat, -- Create/assign age groups
	CASE WHEN r.EthnicCategory = 'A' THEN 'White British' 
		WHEN r.EthnicCategory IN ('B', 'C') THEN 'White Other' 
		WHEN r.EthnicCategory IN ('D', 'E', 'F', 'G') THEN 'Mixed' 
		WHEN r.EthnicCategory IN ('H', 'J', 'K', 'L') THEN 'Asian' 
		WHEN r.EthnicCategory IN ('M', 'N', 'P') THEN 'Black' 
		WHEN r.EthnicCategory IN ('R', 'S') THEN 'Other' 
		ELSE 'Missing/Invalid' END AS EthnicityCat, -- Create/assign ethnicity groups
	CASE WHEN r.Gender = '1' THEN 'Male' 
		WHEN r.Gender = '2' THEN 'Female' 
		WHEN r.Gender = '9' THEN 'Indeterminate' 
		ELSE 'Missing/Invalid' END AS GenderCat, -- Create/assign gender groups
	CASE WHEN d.IMD_Decile IN ('1', '2') THEN 'Quintile 1' 
		WHEN d.IMD_Decile IN ('3', '4') THEN 'Quintile 2' 
		WHEN d.IMD_Decile IN ('5', '6') THEN 'Quintile 3' 
		WHEN d.IMD_Decile IN ('7', '8') THEN 'Quintile 4' 
		WHEN d.IMD_Decile IN ('9', '10') THEN 'Quintile 5' 
		ELSE 'Missing/Invalid' END AS DeprivationQuintile, -- Create/assign deprition quintiles
	r.ServDischDate, 
	r.ReferralRequestReceivedDate, 
	r.ReportingPeriodEndDate AS ReportingPeriodEnd, 
	r.ReportingPeriodStartDate AS ReportingPeriodStart 
INTO #Referrals
FROM [NHSE_Sandbox_MentalHealth].[dbo].[PreProc_Referral] r -- Select referral info from r including referral received date and discharge date and referral demographics 
LEFT JOIN NHSE_Reference.dbo.tbl_Ref_ODS_Provider_Hierarchies o ON r.OrgIDProv = o.Organisation_Code -- Join to o to obtain organisation code for provider
LEFT JOIN NHSE_Reference.dbo.tbl_Ref_Other_ComCodeChanges cc ON r.OrgIDCCGRes = cc.Org_Code
LEFT JOIN NHSE_Reference.dbo.tbl_Ref_ODS_Commissioner_Hierarchies map ON COALESCE(cc.New_Code, r.OrgIDCCGRes) = map.Organisation_Code -- Join to map to obtain provider to CCG / STP / region mappings
LEFT JOIN [NHSE_Reference].[dbo].[tbl_Ref_Other_Deprivation_By_LSOA] d ON r.LSOA2011 = d.LSOA_Code AND d.Effective_Snapshot_Date = '2019-12-31' -- Join to d to obtain IMD decile from LSOA code of residence
WHERE r.ReferralRequestReceivedDate >= '2016-01-01' AND r.UniqMonthID BETWEEN @STARTRP AND @ENDRP AND r.ServTeamTypeRefToMH = 'D05' AND (r.LADistrictAuth lIKE 'E%' OR r.LADistrictAuth IS NULL) -- Select only referrals in England to IPS in the reporting period

---- Insert TEWV referrals (repeat above but tweaked for TEWV where ServTeamTypeRefToMH = 'D05' is not available)

IF OBJECT_ID ('tempdb..#TEWVIPS ') IS NOT NULL
DROP TABLE #TEWVIPS 

SELECT 
	a.RecordNumber, 
	a.UniqServReqID
INTO #TEWVIPS 
FROM [NHSE_Sandbox_MentalHealth].dbo.PreProc_Interventions a 
WHERE a.Der_SNoMEDProcCode IN ('1082621000000104', '772822000') AND a.OrgIDProv = 'RX3' 
GROUP BY a.RecordNumber, a.UniqServReqID

INSERT INTO #Referrals

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
		WHEN r.SourceOfReferralMH IN ('I1','I2','P1') THEN 'Secondary Health Care' 
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
		WHEN r.Gender = '9' THEN 'Indeterminate' 
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
INNER JOIN #TEWVIPS a ON a.RecordNumber = r.RecordNumber AND a.UniqServReqID = r.UniqServReqID -- Select referrals that have a contact related to IPS at TEWV (this means all referrals for TEWV are those that have accessed the service i.e. had a first contact)
WHERE r.ReferralRequestReceivedDate >= '2016-01-01' AND r.UniqMonthID BETWEEN @STARTRP AND @ENDRP AND (r.LADistrictAuth lIKE 'E%' OR r.LADistrictAuth IS NULL) -- Select all referrals for TEWV (as can't select those for IPS via ServTeamTypeToMH)
ORDER BY RecordNumber, UniqServReqID

---- Create activities temp table

IF OBJECT_ID ('tempdb..#Activities') IS NOT NULL
DROP TABLE #Activities

SELECT
	a.RecordNumber, 
	a.UniqMonthID,
	a.Person_ID,
	a.UniqServReqID,
	MAX(a.Der_DirectContactOrder) AS ContactOrder, 
	SUM(CASE WHEN a.Der_DirectContactOrder = '1' THEN 1 ELSE 0 END) AS AccessFlag, -- Assign 1st contact (where direct contact order = 1) as access flag
	SUM(CASE WHEN a.Der_FYDirectContactOrder = '1' THEN 1 ELSE 0 END) AS FYAccessFlag, -- Assign 1st contact (wherre direct contact order = 1) as access flag
	MAX(CASE WHEN a.Der_DirectContactOrder = '1' THEN a.Der_ContactDate ELSE NULL END) AS AccessDate, -- Obtain date for first contact
	SUM(CASE WHEN a.Der_DirectContactOrder IS NOT NULL THEN 1 ELSE 0 END) AS TotalContacts, -- Calculate total contacts per referral per month
	SUM(CASE WHEN a.Der_DirectContactOrder IS NOT NULL AND a.ConsMediumUsed = '01' THEN 1 ELSE 0 END) AS TotalContactsF2F, -- Calculate total contacts per referral per month that were face to face contacts
	SUM(CASE WHEN a.Der_DirectContactOrder IS NOT NULL AND a.ConsMediumUsed = '02' THEN 1 ELSE 0 END) AS TotalContactsTelephone, -- Calculate total contacts per referral per month that were via telephone
	SUM(CASE WHEN a.Der_DirectContactOrder IS NOT NULL AND a.ConsMediumUsed = '03' THEN 1 ELSE 0 END) AS TotalContactsVideo, -- Calculate total contacts per referral per month that were via video
	SUM(CASE WHEN a.Der_DirectContactOrder IS NOT NULL AND a.ConsMediumUsed IN ('04', '05', '06', '98') THEN 1 ELSE 0 END) AS TotalContactsOtherMedium -- Calculate total contacts per referral per month that were through a different medium
INTO #Activities
FROM [NHSE_Sandbox_MentalHealth].dbo.PreProc_Activity a -- Select access info from a
INNER JOIN #Referrals r ON a.RecordNumber = r.RecordNumber AND a.UniqServReqID = r.UniqServReqID -- Only select activity info for referrals in the referral table
WHERE a.OrgIDProv <> 'RX3'
GROUP BY a.RecordNumber, a.UniqServReqID, a.Person_ID, a.UniqMonthID

---- Add in TEWV activities (repeat above but tweaked for TEWV where ServTeamTypeRefToMH = 'D05' is not available)

IF OBJECT_ID ('tempdb..#ActivitiesTEWV') IS NOT NULL
DROP TABLE #ActivitiesTEWV

SELECT
	a.RecordNumber,
	a.UniqMonthID,
	a.Person_ID,
	a.UniqServReqID,
	ROW_NUMBER()OVER(PARTITION BY a.Person_ID, a.UniqServReqID ORDER BY a.Der_ContactDate ASC) AS AccessFlag, -- Use row number to order contacts (as we don't have Der_FacetoFaceContact) - will be turned into an access flag in the master where AccessFlag = 1
	ROW_NUMBER()OVER(PARTITION BY a.Person_ID, a.UniqServReqID, a.Der_FY ORDER BY a.Der_ContactDate ASC) AS FYAccessFlag, -- Use row number to order contacts (as we don't have Der_FacetoFaceContact) - will be turned into an access flag in the master where AccessFlag = 1
	a.Der_ContactDate,
	a.ConsMediumUsed,
	i.Der_SNoMEDProcCode,
	a.Der_DirectContactOrder
	INTO #ActivitiesTEWV
FROM [NHSE_Sandbox_MentalHealth].dbo.PreProc_Activity a
INNER JOIN [NHSE_Sandbox_MentalHealth].dbo.PreProc_Interventions i ON a.RecordNumber = i.RecordNumber AND a.UniqCareContID = i.UniqCareContID AND i.Der_SNoMEDProcCode IN ('1082621000000104', '772822000')
WHERE a.OrgIDProv = 'RX3' -- Only select contacts to IPS at TEWV using SNoMED code

INSERT INTO #Activities

SELECT
	a.RecordNumber,
	a.UniqMonthID,
	a.Person_ID,
	a.UniqServReqID,
	NULL AS ContactOrder, -- All TEWV referrals have accessed as we only know about those that have a contact
	MIN(a.AccessFlag) AS AccessFlag, -- Use row number to order contacts (as we don't have Der_FacetoFaceContact) - will be turned into an access flag in the master where AccessFlag = 1
	MIN(a.FYAccessFlag) AS FYAccessFlag, -- Use row number to order contacts (as we don't have Der_FacetoFaceContact) - will be turned into an access flag in the master where AccessFlag = 1
	MIN(a.Der_ContactDate) AS AccessDate, -- For now, all contacts and their dates listed - will be turned into the access date in the master where AccessFlag = 1
	SUM(CASE WHEN a.Der_SNoMEDProcCode IS NOT NULL THEN 1 ELSE 0 END) AS TotalContacts, -- Calculate total contacts per referral per month (when a SNoMed code is used this is a contact)
	SUM(CASE WHEN a.Der_SNoMEDProcCode IS NOT NULL AND a.ConsMediumUsed = '01' THEN 1 ELSE 0 END) AS TotalContactsF2F, -- Use presence of SNOMED code instead
	SUM(CASE WHEN a.Der_SNoMEDProcCode IS NOT NULL AND a.ConsMediumUsed = '02' THEN 1 ELSE 0 END) AS TotalContactsTelephone,
	SUM(CASE WHEN a.Der_SNoMEDProcCode IS NOT NULL AND a.ConsMediumUsed = '03' THEN 1 ELSE 0 END) AS TotalContactsVideo,
	SUM(CASE WHEN a.Der_DirectContactOrder IS NOT NULL AND a.ConsMediumUsed IN ('04', '05', '06', '98') THEN 1 ELSE 0 END) AS TotalContactsOtherMedium
FROM #ActivitiesTEWV a
GROUP BY a.RecordNumber, a.UniqServReqID, a.Person_ID, a.UniqMonthID

---- Create activiites per referral temp table

IF OBJECT_ID ('tempdb..#ActPerRef') IS NOT NULL
DROP TABLE #ActPerRef

SELECT
	a.Person_ID,
	a.UniqServReqID,
	SUM(CASE WHEN a.Der_DirectContactOrder IS NOT NULL THEN 1 ELSE 0 END) AS TotalContactsPerReferral, -- Same process as above (calculate total contacts) but group by means it's for each referal rather than referral / month
	MAX(CASE WHEN a.Der_DirectContactOrder = '1' THEN a.Der_ContactDate ELSE NULL END) AS AccessDatePerReferal -- Same process as above (obtain date for first contact) but group by means it's for each referal rather than referral / month
INTO #ActPerRef
FROM [NHSE_Sandbox_MentalHealth].dbo.PreProc_Activity a -- Select access info from a
INNER JOIN #Referrals r ON a.RecordNumber = r.RecordNumber AND a.UniqServReqID = r.UniqServReqID -- Only select activity info for referrals in the referral table
WHERE a.OrgIDProv <> 'RX3'
GROUP BY a.UniqServReqID, a.Person_ID -- Group by ONLY referral, ignoring month

---- Add in TEWV activities per referral (repeat above but tweaked for TEWV where ServTeamTypeRefToMH = 'D05' is not available)

INSERT INTO #ActPerRef

SELECT
	a.Person_ID,
	a.UniqServReqID,
	SUM(CASE WHEN a.Der_SNoMEDProcCode IS NOT NULL THEN 1 ELSE 0 END) AS TotalContactsPerReferral, -- Calcuate total contacts for each referral
	MIN(a.Der_ContactDate) AS AccessDatePerReferral -- Find the date of the first contact for each referral
FROM [NHSE_Sandbox_MentalHealth].dbo.PreProc_Interventions a
INNER JOIN (SELECT DISTINCT r.Person_ID, r.UniqServReqID FROM [NHSE_Sandbox_MentalHealth].dbo.PreProc_Referral r GROUP BY r.Person_ID, r.UniqServReqID) r ON a.Person_ID = r.Person_ID AND a.UniqServReqID = r.UniqServReqID -- Select distinct referrals at TEWV who have IPS activities
WHERE a.Der_SNoMEDProcCode IN ('1082621000000104', '772822000') AND a.OrgIDProv = 'RX3'
GROUP BY a.UniqServReqID, a.Person_ID

---- Create outcomes temp table

IF OBJECT_ID ('tempdb..#OutcomesStep1') IS NOT NULL
DROP TABLE #OutcomesStep1

SELECT
	e1.RecordNumber,
	e1.EmployStatus,
	e1.WeekHoursWorked,
	ROW_NUMBER()OVER(PARTITION BY e1.RecordNumber ORDER BY e1.EmployStatusRecDate ASC) AS FirstRecording, -- To highight first and last status, for employed at referral vs employed at discharge
	ROW_NUMBER()OVER(PARTITION BY e1.RecordNumber ORDER BY e1.EmployStatusRecDate DESC) AS LastRecording
INTO #OutcomesStep1
FROM [NHSE_MHSDS].[dbo].[MHS004EmpStatus] e1 -- Select employment status and weekly hours worked from e1 - this is processed data covering up to ENDRP minus 2 months
INNER JOIN #Referrals r ON e1.RecordNumber = r.RecordNumber AND e1.UniqMonthID = r.UniqMonthID -- Only select employment information for referrals in the referral table
INNER JOIN [NHSE_MH_PrePublication].[Test].[MHSDS_SubmissionFlags] s ON e1.NHSEUniqSubmissionID = s.NHSEUniqSubmissionID AND s.Der_IsLatest = 'Y'
WHERE e1.UniqMonthID BETWEEN @STARTRP AND @ENDRP-2

INSERT INTO #OutcomesStep1

SELECT
	e2.RecordNumber,
	e2.EmployStatus,
	e2.WeekHoursWorked,
	ROW_NUMBER()OVER(PARTITION BY e2.RecordNumber ORDER BY e2.EmployStatusRecDate ASC) AS FirstRecording,
	ROW_NUMBER()OVER(PARTITION BY e2.RecordNumber ORDER BY e2.EmployStatusRecDate DESC) AS LastRecording
FROM [NHSE_MH_PrePublication].[test].[MHS004EmpStatus] e2 -- Repeat above (selecting employment status and weekly hours worked) but using e2 - this is unprocessed data covering only ENDRP minus 1 month
INNER JOIN #Referrals r ON e2.RecordNumber = r.RecordNumber AND e2.UniqMonthID = r.UniqMonthID
INNER JOIN [NHSE_MH_PrePublication].[Test].[MHSDS_SubmissionFlags] s ON e2.NHSEUniqSubmissionID = s.NHSEUniqSubmissionID AND s.Der_IsLatest = 'Y'
WHERE e2.UniqMonthID >= @ENDRP-1

IF OBJECT_ID ('tempdb..#Outcomes') IS NOT NULL
DROP TABLE #Outcomes

SELECT
	o.RecordNumber,
	MAX(CASE WHEN o.FirstRecording = 1 THEN o.EmployStatus ELSE NULL END) AS EmployStatusFirst,
	MAX(CASE WHEN o.LastRecording = 1 THEN o.EmployStatus ELSE NULL END) AS EmployStatusLast,
	MAX(CASE WHEN o.LastRecording = 1 THEN o.WeekHoursWorked ELSE NULL END) AS WeekHoursWorkedLast
INTO #Outcomes
FROM #OutcomesStep1 o
GROUP BY o.RecordNumber

---- Join temp tables in a master

IF OBJECT_ID ('tempdb..#Master') IS NOT NULL
DROP TABLE #Master

SELECT	
	r.RecordNumber,
	r.Person_ID,
	r.UniqServReqID,
	r.UniqMonthID,
	RIGHT(p.UniqCareProfTeamID,(LEN(p.UniqCareProfTeamID) - LEN(p.OrgIDProv))) AS  CareProfTeamLocalId,
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
	(CASE WHEN a.AccessFlag = 1 THEN 1 ELSE 0 END) AS AccessFlag, -- Ensure AccessFlag is using the first contact of TEWV (which used row number)
	(CASE WHEN a.FYAccessFlag = 1 THEN 1 ELSE 0 END) AS FYAccessFlag,
	(CASE WHEN a.AccessFlag = 1 THEN a.AccessDate ELSE NULL END) AS AccessDate, 
	ap.AccessDatePerReferal,
	ISNULL (a.TotalContacts, 0) AS TotalContacts, -- Convert any NULLs to 0 to enable calculations in the next #Agg table
	ISNULL (ap.TotalContactsPerReferral, 0) AS TotalContactsPerReferral,
	ISNULL (a.TotalContactsF2F, 0) AS TotalContactsF2F,
	ISNULL (a.TotalContactsTelephone, 0) AS TotalContactsTelephone, 
	ISNULL (a.TotalContactsVideo, 0) AS TotalContactsVideo, 
	ISNULL (a.TotalContactsOtherMedium, 0) AS TotalContactsOtherMedium,
	ISNULL (o.EmployStatusFirst, 0) AS EmployStatusFirst,
	ISNULL (o.EmployStatusLast, 0) AS EmployStatusLast,
	ISNULL (o.WeekHoursWorkedLast, 0) AS WeekHoursWorkedLast,
	o.EmployStatusLast AS EmployStatusLastWithNulls, -- Leave a version of employment status where NULLs have not been converted to 0s to allow the employment status data quality measure calculated below to use assign 'Missing/Invalid' to NULL values
	o.WeekHoursWorkedLast AS WeekHoursWorkedLastWithNulls
INTO #Master
FROM #Referrals r -- Select and join all relevant columns from r, a, o and ap temp tables constructed above
LEFT JOIN #Activities a ON a.RecordNumber = r.RecordNumber AND a.UniqServReqID = r.UniqServReqID -- CHECK THIS
LEFT JOIN #Outcomes o ON o.RecordNumber = r.RecordNumber 
LEFT JOIN #ActPerRef ap ON ap.Person_ID = r.Person_ID AND ap.UniqServReqID = r.UniqServReqID
LEFT JOIN [NHSE_Sandbox_MentalHealth].[dbo].[PreProc_Referral] p ON p.RecordNumber = r.RecordNumber AND p.UniqServReqID = r.UniqServReqID -- Add in local team identifier for each referral
 
---------- Create measures at month / aggregated geography level ---------

IF OBJECT_ID ('tempdb..#Agg') IS NOT NULL
DROP TABLE #Agg

SELECT 
	r.UniqMonthID, 
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

-- An open referral not yet discharged = part of the caseload (1=YES, open referral this month) 
SUM(CASE WHEN r.ServDischDate IS NULL THEN 1 ELSE 0 END) AS Caseload, 
SUM(CASE WHEN r.ServDischDate IS NULL AND r.ContactOrder > 0 THEN 1 ELSE 0 END) AS CaseloadAccessed,

-- Time in days from referral / access date to discharge date
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND DATEDIFF(DD, r.ReferralRequestReceivedDate, r.ServDischDate) > 180 THEN 1 ELSE 0 END) AS PrevTimeInCaseloadSinceReferredOver180, 
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND DATEDIFF(DD, r.ReferralRequestReceivedDate, r.ServDischDate) BETWEEN 91 AND 180 THEN 1 ELSE 0 END) AS PrevTimeInCaseloadSinceReferred91To180,
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND DATEDIFF(DD, r.ReferralRequestReceivedDate, r.ServDischDate) BETWEEN 0 AND 90 THEN 1 ELSE 0 END) AS PrevTimeInCaseloadSinceReferred0To90,
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND DATEDIFF(DD, r.AccessDatePerReferal, r.ServDischDate) > 180 THEN 1 ELSE 0 END) AS PrevTimeInCaseloadSinceAccessedOver180,
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND DATEDIFF(DD, r.AccessDatePerReferal, r.ServDischDate) BETWEEN 91 AND 180 THEN 1 ELSE 0 END) AS PrevTimeInCaseloadSinceAccessed91To180,
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND DATEDIFF(DD, r.AccessDatePerReferal, r.ServDischDate) BETWEEN 0 AND 90 THEN 1 ELSE 0 END) AS PrevTimeInCaseloadSinceAccessed0To90,
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND DATEDIFF(DD, r.AccessDatePerReferal, r.ServDischDate) >= 0 THEN 1 ELSE 0 END) AS PTAforDenom,

-- Referral accessed care in the month, 1st contact (1=YES, new access this month)
SUM(r.AccessFlag) AS TotalAccessed, 
SUM(r.FYAccessFlag) AS FYTotalAccessed,

-- Time between referral and access / first contact
SUM(CASE WHEN r.AccessFlag = '1' AND DATEDIFF(DD, r.ReferralRequestReceivedDate, r.AccessDate) <= 7 THEN 1 ELSE 0 END) AS SeenIn7,
SUM(CASE WHEN r.AccessFlag = '1' AND DATEDIFF(DD, r.ReferralRequestReceivedDate, r.AccessDate) BETWEEN 8 AND 30 THEN 1 ELSE 0 END) AS SeenIn8To30, 
SUM(CASE WHEN r.AccessFlag = '1' AND DATEDIFF(DD, r.ReferralRequestReceivedDate, r.AccessDate) > 30 THEN 1 ELSE 0 END) AS SeenInOver30,

-- Total contacts within the month, split by face to face and other contact medium
SUM(r.TotalContacts) AS TotalContacts, 
SUM(r.TotalContactsF2F) AS TotalContactsF2F,
SUM(r.TotalContactsTelephone) AS TotalContactsTelephone,
SUM(r.TotalContactsVideo) AS TotalContactsVideo,
SUM(r.TotalContactsOtherMedium) AS TotalContactsOtherMedium,

-- Employment status at time of discharge
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND r.EmployStatusLast = '01' THEN 1 ELSE 0 END) AS EmployedAtDischarge, 
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND r.EmployStatusLast IN ('02', '03', '04', '05', '06', '07', '08') THEN 1 ELSE 0 END) AS NotEmployedAtDischarge, 
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND r.EmployStatusLast IN ('0', 'ZZ') THEN 1 ELSE 0 END) AS UnknownEmployedAtDischarge, 
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND r.EmployStatusLast IN ('01', '02', '03', '04', '05', '06', '07', '08') THEN 1 ELSE 0 END) AS EMPforDenom,

-- Hours worked by those employed at discharge
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND r.EmployStatusLast = '01' AND r.WeekHoursWorkedLast = '01' THEN 1 ELSE 0 END) AS EmployedAtDischarge30Hours, 
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND r.EmployStatusLast = '01' AND r.WeekHoursWorkedLast = '02' THEN 1 ELSE 0 END) AS EmployedAtDischarge16to29Hours,
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND r.EmployStatusLast = '01' AND r.WeekHoursWorkedLast IN ('03','04') THEN 1 ELSE 0 END) AS EmployedAtDischarge15OrLess,

-- Length of time using service (since access) by those employed at discharge
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND r.EmployStatusLast = '01' AND DATEDIFF(DD, r.AccessDatePerReferal, r.ServDischDate) > 180 THEN 1 ELSE 0 END) AS EmployedAtDischargeSeenForOver180, 
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND r.EmployStatusLast = '01' AND DATEDIFF(DD, r.AccessDatePerReferal, r.ServDischDate) BETWEEN 91 AND 180 THEN 1 ELSE 0 END) AS EmployedAtDischargeSeenFor91To180,
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND r.EmployStatusLast = '01' AND DATEDIFF(DD, r.AccessDatePerReferal, r.ServDischDate) BETWEEN 0 AND 60 THEN 1 ELSE 0 END) AS EmployedAtDischargeSeenFor0To90,

-- Number of contacts whilst using the service by those employed at discharge
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND r.EmployStatusLast = '01' AND r.TotalContactsPerReferral >10 THEN 1 ELSE 0 END) AS EmployedAtDischargeSeenOver10Times, 
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND r.EmployStatusLast = '01' AND r.TotalContactsPerReferral BETWEEN 6 AND 10 THEN 1 ELSE 0 END) AS EmployedAtDischargeSeen6To10Times,
SUM(CASE WHEN r.ServDischDate IS NOT NULL AND r.EmployStatusLast = '01' AND r.TotalContactsPerReferral BETWEEN 1 AND 5 THEN 1 ELSE 0 END) AS EmployedAtDischargeSeen1To5Times,

-- Employment status at time of referral
SUM(CASE WHEN r.ReferralRequestReceivedDate BETWEEN r.ReportingPeriodStart AND r.ReportingPeriodEnd AND r.EmployStatusFirst = '01' THEN 1 ELSE 0 END) AS EmployedAtReferral, 
SUM(CASE WHEN r.ReferralRequestReceivedDate BETWEEN r.ReportingPeriodStart AND r.ReportingPeriodEnd AND r.EmployStatusFirst IN ('02', '03', '04', '05', '06', '07', '08') THEN 1 ELSE 0 END) AS NotEmployedAtReferral,
SUM(CASE WHEN r.ReferralRequestReceivedDate BETWEEN r.ReportingPeriodStart AND r.ReportingPeriodEnd AND r.EmployStatusFirst IN ('0', 'ZZ') THEN 1 ELSE 0 END) AS UnknownEmployedAtReferral,


-- Total missing / not missing for selected fields
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
SUM(CASE WHEN r.WeekHoursWorkedLastWithNulls IS NULL OR r.WeekHoursWorkedLastWithNulls IN ('97', '99') AND r.EmployStatusLast = '01' THEN 1 ELSE 0 END) AS WeekHoursWorkedMissing,
SUM(CASE WHEN r.WeekHoursWorkedLastWithNulls IS NOT NULL AND r.WeekHoursWorkedLastWithNulls NOT IN ('97', '99') AND r.EmployStatusLast = '01' THEN 1 ELSE 0 END) AS WeekHoursWorkedNotMissing
INTO #Agg
FROM #Master r
GROUP BY r.UniqMonthID, r.ReportingPeriodEnd, r.CareProfTeamLocalId, r.OrgIDProv, r.ProvName, r.OrgIDCCGRes, r.CCGName, r.STP_Code, r.STP_Name, r.Region_Code, r.Region_Name, r.GenderCat, r.AgeCat, r.EthnicityCat, r.SourceCat, r.DeprivationQuintile -- Measures calculated for every combination of referral, month, geography, gender, age, ethnicity, source of referral and deprivation quintile

---- Final list of measures

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
	a.Caseload,
	a.CaseloadAccessed,
	a.PrevTimeInCaseloadSinceReferredOver180, 
	a.PrevTimeInCaseloadSinceReferred91To180,
	a.PrevTimeInCaseloadSinceReferred0To90,
	a.PrevTimeInCaseloadSinceAccessedOver180,
	a.PrevTimeInCaseloadSinceAccessed91To180,
	a.PrevTimeInCaseloadSinceAccessed0To90,
	a.TotalAccessed,
	a.FYTotalAccessed,
	a.SeenIn7,
	a.SeenIn8To30, 
	a.SeenInOver30,
	a.TotalContacts, 
	a.TotalContactsF2F,
	a.TotalContactsTelephone,
	a.TotalContactsVideo,
	a.TotalContactsOtherMedium,
	a.EmployedAtDischarge,
	a.NotEmployedAtDischarge,
	a.UnknownEmployedAtDischarge,
	a.EmployedAtDischarge30Hours, 
	a.EmployedAtDischarge16to29Hours,
	a.EmployedAtDischarge15OrLess,
	a.EmployedAtDischargeSeenForOver180,
	a.EmployedAtDischargeSeenFor91To180,
	a.EmployedAtDischargeSeenFor0To90,
	a.EmployedAtDischargeSeenOver10Times, 
	a.EmployedAtDischargeSeen6To10Times,
	a.EmployedAtDischargeSeen1To5Times,
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
	a.EMPforDenom, -- Creates 2 denominators that are needed to calculate proportions in Tableau (to add into the Tooltip)
	a.PTAforDenom, 
	a.TotalAccessed AS TAforDenom, -- Create duplicates for 3 measures that are needed as denominators to calculate proportions in Tableau (to add into the Tooltip)
	a.ClosedReferrals AS CRforDenom, 
	a.TotalContacts AS TCforDenom
INTO #AggFinal
FROM #Agg a

---- Pivot final table into long format and refresh 'Dashboard_IPS_rebuild'

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
	MeasureName, -- MeasureName now includes all measures calculated above / included in the unpivot below - there will be a row for each measure, for each of the referral / month / geography (etc.) combinations
	MeasureValue, -- MeasureValue will change depending on the MeasureName
	CASE WHEN MeasureName IN ('EmployedAtDischarge', 'NotEmployedAtDischarge') THEN a.EMPforDenom
		WHEN MeasureName IN ('PrevTimeInCaseloadSinceReferredOver180', 'PrevTimeInCaseloadSinceReferred91To180', 'PrevTimeInCaseloadSinceReferred0To90') THEN a.CRforDenom
		WHEN MeasureName IN ('PrevTimeInCaseloadSinceAccessedOver180', 'PrevTimeInCaseloadSinceAccessed91To180', 'PrevTimeInCaseloadSinceAccessed0To90') THEN a.PTAforDenom
		WHEN MeasureName IN ('SeenIn7', 'SeenIn8To30', 'SeenInOver30') THEN a.TAforDenom
		WHEN MeasureName IN ('TotalContactsF2F', 'TotalContactsTelephone', 'TotalContactsVideo') THEN a.TCforDenom 
		ELSE NULL END AS Denominator -- The relevant denominator (given the measure name) is provided alongside the measure value, both are used to calculate proportions in Tableau

INTO NHSE_Sandbox_MentalHealth.dbo.Dashboard_IPS_rebuild
FROM #AggFinal a

UNPIVOT (MeasureValue FOR MeasureName IN (
	a.NewReferrals, 
	a.ClosedReferrals, 
	a.Caseload,
	a.CaseloadAccessed,
	a.PrevTimeInCaseloadSinceReferredOver180, 
	a.PrevTimeInCaseloadSinceReferred91To180,
	a.PrevTimeInCaseloadSinceReferred0To90,
	a.PrevTimeInCaseloadSinceAccessedOver180,
	a.PrevTimeInCaseloadSinceAccessed91To180,
	a.PrevTimeInCaseloadSinceAccessed0To90,
	a.TotalAccessed,
	a.FYTotalAccessed,
	a.SeenIn7,
	a.SeenIn8To30,
	a.SeenInOver30,
	a.TotalContacts, 
	a.TotalContactsF2F,
	a.TotalContactsTelephone,
	a.TotalContactsVideo,
	a.TotalContactsOtherMedium,
	a.EmployedAtDischarge,
	a.NotEmployedAtDischarge,
	a.UnknownEmployedAtDischarge,
	a.EmployedAtDischarge30Hours, 
	a.EmployedAtDischarge16to29Hours,
	a.EmployedAtDischarge15OrLess,
	a.EmployedAtDischargeSeenForOver180,
	a.EmployedAtDischargeSeenFor91To180,
	a.EmployedAtDischargeSeenFor0To90,
	a.EmployedAtDischargeSeenOver10Times, 
	a.EmployedAtDischargeSeen6To10Times,
	a.EmployedAtDischargeSeen1To5Times,
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
	a.WeekHoursWorkedNotMissing)) a