"""Vyapar → Product Box Size app: daily stock + continue/discontinue sync.

Run by the cloud routine every morning. The routine's Claude session first
pulls the rows from the source Supabase project (begblflwhxbbipsmxytd, via
the Supabase MCP) and writes them to sync/vyapar_dump.json as a list of
    [item_name, live_stock, is_active, phase_out_date_or_null]
where live_stock = coalesce(stock_quantity_override, current_stock) — the
override column is the figure Vyapar itself shows; current_stock is stale.

This script then upserts that dump into pbs_vyapar_items in the app's own
project (genlxypyehcpxatcsiut) and marks anything missing from the dump as
not live, so an item deleted in Vyapar stops counting the next morning.

It prints a short summary the routine relays: how many rows, how many
changed, and any product in the app whose status flipped to discontinued.
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
        payload.append({
            "item_name": name,
            "current_stock": stock,
            "is_active": bool(active),
            "is_discontinued": phase is not None,
            "phase_out_date": phase,
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
    newly_disc = [p["item_name"] for p in payload
                  if p["is_discontinued"] and p["item_name"] in before
                  and not before[p["item_name"]]["is_discontinued"]]
    live = sum(1 for p in payload if p["is_active"])

    print(f"SYNC OK {now}")
    print(f"  rows: {len(payload)} | live: {live} | stock badla: {changed} | Vyapar se gaayab: {len(gone)}")
    if newly_disc:
        print("  naye discontinued: " + ", ".join(newly_disc))
    if gone:
        print("  ab live nahi: " + ", ".join(gone[:20]))


if __name__ == "__main__":
    main()
