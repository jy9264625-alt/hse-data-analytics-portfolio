# HSE Data Analytics Portfolio

I have spent twenty years in HSE across mining, construction, and government. The gap I kept running into was the distance between raw incident data and a clear picture of what was actually happening on site. Rates were calculated in spreadsheets with hardcoded denominators, near-miss trends were invisible until someone noticed them in a meeting, and corrective action close-out was tracked in a register that nobody queried. These projects are how I closed that gap for myself.

The dataset underpinning all four projects is a 500-row incident register built to mirror the structure of real operational data across five Western Australian sites. It includes the noise that real registers carry: exposure hour figures that conflict within the same reporting month, and a corrective action backlog that accumulates across years. Finding and accounting for that noise is part of the work — the data quality audits in Projects 1 and 2 document what was found and what was ruled out.

---

## Projects

### 01 — SQL (BigQuery)
Seven analytical sections built in BigQuery Standard SQL, progressing from a data quality audit through to a CTE-based executive KPI rollup. The rate calculations use a 1,000,000-hour denominator — the Australian standard per Safe Work Australia — not the 200,000-hour US OSHA convention. The rolling 12-month TRIFR uses a window function with a trailing boundary rather than a fixed calendar reset, which matters when you are reporting across a project that started mid-year.

[View project →](./01_sql_hse_analytics/)

### 02 — Excel
The same register rebuilt as a five-sheet reporting workbook: Power Query import with locale-verified date parsing, a deduplicated exposure table, SUMIFS-driven TRIFR and LTIFR, PivotTable analysis with connected slicers, and an executive dashboard with traffic-light thresholds. The exposure sheet carries the methodology — monthly hours repeat on every incident row and conflict within 128 of the 144 site-month combinations, so they are collapsed with MAXIFS under the same maximum-hours assumption my SQL build documents, and the two projects reconcile to the decimal: 14,492,423 exposure hours in both. The KPI sheet is deliberately formula-based rather than a PivotTable, so the dashboard always reads from a fixed layout that survives refresh and field changes.

[View project →](./02_excel_hse_workbook/)

### 03 — Python
A fully executable script producing six publication-quality visualisations including a cause-by-site heatmap, rolling TRIFR trend lines, and a lead:lag indicator ratio chart. The script exports a five-sheet Excel summary automatically. The seaborn heatmap was chosen over a matplotlib grid because the colour scaling handles sparse cells — sites with low incident volume in a given cause category — without distorting the visual interpretation.

[View project →](./03_python_hse_analysis/)

### 04 — Power BI
A four-page interactive report with a full DAX measure library covering TRIFR, LTIFR, Severity Index, Lead:Lag Ratio, and year-on-year comparisons using SAMEPERIODLASTYEAR. The report requires a dedicated Dim_Date table — time intelligence functions in DAX do not operate correctly against a date column in the fact table.

[View project →](./04_powerbi_hse_dashboard/)

---

## Standards and References

Rate calculations align to Safe Work Australia guidance and ISO 45001 requirements. Regulatory context reflects DMIRS (Department of Mines, Industry Regulation and Safety) Western Australia reporting conventions.
