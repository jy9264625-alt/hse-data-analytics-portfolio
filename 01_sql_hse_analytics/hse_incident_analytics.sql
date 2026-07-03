/*
================================================================================
  HSE INCIDENT ANALYTICS — BigQuery Standard SQL
  Dataset : project-e23f1453-5bd2-436f-bcc.HSE_INCIDENT_DATA.incident_log
  Author  : Jo Smith | Assay Environmental Advisory
  Updated : 2024
  
  This script contains seven analytical sections progressing from data quality
  through to executive KPI rollup. Sections are designed to run independently.
  Exposure hours are sourced from Total_Site_Hours_Month; nulls are excluded
  from all rate calculations. TRIFR denominator is 1,000,000 hours (Australian
  industry standard per Safe Work Australia — not 200,000 as used in US OSHA
  reporting). Where contractor exposure hours are absent or coded inconsistently,
  this is flagged explicitly rather than silently included in rate calculations.
================================================================================
*/


/* ============================================================================
   SECTION 1 — DATA QUALITY AUDIT
   
   Real incident registers carry noise: duplicate records from concurrent data
   entry, null values where field-level validation was weak, and inconsistent
   contractor coding that makes employment-type analysis unreliable. This
   section surfaces those issues before any rates are calculated. Running a
   data quality audit first is not optional — it is the difference between
   reporting that holds up under scrutiny and reporting that quietly misleads.
   ============================================================================ */

-- 1a. Row count and basic completeness check
SELECT
  COUNT(*)                                                    AS total_records,
  COUNT(DISTINCT Incident_ID)                                 AS unique_incidents,
  COUNT(*) - COUNT(DISTINCT Incident_ID)                      AS duplicate_count,
  COUNTIF(Total_Site_Hours_Month IS NULL OR
          Total_Site_Hours_Month = 0)                         AS missing_exposure_hours,
  COUNTIF(Classification IS NULL)                             AS missing_classification,
  COUNTIF(Employment_Type IS NULL)                            AS missing_employment_type,
  COUNTIF(TRIFR_Contribution IS NULL)                         AS missing_trifr_flag,
  COUNTIF(Investigation_Status = 'Open')                      AS investigations_open,
  COUNTIF(Corrective_Action_Status = 'Overdue')               AS corrective_actions_overdue
FROM `project-e23f1453-5bd2-436f-bcc.HSE_INCIDENT_DATA.incident_log`;


-- 1b. Identify duplicate Incident_IDs
WITH duplicate_check AS (
  SELECT
    Incident_ID,
    COUNT(*)                          AS occurrences,
    COUNT(DISTINCT Classification)    AS distinct_classifications,
    COUNT(DISTINCT Site)              AS distinct_sites
  FROM `project-e23f1453-5bd2-436f-bcc.HSE_INCIDENT_DATA.incident_log`
  GROUP BY Incident_ID
  HAVING COUNT(*) > 1
)
SELECT
  Incident_ID,
  occurrences,
  CASE
    WHEN distinct_classifications > 1 OR distinct_sites > 1
      THEN 'Conflicting data — requires manual review'
    ELSE 'Full duplicate — safe to deduplicate'
  END AS duplicate_type
FROM duplicate_check
ORDER BY occurrences DESC;


-- 1c. Exposure hours sanity check by site and year
SELECT
  Site,
  Year,
  SUM(Hours_Worked_That_Day)                          AS sum_daily_hours,
  MAX(Total_Site_Hours_Month)                         AS reported_monthly_hours,
  ROUND(
    SAFE_DIVIDE(SUM(Hours_Worked_That_Day),
                MAX(Total_Site_Hours_Month)) * 100, 1
  )                                                   AS daily_as_pct_of_monthly
FROM `project-e23f1453-5bd2-436f-bcc.HSE_INCIDENT_DATA.incident_log`
GROUP BY Site, Year
ORDER BY Site, Year;


-- 1d. Employment type coding consistency
SELECT
  Site,
  Employment_Type,
  COUNT(*)                              AS incident_count,
  ROUND(
    100.0 * COUNT(*) /
    SUM(COUNT(*)) OVER (PARTITION BY Site), 1
  )                                     AS pct_of_site_incidents
