"""
NutriWise AI pipeline benchmark.

Measures speed, accuracy, database matching, reliability and allergen safety by
calling the ai_services functions DIRECTLY. No backend or frontend is needed.

Run from the ai-services folder (the one that contains ai_services/):

    python benchmark/run_benchmark.py --init      # create sample test-data files (once)
    python benchmark/run_benchmark.py             # run everything
    python benchmark/run_benchmark.py --skip-plans --pause 3   # lighter run for free-tier quota

Needs the same environment variables as the app: GEMINI_API_KEY, SUPABASE_URL, SUPABASE_KEY
(a .env file in ai-services/ is loaded automatically if python-dotenv is installed).

Outputs (in benchmark/results/):
    benchmark_report.md       tables you can paste into your report
    benchmark_results.json    all numbers, machine readable
    calls.csv                 one row per AI call (label, seconds, ok, error)
"""
import argparse
import csv
import difflib
import json
import mimetypes
import os
import re
import statistics
import sys
import time
from collections import Counter
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))  # so "import ai_services" works

try:
    from dotenv import load_dotenv
    load_dotenv(HERE.parent / ".env")
except ImportError:
    pass

# ---------------------------------------------------------------------------
# Targets: edit these to match what your team promised. They decide pass/fail.
# ---------------------------------------------------------------------------
TARGETS = {
    "meal_s": 20.0,          # seconds, average, per meal photo
    "fridge_s": 20.0,
    "recipes_s": 40.0,
    "plan_s": 300.0,
    "grocery_s": 40.0,
    "journey_s": 300.0,       # fridge photo -> recipes -> weekly plan -> grocery list, all steps added up
    "food_recall": 0.80,     # share of real foods that the AI found
    "calorie_error_pct": 25.0,
    "db_match": 0.70,        # share of items matched to your foods table
    "success_rate": 0.95,    # share of calls that finished without an exception
    "plan_valid": 1.00,      # share of plans with a correct 7-day structure
    "allergen_catch": 1.00,  # share of real allergen hits that the plan's own check flagged
}

# Words that count as a real hit for each allergy. Add more for your own list.
RELATED = {
    "milk": ["milk", "paneer", "curd", "dahi", "yogurt", "yoghurt", "ghee", "butter", "cheese",
             "cream", "lassi", "buttermilk", "khoya", "khoa", "whey", "kheer"],
    "peanut": ["peanut", "groundnut", "peanut butter"],
    "egg": ["egg", "omelette", "omelet", "mayonnaise"],
    "wheat": ["wheat", "roti", "chapati", "chapathi", "paratha", "naan", "bread", "atta", "semolina", "rava", "suji"],
    "soy": ["soy", "soya", "tofu", "edamame", "soy sauce"],
    "fish": ["fish", "salmon", "tuna", "cod", "mackerel", "sardine"],
    "shellfish": ["shrimp", "prawn", "crab", "lobster", "oyster", "mussel", "clam"],
    "tree_nuts": ["almond", "cashew", "walnut", "pistachio", "hazelnut", "pecan"],
    "sesame": ["sesame", "til", "tahini"],
}

SLOTS = ("breakfast", "lunch", "dinner", "snack")
WEEK = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

SAMPLE_MEALS = [
    {"file": "meal1.jpg", "foods": ["rice", "dal", "mixed vegetable curry"], "calories": 650},
    {"file": "meal2.jpg", "foods": ["idli", "sambar", "coconut chutney"], "calories": 400},
]
SAMPLE_FRIDGE = [
    {"file": "fridge1.jpg", "items": ["milk", "eggs", "tomato", "onion", "spinach"]},
]


