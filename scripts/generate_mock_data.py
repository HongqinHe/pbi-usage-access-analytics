"""
Generate synthetic raw data that mimics what the Power BI Admin REST APIs,
Azure AD (Entra ID) and an HR system would land in the raw layer.

Everything is fictional (example.com). The data is deterministic (fixed seed)
so `dbt build` produces the same results on every machine and in CI.

Deliberately includes the messy things real data has, so the dbt models and
tests have something to handle:
  * duplicate activity events (overlapping re-runs)
  * blank ('') dataset / report ids instead of NULL
  * a historical CSV backfill (DATA_SOURCE = 'HISTORICAL_CSV') before go-live
  * permission snapshots that only start at pipeline go-live, with a few
    failed (missing) runs -> exercises the as-of fallback
  * auto-created "Usage Metrics" datasets and app workspaces -> scoped out
  * a report-only workspace whose reports point at a dataset elsewhere
  * people who change department mid-period -> SCD Type 2
  * users who get access through two groups -> multi-group double counting
  * service / guest accounts that are not in HR

Usage:
    python scripts/generate_mock_data.py            # writes data/raw/*.csv
"""

from __future__ import annotations

import csv
import json
import random
from datetime import date, datetime, timedelta
from pathlib import Path

SEED = 42
START = date(2026, 9, 1)          # first day of activity (historical CSV)
GO_LIVE = date(2026, 9, 15)       # pipeline go-live: API ingest + snapshots start
END = date(2026, 10, 31)          # last day of activity
FAILED_RUNS = {date(2026, 9, 22), date(2026, 10, 6), date(2026, 10, 7)}

OUT = Path(__file__).resolve().parents[1] / "data" / "raw"
rng = random.Random(SEED)


def days(start: date, end: date):
    d = start
    while d <= end:
        yield d
        d += timedelta(days=1)


def write(name: str, rows: list[dict]) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{name}.csv"
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print(f"  {name:<32} {len(rows):>7,} rows")


# --------------------------------------------------------------------------
# People (HR) -- with mid-period department changes
# --------------------------------------------------------------------------
FIRST = ["Ava", "Ben", "Chloe", "Daniel", "Emma", "Felix", "Grace", "Henry",
         "Iris", "Jack", "Kara", "Liam", "Maya", "Noah", "Olivia", "Peter",
         "Quinn", "Ruby", "Sam", "Tara", "Umar", "Vera", "Will", "Xena",
         "Yusuf", "Zoe", "Aiden", "Bella", "Caleb", "Diana"]
LAST = ["Chen", "Garcia", "Patel", "Kim", "Nguyen", "Smith", "Lopez", "Wang",
        "Brown", "Singh"]
DEPTS = {
    "Finance": ["Financial Analyst", "Senior Accountant", "Finance Manager"],
    "FP&A": ["FP&A Analyst", "Senior FP&A Analyst", "FP&A Manager"],
    "Supply Chain": ["Supply Planner", "Logistics Analyst"],
    "Operations": ["Operations Analyst", "Operations Manager"],
    "HR": ["HR Business Partner", "People Analyst"],
    "IT": ["BI Developer", "Platform Engineer"],
    "Sales": ["Account Executive", "Sales Ops Analyst"],
    "Executive": ["VP Finance", "CFO"],
}
dept_weights = {"Finance": 12, "FP&A": 8, "Supply Chain": 6, "Operations": 6,
                "HR": 4, "IT": 5, "Sales": 6, "Executive": 3}

employees = []
i = 0
for dept, n in dept_weights.items():
    for _ in range(n):
        i += 1
        first, last = FIRST[i % len(FIRST)], LAST[(i * 7) % len(LAST)]
        employees.append({
            "upn": f"{first.lower()}.{last.lower()}{i:02d}@example.com",
            "name": f"{first} {last}",
            "department": dept,
            "job_title": rng.choice(DEPTS[dept]),
            # persona drives how often they use what they have access to
            "persona": rng.choices(["power", "regular", "light", "dormant"],
                                   weights=[2, 4, 3, 2])[0],
        })

# 5 people transfer department during the period (SCD2 material)
transfers = {}
for emp in rng.sample([e for e in employees if e["department"] in
                       ("Finance", "FP&A", "Operations")], 5):
    new_dept = rng.choice([d for d in ("Finance", "FP&A", "Operations",
                                       "Supply Chain") if d != emp["department"]])
    transfers[emp["upn"]] = (START + timedelta(days=rng.randint(15, 45)),
                             new_dept, rng.choice(DEPTS[new_dept]))

