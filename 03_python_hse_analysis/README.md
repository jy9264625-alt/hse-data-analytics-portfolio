# Python HSE Analysis

## The Problem

BigQuery and Excel both answer the TRIFR/LTIFR question well, but neither is built for exploratory statistical work or for producing publication-quality charts without manual formatting. I wanted a third, independent path to the same numbers — one that could also surface patterns that don't show up cleanly in a pivot table, like the shape of the lost-time-days distribution or how leading and lagging indicators move against each other over time. Python is where that kind of analysis belongs.

## What Was Built

`hse_analysis.py` runs the full pipeline in one pass: it loads the 500-row incident register, runs a data quality audit, calculates annual and site-level TRIFR/LTIFR, generates six charts, and exports a five-sheet Excel workbook. Six visualisations, each chosen because it answers a specific operational question rather than because it looked interesting in a gallery:

- TRIFR trend by site — is the rate improving, and where specifically
- Cause × site heatmap — is a given cause a site-specific problem or systemic across the operation
- Contractor vs direct employee TRIFR — the comparison that gets challenged first in any review
- Corrective action close-out status — a lagging indicator on the system itself, not just the incidents
- Lost time days distribution — where the compensation cost actually lives, in the long tail
- Leading vs lagging indicator ratio — HPI reports against TRIFR, by year

## Technical Notes

Seaborn over plain matplotlib for the heatmap specifically — `sns.heatmap()` handles colour scaling and cell annotation natively, and doing that by hand in matplotlib is a lot of code for a worse result. Everywhere else I used matplotlib directly, since seaborn's real benefit is statistical plotting, not styling for its own sake.

TRIFR here uses the 1,000,000-hour denominator, consistent with the SQL and Excel builds — not the 200,000-hour figure some US frameworks use. Getting this wrong doesn't just shift a decimal point; it produces a number roughly five times off from what a WA site would report.

The contractor vs direct employee chart is only as good as the underlying exposure hours, and contractor hours on multi-employer sites are notoriously unreliable — workers moving between principal contractor and subcontractor rosters mid-shift, hours logged against the wrong entity. That caveat belongs in the README, not buried in a code comment.

## How to Use It

Requires `pandas`, `matplotlib`, `seaborn`, and `openpyxl`. Place `SQL_Project_HSE_Incident_Register.csv` in the same folder as the script, then run:

python hse_analysis.py

Charts and the Excel workbook are written to the `outputs/` folder. The script prints a reconciliation block at the end — TRIFR/LTIFR by year — to check against the BigQuery and Excel figures before anything gets committed.