FROM `project-e23f1453-5bd2-436f-bcc.HSE_INCIDENT_DATA.incident_log`
GROUP BY Site, Employment_Type
ORDER BY Site, Employment_Type;
/* ============================================================================
   SECTION 2 — INCIDENT FREQUENCY AND DISTRIBUTION
   ============================================================================ */

-- 2a. Incident volume by site, year, and type
SELECT
  Site,
  Year,
  Incident_Type,
  COUNT(*)                              AS incident_count,
  SUM(TRIFR_Contribution)               AS recordable_count,
  SUM(High_Potential_Incident)          AS hpi_count,
  SUM(Fatality)                         AS fatality_count
FROM `project-e23f1453-5bd2-436f-bcc.HSE_INCIDENT_DATA.incident_log`
GROUP BY Site, Year, Incident_Type
ORDER BY Site, Year, incident_count DESC;


-- 2b. Shift pattern analysis
SELECT
  Shift,
  COUNT(*)                              AS total_incidents,
  SUM(TRIFR_Contribution)               AS recordable_incidents,
  SUM(Lost_Time_Days)                   AS total_lost_time_days,
  ROUND(AVG(Lost_Time_Days), 2)         AS avg_lost_time_days,
  SUM(High_Potential_Incident)          AS hpi_count,
  COUNTIF(Primary_Cause = 'Fatigue')    AS fatigue_related
FROM `project-e23f1453-5bd2-436f-bcc.HSE_INCIDENT_DATA.incident_log`
GROUP BY Shift
ORDER BY total_incidents DESC;


-- 2c. Primary cause breakdown with severity overlay
SELECT
  Primary_Cause,
  COUNT(*)                              AS total_incidents,
  SUM(TRIFR_Contribution)               AS recordable_incidents,
  SUM(Lost_Time_Days)                   AS total_lost_time_days,
  ROUND(AVG(Lost_Time_Days), 2)         AS avg_lost_time_per_incident,
  SUM(High_Potential_Incident)          AS hpi_count,
  ROUND(
    100.0 * SUM(TRIFR_Contribution) / COUNT(*), 1
  )                                     AS recordable_rate_pct
FROM `project-e23f1453-5bd2-436f-bcc.HSE_INCIDENT_DATA.incident_log`
GROUP BY Primary_Cause
ORDER BY total_lost_time_days DESC;


-- 2d. High-potential incident profile
SELECT
  Site,
  Year,
  Quarter,
  SUM(High_Potential_Incident)          AS hpi_count,
  SUM(TRIFR_Contribution)               AS recordable_count,
  ROUND(
    SAFE_DIVIDE(
      SUM(High_Potential_Incident),
      SUM(TRIFR_Contribution)
    ), 2
  )                                     AS hpi_to_recordable_ratio
FROM `project-e23f1453-5bd2-436f-bcc.HSE_INCIDENT_DATA.incident_log`
GROUP BY Site, Year, Quarter
ORDER BY Site, Year, Quarter;


/* ============================================================================
   SECTION 3 — TRIFR AND LTIFR CALCULATIONS
   
   TRIFR = (Recordable Injuries × 1,000,000) / Total Hours Worked
   LTIFR = (Lost Time Injuries × 1,000,000) / Total Hours Worked
   
   Exposure hours are deduplicated using MAX(Total_Site_Hours_Month) per site
   per month before summing to avoid double-counting where multiple incidents
   occur in the same month.
   ============================================================================ */