non_hr_accounts = ["svc-refresh@example.com", "svc-etl@example.com",
                   "partner.guest@external.example.org"]

hr_rows = []
for d in days(START, END):
    for e in employees:
        dept, title = e["department"], e["job_title"]
        if e["upn"] in transfers and d >= transfers[e["upn"]][0]:
            _, dept, title = transfers[e["upn"]]
        hr_rows.append({"extract_date": d.isoformat(), "employee_upn": e["upn"],
                        "employee_name": e["name"], "department": dept,
                        "job_title": title})

# --------------------------------------------------------------------------
# Workspaces, apps, semantic models (datasets)
# --------------------------------------------------------------------------
workspaces = [
    ("ws-01", "Finance - OpEx Reporting"),
    ("ws-02", "Finance - O&M Reporting"),
    ("ws-03", "FP&A Planning"),
    ("ws-04", "Supply Chain Operations"),
    ("ws-05", "HR People Analytics"),
    ("ws-06", "IT BI Platform"),
    ("ws-07", "Sales Performance"),      # has an app -> App layer owns it
    ("ws-08", "Executive Dashboards"),   # has an app -> App layer owns it
    ("ws-09", "Finance Report Hub"),     # report-only: no datasets of its own
]
workspace_rows = [{"workspace_id": w, "workspace_name": n, "workspace_type": "Workspace",
                   "state": "Active"} for w, n in workspaces]
app_rows = [
    {"workspace_id": "ws-07", "app_id": "app-701", "app_name": "Sales Performance App"},
    {"workspace_id": "ws-08", "app_id": "app-801", "app_name": "Executive Dashboards App"},
]

datasets = [
    ("ds-101", "ws-01", "OpEx Semantic Model"),
    ("ds-102", "ws-01", "OpEx Headcount Model"),
    ("ds-103", "ws-01", "Report Usage Metrics Model"),   # auto-created noise
    ("ds-201", "ws-02", "O&M Semantic Model"),
    ("ds-301", "ws-03", "Plan vs Actual Model"),
    ("ds-302", "ws-03", "Forecast Model"),
    ("ds-401", "ws-04", "Inventory Model"),
    ("ds-402", "ws-04", "Report Usage Metrics Model"),   # auto-created noise
    ("ds-501", "ws-05", "Workforce Model"),
    ("ds-601", "ws-06", "BI Usage Model"),
    ("ds-701", "ws-07", "Pipeline Model"),
    ("ds-801", "ws-08", "Executive KPI Model"),
]
dataset_rows = [{"dataset_id": d, "workspace_id": w, "dataset_name": n,
                 "configured_by": "svc-refresh@example.com"} for d, w, n in datasets]

# reports: report-only hub points at the OpEx model in ws-01
reports = {
    "ws-01": [("rp-1011", "ds-101"), ("rp-1012", "ds-101"), ("rp-1021", "ds-102"),
              ("rp-1031", "ds-103")],
    "ws-02": [("rp-2011", "ds-201")],
    "ws-03": [("rp-3011", "ds-301"), ("rp-3021", "ds-302")],
    "ws-04": [("rp-4011", "ds-401"), ("rp-4021", "ds-402")],
    "ws-05": [("rp-5011", "ds-501")],
    "ws-06": [("rp-6011", "ds-601")],
    "ws-07": [("rp-7011", "ds-701")],
    "ws-08": [("rp-8011", "ds-801")],
    "ws-09": [("rp-9011", "ds-101"), ("rp-9012", "ds-201")],   # cross-workspace
}

# --------------------------------------------------------------------------
# Azure AD groups -- membership changes over time (weekly snapshots)
# --------------------------------------------------------------------------
def members(*depts):
    return [e["upn"] for e in employees if e["department"] in depts]