# ---------------------------------------------------------------------------
# Loading the project
# ---------------------------------------------------------------------------
def load_ai():
    try:
        try:
            from ai_services import (analyze_meal, analyze_fridge, suggest_recipes,
                                     generate_meal_plan, generate_grocery_list)
        except ImportError:
            from ai_services.meal_analyzer import analyze_meal
            from ai_services.fridge_analyzer import analyze_fridge
            from ai_services.recipes import suggest_recipes
            from ai_services.meal_plan import generate_meal_plan
            from ai_services.grocery import generate_grocery_list
        from ai_services.schemas import FamilyMember, FridgeInventory, InventoryItem
    except Exception as e:
        print(f"\nCould not import ai_services: {type(e).__name__}: {e}")
        print("Check that you run this from the ai-services folder and that GEMINI_API_KEY,")
        print("SUPABASE_URL and SUPABASE_KEY are set BEFORE the import (importing connects to both).")
        sys.exit(1)
    return dict(analyze_meal=analyze_meal, analyze_fridge=analyze_fridge, suggest_recipes=suggest_recipes,
                generate_meal_plan=generate_meal_plan, generate_grocery_list=generate_grocery_list,
                FamilyMember=FamilyMember, FridgeInventory=FridgeInventory, InventoryItem=InventoryItem)


# ---------------------------------------------------------------------------
# Timing helper: every AI call goes through here
# ---------------------------------------------------------------------------
CALLS = []
PAUSE = 1.0


def timed(label, fn, *args, **kwargs):
    t0 = time.perf_counter()
    out, err = None, None
    try:
        out = fn(*args, **kwargs)
    except Exception as e:  # a failed call is a result, not a crash
        err = f"{type(e).__name__}: {str(e)[:150]}"
    seconds = time.perf_counter() - t0
    CALLS.append({"label": label, "seconds": round(seconds, 3), "ok": err is None, "error": err or ""})
    status = "ok" if err is None else "FAILED"
    print(f"  {label:<10} {seconds:6.1f}s  {status}" + (f"  ({err})" if err else ""))
    time.sleep(PAUSE)  # be gentle on the free-tier rate limit
    return out


def name_match(expected, found_names, threshold=0.6):
    e = expected.lower().strip()
    for f in found_names:
        f = f.lower().strip()
        if e in f or f in e or difflib.SequenceMatcher(None, e, f).ratio() >= threshold:
            return True
    return False


def term_hits(text, allergen):
    terms = set(RELATED.get(allergen.lower().replace(" ", "_"), [])) | {allergen.lower()}
    return any(re.search(rf"\b{re.escape(t)}s?\b", text.lower()) for t in terms)


def read_image(path):
    mime = mimetypes.guess_type(str(path))[0] or "image/jpeg"
    return path.read_bytes(), mime


def load_cases(name):
    f = HERE / "test_data" / name
    if not f.exists():
        return []
    return json.loads(f.read_text(encoding="utf-8"))


# ---------------------------------------------------------------------------
# Test sections
# ---------------------------------------------------------------------------
def test_meals(ai, repeat):
    print("\n[1/5] Meal photo analysis")
    cases = load_cases("meals.json")
    res = {"photos": 0, "expected": 0, "found_expected": 0, "found_total": 0, "found_correct": 0,
           "items": 0, "items_matched": 0, "items_review": 0, "cal_errors": []}
    if not cases:
        print("  skipped: benchmark/test_data/meals.json not found (run with --init)")
        return None
    for c in cases:
        img = HERE / "test_data" / "images" / c["file"]
        if not img.exists():
            print(f"  skipped {c['file']}: image not found")
            continue
        data, mime = read_image(img)
        for _ in range(repeat):
            out = timed("meal", ai["analyze_meal"], data, mime)
            if out is None:
                continue
            names = [i.name for i in out.items]
            res["photos"] += 1
            res["expected"] += len(c["foods"])
            res["found_expected"] += sum(name_match(f, names) for f in c["foods"])
            res["found_total"] += len(names)
            res["found_correct"] += sum(name_match(n, c["foods"]) for n in names)
            res["items"] += len(out.items)
            res["items_matched"] += sum(i.food_id is not None for i in out.items)
            res["items_review"] += sum(bool(i.needs_review) for i in out.items)
            if c.get("calories"):
                res["cal_errors"].append(abs(out.total.calories - c["calories"]) / c["calories"] * 100)
    return res