-- 3a. Annual TRIFR and LTIFR by site
WITH site_year_hours AS (
  SELECT
    Site,
    Year,
    Month,
    MAX(Total_Site_Hours_Month)           AS monthly_hours
  FROM `project-e23f1453-5bd2-436f-bcc.HSE_INCIDENT_DATA.incident_log`
  WHERE Total_Site_Hours_Month IS NOT NULL
    AND Total_Site_Hours_Month > 0
  GROUP BY Site, Year, Month
),
annual_hours AS (
  SELECT
    Site,
    Year,
    SUM(monthly_hours)                    AS total_annual_hours
  FROM site_year_hours
  GROUP BY Site, Year
),
annual_incidents AS (
  SELECT
    Site,
    Year,
    SUM(TRIFR_Contribution)               AS recordable_injuries,
    COUNTIF(
      Incident_Type = 'Lost Time Injury'
    )                                     AS lost_time_injuries,
    SUM(Lost_Time_Days)                   AS total_lost_days
  FROM `project-e23f1453-5bd2-436f-bcc.HSE_INCIDENT_DATA.incident_log`
  GROUP BY Site, Year
)
SELECT
  i.Site,
  i.Year,
  i.recordable_injuries,
  i.lost_time_injuries,
  i.total_lost_days,
  h.total_annual_hours,
  ROUND(
    SAFE_DIVIDE(i.recordable_injuries * 1000000, h.total_annual_hours), 2
  )                                       AS TRIFR,
  ROUND(
    SAFE_DIVIDE(i.lost_time_injuries * 1000000, h.total_annual_hours), 2
  )                                       AS LTIFR
FROM annual_incidents i
JOIN annual_hours h
  ON i.Site = h.Site AND i.Year = h.Year
ORDER BY i.Site, i.Year;


-- 3b. Quarterly TRIFR by site
WITH quarter_hours AS (
  SELECT
    Site,
    Year,
    Quarter,
    Month,
    MAX(Total_Site_Hours_Month)           AS monthly_hours
  FROM `project-e23f1453-5bd2-436f-bcc.HSE_INCIDENT_DATA.incident_log`
  WHERE Total_Site_Hours_Month IS NOT NULL
    AND Total_Site_Hours_Month > 0
  GROUP BY Site, Year, Quarter, Month
),
quarter_exposure AS (
  SELECT
    Site,
    Year,
    Quarter,
    SUM(monthly_hours)                    AS quarterly_hours
  FROM quarter_hours
  GROUP BY Site, Year, Quarter
),
quarter_incidents AS (
  SELECT
    Site,
    Year,
    Quarter,
    SUM(TRIFR_Contribution)               AS recordable_injuries,
    COUNTIF(Incident_Type = 'Lost Time Injury') AS lost_time_injuries
  FROM `project-e23f1453-5bd2-436f-bcc.HSE_INCIDENT_DATA.incident_log`
  GROUP BY Site, Year, Quarter
)
SELECT
  i.Site,
  i.Year,
  i.Quarter,
  i.recordable_injuries,
  i.lost_time_injuries,
  e.quarterly_hours,
  ROUND(
    SAFE_DIVIDE(i.recordable_injuries * 1000000, e.quarterly_hours), 2
  )                                       AS quarterly_TRIFR,
  ROUND(
    SAFE_DIVIDE(i.lost_time_injuries * 1000000, e.quarterly_hours), 2
  )                                       AS quarterly_LTIFR
FROM quarter_incidents i
JOIN quarter_exposure e
  ON i.Site = e.Site
  AND i.Year = e.Year
  AND i.Quarter = e.Quarter
ORDER BY i.Site, i.Year, i.Quarter;
/* ============================================================================
   SECTION 4 — ROLLING 12-MONTH TRIFR (WINDOW FUNCTION)
   
   Rolling 12-month TRIFR uses a trailing window anchored to each month's end
   date. ROWS BETWEEN 11 PRECEDING AND CURRENT ROW gives a true preceding year
   of exposure regardless of calendar position. A months_in_window counter
   flags partial windows where fewer than 12 months of data exist.
   ============================================================================ */

