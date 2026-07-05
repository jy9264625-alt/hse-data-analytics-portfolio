import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import os

def load_and_audit_data(filepath):
    df = pd.read_csv(filepath)
    print("=" * 60)
    print("SECTION 1: DATA LOAD AND QUALITY AUDIT")
    print("=" * 60)
    print(f"Rows: {df.shape[0]}, Columns: {df.shape[1]}")
    duplicates = df["Incident_ID"].duplicated().sum()
    print(f"Duplicate Incident_ID values: {duplicates}")
    null_hours = df[["Hours_Worked_That_Day", "Total_Site_Hours_Month"]].isnull().sum()
    print("Nulls in exposure hour fields:")
    print(null_hours.to_string())
    print()
    return df

def calculate_annual_rates(df):
    annual = df.groupby("Year").agg(
        total_incidents=("Incident_ID", "count"),
        trifr_incidents=("TRIFR_Contribution", "sum"),
        lost_time_incidents=("Lost_Time_Days", lambda x: (x > 0).sum()),
        total_hours=("Total_Site_Hours_Month", "sum"),
    ).reset_index()
    annual["TRIFR"] = round(annual["trifr_incidents"] / annual["total_hours"] * 1000000, 2)
    annual["LTIFR"] = round(annual["lost_time_incidents"] / annual["total_hours"] * 1000000, 2)
    return annual

def calculate_site_rates(df):
    site = df.groupby("Site").agg(
        total_incidents=("Incident_ID", "count"),
        trifr_incidents=("TRIFR_Contribution", "sum"),
        total_hours=("Total_Site_Hours_Month", "sum"),
    ).reset_index()
    site["TRIFR"] = round(site["trifr_incidents"] / site["total_hours"] * 1000000, 2)
    return site.sort_values("TRIFR", ascending=False)

def plot_trifr_trend_by_site(df, output_dir):
    site_year = df.groupby(["Year", "Site"]).agg(
        trifr_incidents=("TRIFR_Contribution", "sum"),
        total_hours=("Total_Site_Hours_Month", "sum"),
    ).reset_index()
    site_year["TRIFR"] = site_year["trifr_incidents"] / site_year["total_hours"] * 1000000
    plt.figure(figsize=(10, 6))
    sns.lineplot(data=site_year, x="Year", y="TRIFR", hue="Site", marker="o")
    plt.title("Annual TRIFR Trend by Site")
    plt.ylabel("TRIFR (per million hours worked)")
    plt.xticks(site_year["Year"].unique())
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, "01_trifr_trend_by_site.png"), dpi=150)
    plt.close()

def plot_cause_site_heatmap(df, output_dir):
    cross = pd.crosstab(df["Primary_Cause"], df["Site"])
    plt.figure(figsize=(10, 8))
    sns.heatmap(cross, annot=True, fmt="d", cmap="YlOrRd", cbar_kws={"label": "Incident Count"})
    plt.title("Incident Count by Primary Cause and Site")
    plt.ylabel("Primary Cause")
    plt.xlabel("Site")
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, "02_cause_site_heatmap.png"), dpi=150)
    plt.close()

def plot_contractor_vs_direct(df, output_dir):
    emp = df.groupby("Employment_Type").agg(
        trifr_incidents=("TRIFR_Contribution", "sum"),
        total_hours=("Total_Site_Hours_Month", "sum"),
    ).reset_index()
    emp["TRIFR"] = emp["trifr_incidents"] / emp["total_hours"] * 1000000
    plt.figure(figsize=(8, 6))
    sns.barplot(data=emp, x="Employment_Type", y="TRIFR", hue="Employment_Type", legend=False)
    plt.title("TRIFR: Contractor vs Direct Employee")
    plt.ylabel("TRIFR (per million hours worked)")
    plt.xlabel("")
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, "03_contractor_vs_direct.png"), dpi=150)
    plt.close()

def plot_corrective_action_status(df, output_dir):
    status_counts = df["Corrective_Action_Status"].value_counts()
    plt.figure(figsize=(8, 6))
    status_counts.plot(kind="bar", color=sns.color_palette("Set2"))
    plt.title("Corrective Action Close-Out Status")
    plt.ylabel("Number of Incidents")
    plt.xlabel("")
    plt.xticks(rotation=0)
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, "04_corrective_action_status.png"), dpi=150)
    plt.close()