def test_fridge(ai, repeat):
    print("\n[2/5] Fridge photo analysis")
    cases = load_cases("fridge.json")
    res = {"photos": 0, "expected": 0, "found_expected": 0, "inventory": None}
    if not cases:
        print("  skipped: benchmark/test_data/fridge.json not found (run with --init)")
        return None
    for c in cases:
        img = HERE / "test_data" / "images" / c["file"]
        if not img.exists():
            print(f"  skipped {c['file']}: image not found")
            continue
        data, mime = read_image(img)
        for _ in range(repeat):
            out = timed("fridge", ai["analyze_fridge"], data, mime)
            if out is None:
                continue
            names = [i.name for i in out.items]
            res["photos"] += 1
            res["expected"] += len(c["items"])
            res["found_expected"] += sum(name_match(f, names) for f in c["items"])
            res["inventory"] = res["inventory"] or out
    if res["inventory"] is None and cases:
        items = [ai["InventoryItem"](name=n) for n in cases[0]["items"]]
        res["inventory"] = ai["FridgeInventory"](items=items)
    return res


def families(ai):
    F = ai["FamilyMember"]
    return {
        "Adult, no allergies": [F(name="Asha", age=30, gender="female")],
        "Milk allergy, vegetarian": [F(name="Ravi", age=35, gender="male", allergies=["milk"],
                                       food_preferences=["vegetarian"]),
                                     F(name="Mina", age=8, gender="female", allergies=["milk"])],
        "Peanut and egg allergy": [F(name="Sam", age=12, gender="male", allergies=["peanut", "egg"])],
    }


def test_recipes(ai, inventory, repeat):
    print("\n[3/5] Recipe suggestions")
    res = {"runs": 0, "recipes": 0, "ingredients": 0, "unmatched": 0}
    if inventory is None:
        print("  skipped: no fridge inventory available")
        return None
    fam = families(ai)["Adult, no allergies"]
    for _ in range(repeat):
        out = timed("recipes", ai["suggest_recipes"], inventory, fam)
        if out is None:
            continue
        res["runs"] += 1
        res["recipes"] += len(out.recipes)
        for r in out.recipes:
            res["ingredients"] += len(r.ingredients) + len(r.unmatched_ingredients)
            res["unmatched"] += len(r.unmatched_ingredients)
    return res


def plan_names(day):
    names = list(day.ingredients)
    for slot in SLOTS:
        meal = getattr(day, slot, None)
        if meal:
            names += [i.name for i in meal.ingredients]
    return names


def check_plan_structure(plan):
    problems = []
    if len(plan.days) != 7:
        problems.append(f"{len(plan.days)} days instead of 7")
    elif [d.day.strip().title() for d in plan.days] != WEEK:
        problems.append("days are not Monday to Sunday in order")
    for d in plan.days:
        for slot in ("breakfast", "lunch", "dinner"):
            meal = getattr(d, slot, None)
            if meal is None or not meal.ingredients:
                problems.append(f"{d.day} {slot} missing or empty")
        if d.nutrients.calories <= 0:
            problems.append(f"{d.day} has zero calories")
    return problems


def find_violations(plan, allergens):
    hits, seen = [], set()
    for d in plan.days:
        for name in plan_names(d):
            for a in allergens:
                if term_hits(name, a):
                    key = (d.day, name.lower(), a)
                    if key not in seen:
                        seen.add(key)
                        hits.append({"day": d.day, "item": name, "allergen": a})
    return hits


