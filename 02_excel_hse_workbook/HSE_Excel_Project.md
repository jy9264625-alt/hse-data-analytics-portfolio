# HSE Excel Workbook — Build Guide

This document is the construction record for the five-sheet HSE reporting workbook. It exists because an `.xlsx` file is a black box on GitHub — the formulas and structure are invisible until downloaded — so this guide makes the build reviewable in the browser, and reproducible by anyone with the source CSV. Everything below is the workbook as actually built, including the validation checkpoints I used and a couple of problems I hit along the way.

Two conventions apply throughout. First, plain cell references rather than structured references: I made that call early after structured references (`[@Column]` syntax) caused repeated formula failures in my environment, and consistency mattered more than elegance. Second, every sheet ends with a validation step against independently calculated control figures — the same numbers my SQL project produces from the identical dataset. No sheet is trusted until it reconciles.

The build order is deliberate. Each sheet depends on the one before it:

1. `01_Data` — the register, imported and flagged
2. `02_Exposure_Hours` — the deduplicated denominator
3. `03_KPI_Summary` — TRIFR and LTIFR calculation
4. `04_Pivots` — the exploratory layer
5. `05_Dashboard` — the executive view

---

## Sheet 1 — 01_Data

### Purpose

Single source of truth. Every formula, pivot, and chart in the workbook reads from this sheet; nothing downstream touches the CSV directly.

### Import

I brought the CSV in through **Data → Get Data → From Text/CSV** (Power Query) rather than opening it directly. Two reasons: the connection is refreshable if the source data changes, and Power Query forces the data typing to be explicit rather than guessed at open. It's also the same engine Power BI uses, so the import logic transfers directly to Project 4.

The one check that matters at this stage is the Date column. The register uses day-first Australian dates, and a silent US-style parse would swap day and month on every date where the day is 12 or under — an error that stays invisible until a quarterly trend looks wrong months later. In the Power Query editor, the Date column should show the calendar icon; if it shows ABC (text), the fix is the column's type menu → **Using Locale → Date → English (Australia)**. The dataset carries its own verification: the Date column can be cross-checked against the Month and Month_Name columns row by row, and they must agree.

After **Close & Load**, the data lands as an Excel Table. I renamed it `tbl_Incidents` (Table Design → Table Name) and renamed the sheet tab `01_Data`.

### Helper columns

Three calculated columns added to the right of the imported data. Excel auto-fills them down all 500 rows.

**LTI_Flag** — the LTIFR numerator. Flags any incident with lost time:

```text
=IF([@[Lost_Time_Days]]>0, 1, 0)
```

**Month_Key** — a true date anchored to the first of each month, for clean time grouping:

```text
=DATE([@Year], [@Month], 1)
```

**Site_Month_Key** — the concatenated key that Sheet 2's deduplication hangs off. Built with plain references after the structured version repeatedly failed (Site is column G, Month_Key is column Z):

```text
=G2&"|"&TEXT(Z2,"yyyy-mm")
```

Result: `Thunderbird Mine|2023-10`. The recordable flag (`TRIFR_Contribution`) ships in the source data, so no helper column is needed for the TRIFR numerator.

### Data quality audit

Before trusting the table, I replicated the duplicate audit from my SQL project. A temporary column:

```text
=COUNTIF(A:A,A2)
```

counts each Incident_ID's occurrences across the full ID column. Every value must be at least 1 (each ID counts itself); values above 1 are duplicates.

**Result: all 500 IDs returned 1 — zero duplicates, and zero missing exposure hours.** The same audit in BigQuery and an independent check against the raw CSV agreed. A clean result is still a result: the point of the audit is that data quality was verified rather than assumed. The temporary column was deleted after the audit — the finding lives here, not as dead weight in the file.

---

## Sheet 2 — 02_Exposure_Hours

### Purpose

This sheet solves the trap at the centre of frequency-rate reporting from incident registers. `Total_Site_Hours_Month` repeats on every incident row, so summing it straight from the register counts each month's hours once per incident and inflates the denominator to nearly four times its true value — which crushes every TRIFR calculated from it. A rate that flatters the operation is worse than no rate at all. This sheet collapses the register to one exposure figure per site per month.

