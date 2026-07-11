# HSE Power BI Dashboard — Build Guide

## The Problem

Every HSE report I've written eventually gets asked the same question: "is this getting better or worse compared to last year?" A static spreadsheet answers that once. A Power BI model answers it every time someone opens the report, at whatever level of the business they're looking at — site, department, quarter. That's the gap this project closes: a report that carries its own time intelligence rather than needing to be rebuilt every reporting cycle.

## What This Is Built On

Source data is the same 500-row incident register used across all four projects (`SQL_Project_HSE_Incident_Register.csv`), reconciled against the same control figures established in the SQL and Excel builds. If the numbers in this report don't tie back to those, something in the model is wrong — not the source data.

---

## 1. Data Model

**Fact table:** `incident_log`, imported via Power Query.

**Dimension table:** `Dim_Date`, built with:

```
Dim_Date = CALENDAR(DATE(2022,1,1), DATE(2024,12,31))
```

Extend it with `Year`, `Month`, `Month Name`, `Quarter`, and a `Year-Month` sort key column (plain integer, e.g. `202401`, so month names sort chronologically instead of alphabetically — this trips people up constantly and it's a one-line fix).

Mark `Dim_Date` as a date table in Model view (Table tools → Mark as date table → select the `Date` column). This is not optional. Time intelligence functions in DAX assume this relationship exists; skip it and `SAMEPERIODLASTYEAR` will either throw an error or, worse, return a number that looks plausible and isn't.

Relationship: `Dim_Date[Date]` (one) → `incident_log[Date]` (many). Single direction is fine here — you don't need bidirectional filtering for this model, and adding it just invites ambiguous filter paths later once you bring in a `Dim_Site` table.

**Optional but recommended:** a small `Dim_Site` table (five rows — one per site) if you want to add site metadata later (region, site manager, workforce headcount) without bloating the fact table. Not required for v1.

## 2. Power Query Transformations

Applied in the Power Query Editor before load:

- **Date column:** convert text to Date type explicitly; don't trust auto-detect on a CSV import, it has guessed US date format on this dataset before.
- **Trim and Clean:** applied to `Site`, `Department`, and `Investigator` — free-text fields are where inconsistent spacing and casing creep in, and a PivotTable-style slicer will show "Thunderbird Mine" and "Thunderbird Mine " as two different values if you don't.
- **Data type enforcement:** `Lost_Time_Days`, `Hours_Worked_That_Day`, `Total_Site_Hours_Month`, `TRIFR_Contribution`, `Fatality`, `High_Potential_Incident` all explicitly set to whole number — CSV imports sometimes infer these as text if there's a blank row anywhere in the column.
- **Duplicate check:** a reference query counting rows by `Incident_ID` grouped, filtered to `Count > 1`. Should return zero rows if the SQL and Excel data quality audits were correct. If it doesn't, stop and reconcile before building anything downstream.

## 3. DAX Measure Library

### Core rate measures

```
Total Recordable Incidents =
CALCULATE(
    COUNTROWS(incident_log),
    incident_log[Classification] IN {"Lost Time Injury", "Medical Treatment Injury", "Restricted Work Injury"}
)
```

```
Total Hours Worked =
SUM(incident_log[Hours_Worked_That_Day])
```

```
TRIFR =
DIVIDE([Total Recordable Incidents] * 1000000, [Total Hours Worked], 0)
```

The million-hour denominator isn't arbitrary — it's the Safe Work Australia and DMIRS convention, and it's what makes your TRIFR comparable to industry benchmark data rather than an internal-only number nobody outside the business can sanity-check.

```
LTIFR =
VAR LTICount =
    CALCULATE(COUNTROWS(incident_log), incident_log[Classification] = "Lost Time Injury")
RETURN
    DIVIDE(LTICount * 1000000, [Total Hours Worked], 0)
```

### Severity

```
Severity Index =
DIVIDE(SUM(incident_log[Lost_Time_Days]), [Total Recordable Incidents], 0)
```

Average lost days per recordable incident — this is the measure that catches a site with a low TRIFR but one catastrophic outlier dragging the severity number up. TRIFR alone hides that.

### Leading vs lagging

```
Lead-Lag Ratio =
VAR NearMiss =
    CALCULATE(COUNTROWS(incident_log), incident_log[Incident_Type] = "Near Miss")
VAR Recordable = [Total Recordable Incidents]
RETURN
    DIVIDE(NearMiss, Recordable, 0)
```

A ratio trending down over time is usually a reporting-culture problem before it's a safety-performance problem — near misses are voluntary reporting, recordables aren't.

### Time intelligence

```
TRIFR PY =
CALCULATE([TRIFR], SAMEPERIODLASTYEAR(Dim_Date[Date]))
```

```
TRIFR YoY % Change =
DIVIDE([TRIFR] - [TRIFR PY], [TRIFR PY], BLANK())
```

**Where this breaks:** `SAMEPERIODLASTYEAR` walks the `Dim_Date` table looking for the equivalent period one year back. If `Dim_Date` isn't marked as a date table, or if there's a gap in the date range (say it only starts at the first incident date rather than 1 Jan), the function has no contiguous range to walk and returns blank instead of erroring — which is worse, because a blank card looks like "no data" instead of "broken relationship."

### Contractor vs direct comparison

```
TRIFR - Contractor =
CALCULATE([TRIFR], incident_log[Employment_Type] = "Contractor")
```

```
TRIFR - Direct =
CALCULATE([TRIFR], incident_log[Employment_Type] = "Direct Employee")
```

Kept as separate measures rather than one measure sliced by a visual-level filter, because I want both numbers visible side by side on the same card visual without needing two copies of the same visual with different filter contexts.

## 4. Report Architecture — Four Pages

**Page 1 — Executive Summary**
KPI cards across the top: TRIFR, LTIFR, YoY % change, total recordables. Below that, a TRIFR trend line by month across all sites, and a matrix of TRIFR by site for the current year. This page answers "how are we doing" in under ten seconds — it's the page a GM looks at once and moves on from.

**Page 2 — Site & Department Drill-down**
Bar chart of TRIFR by site, cross-filtering into a department breakdown when a site is selected. Slicers for Year and Quarter. This is the page a site HSE lead actually works from.

**Page 3 — Leading Indicators**
Lead-Lag Ratio trend, near-miss reporting rate by site, corrective action close-out rate. This page exists because lagging indicators alone tell you what already happened — this is where you catch it before it becomes a recordable.

**Page 4 — Compliance & Corrective Actions**
Table of open corrective actions by age bracket (0–30, 31–60, 61–90, 90+ days), investigation status by classification, and a card showing overdue investigations. This is the page that gets exported for a DMIRS or board audit trail.

---

## Technical Notes

- Slicers are synced across pages 2–4 (Year, Quarter, Site) via the Sync Slicers pane — one selection carries through, so the story doesn't reset every time someone clicks to a new page.
- All rate measures use `DIVIDE()` rather than the `/` operator, with an explicit zero fallback — a month with zero hours worked (site shutdown, data gap) should show 0, not a divide-by-zero error breaking the visual.
- Conditional formatting on the TRIFR card uses a fixed threshold rather than a relative scale, matching the traffic-light logic from the Excel dashboard, so the two projects tell a consistent story if someone compares them side by side.

## How to Use It

Open in Power BI Desktop. Slicers on pages 2–4 are synced — set Year/Quarter/Site once, it carries across pages. Page 1 has no slicers by design; it's the unfiltered current-state view.