def test_plans_and_grocery(ai, inventory, repeat):
    print("\n[4/5] Weekly plans and grocery lists")
    res = {"plans": 0, "valid": 0, "problems": [], "ingredients": 0, "matched": 0,
           "violations": 0, "caught": 0, "plans_with_violation": 0, "allergy_plans": 0,
           "details": [], "groceries": 0, "grocery_violations": 0, "grocery_items": 0,
           "grocery_not_in_db": 0}
    for fam_name, fam in families(ai).items():
        allergens = {a for m in fam for a in (m.allergies + m.anyother_specific_allergy)}
        for _ in range(repeat):
            plan = timed("plan", ai["generate_meal_plan"], fam, inventory)
            if plan is None:
                continue
            res["plans"] += 1
            problems = check_plan_structure(plan)
            if not problems:
                res["valid"] += 1
            else:
                res["problems"].append({"family": fam_name, "problems": problems[:5]})
            for d in plan.days:
                for slot in SLOTS:
                    meal = getattr(d, slot, None)
                    for ing in (meal.ingredients if meal else []):
                        res["ingredients"] += 1
                        res["matched"] += ing.food_id is not None
            if allergens:
                res["allergy_plans"] += 1
                hits = find_violations(plan, allergens)
                notes = " ".join(plan.notes).lower()
                caught = [h for h in hits if h["day"].lower() in notes and h["item"].lower() in notes]
                res["violations"] += len(hits)
                res["caught"] += len(caught)
                res["plans_with_violation"] += bool(hits)
                res["details"].append({"family": fam_name, "allergens": sorted(allergens),
                                       "violations": hits[:10], "caught": len(caught)})
            grocery = timed("grocery", ai["generate_grocery_list"], fam, plan, inventory)
            if grocery is not None:
                res["groceries"] += 1
                res["grocery_items"] += len(grocery.items)
                res["grocery_not_in_db"] += len(grocery.not_in_database)
                res["grocery_violations"] += sum(term_hits(g.name, a) for g in grocery.items for a in allergens)
    return res


# ---------------------------------------------------------------------------
# Summaries
# ---------------------------------------------------------------------------
def latency_table():
    rows = []
    for label in ["meal", "fridge", "recipes", "plan", "grocery"]:
        calls = [c for c in CALLS if c["label"] == label]
        if not calls:
            continue
        good = sorted(c["seconds"] for c in calls if c["ok"])
        rows.append({
            "label": label, "calls": len(calls), "ok": len(good),
            "avg": round(statistics.mean(good), 2) if good else None,
            "median": round(statistics.median(good), 2) if good else None,
            "p95": round(good[min(len(good) - 1, int(0.95 * len(good)))], 2) if good else None,
            "max": round(max(good), 2) if good else None,
        })
    return rows


def pct(a, b):
    return a / b if b else None


def fmt_pct(x):
    return "n/a" if x is None else f"{x * 100:.0f}%"