It is the Excel equivalent of the deduplication CTE in my SQL project's Section 3, and it must produce the same numbers.

### Build

This is a plain worksheet, not a Table — the UNIQUE function used below spills its results, and spill ranges don't work inside Tables.

Headers in row 1: `Site_Month_Key` (A1), `Site` (B1), `Year` (C1), `Monthly_Hours` (D1).

**A2 — the unique key list.** One formula that spills every distinct site-month combination:

```text
=UNIQUE('01_Data'!AA2:AA501)
```

Checkpoint: the spill ends at row 145 — **144 unique site-month combinations** across five sites and the 2022–2024 period.

**B2, copied down to B145 — split the site back out of the key:**

```text
=LEFT(A2, FIND("|",A2)-1)
```

**C2, copied down — extract the year as a number** (so Sheet 3 can filter on it):

```text
=VALUE(MID(A2, FIND("|",A2)+1, 4))
```

**D2, copied down — the deduplicated hours.** The load-bearing formula of the workbook:

```text
=MAXIFS('01_Data'!U:U, '01_Data'!AA:AA, A2)
```

Column U is `Total_Site_Hours_Month`; column AA is the Site_Month_Key. The formula returns the largest hours figure among all incident rows sharing this site-month.

**Why MAX matters here — and why the choice isn't cosmetic.** The exposure figures on this register do *not* agree within a site-month: 128 of the 144 combinations carry conflicting values across their incident rows. That means the aggregation method genuinely moves the denominator, and it had to be a documented decision rather than an accident of whichever row a lookup hit first. I took the maximum — the fullest reported monthly figure, and the one least likely to understate exposure — because that is the assumption my SQL build documents in its Section 3 CTE (`MAX(Total_Site_Hours_Month)` grouped by site, year, month). One methodology, applied identically in both tools, is what makes the cross-project reconciliation meaningful.

### Validation

Checksum cell beside the table:

```text
=SUM(D2:D145)
```

**Control figure: 14,492,423 hours**, splitting 5,805,541 (2022), 5,713,661 (2023), and 2,973,221 (2024). The Excel result, the BigQuery result, and an independent recalculation from the raw CSV all agree. Every rate in the workbook divides by column D of this sheet.

---

## Sheet 3 — 03_KPI_Summary

### Purpose

The calculation engine. I built this sheet with SUMIFS formulas rather than a PivotTable deliberately: pivots reshape themselves on refresh and field changes, which breaks any cell reference pointing at them. The dashboard's KPI cards and charts need a fixed layout to read from, and formulas provide one. The pivots live on their own sheet, where reshaping does no harm.

### Layout

Two tables. The annual table occupies rows 3–6 (headers in row 3, years 2022–2024 in A4:A6). The site table occupies rows 9–14 (headers in row 9, the five site names in A10:A14). Site names must match the data exactly — SUMIFS matches text literally, so the safe method is copying them from column B of the exposure sheet rather than retyping.

Columns in both tables: `Recordable_Injuries`, `LTIs`, `Exposure_Hours`, `TRIFR`, `LTIFR`.

### Annual table formulas (row 4, copied down through row 6)

```text
B4: =SUMIFS('01_Data'!V:V, '01_Data'!C:C, A4)
C4: =SUMIFS('01_Data'!Y:Y, '01_Data'!C:C, A4)
D4: =SUMIFS('02_Exposure_Hours'!D:D, '02_Exposure_Hours'!C:C, A4)
E4: =ROUND(B4/D4*1000000, 2)
F4: =ROUND(C4/D4*1000000, 2)
```

In plain language: B4 sums the recordable flags (column V, `TRIFR_Contribution`) for rows matching this year; C4 does the same with the LTI flag (column Y). D4 pulls exposure from the deduplicated Sheet 2 table — never from the raw register, which is the entire reason Sheet 2 exists. E4 and F4 apply the standard Australian formulas: events per **1,000,000 hours worked**, the Safe Work Australia and DMIRS convention. (Using the US OSHA denominator of 200,000 here would produce rates five times too high against any Australian benchmark — a common and expensive mistake.)

### Site table formulas (row 10, copied down through row 14)

Same pattern, two criteria changes: the year column (C) becomes the site column (G) on the data sheet, and the year column (C) becomes the site column (B) on the exposure sheet.