groups = {
    "grp-finance-readers": ("g-01", members("Finance", "Executive")),
    "grp-fpa-analysts": ("g-02", members("FP&A")),
    "grp-finance-all": ("g-03", members("Finance", "FP&A")),   # overlaps g-01/g-02
    "grp-supplychain-users": ("g-04", members("Supply Chain", "Operations")),
    "grp-hr-analytics": ("g-05", members("HR")),
    "grp-bi-admins": ("g-06", members("IT")),
    "grp-sales-users": ("g-07", members("Sales")),
    "grp-exec-viewers": ("g-08", members("Executive")),
    "grp-report-hub-viewers": ("g-09", members("Operations", "Finance")),
}
# a few people are added to a group part-way through
late_joiners = {u: START + timedelta(days=rng.randint(20, 50))
                for u in rng.sample(members("Operations", "Supply Chain"), 4)}

aad_rows = []
for d in days(START, END):
    if d.weekday() != 0 and d != START:      # weekly snapshot (Mondays) + day 1
        continue
    for gname, (gid, mlist) in groups.items():
        for upn in mlist:
            if gname == "grp-report-hub-viewers" and upn in late_joiners and d < late_joiners[upn]:
                continue
            aad_rows.append({"snapshot_date": d.isoformat(), "group_id": gid,
                             "group_name": gname, "member_upn": upn.upper() if rng.random() < 0.05 else upn})
    # one late joiner also lands in supply chain group again (no-op) -> fine

# --------------------------------------------------------------------------
# Permission snapshots (one per successful daily pipeline run from go-live)
#   scope_level = 'workspace' rows: workspace role membership (dataset_id blank)
#   scope_level = 'dataset'   rows: effective dataset access
# --------------------------------------------------------------------------
ws_roles = {   # workspace -> list of (principal_type, principal, role)
    "ws-01": [("Group", "grp-finance-readers", "Viewer"), ("Group", "grp-finance-all", "Viewer"),
              ("Group", "grp-bi-admins", "Admin")],
    "ws-02": [("Group", "grp-finance-readers", "Viewer"), ("Group", "grp-bi-admins", "Admin")],
    "ws-03": [("Group", "grp-fpa-analysts", "Contributor"), ("Group", "grp-finance-all", "Viewer")],
    "ws-04": [("Group", "grp-supplychain-users", "Viewer")],
    "ws-05": [("Group", "grp-hr-analytics", "Member")],
    "ws-06": [("Group", "grp-bi-admins", "Admin")],
    "ws-07": [("Group", "grp-sales-users", "Viewer")],
    "ws-08": [("Group", "grp-exec-viewers", "Viewer")],
    "ws-09": [("Group", "grp-report-hub-viewers", "Viewer")],
}
direct_grants = [   # (dataset, user, granted_from)
    ("ds-101", members("Operations")[0], GO_LIVE),
    ("ds-301", members("Supply Chain")[0], date(2026, 10, 1)),   # new grant mid-period
    ("ds-501", "partner.guest@external.example.org", GO_LIVE),
    ("ds-601", "svc-etl@example.com", GO_LIVE),
]
group_ids = {g: gid for g, (gid, _) in groups.items()}

access_rows = []
run_no = 0
for d in days(GO_LIVE, END):
    if d in FAILED_RUNS:
        continue
    run_no += 1
    run_id = f"run-{run_no:04d}"
    for ws, roles in ws_roles.items():
        for ptype, pname, role in roles:
            base = {"snapshot_date": d.isoformat(), "run_id": run_id, "workspace_id": ws,
                    "principal_type": ptype, "principal_id": group_ids[pname],
                    "principal_name": pname, "access_right": role}
            access_rows.append({**base, "dataset_id": "", "scope_level": "workspace",
                                "access_source": "WorkspaceRole"})
            for ds, dws, _ in datasets:
                if dws == ws:
                    access_rows.append({**base, "dataset_id": ds, "scope_level": "dataset",
                                        "access_source": "WorkspaceRole"})
    for ds, upn, since in direct_grants:
        if d >= since:
            ws = next(w for x, w, _ in datasets if x == ds)
            access_rows.append({"snapshot_date": d.isoformat(), "run_id": run_id,
                                "workspace_id": ws, "principal_type": "User",
                                "principal_id": upn, "principal_name": upn,
                                "access_right": "Read", "dataset_id": ds,
                                "scope_level": "dataset", "access_source": "DatasetDirectAccess"})

# --------------------------------------------------------------------------
# Activity events
# --------------------------------------------------------------------------
persona_p = {"power": 0.85, "regular": 0.45, "light": 0.15, "dormant": 0.0}

