Power BI — HSE Compliance Dashboard

The Problem

Every HSE report I've written eventually gets asked the same question: is this getting better or worse compared to last year? A static spreadsheet answers that once, for one point in time. Somebody has to rebuild it next quarter, and the quarter after that. This project is my answer to that problem — a report that carries its own time intelligence, so the comparison updates itself every time someone opens the file, at whatever level of the business they're looking at.

It's also the platform-fluency piece of this portfolio. Tableau shows up elsewhere in my study plan, but Power BI is what I've actually built with mining and construction clients before, and DAX measures written from scratch demonstrate a different kind of technical depth than a PivotTable does.

What Was Built

A four-page Power BI report, built on the same 500-row incident register that reconciles against the SQL, Excel, and Python projects in this portfolio.

Page 1 — Executive Summary. Four KPI cards (TRIFR, LTIFR, year-over-year TRIFR change, total recordable incidents), a monthly TRIFR trend line across 2022–2024, and a site-by-site TRIFR table. This is the page a GM looks at once and moves on from — everything that matters sits above the fold.

Page 2 — Site & Department Drill-down. Two bar charts, TRIFR by site and TRIFR by department, with Year and Quarter slicers synced across the whole report. Click a site, the department breakdown updates. This is the page a site HSE lead actually works from day to day.

Page 3 — Leading Indicators. A Lead-Lag Ratio trend line, the same ratio broken out by site, and the corrective action close-out rate as a standalone card. Lagging indicators tell you what already happened. This page is where I catch the drift before it becomes a recordable.

Page 4 — Compliance & Corrective Actions. Incident volume by age bracket, investigation status cross-tabulated against classification, and an overdue investigations count. This is the page that gets exported for a DMIRS or board audit trail.

Screenshots of all four pages sit in the screenshots/ folder. The full build guide, including every DAX measure and the reasoning behind each one, is in HSE_PowerBI_Project.md.

Technical Notes

Dim_Date is not optional. Every time-intelligence measure in this report — the year-over-year TRIFR comparison in particular — depends on SAMEPERIODLASTYEAR() walking back through a continuous calendar. I built a dedicated Dim_Date table with CALENDAR(), explicitly marked it as a date table, and related it to the fact table on the Date field. Skip that step and the time-intelligence measures don't error out loudly — they return blank, which looks like "no data" rather than "broken relationship." That's a worse failure mode, because it's silent.

The exposure hours calculation mirrors the Excel logic, not the naive one. My first attempt at Total Hours Worked summed Hours_Worked_That_Day, which only reflects the hours logged against incident rows themselves — a tiny, misleading fraction of true site exposure. That produced a TRIFR of 24,000-plus, which was obviously wrong the moment I looked at it. The correct field is Total_Site_Hours_Month, but 128 of 144 site-month combinations in this register carry conflicting values for it. The Excel workbook resolves this with MAXIFS, taking the highest recorded figure per site-month as the documented, consistent assumption. Power BI has no direct MAXIFS equivalent, so I rebuilt the same logic with SUMX(SUMMARIZE(...), MAX(...)) — group by site, year, and month, take the maximum hours figure for each group, then sum those. Same assumption, different tool.

Classification, not Incident_Type, drives the recordable count. Early in the build I wrote Total Recordable Incidents against Incident_Type, expecting values like "Lost Time Injury" or "Medical Treatment Injury." That field actually holds category names like Near Miss, First Aid, and Hazard Observation — not severity classifications. The clean binary I needed, Recordable versus Non-Recordable, lives in the Classification field. LTIFR draws from Incident_Type correctly, since Lost Time Injury genuinely is a value there — it's only the recordable count that needed the other column.

Days Open uses subtraction, not DATEDIFF. DATEDIFF(incident_log[Date], TODAY(), DAY) threw a row-context error I couldn't resolve directly. INT(TODAY() - MIN(incident_log[Date])) does the identical calculation and committed cleanly. Worth knowing if anyone else hits the same wall — it's a known DAX quirk with DATEDIFF in a calculated-column context, not a mistake in the logic itself.

The age bracket chart is a limitation worth stating plainly. Because every incident date in this register sits in 2022–2024 and the report is being built and viewed years later, effectively all 500 incidents fall into the "90+ days" bracket. The bracket logic itself is sound and would behave correctly against live, current data — it's the synthetic dataset's fixed historical dates that make this particular visual less informative than it would be in a real, ongoing HSE program. I've kept it in because the DAX pattern (SWITCH(TRUE(), ...)) is a genuinely useful technique to demonstrate, even though this dataset doesn't show it off well.

How to Use It

Open HSE_PowerBI_Dashboard.pbix in Power BI Desktop. Year and Quarter slicers on pages 2 through 4 are synced — set them once on any page and the filter carries across the rest of the report. Page 1 has no slicers by design; it's meant to be the unfiltered, current-state view a leadership team sees first.

Data connects to BigQuery (project-e23f1453-5bd2-436f-bcc → HSE_INCIDENT_DATA.incident_log) via Import mode, the same source table the SQL project queries directly — one register, four tools, one set of numbers.