```text
B10: =SUMIFS('01_Data'!V:V, '01_Data'!G:G, A10)
C10: =SUMIFS('01_Data'!Y:Y, '01_Data'!G:G, A10)
D10: =SUMIFS('02_Exposure_Hours'!D:D, '02_Exposure_Hours'!B:B, A10)
E10: =ROUND(B10/D10*1000000, 2)
F10: =ROUND(C10/D10*1000000, 2)
```

A note from the build: these five formulas belong side by side in one row, each reading its own row's label in column A. I initially entered them down a column instead — five formulas stacked vertically, all reading row 10 — which produced Thunderbird's numbers labelled as four different sites and a pair of `#DIV/0!` errors. The tell was that every visible value belonged to one site. The mental model that fixes it: each row is one site's complete story read left to right, and nothing in these tables reads vertically.

### Validation — the full control set

| Year | Recordables | LTIs | Hours | TRIFR | LTIFR |
|------|------------|------|-----------|-------|-------|
| 2022 | 51 | 23 | 5,805,541 | 8.78 | 3.96 |
| 2023 | 51 | 29 | 5,713,661 | 8.93 | 5.08 |
| 2024 | 20 | 5 | 2,973,221 | 6.73 | 1.68 |

| Site | Recordables | LTIs | Hours | TRIFR | LTIFR |
|------|------------|------|-----------|-------|-------|
| Broome Logistics Hub | 23 | 8 | 2,994,737 | 7.68 | 2.67 |
| Darwin Port Facility | 24 | 9 | 2,943,430 | 8.15 | 3.06 |
| Katherine Processing Site | 18 | 13 | 2,538,662 | 7.09 | 5.12 |
| Pilbara Crusher Plant | 31 | 13 | 3,051,014 | 10.16 | 4.26 |
| Thunderbird Mine | 26 | 14 | 2,964,580 | 8.77 | 4.72 |

Every cell reconciles with the BigQuery Section 3 output. Two findings in these tables drive the dashboard commentary: the 2023 LTIFR jump (3.96 → 5.08) against a near-flat TRIFR — steady incident frequency, worsening severity — and Katherine Processing holding the lowest TRIFR but the highest LTIFR of the five sites, meaning few incidents but disproportionately serious ones.

### The LET example

One demonstration cell (H10, labelled) rebuilds Thunderbird's TRIFR as a single self-contained formula:

```text
=LET(rec, SUMIFS('01_Data'!V:V,'01_Data'!G:G,A10), hrs, SUMIFS('02_Exposure_Hours'!D:D,'02_Exposure_Hours'!B:B,A10), ROUND(rec/hrs*1000000,2))
```

LET declares `rec` and `hrs` as named variables, computes each SUMIFS once, and derives the rate from them — no helper cells, no repeated calculation, and a formula the next person can read. Its validation is built in: it must return exactly what the conventional version in E10 returns (8.77), and it does. In a production KPI sheet the practical benefit is maintenance: change a criteria range once instead of in every cell that repeats the SUMIFS.

---

## Sheet 4 — 04_Pivots

### Purpose

The exploratory layer — the sheet for questions the fixed KPI tables don't anticipate. Where Sheet 3 is deliberately rigid, this sheet is deliberately flexible.

### The three pivots

All three read from `tbl_Incidents` — entering the table name in the PivotTable dialog's Table/Range box is where the Sheet 1 naming pays off. Pivots on a shared sheet need a few blank rows between them; they refuse to overlap when they expand.

**Pivot 1 — Incident type by site.** Incident_Type to Rows, Site to Columns, Incident_ID to Values (count). Checkpoint: grand total **500**, with row totals of Environmental 85, First Aid 76, Hazard Observation 75, Near Miss 74, Property Damage 68, Medical Treatment 65, Lost Time Injury 57.

**Pivot 2 — Primary cause with severity overlay.** Primary_Cause to Rows; Incident_ID (count) and Lost_Time_Days (sum) both to Values; sorted descending on lost days. This pairing is the point of the pivot: frequency alone misdirects intervention effort. In this data, manual handling produces the most incidents (65) but ranks third on severity (120 lost days), behind vehicle interaction (55 incidents, 131 days) and chemical contact (52 incidents, 128 days). Ranking by count and ranking by consequence produce different priorities, and the pivot shows both.

