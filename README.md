# HSE Data Analytics Portfolio

I've spent twenty years in HSE across mining, construction, and Australian government. The gap I kept running into was the distance between raw incident data and a clear picture of what was actually happening on site — reports that took a full day to build, numbers that didn't tie back to each other, and no easy way to show a rate trending up before it became a serious injury. These four projects are how I closed that gap for myself, using the same incident register built out four different ways, in four different tools.

Every project reconciles against the same control figures. If a number in the Power BI report doesn't match the same number in the SQL output, something's wrong — and I've treated that as non-negotiable throughout the build.

## The Dataset

All four projects run on SQL_Project_HSE_Incident_Register.csv — a synthetic 500-row incident register built to mirror the structure of real operational data, spanning 2022–2024 across five Western Australian sites: Thunderbird Mine, Darwin Port Facility, Pilbara Crusher Plant, Broome Logistics Hub, and Katherine Processing Site. It includes the data quality issues that real registers actually have — duplicate records, inconsistent field values, and conflicting exposure-hour entries — because a clean, tidy dataset teaches you nothing about how to handle the ones you get in practice. TRIFR and LTIFR throughout are calculated against a 1,000,000-hour denominator, in line with Safe Work Australia and DMIRS convention.

## Project 1 — SQL (01_sql_hse_analytics)

Seven analytical sections in BigQuery Standard SQL, progressing from data quality audits through to rolling 12-month TRIFR window functions, contractor-versus-direct-employee rate comparisons, and a CTE-based executive KPI rollup. The rolling TRIFR uses a window function rather than a fixed calendar boundary, which matters when a site's reporting period doesn't line up neatly with the calendar year.

## Project 2 — Excel (02_excel_hse_workbook)

A five-sheet workbook: cleaned data with helper flag columns, a SUMIFS-driven KPI summary calculating TRIFR and LTIFR, PivotTables with slicers, and an executive dashboard with traffic-light conditional formatting. The KPI sheet uses MAXIFS rather than a straight SUMIFS for exposure hours, because 128 of the 144 site-month combinations in this register carry conflicting hours figures — taking the maximum is the documented, consistent assumption that carries through every other project in this portfolio.

## Project 3 — Python (03_python_hse_analysis)

A fully executable script covering data cleaning, descriptive statistics, TRIFR and LTIFR calculation, and six publication-quality visualisations, including a seaborn cause-by-site heatmap and a lead-to-lag indicator ratio chart. Exports a five-sheet Excel workbook automatically. Run with python hse_analysis.py.

## Project 4 — Power BI (04_powerbi_hse_dashboard)

A four-page interactive report: an Executive Summary with live KPI cards and a TRIFR trend line, a Site and Department drill-down with synced slicers, a Leading Indicators page tracking the near-miss-to-recordable ratio, and a Compliance and Corrective Actions page for audit tracking. A full DAX measure library sits behind it, including SAMEPERIODLASTYEAR time intelligence for genuine year-over-year comparison — which only works because the report is built on a proper Dim_Date calendar table rather than filtering directly off the incident dates.

## Why Four Tools, One Dataset

A hiring manager doesn't need me to explain what SQL or Power BI is. What's harder to fake is knowing why a MAXIFS assumption in Excel has to be rebuilt as a SUMX(SUMMARIZE(...)) pattern in DAX to produce the same number, or why a Classification field and an Incident_Type field look interchangeable until one of them breaks a measure. That's the kind of judgment this portfolio is built to demonstrate — not that I can follow a tutorial in four different pieces of software, but that I can carry one real operational problem across all of them and get the same, defensible answer every time.