# who can reach which workspace (from groups) -- used only to make activity realistic
ws_users: dict[str, set[str]] = {ws: set() for ws, _ in workspaces}
for ws, roles in ws_roles.items():
    for _, g, _ in roles:
        ws_users[ws].update(groups[g][1])
persona = {e["upn"]: e["persona"] for e in employees}

dataset_ops = ["ViewReport", "ViewReport", "ViewReport", "ViewDashboard",
               "ExportReport", "AnalyzeInExcel"]
workspace_ops = ["RequestCopilot", "ConnectFromExternalApplication"]

events = []
seq = 0
for d in days(START, END):
    if d.weekday() >= 5 and rng.random() < 0.7:     # quiet weekends
        continue
    for ws, _ in workspaces:
        for upn in sorted(ws_users[ws]):
            p = persona_p[persona.get(upn, "light")]
            if rng.random() > p * (0.6 if ws in ("ws-07", "ws-08") else 0.35):
                continue
            for _ in range(rng.randint(1, 4)):
                seq += 1
                ts = datetime(d.year, d.month, d.day, rng.randint(13, 23),
                              rng.randint(0, 59), rng.randint(0, 59))
                if rng.random() < 0.12:
                    op, rp, ds = rng.choice(workspace_ops), "", ""
                else:
                    op = rng.choice(dataset_ops)
                    rp, ds = rng.choice(reports[ws])
                events.append({
                    "event_id": f"evt-{seq:06d}",
                    "event_time": ts.isoformat(sep=" "),
                    "workspace_id": ws, "dataset_id": ds, "report_id": rp,
                    "actor_upn": upn, "operation": op,
                })
    # service account + guest activity
    if d >= GO_LIVE:
        seq += 1
        events.append({"event_id": f"evt-{seq:06d}",
                       "event_time": f"{d.isoformat()} 06:00:00", "workspace_id": "ws-06",
                       "dataset_id": "ds-601", "report_id": "",
                       "actor_upn": "svc-etl@example.com", "operation": "ConnectFromExternalApplication"})
        if rng.random() < 0.3:
            seq += 1
            events.append({"event_id": f"evt-{seq:06d}",
                           "event_time": f"{d.isoformat()} 15:30:00", "workspace_id": "ws-05",
                           "dataset_id": "ds-501", "report_id": "rp-5011",
                           "actor_upn": "partner.guest@external.example.org",
                           "operation": "ViewReport"})

activity_rows = []
for e in events:
    d = date.fromisoformat(e["event_time"][:10])
    is_hist = d < GO_LIVE
    row = {
        # the API's own Id is NOT reliable -> historical CSV has none, and
        # a few API ids are reused (we never dedup on it)
        "event_id": "" if is_hist else e["event_id"],
        "event_time": e["event_time"],
        "workspace_id": e["workspace_id"],
        "dataset_id": e["dataset_id"],
        "report_id": e["report_id"],
        "actor_upn": e["actor_upn"],
        "operation": e["operation"],
        "data_source": "HISTORICAL_CSV" if is_hist else "API",
        "loaded_at": (datetime(d.year, d.month, d.day) + timedelta(days=1, hours=2)).isoformat(sep=" "),
        "raw_event": json.dumps({"Activity": e["operation"], "UserId": e["actor_upn"],
                                 "WorkSpaceId": e["workspace_id"],
                                 "DatasetId": e["dataset_id"] or None}),
    }
    activity_rows.append(row)
    # ~3% duplicated by an overlapping re-run, loaded later
    if not is_hist and rng.random() < 0.03:
        activity_rows.append({**row, "loaded_at": (datetime.fromisoformat(row["loaded_at"])
                                                   + timedelta(days=1)).isoformat(sep=" ")})

# reuse a handful of API ids for *different* events -> proves Id isn't unique
api_rows = [r for r in activity_rows if r["event_id"]]
for a, b in zip(rng.sample(api_rows, 10), rng.sample(api_rows, 10)):
    b["event_id"] = a["event_id"]

rng.shuffle(activity_rows)

if __name__ == "__main__":
    print(f"Writing mock raw data to {OUT}")
    write("pbi_workspaces", workspace_rows)
    write("pbi_workspace_apps", app_rows)
    write("pbi_semantic_models", dataset_rows)
    write("pbi_access_snapshots", access_rows)
    write("pbi_activity_events", activity_rows)
    write("aad_group_member_snapshots", aad_rows)
    write("hr_employee_extracts", hr_rows)
    print("Done.")
