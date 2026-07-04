#!/usr/bin/env python3
"""ui_smoke.py (v2) — drives the full Swish Strike flow in headless Chrome via Playwright:
home grid → guided setup (auto-calibrate/coach) → play (counts + per-player) →
result. Verifies the on-device Simulation source end to end. Server on :8777.
  python3 test/ui_smoke.py
"""
import os, sys, time, re
from pathlib import Path
from playwright.sync_api import sync_playwright

BASE = os.environ.get("BASE", "http://localhost:8777")
OUT = Path(__file__).parent / "screenshots"; OUT.mkdir(parents=True, exist_ok=True)

failures = 0
def ok(name, cond):
    global failures
    print(f"  {'✔' if cond else '✘ FAIL:'} {name}")
    if not cond: failures += 1

def wait_phase(page, want, timeout=12.0):
    t = 0.0
    while t < timeout:
        if page.evaluate("window.swishTest.phase()") == want:
            return True
        time.sleep(0.2); t += 0.2
    return False

print("Swish Strike v2 — end-to-end UI flow")
errors = []
with sync_playwright() as p:
    browser = p.chromium.launch(channel="chrome", headless=True)
    page = browser.new_page(viewport={"width": 430, "height": 932})
    page.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
    page.on("pageerror", lambda e: errors.append(str(e)))
    page.goto(f"{BASE}/index.html", wait_until="networkidle")

    # 1. Home grid
    page.wait_for_selector("#grid .card")
    cards = page.eval_on_selector_all("#grid .card", "els => els.length")
    ok(f"home grid renders all 14 game cards (got {cards})", cards == 14)
    heroes = page.eval_on_selector_all("#grid .card .hero svg", "els => els.length")
    ok(f"every card has crafted hero art (got {heroes})", heroes == 14)
    page.screenshot(path=str(OUT / "home.png"))

    # 2. Open basketball -> guided SETUP auto-calibrates and advances to PLAY
    page.evaluate("window.swishTest.openGame('hoop-count')")
    ok("game opens in the guided setup phase", page.evaluate("window.swishTest.phase()") == "setup")
    time.sleep(0.8)
    page.screenshot(path=str(OUT / "setup-coach.png"))
    ok("setup auto-advances to play after coaching/calibration", wait_phase(page, "play", 8.0))

    # 3. PLAY — counts makes AND attributes them per player (2 sim players)
    time.sleep(7.0)
    total = page.evaluate("window.swishTest.count()")
    ok(f"basketball counts makes (total={total})", total >= 2)
    players = page.evaluate("window.swishTest.players()")
    ok(f"two players are tracked (got {len(players)})", len(players) == 2)
    each = {p['name']: p['count'] for p in players}
    ok(f"each player has their own score {each}", len(players) == 2 and all(p['count'] >= 1 for p in players))
    ok(f"per-player totals add up to the count ({sum(p['count'] for p in players)} == {total})",
       sum(p['count'] for p in players) == total)

    # 3b. Shot-quality classification (swish vs rim) surfaces end-to-end, and the
    #     made-shot arc is captured for the replay/share card.
    quals = page.evaluate("window.swishTest.qualities()")
    ok(f"every make is classified swish/rim (got {len(quals)} of {total})", len(quals) == total)
    ok(f"the demo shows BOTH a clean swish and a rim rattle (got {sorted(set(quals))})",
       'swish' in quals and 'rim' in quals)
    arc = page.evaluate("window.swishTest.savedArc()")
    ok(f"the made-shot arc is captured for the share card ({len(arc)} points)", len(arc) > 3)
    page.screenshot(path=str(OUT / "play-multiplayer.png"))

    # 4. RESULT
    page.evaluate("window.swishTest.finish()")
    ok("finishing shows the result screen", page.evaluate("window.swishTest.phase()") == "result")
    rtotal = page.text_content("#result-total")
    ok(f"result total matches the count (shows {rtotal})", int(rtotal) == total)
    breakdown = page.text_content("#result-breakdown")
    ok(f"result shows the swish/rim breakdown ('{breakdown.strip()}')", 'swish' in breakdown)
    page.screenshot(path=str(OUT / "result.png"))

    # 5. A bounce game (keepie-uppie) — no calibration target, counts touches
    page.evaluate("window.swishTest.openGame('keepie-uppie')")
    ok("bounce game reaches play", wait_phase(page, "play", 8.0))
    time.sleep(4.5)
    juggle = page.evaluate("window.swishTest.count()")
    ok(f"keepie-uppie counts touches (count={juggle})", juggle >= 3)
    page.screenshot(path=str(OUT / "play-juggle.png"))

    # 5b. Free-Throw Streak — the streak builds, and a miss resets it to zero
    page.evaluate("window.swishTest.openGame('free-throw-streak')")
    ok("free-throw reaches play", wait_phase(page, "play", 8.0))
    time.sleep(13.0)  # enough for several makes plus at least one brick
    ft_max = page.evaluate("window.swishTest.maxStreak()")
    ft_misses = page.evaluate("window.swishTest.misses()")
    ok(f"free-throw builds a consecutive streak (longest={ft_max})", ft_max >= 2)
    ok(f"a miss resets the streak (misses detected={ft_misses})", ft_misses >= 1)
    page.screenshot(path=str(OUT / "play-free-throw.png"))

    # 6. No fatal console errors
    fatal = [e for e in errors if not re.search(r"coco|tf|pose|vendor|weight|storage|favicon|net::|Failed to load resource", e, re.I)]
    ok(f"no fatal console errors ({len(fatal)})", len(fatal) == 0)
    for e in fatal: print("     · " + e)

    browser.close()

print()
if failures == 0: print("All v2 UI flow checks passed.")
else: print(f"{failures} check(s) FAILED."); sys.exit(1)
