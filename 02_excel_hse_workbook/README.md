# Excel HSE Reporting Workbook

## The Problem

Most HSE reporting I've been involved with lives or dies in Excel, whatever the corporate system of record happens to be. The recurring problem isn't building a chart — it's getting from a raw incident register to frequency rates you'd be willing to put in front of a general manager, without quietly inflating the exposure denominator or losing track of how a number was derived. This workbook is my Excel answer to that problem: the same 500-row incident register I analysed in BigQuery (Project 1), rebuilt as a five-sheet reporting workbook where every figure can be traced back to source and reconciled against the SQL results to the decimal.

## What Was Built

The workbook runs in a deliberate sequence. Sheet 1 holds the register itself, imported through Power Query rather than opened directly, with date parsing verified against the day-first Australian format and three helper columns added for downstream analysis. Sheet 2 collapses the register to a deduplicated exposure table — one row per site per month, 144 rows in total — because exposure hours repeat on every incident row and summing them raw would overstate the denominator several times over. Sheet 3 calculates TRIFR and LTIFR by year and by site using SUMIFS against the one-million-hour denominator used by Safe Work Australia and DMIRS. Sheet 4 carries three PivotTables with connected slicers for exploratory work: incident type by site, primary cause paired with lost-time severity, and an employment type breakdown. Sheet 5 is the executive dashboard — KPI cards with traffic-light formatting, a site comparison chart, a three-year trend, and a slicer-driven PivotChart.

The dashboard exists to answer three questions on one screen: how are we performing, which sites are driving it, and what's underneath the numbers. The data itself gives those questions teeth. The 2023 result shows TRIFR nearly flat against 2022 (8.93 vs 8.78) while LTIFR climbed from 3.96 to 5.08 — incident frequency held steady but severity worsened, which is a different management conversation than either number suggests alone. The cause analysis shows the same principle: manual handling generates the most incidents, but vehicle interaction and chemical contact cost more lost days. Ranking causes by frequency alone would put the intervention effort in the wrong place.

## Technical Notes

**Exposure deduplication.** The register carries a monthly exposure figure on every incident row, and those figures don't always agree — 128 of the 144 site-month combinations contain conflicting values across their rows. I resolved this by taking the maximum value per site-month with MAXIFS, on the basis that the fullest reported figure is the least likely to understate exposure. That's the same assumption my SQL build documents in its Section 3 CTE, which matters: the two projects apply one methodology, and the deduplicated total of 14,492,423 hours reconciles exactly between BigQuery, Excel, and an independent check against the source file. I'd rather publish a stated assumption than a silent one.

**SUMIFS over a PivotTable for the KPI sheet.** PivotTables reshape themselves on refresh and field changes, which breaks anything referencing their cells. The KPI sheet feeds the dashboard's cards and charts, so it needed a fixed layout — formulas give me that, plus full control over the calculation logic. The pivots live on their own sheet where reshaping does no damage.

**LET.** The KPI sheet includes one measure built with LET as a working example. It declares the recordable count and exposure hours as named variables and computes the rate from them in a single cell — no helper cells, each SUMIFS evaluated once, and a formula the next person can actually read. It returns the same result as the conventional version beside it, which was the point of building both.

**Referencing convention.** I standardised on plain cell references after structured references caused repeated formula failures in my environment early in the build. Less elegant, but every formula in the workbook can be audited by anyone who reads Excel, and consistency won out over sophistication.

**Dashboard design.** The KPI cards and summary charts are formula-driven and deliberately do not respond to the slicers — they report fixed, all-period performance. The PivotChart does respond. That split is intentional: executive reference figures stay stable while the exploratory layer stays interactive, and the two shouldn't be confused for one another. The traffic-light thresholds on the cards are values I set to discriminate within this dataset's range; in production they'd come from corporate targets or DMIRS benchmarking.

**Employment type is counts, not rates.** Exposure hours in this register are recorded at site level, not by employment type, so a contractor TRIFR can't legitimately be calculated from this data. Direct employees log the most incidents, but without their share of hours worked that comparison means nothing. The pivot presents counts and says so — publishing a rate I couldn't defend would be worse than publishing none.

## How to Use It

Open the workbook and enable data connections if prompted — the register loads through Power Query and can be refreshed if the source CSV changes. The KPI sheet holds the headline rates; the dashboard sheet is the intended entry point for anyone reviewing performance. The Year and Site slicers filter the PivotChart and the pivot sheet behind it, but not the formula-driven cards and charts, for the reasons above. Sheet order mirrors build order, so reading the workbook left to right is also reading the methodology.