**Pivot 3 — Employment type.** Employment_Type to Rows; Incident_ID, TRIFR_Contribution, and LTI_Flag to Values — summing a 0/1 flag counts the 1s. Checkpoint: Direct Employee 246 / 60 / 28, Labour Hire 145 / 39 / 17, Contractor 109 / 23 / 12. The totals (500 / 122 / 57) cross-check against Sheet 3's annual sums, which is the workbook's internal consistency showing.

**A limitation stated deliberately: this pivot presents counts, not rates.** Exposure hours in the register are site-level, not split by employment category, so a contractor TRIFR cannot legitimately be calculated from this data. Direct employees logging the most incidents means nothing without their share of hours worked. Publishing a rate I couldn't defend would be worse than publishing none — and contractor exposure data being unreliable or absent is one of the most common real-world problems in HSE reporting, so the limitation is worth naming rather than hiding.

### Slicers

Year and Site slicers inserted from Pivot 1 (PivotTable Analyze → Insert Slicer), then wired to all three pivots via right-click → **Report Connections**, ticking every pivot. That wiring step is the one most builds miss: an unconnected slicer filters one pivot and silently ignores the rest, which on a dashboard produces numbers that quietly disagree with each other.

---

## Sheet 5 — 05_Dashboard

### Purpose

The executive view. One screen answering three questions: how are we performing, which sites are driving it, and what sits underneath the numbers. Nothing on this sheet calculates anything — every element reads from Sheets 3 and 4, and no value is ever typed in as a static number.

### KPI cards

Four cells linked directly to the KPI sheet's 2024 row, with labels above and large bold formatting:

```text
TRIFR 2024:        ='03_KPI_Summary'!E6     → 6.73
LTIFR 2024:        ='03_KPI_Summary'!F6     → 1.68
Recordables 2024:  ='03_KPI_Summary'!B6     → 20
LTIs 2024:         ='03_KPI_Summary'!C6     → 5
```

Traffic-light conditional formatting on the two rate cards (Home → Conditional Formatting → Highlight Cells Rules): TRIFR green below 8, yellow between 8 and 10, red above 10; LTIFR thresholds at 3 and 5. I set those bands to discriminate within this dataset's actual range (site TRIFRs run 7.09 to 10.16) — a traffic light that shows green for everything is decoration, not signal. In production these thresholds would come from corporate targets or DMIRS benchmarking rather than the data's own spread.

### Charts

**TRIFR by Site** (clustered column) and **TRIFR & LTIFR Trend** — both built from Sheet 3's tables. A construction note from the build: selecting labels and values as a non-adjacent range (Ctrl-select) is fragile, and if the second selection doesn't register, the chart arrives empty with the labels swallowed into the title. The reliable sequence is to chart the numeric columns alone, then attach the labels afterwards via right-click → **Select Data → Horizontal (Category) Axis Labels → Edit**. That repair route also fixes any chart whose selection went wrong, without rebuilding it.

**The interactive chart** is a PivotChart created from Pivot 1 (PivotTable Analyze → PivotChart) and moved to the dashboard, alongside the two slicers cut and pasted across from Sheet 4 — slicers keep their pivot connections regardless of which sheet they live on.

### Design decision — two layers, on purpose

The formula-driven elements (KPI cards, site chart, trend chart) do **not** respond to the slicers; they report fixed, all-period performance from Sheet 3's SUMIFS cells. Only the PivotChart responds. That split is intentional: executive reference figures stay stable no matter what filtering a user does, while the exploratory layer stays fully interactive. The two kinds of chart answer different questions and shouldn't be confused for one another — it's the difference between formula-driven and pivot-cache-driven reporting, and the dashboard uses both knowingly.

---

## Outcome

Five sheets, built in dependency order, each validated before the next was started. The workbook takes a 500-row incident register from raw CSV to executive dashboard with every figure traceable to source: exposure deduplicated to 144 site-months totalling 14,492,423 hours, TRIFR and LTIFR reconciled to the decimal against an independent SQL build of the same data, and the audit trail documented rather than assumed. The framework is repeatable — refresh the Power Query connection with new data and the workbook recalculates end to end.