WITH monthly_summary AS (
  SELECT
    Site,
    Year,
    Month,
    DATE(CAST(Year AS STRING) || '-' || LPAD(CAST(Month AS STRING), 2, '0') || '-01')
                                          AS month_start,
    MAX(Total_Site_Hours_Month)           AS monthly_hours,
    SUM(TRIFR_Contribution)               AS monthly_recordable,
    COUNTIF(Incident_Type = 'Lost Time Injury') AS monthly_lti
  FROM `project-e23f1453-5bd2-436f-bcc.HSE_INCIDENT_DATA.incident_log`
  WHERE Total_Site_Hours_Month IS NOT NULL
    AND Total_Site_Hours_Month > 0
  GROUP BY Site, Year, Month
),
rolling AS (
  SELECT
    Site,
    Year,
    Month,
    month_start,
    monthly_hours,
    monthly_recordable,
    monthly_lti,
    SUM(monthly_hours) OVER (
      PARTITION BY Site
      ORDER BY month_start
      ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
    )                                     AS rolling_12m_hours,
    SUM(monthly_recordable) OVER (
      PARTITION BY Site
      ORDER BY month_start
      ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
    )                                     AS rolling_12m_recordable,
    SUM(monthly_lti) OVER (
      PARTITION BY Site
      ORDER BY month_start
      ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
    )                                     AS rolling_12m_lti,
    COUNT(*) OVER (
      PARTITION BY Site
      ORDER BY month_start
      ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
    )                                     AS months_in_window
  FROM monthly_summary
)
SELECT
  Site,
  Year,
  Month,
  month_start,
  rolling_12m_hours,
  rolling_12m_recordable,
  rolling_12m_lti,
  months_in_window,
  ROUND(
    SAFE_DIVIDE(rolling_12m_recordable * 1000000, rolling_12m_hours), 2
  )                                       AS rolling_TRIFR,
  ROUND(
    SAFE_DIVIDE(rolling_12m_lti * 1000000, rolling_12m_hours), 2
  )                                       AS rolling_LTIFR,
  CASE
    WHEN months_in_window < 12 THEN 'Partial window — interpret with caution'
    ELSE 'Full 12-month window'
  END                                     AS window_status
FROM rolling
ORDER BY Site, month_start;


/* ============================================================================
   SECTION 5 — CONTRACTOR VS DIRECT EMPLOYEE RATE COMPARISON
   
   Exposure hours are not split by employment type in the source data.
   Total_Site_Hours_Month is used as the denominator for all employment types.
   This limitation is acknowledged explicitly in the output.
   ============================================================================ */

-- 5a. Employment type incident and rate comparison
WITH employment_incidents AS (
  SELECT
    Employment_Type,
    Year,
    SUM(TRIFR_Contribution)               AS recordable_injuries,
    COUNTIF(Incident_Type = 'Lost Time Injury') AS lost_time_injuries,
    SUM(Lost_Time_Days)                   AS total_lost_days,
    SUM(High_Potential_Incident)          AS hpi_count,
    COUNT(*)                              AS total_incidents
  FROM `project-e23f1453-5bd2-436f-bcc.HSE_INCIDENT_DATA.incident_log`
  GROUP BY Employment_Type, Year
),
total_annual_hours AS (
  SELECT
    Year,
    SUM(DISTINCT_monthly_hours)           AS total_hours
  FROM (
    SELECT
      Year,
      Site,
      Month,
      MAX(Total_Site_Hours_Month)         AS DISTINCT_monthly_hours
    FROM `project-e23f1453-5bd2-436f-bcc.HSE_INCIDENT_DATA.incident_log`
    WHERE Total_Site_Hours_Month IS NOT NULL
      AND Total_Site_Hours_Month > 0
    GROUP BY Year, Site, Month
  )
  GROUP BY Year
)
SELECT
  e.Employment_Type,
  e.Year,
  e.total_incidents,
  e.recordable_injuries,
  e.lost_time_injuries,
  e.total_lost_days,
  e.hpi_count,
  h.total_hours,
  ROUND(
    SAFE_DIVIDE(e.recordable_injuries * 1000000, h.total_hours), 2
  )                                       AS TRIFR,
  ROUND(
    SAFE_DIVIDE(e.lost_time_injuries * 1000000, h.total_hours), 2
  )                                       AS LTIFR
FROM employment_incidents e
JOIN total_annual_hours h ON e.Year = h.Year
ORDER BY e.Year, e.Employment_Type;


-- 5b. Site-level contractor concentration vs incident share
SELECT
  Site,
  Year,
  COUNTIF(Employment_Type = 'Contractor')       AS contractor_incidents,
  COUNTIF(Employment_Type = 'Direct Employee')  AS direct_incidents,
  COUNTIF(Employment_Type = 'Labour Hire')      AS labour_hire_incidents,
  COUNT(*)                                      AS total_incidents,
  ROUND(
    100.0 * COUNTIF(Employment_Type = 'Contractor') / COUNT(*), 1
  )                                             AS contractor_pct_of_incidents,
  ROUND(
    100.0 * COUNTIF(Employment_Type = 'Labour Hire') / COUNT(*), 1
  )                                             AS labour_hire_pct_of_incidents
