"""Vyapar → Product Box Size app: manual fallback for the daily stock sync.

The daily sync no longer runs from here. It lives inside Postgres now: the
pg_cron job `push_vyapar_to_box_app` in the source project
(begblflwhxbbipsmxytd) fires at 05:30 UTC — 45 minutes after Vyapar's own
pull lands around 04:45 — and the SQL function of the same name reads
vyapar_items and POSTs it straight to pbs_vyapar_items in the app's project
(genlxypyehcpxatcsiut). Nothing on anyone's PC has to be awake for it.
Successful runs land in public.pbs_push_log; failures land in
cron.job_run_details, which is the place to look when stock goes stale.

That move happened because this script's cloud routine stopped on
15 Sep 2026 and nobody noticed for three days — the app quietly served
stock that was 6,029 units off.

This script stays as the by-hand path: pull the rows from the source project
and write them to sync/vyapar_dump.json as a list of
    [item_name, live_stock, is_active, phase_out_date_or_null]
where live_stock = coalesce(stock_quantity_override, current_stock) — the
override column is the figure Vyapar itself shows; current_stock is stale.

It then upserts that dump into pbs_vyapar_items and marks anything missing
from the dump as not live, so an item deleted in Vyapar stops counting. It
prints a short summary: how many rows, how many changed, and what went away.

Needs Python, which the Windows box this repo sits on does not have.
"""
import json, os, sys, datetime, urllib.request, urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
DUMP = os.path.join(HERE, "vyapar_dump.json")
URL = "https://genlxypyehcpxatcsiut.supabase.co/rest/v1"
# Publishable key: same one that ships inside index.html, write access is
# granted by the table's RLS policy, nothing secret here.
KEY = "sb_publishable_pxE-irYl9twtYkk2UDi38g_NWkaW4jP"


def call(method, path, body=None, prefer=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(URL + path, data=data, method=method)
    r.add_header("apikey", KEY)
    r.add_header("Authorization", "Bearer " + KEY)
    r.add_header("Content-Type", "application/json")
    if prefer:
        r.add_header("Prefer", prefer)
    with urllib.request.urlopen(r, timeout=60) as resp:
        raw = resp.read().decode()
        return json.loads(raw) if raw.strip() else None


def main():
    if not os.path.exists(DUMP):
        print("ERROR: sync/vyapar_dump.json nahi mila — pehle MCP se dump likho.")
        sys.exit(1)
    rows = json.load(open(DUMP, encoding="utf-8"))
    if not isinstance(rows, list) or len(rows) < 100:
        print(f"ERROR: dump me sirf {len(rows) if isinstance(rows, list) else 0} rows — "
              "itna chhota dump galat lagta hai, kuch nahi badla.")
        sys.exit(1)

    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    before = {r["item_name"]: r for r in call(
        "GET", "/pbs_vyapar_items?select=item_name,current_stock,is_active,is_discontinued&limit=5000")}

    payload, seen = [], set()
    for name, stock, active, phase in rows:
        seen.add(name)
        # Sirf stock aur live/band. Discontinue is script ka kaam nahi —
        # wo user app me haath se lagata hai (discontinued_manual), aur is
        # payload me na hone se upsert use chhuta bhi nahi.
        payload.append({
            "item_name": name,
            "current_stock": stock,
            "is_active": bool(active),
            "synced_at": now,
        })
    for i in range(0, len(payload), 200):
        call("POST", "/pbs_vyapar_items", payload[i:i + 200],
             prefer="resolution=merge-duplicates,return=minimal")

    # Vyapar se gaayab item = ab live nahi
    gone = [n for n in before if n not in seen and before[n]["is_active"]]
    for n in gone:
        call("PATCH", "/pbs_vyapar_items?item_name=eq." + urllib.parse.quote(n, safe=""),
             {"is_active": False, "synced_at": now})

    changed = sum(1 for p in payload if p["item_name"] not in before
                  or before[p["item_name"]]["current_stock"] != p["current_stock"])
    live = sum(1 for p in payload if p["is_active"])

    print(f"SYNC OK {now}")
    print(f"  rows: {len(payload)} | live: {live} | stock badla: {changed} | Vyapar se gaayab: {len(gone)}")
    if gone:
        print("  ab live nahi: " + ", ".join(gone[:20]))


if __name__ == "__main__":
    main()