def plot_lost_time_distribution(df, output_dir):
    lt = df[df["Lost_Time_Days"] > 0]["Lost_Time_Days"]
    plt.figure(figsize=(8, 6))
    sns.histplot(lt, bins=15, color="#4C72B0")
    plt.title("Distribution of Lost Time Days (Lost Time Incidents Only)")
    plt.xlabel("Lost Time Days")
    plt.ylabel("Number of Incidents")
    plt.tight_layout()
    plt.savefig(os.path.join(output_dir, "05_lost_time_distribution.png"), dpi=150)
    plt.close()

def plot_leading_lagging_ratio(df, output_dir):
    yearly = df.groupby("Year").agg(
        hpi_reports=("High_Potential_Incident", "sum"),
        trifr_incidents=("TRIFR_Contribution", "sum"),
        total_hours=("Total_Site_Hours_Month", "sum"),
    ).reset_index()
    yearly["TRIFR"] = yearly["trifr_incidents"] / yearly["total_hours"] * 1000000
    fig, ax1 = plt.subplots(figsize=(9, 6))
    ax2 = ax1.twinx()
    ax1.bar(yearly["Year"], yearly["hpi_reports"], color="#55A868", alpha=0.7, label="HPI Reports")
    ax2.plot(yearly["Year"], yearly["TRIFR"], color="#C44E52", marker="o", linewidth=2, label="TRIFR")
    ax1.set_xlabel("Year")
    ax1.set_ylabel("High Potential Incident Reports", color="#55A868")
    ax2.set_ylabel("TRIFR (per million hours)", color="#C44E52")
    ax1.set_xticks(yearly["Year"])
    plt.title("Leading Indicator (HPI Reports) vs Lagging Indicator (TRIFR)")
    fig.tight_layout()
    plt.savefig(os.path.join(output_dir, "06_leading_lagging_ratio.png"), dpi=150)
    plt.close()

def export_summary_workbook(df, annual, site, output_dir):
    filepath = os.path.join(output_dir, "HSE_Summary_Report.xlsx")
    with pd.ExcelWriter(filepath, engine="openpyxl") as writer:
        df.to_excel(writer, sheet_name="Raw_Data", index=False)
        annual.to_excel(writer, sheet_name="Annual_KPIs", index=False)
        site.to_excel(writer, sheet_name="Site_KPIs", index=False)
        status = df["Corrective_Action_Status"].value_counts().reset_index()
        status.columns = ["Status", "Count"]
        status.to_excel(writer, sheet_name="Corrective_Actions", index=False)
        quality = pd.DataFrame({
            "Check": ["Total Rows", "Duplicate Incident_IDs", "Null Hours_Worked_That_Day", "Null Total_Site_Hours_Month"],
            "Result": [
                len(df),
                df["Incident_ID"].duplicated().sum(),
                df["Hours_Worked_That_Day"].isnull().sum(),
                df["Total_Site_Hours_Month"].isnull().sum(),
            ],
        })
        quality.to_excel(writer, sheet_name="Data_Quality", index=False)
    print(f"Excel workbook exported to: {filepath}")

def print_reconciliation(annual):
    print("=" * 60)
    print("SECTION 5: RECONCILIATION")
    print("=" * 60)
    print(annual[["Year", "total_incidents", "TRIFR", "LTIFR"]].to_string(index=False))

def main():
    output_dir = "outputs"
    os.makedirs(output_dir, exist_ok=True)
    df = load_and_audit_data("SQL_Project_HSE_Incident_Register.csv")
    annual = calculate_annual_rates(df)
    site = calculate_site_rates(df)
    print("=" * 60)
    print("SECTION 2: TRIFR / LTIFR CALCULATIONS")
    print("=" * 60)
    print(annual[["Year", "total_incidents", "TRIFR", "LTIFR"]].to_string(index=False))
    print(site[["Site", "total_incidents", "TRIFR"]].to_string(index=False))
    print()
    print("SECTION 3: GENERATING VISUALISATIONS")
    plot_trifr_trend_by_site(df, output_dir)
    print("Saved: 01_trifr_trend_by_site.png")
    plot_cause_site_heatmap(df, output_dir)
    print("Saved: 02_cause_site_heatmap.png")
    plot_contractor_vs_direct(df, output_dir)
    print("Saved: 03_contractor_vs_direct.png")
    plot_corrective_action_status(df, output_dir)
    print("Saved: 04_corrective_action_status.png")
    plot_lost_time_distribution(df, output_dir)
    print("Saved: 05_lost_time_distribution.png")
    plot_leading_lagging_ratio(df, output_dir)
    print("Saved: 06_leading_lagging_ratio.png")
    print()
    print("SECTION 4: EXCEL EXPORT")
    export_summary_workbook(df, annual, site, output_dir)
    print()
    print_reconciliation(annual)

if __name__ == "__main__":
    main()