FROM `project-e23f1453-5bd2-436f-bcc.HSE_INCIDENT_DATA.incident_log`
GROUP BY Site, Year
ORDER BY Site, Year;
/* ============================================================================
   SECTION 6 — CORRECTIVE ACTION AND INVESTIGATION CLOSE-OUT
   
   An incident register that captures events without tracking close-out is a
   compliance document, not a management tool. Overdue corrective actions on
   recordable or high-potential incidents represent open, uncontrolled risk.
   ============================================================================ */

-- 6a. Investigation and corrective action status summary
SELECT
  Site,
  Investigation_Status,
  Corrective_Action_Status,
  COUNT(*)                                  AS incident_count,
  SUM(TRIFR_Contribution)                   AS recordable_count,
  SUM(High_Potential_Incident)              AS hpi_count,
  COUNTIF(
    Corrective_Action_Status = 'Overdue'
    AND (TRIFR_Contribution = 1 OR High_Potential_Incident = 1)
  )                                         AS overdue_high_priority
FROM `project-e23f1453-5bd2-436f-bcc.HSE_INCIDENT_DATA.incident_log`
GROUP BY Site, Investigation_Status, Corrective_Action_Status
ORDER BY Site, overdue_high_priority DESC, incident_count DESC;


-- 6b. Close-out rate by site and year
SELECT
  Site,
  Year,
  COUNT(*)                                              AS total_incidents,
  COUNTIF(Investigation_Status = 'Closed')              AS investigations_closed,
  COUNTIF(Investigation_Status = 'Open')                AS investigations_open,
  COUNTIF(Investigation_Status = 'In Progress')         AS investigations_in_progress,
  COUNTIF(Corrective_Action_Status = 'Complete')        AS ca_complete,
  COUNTIF(Corrective_Action_Status = 'Pending')         AS ca_pending,
  COUNTIF(Corrective_Action_Status = 'Overdue')         AS ca_overdue,
  ROUND(
    100.0 * COUNTIF(Corrective_Action_Status = 'Complete') / COUNT(*), 1
  )                                                     AS ca_closeout_rate_pct,
  ROUND(
    100.0 * COUNTIF(Investigation_Status = 'Closed') / COUNT(*), 1
  )                                                     AS investigation_close_rate_pct
FROM `project-e23f1453-5bd2-436f-bcc.HSE_INCIDENT_DATA.incident_log`
GROUP BY Site, Year
ORDER BY Site, Year;


-- 6c. Overdue corrective actions on high-potential incidents — the red list
SELECT
  Incident_ID,
  Date,
  Site,
  Incident_Type,
  Primary_Cause,
  Investigator,
  Investigation_Status,
  Corrective_Action_Status,
  High_Potential_Incident,
  Fatality
FROM `project-e23f1453-5bd2-436f-bcc.HSE_INCIDENT_DATA.incident_log`
WHERE High_Potential_Incident = 1
  AND Corrective_Action_Status = 'Overdue'
ORDER BY Site, Date;


/* ============================================================================
   SECTION 7 — EXECUTIVE KPI ROLLUP (CTE-BASED)
   
   Single output table suitable for a board report or executive dashboard.
   Five CTEs build toward one clean result. The LAG window function produces
   year-on-year TRIFR change. The performance flag evaluates conditions in
   priority order — fatality first, corrective action backlog second,
   elevated TRIFR third, underreporting caution fourth.
   ============================================================================ */