def build_metrics(meals, fridge, recipes, plans, lat):
    M = []  # (metric, result, target, status)

    def row(name, value, shown, target, target_shown, higher_better):
        if value is None:
            M.append((name, "n/a", target_shown, "not run"))
        else:
            ok = value >= target if higher_better else value <= target
            M.append((name, shown, target_shown, "PASS" if ok else "FAIL"))

    avg = {r["label"]: r["avg"] for r in lat}
    for label, key, nice in [("meal", "meal_s", "Meal photo analysis time (avg)"),
                             ("fridge", "fridge_s", "Fridge photo analysis time (avg)"),
                             ("recipes", "recipes_s", "Recipe suggestion time (avg)"),
                             ("plan", "plan_s", "Weekly plan generation time (avg)"),
                             ("grocery", "grocery_s", "Grocery list generation time (avg)")]:
        v = avg.get(label)
        row(nice, v, f"{v} s" if v is not None else "", TARGETS[key], f"under {TARGETS[key]:.0f} s", False)

    steps = [avg.get(k) for k in ("fridge", "recipes", "plan", "grocery")]
    if all(v is not None for v in steps):
        j = round(sum(steps), 1)
        row("End-to-end journey: fridge to grocery list", j, f"{j} s", TARGETS["journey_s"],
            f"under {TARGETS['journey_s']:.0f} s", False)

    if meals and meals["expected"]:
        r = pct(meals["found_expected"], meals["expected"])
        row("Meal foods correctly identified", r, f"{meals['found_expected']} of {meals['expected']} ({fmt_pct(r)})",
            TARGETS["food_recall"], fmt_pct(TARGETS["food_recall"]), True)
        if meals["cal_errors"]:
            e = statistics.mean(meals["cal_errors"])
            row("Calorie error vs reference (avg)", e, f"{e:.0f}%", TARGETS["calorie_error_pct"],
                f"under {TARGETS['calorie_error_pct']:.0f}%", False)
        if meals["items"]:
            r = pct(meals["items_matched"], meals["items"])
            row("Meal items matched to foods database", r,
                f"{meals['items_matched']} of {meals['items']} ({fmt_pct(r)})",
                TARGETS["db_match"], fmt_pct(TARGETS["db_match"]), True)
    if fridge and fridge["expected"]:
        r = pct(fridge["found_expected"], fridge["expected"])
        row("Fridge items correctly identified", r, f"{fridge['found_expected']} of {fridge['expected']} ({fmt_pct(r)})",
            TARGETS["food_recall"], fmt_pct(TARGETS["food_recall"]), True)
    if plans and plans["ingredients"]:
        r = pct(plans["matched"], plans["ingredients"])
        row("Plan ingredients matched to database", r, f"{plans['matched']} of {plans['ingredients']} ({fmt_pct(r)})",
            TARGETS["db_match"], fmt_pct(TARGETS["db_match"]), True)
    if plans and plans["plans"]:
        r = pct(plans["valid"], plans["plans"])
        row("Plans with valid 7-day structure", r, f"{plans['valid']} of {plans['plans']}",
            TARGETS["plan_valid"], fmt_pct(TARGETS["plan_valid"]), True)
    total, ok = len(CALLS), sum(c["ok"] for c in CALLS)
    if total:
        r = ok / total
        row("Calls finished without error", r, f"{ok} of {total} ({fmt_pct(r)})",
            TARGETS["success_rate"], fmt_pct(TARGETS["success_rate"]), True)
    if plans and plans["violations"]:
        r = pct(plans["caught"], plans["violations"])
        row("Real allergen hits flagged by plan check", r, f"{plans['caught']} of {plans['violations']} ({fmt_pct(r)})",
            TARGETS["allergen_catch"], fmt_pct(TARGETS["allergen_catch"]), True)
    return M


