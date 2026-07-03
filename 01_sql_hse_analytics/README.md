# 01 — SQL: HSE Incident Analytics (BigQuery)

The question that drove this project was one I had asked on site more times than I can count: what is the register actually telling us, and do we trust the numbers enough to act on them? Incident registers in operational environments accumulate noise — duplicate entries from concurrent data systems, monthly exposure hours that were never reconciled against timekeeping, contractor records coded inconsistently across sites. Before a single rate is calculated, that noise has to be found and accounted for. This project does that work first.

---

## What Was Built

Seven analytical sections in BigQuery Standard SQL, executed against a 500-row incident register spanning three years across five Western Australian sites.

**Section 1 — Data Quality Audit.** Four queries establishing the integrity of the dataset before any rates are calculated. Duplicate detection distinguishes between full duplicates and conflicting records on the same ID — a distinction that matters when you are deciding whether to remove a record or escalate it for review.

**Section 2 — Incident Frequency and Distribution.** Volume by site, year, and incident type. Shift pattern analysis with fatigue cause overlay. Primary cause ranked by severity rather than frequency — because a cause that appears ten times with eight lost days per incident is a different problem from one that appears fifty times with zero. High-potential incident profile including the HPI-to-recordable ratio, which is a more honest indicator of reporting culture than incident count alone.

**Section 3 — Annual and Quarterly TRIFR and LTIFR.** Rate calculations using a 1,000,000-hour denominator — the Australian standard per Safe Work Australia. Exposure hours are deduplicated before summing: a site with three incidents in one month has three rows in the dataset, each carrying the same monthly hours figure. Summing directly would triple-count the exposure and produce a rate that looks correct but is not. The fix is MAX(Total_Site_Hours_Month) per site per month before aggregation.

**Section 4 — Rolling 12-Month TRIFR.** A fixed-calendar TRIFR resets every 1 January. That reset is convenient but misleading for projects that commenced mid-year. The rolling version uses a window function with ROWS BETWEEN 11 PRECEDING AND CURRENT ROW, anchored to month start date and partitioned by site. A months_in_window counter flags partial windows so early-period rates are not benchmarked against a full-year figure.

**Section 5 — Contractor vs Direct Employee Rate Comparison.** The denominator limitation is acknowledged explicitly in the output rather than buried in a footnote: exposure hours in this dataset are not split by employment type, so the rates reflect total site hours rather than workforce-segment-specific hours. Rates are presented with that caveat embedded as a column rather than suppressed. Labour Hire is treated separately from Contractor because the statutory exposure is different — Labour Hire workers operate under the host employer's SWMS and daily supervision.

**Section 6 — Corrective Action and Investigation Close-Out.** Three queries: status summary by site, close-out rate by site and year, and a targeted red list — every high-potential incident with an overdue corrective action, investigator named. The red list is the query you run before a board meeting, not after.

**Section 7 — Executive KPI Rollup.** Five CTEs building toward a single output table: deduplicated hours, incident counts, close-out metrics, assembled KPIs, and an automated performance flag. The LAG window function produces year-on-year TRIFR change. The performance flag evaluates conditions in priority order — a fatality fires before a corrective action backlog, which fires before an elevated TRIFR.

---

## Technical Notes

CTEs were used throughout rather than nested subqueries for one practical reason: when a number looks wrong in a board pack, being able to step into each CTE individually and verify the intermediate result is worth the extra lines. Subqueries compress the logic into something that runs faster to write and slower to debug.

The rolling TRIFR window function was the most technically demanding piece in this project. The date construction using string concatenation and LPAD was necessary because the source data stores Year and Month as separate integer columns. BigQuery requires a properly formatted DATE value to sort months chronologically across year boundaries — without it, the window function produces incorrect results.

SAFE_DIVIDE appears throughout in place of standard division. BigQuery will throw a division-by-zero error on any month with zero exposure hours. SAFE_DIVIDE returns NULL in that case rather than failing the query, which allows the output to continue and flag the gap rather than terminate.

---

## How to Use It

project-e23f1453-5bd2-436f-bcc.HSE_INCIDENT_DATA.incident_log

Each section is self-contained and can be run independently. Copy the section from its opening comment block to the next section header and execute in the BigQuery console. Sections do not depend on prior sections being run — each queries the source table directly.

The reference file `hse_incident_analytics.sql` contains all seven sections with inline documentation.

---

## Standards and References

Rate calculations align to Safe Work Australia — *Work-related Traumatic Injury Fatalities, Australia* methodology. Regulatory context reflects DMIRS Western Australia reporting conventions. Classification of recordable injuries follows the model WHS Regulations definition of notifiable incidents.