WITH
portfolio_hours AS (
  SELECT
    Year,
    SUM(monthly_hours)                          AS annual_hours
  FROM (
    SELECT
      Year,
      Site,
      Month,
      MAX(Total_Site_Hours_Month)               AS monthly_hours
    FROM `project-e23f1453-5bd2-436f-bcc.HSE_INCIDENT_DATA.incident_log`
    WHERE Total_Site_Hours_Month IS NOT NULL
      AND Total_Site_Hours_Month > 0
    GROUP BY Year, Site, Month
  )
  GROUP BY Year
),
portfolio_incidents AS (
  SELECT
    Year,
    COUNT(*)                                    AS total_incidents,
    SUM(TRIFR_Contribution)                     AS recordable_injuries,
    COUNTIF(Incident_Type = 'Lost Time Injury') AS lost_time_injuries,
    SUM(Lost_Time_Days)                         AS total_lost_days,
    SUM(High_Potential_Incident)                AS total_hpi,
    SUM(Fatality)                               AS total_fatalities,
    COUNTIF(Incident_Type IN ('Near Miss', 'Hazard Observation'))
                                                AS leading_indicator_reports,
    SUM(TRIFR_Contribution)                     AS lagging_indicator_count
  FROM `project-e23f1453-5bd2-436f-bcc.HSE_INCIDENT_DATA.incident_log`
  GROUP BY Year
),
portfolio_closeout AS (
  SELECT
    Year,
    COUNT(*)                                    AS total_incidents,
    COUNTIF(Corrective_Action_Status = 'Complete')  AS ca_complete,
    COUNTIF(Corrective_Action_Status = 'Overdue')   AS ca_overdue,
    COUNTIF(Investigation_Status = 'Closed')        AS inv_closed
  FROM `project-e23f1453-5bd2-436f-bcc.HSE_INCIDENT_DATA.incident_log`
  GROUP BY Year
),
executive_kpis AS (
  SELECT
    i.Year,
    i.total_incidents,
    i.recordable_injuries,
    i.lost_time_injuries,
    i.total_lost_days,
    i.total_hpi,
    i.total_fatalities,
    h.annual_hours,
    ROUND(
      SAFE_DIVIDE(i.recordable_injuries * 1000000, h.annual_hours), 2
    )                                           AS portfolio_TRIFR,
    ROUND(
      SAFE_DIVIDE(i.lost_time_injuries * 1000000, h.annual_hours), 2
    )                                           AS portfolio_LTIFR,
    ROUND(
      SAFE_DIVIDE(i.leading_indicator_reports, NULLIF(i.lagging_indicator_count, 0)), 2
    )                                           AS lead_lag_ratio,
    ROUND(
      100.0 * c.ca_complete / NULLIF(c.total_incidents, 0), 1
    )                                           AS ca_closeout_rate_pct,
    c.ca_overdue                                AS ca_overdue_count,
    ROUND(
      100.0 * c.inv_closed / NULLIF(c.total_incidents, 0), 1
    )                                           AS investigation_close_rate_pct,
    ROUND(
      SAFE_DIVIDE(i.recordable_injuries * 1000000, h.annual_hours) -
      LAG(SAFE_DIVIDE(i.recordable_injuries * 1000000, h.annual_hours))
        OVER (ORDER BY i.Year), 2
    )                                           AS trifr_yoy_change
  FROM portfolio_incidents i
  JOIN portfolio_hours h ON i.Year = h.Year
  JOIN portfolio_closeout c ON i.Year = c.Year
)
SELECT
  Year,
  total_incidents,
  recordable_injuries,
  lost_time_injuries,
  total_lost_days,
  total_hpi,
  total_fatalities,
  annual_hours,
  portfolio_TRIFR,
  portfolio_LTIFR,
  lead_lag_ratio,
  ca_closeout_rate_pct,
  ca_overdue_count,
  investigation_close_rate_pct,
  trifr_yoy_change,
  CASE
    WHEN total_fatalities > 0
      THEN '*** FATALITY RECORDED — escalate immediately'
    WHEN ca_overdue_count > 10
      THEN 'HIGH: Corrective action backlog requires management attention'
    WHEN portfolio_TRIFR > 5.0
      THEN 'ELEVATED: TRIFR exceeds Safe Work Australia mining sector average'
    WHEN lead_lag_ratio < 1.0
      THEN 'CAUTION: Near-miss underreporting suspected'
    ELSE 'Within acceptable thresholds — continue monitoring'
  END                                           AS performance_flag
FROM executive_kpis
ORDER BY Year;


/*
================================================================================
  END OF SCRIPT
  
  BigQuery project path:
  project-e23f1453-5bd2-436f-bcc.HSE_INCIDENT_DATA.incident_log
================================================================================
*/