def write_outputs(M, lat, meals, fridge, recipes, plans, args):
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    model = os.getenv("MODEL_NAME", "(default)")
    errors = Counter(c["error"].split(":")[0] for c in CALLS if not c["ok"])

    lines = [f"# Prototype Performance Report", "",
             f"Run: {datetime.now():%Y-%m-%d %H:%M}  |  Model: `{model}`  |  Calls made: {len(CALLS)}  |  Repeat: {args.repeat}",
             "", "## Results against targets", "", "| Metric | Result | Target | Status |", "|---|---|---|---|"]
    lines += [f"| {a} | {b} | {c} | {d} |" for a, b, c, d in M]

    lines += ["", "## Speed (seconds, successful calls only)", "",
              "| Function | Calls | Succeeded | Average | Median | 95th percentile | Slowest |", "|---|---|---|---|---|---|---|"]
    lines += [f"| {r['label']} | {r['calls']} | {r['ok']} | {r['avg']} | {r['median']} | {r['p95']} | {r['max']} |" for r in lat]

    lines += ["", "## Reliability", ""]
    if errors:
        lines += ["Failures by type:", ""] + [f"- {k}: {v}" for k, v in errors.items()]
    else:
        lines.append("No call failed.")
    if plans and plans["problems"]:
        lines += ["", "Plan structure problems:", ""]
        lines += [f"- {p['family']}: {'; '.join(p['problems'])}" for p in plans["problems"]]

    if plans and plans["allergy_plans"]:
        lines += ["", "## Allergen safety", "",
                  f"- Plans generated for allergic families: {plans['allergy_plans']}",
                  f"- Plans that contained a real allergen or related ingredient: {plans['plans_with_violation']}",
                  f"- Real hits in total: {plans['violations']}; flagged by the plan's own check: {plans['caught']}",
                  f"- Allergen hits found in grocery lists (no check exists there): {plans['grocery_violations']}", ""]
        for d in plans["details"]:
            if d["violations"]:
                ex = ", ".join(f"{v['day']}: {v['item']} ({v['allergen']})" for v in d["violations"][:5])
                lines.append(f"- {d['family']}: {ex}")
        lines += ["", "Hits are found with a related-ingredient list (for example milk includes paneer, curd, ghee), "
                      "so they show what the current substring check can miss."]

    lines += ["", "## Test set", ""]
    if meals:
        lines.append(f"- Meal photos analysed: {meals['photos']}")
    if fridge:
        lines.append(f"- Fridge photos analysed: {fridge['photos']}")
    if recipes:
        lines.append(f"- Recipes returned: {recipes['recipes']} (unmatched ingredients: {recipes['unmatched']} of {recipes['ingredients']})")
    if plans:
        lines.append(f"- Weekly plans generated: {plans['plans']}; grocery lists: {plans['groceries']}")
    (out / "benchmark_report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    (out / "benchmark_results.json").write_text(json.dumps(
        {"date": datetime.now().isoformat(), "model": model, "metrics": [dict(zip(["metric", "result", "target", "status"], m)) for m in M],
         "latency": lat, "meals": meals and {k: v for k, v in meals.items()},
         "fridge": fridge and {k: v for k, v in fridge.items() if k != "inventory"},
         "recipes": recipes, "plans": plans}, indent=2, default=str), encoding="utf-8")
    with open(out / "calls.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["label", "seconds", "ok", "error"])
        w.writeheader()
        w.writerows(CALLS)


def init_files():
    d = HERE / "test_data"
    (d / "images").mkdir(parents=True, exist_ok=True)
    for name, data in [("meals.json", SAMPLE_MEALS), ("fridge.json", SAMPLE_FRIDGE)]:
        f = d / name
        if not f.exists():
            f.write_text(json.dumps(data, indent=2), encoding="utf-8")
    print(f"Created {d}")
    print("1. Put your photos in benchmark/test_data/images/")
    print("2. Edit meals.json and fridge.json so each file lists what is REALLY in the photo")
    print("   (add \"calories\" per meal only if you have a trusted reference number).")
    print("3. Run: python benchmark/run_benchmark.py")


def main():
    global PAUSE
    ap = argparse.ArgumentParser()
    ap.add_argument("--init", action="store_true", help="create sample test_data files and exit")
    ap.add_argument("--repeat", type=int, default=1, help="repeat each test case N times for steadier timings")
    ap.add_argument("--pause", type=float, default=1.0, help="seconds to wait between calls (raise for free-tier quota)")
    ap.add_argument("--skip-plans", action="store_true", help="skip weekly plans and grocery lists (they use the most quota)")
    ap.add_argument("--out", default=str(HERE / "results"))
    args = ap.parse_args()
    if args.init:
        init_files()
        return
    PAUSE = args.pause

    ai = load_ai()
    print(f"Benchmark started. Model: {os.getenv('MODEL_NAME', '(default)')}")
    meals = test_meals(ai, args.repeat)
    fridge = test_fridge(ai, args.repeat)
    inventory = fridge["inventory"] if fridge else None
    recipes = test_recipes(ai, inventory, args.repeat)
    plans = None
    if args.skip_plans:
        print("\n[4/5] Skipped (--skip-plans)")
    else:
        plans = test_plans_and_grocery(ai, inventory, args.repeat)

    print("\n[5/5] Writing results")
    lat = latency_table()
    M = build_metrics(meals, fridge, recipes, plans, lat)
    write_outputs(M, lat, meals, fridge, recipes, plans, args)

    print("\n" + "=" * 78)
    print(f"{'Metric':<44}{'Result':<22}{'Target':<12}Status")
    print("-" * 78)
    for a, b, c, d in M:
        print(f"{a:<44}{b:<22}{c:<12}{d}")
    print("=" * 78)
    print(f"Saved to {args.out}: benchmark_report.md, benchmark_results.json, calls.csv")


if __name__ == "__main__":
    main()