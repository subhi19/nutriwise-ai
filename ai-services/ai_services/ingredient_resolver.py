# """
# ingredient_resolver.py

# Speeds up generate_meal_plan() WITHOUT changing what it returns.

# The slow part of a 7-day plan is not the main Gemini call. It is looking up
# every ingredient one after another:
#     database word match -> vector search (embedding call + Supabase call)
#     -> if still missing, one separate Gemini call per ingredient.

# This module does the same work in cheaper steps:
#     1. Look up all ingredients in the database IN PARALLEL.
#     2. For anything the database lacks (not found, or the row has empty nutrient
#        values), use the per-100 g values Gemini returned TOGETHER WITH THE PLAN
#        (the "ingredient_nutrition" table). No extra Gemini call is needed.
#     3. Only for names Gemini left out (or gave unrealistic numbers for), estimate
#        them in a few batched calls that run at the same time.
#     4. Only if a name is still missing, estimate that one individually.

# It fills the same `lookup_cache` that meal_plan.py already uses, so the rest of
# meal_plan.py does not change.

# Environment variables (both optional):
#     LOOKUP_WORKERS          parallel database lookups (default 8)
#     ESTIMATE_BATCH_SIZE     foods per batched Gemini estimate (default 25)
#     INLINE_NUTRITION        1 (default) = ask Gemini for ingredient values inside the plan;
#                             0 = old behaviour (separate estimate calls after the plan)
#     GEMINI_THINKING_BUDGET  e.g. 0 to switch off "thinking" on models that allow
#                             it (faster for structured JSON). Leave unset if unsure.
# """
# import json
# import os
# import time
# from concurrent.futures import ThreadPoolExecutor
# from .gemini_client import client, MODEL_NAME
# from google.genai import types
# from .retry_utils import call_with_retry
# from .nutrition_repo import search_food
# from .meal_analyzer import estimate_nutrients_with_gemini
# from .schemas import DayPreference

# MAX_WORKERS = int(os.getenv("LOOKUP_WORKERS", "8"))
# BATCH_SIZE = int(os.getenv("ESTIMATE_BATCH_SIZE", "25"))  # foods per batched Gemini estimate

# NUTRIENT_KEYS = ["calories", "protein_g", "carbs_g", "fat_g", "fiber_g",
#                  "iron_mg", "calcium_mg", "vitamin_a_mcg", "vitamin_c_mg"]


# def generation_config():
#     kwargs = {"response_mime_type": "application/json"}

#     budget = os.getenv("GEMINI_THINKING_BUDGET", "").strip()

#     if budget:
#         kwargs["thinking_config"] = types.ThinkingConfig(
#             thinking_budget=int(budget)
#         )
#     print(
#     "GEMINI_THINKING_BUDGET =",
#     os.getenv("GEMINI_THINKING_BUDGET")
# )

#     return types.GenerateContentConfig(**kwargs)


# def all_ingredient_names(plan_data: dict) -> list[str]:
#     """Unique ingredient names across the whole raw plan returned by Gemini."""
#     seen, names = set(), []
#     for day in plan_data.get("days", []):
#         for slot in ("breakfast", "lunch", "dinner", "snack"):
#             meal = day.get(slot)
#             if not meal:
#                 continue
#             for ing in meal.get("ingredients", []):
#                 name = str(ing.get("name", "")).strip()
#                 key = name.lower()
#                 if name and key not in seen:
#                     seen.add(key)
#                     names.append(name)
#     return names


# def _clean(item: dict) -> dict:
#     out = {}
#     for k in NUTRIENT_KEYS:
#         try:
#             v = float(item.get(k) or 0)
#         except (TypeError, ValueError):
#             v = 0.0
#         out[k] = min(max(v, 0.0), 900.0 if k == "calories" else 10000.0)
#     return out


# INLINE_NUTRITION = os.getenv("INLINE_NUTRITION", "1").strip().lower() not in ("0", "false", "no", "off")
# NUTRIENT_ORDER = "[calories, protein_g, carbs_g, fat_g, fiber_g, iron_mg, calcium_mg, vitamin_a_mcg, vitamin_c_mg]"


# def inline_nutrition_enabled() -> bool:
#     return INLINE_NUTRITION


# def inline_nutrition_prompt() -> str:
#     """Extra instruction for the plan prompt: a compact per-100 g table for every ingredient."""
#     return (
#         'ALSO include a top-level "ingredient_nutrition" object with exactly ONE entry for every '
#         "distinct ingredient name used anywhere in the plan (spell each name exactly as in the meals). "
#         "Each value is an array of 9 numbers: typical nutrition per 100 g of that ingredient, in this "
#         f"order: {NUTRIENT_ORDER}. Use realistic average values with at most 1 decimal. "
#         "This table is only a fallback for foods missing from our database."
#     )


# def row_has_values(food) -> bool:
#     """True if a database row has all nine nutrient values filled in."""
#     try:
#         return all(food.get(k) is not None for k in NUTRIENT_KEYS)
#     except AttributeError:
#         return False


# def _plausible(n: dict) -> bool:
#     """Calories should roughly match protein/carbs/fat (4/4/9 kcal per gram)."""
#     kcal = n["calories"]
#     atwater = 4 * n["protein_g"] + 4 * n["carbs_g"] + 9 * n["fat_g"]
#     return abs(kcal - atwater) <= max(40.0, 0.35 * max(kcal, atwater))


# def parse_inline_nutrition(raw) -> dict[str, dict]:
#     """Turns Gemini's {"name": [9 numbers]} table into {name_lower: {nutrient: value}}; skips bad entries."""
#     out: dict[str, dict] = {}
#     if not isinstance(raw, dict):
#         return out
#     for name, vals in raw.items():
#         if isinstance(vals, (list, tuple)) and len(vals) >= 9:
#             item = dict(zip(NUTRIENT_KEYS, vals[:9]))
#         elif isinstance(vals, dict):
#             item = vals
#         else:
#             continue
#         try:
#             [float(item.get(k)) for k in NUTRIENT_KEYS]  # every value must be a real number
#         except (TypeError, ValueError):
#             continue
#         cleaned = _clean(item)
#         if any(cleaned.values()) and _plausible(cleaned):  # all-zero entries go to the batch estimate
#             out[str(name).strip().lower()] = cleaned
#     return out


# def _estimate_batch(names: list[str]) -> dict[str, dict]:
#     """One Gemini call that estimates nutrition per 100 g for many foods."""
#     prompt = (
#         "Estimate typical nutrition PER 100 g for each food below. Use realistic "
#         "average values for the food as normally eaten.\n"
#         'Return JSON only: {"foods": [{"name": "<exactly as given>", "calories": 0, '
#         '"protein_g": 0, "carbs_g": 0, "fat_g": 0, "fiber_g": 0, "iron_mg": 0, '
#         '"calcium_mg": 0, "vitamin_a_mcg": 0, "vitamin_c_mg": 0}]}\n'
#         "Foods:\n" + "\n".join(f"- {n}" for n in names)
#     )

#     def request():
#         resp = client.models.generate_content(model=MODEL_NAME, contents=[prompt], config=generation_config())
#         return json.loads(resp.text)

#     items = call_with_retry(request, label="Gemini (batch nutrition estimate)").get("foods", [])
#     by_name = {str(i.get("name", "")).strip().lower(): _clean(i) for i in items}
#     if len(items) == len(names):  # same count: also allow matching by position
#         for n, i in zip(names, items):
#             by_name.setdefault(n.strip().lower(), _clean(i))
#     return by_name


# def prefetch_ingredients(names: list[str], cache: dict, inline: dict | None = None) -> None:
#     """
#     Fills `cache[name.lower()] = (food_row_or_None, per_100g_estimate_or_None)`.

#     inline: the "ingredient_nutrition" table Gemini returned together with the plan
#             (name -> 9 numbers per 100 g). Used for any food the database lacks.
#     """
#     todo = [n for n in names if n.strip().lower() not in cache]
#     if not todo:
#         return
#     t0 = time.perf_counter()

#     def find(n):
#         try:
#             return search_food(n)
#         except Exception:  # a failed lookup is treated as "not found", then estimated
#             return None

#     with ThreadPoolExecutor(max_workers=MAX_WORKERS) as ex:
#         foods = list(ex.map(find, todo))

#     missing, incomplete = [], 0
#     for n, food in zip(todo, foods):
#         if food and row_has_values(food):
#             cache[n.strip().lower()] = (food, None)
#         else:
#             incomplete += bool(food)  # row found, but some nutrient values are empty
#             missing.append(n)
#     t1 = time.perf_counter()

#     # 1) values Gemini already gave us together with the plan: no extra call
#     from_plan = parse_inline_nutrition(inline) if inline else {}
#     estimates: dict[str, dict] = {k: from_plan[k] for k in (n.strip().lower() for n in missing) if k in from_plan}
#     n_plan = len(estimates)
#     need = [n for n in missing if n.strip().lower() not in estimates]

#     # 2) names Gemini left out: batched estimates, several calls at the same time
#     chunks = [need[i:i + BATCH_SIZE] for i in range(0, len(need), BATCH_SIZE)]

#     def run_chunk(chunk):
#         tb = time.perf_counter()
#         try:
#             result = _estimate_batch(chunk)
#             print(f"[meal_plan] estimated {len(chunk)} foods in one call: {time.perf_counter() - tb:.1f}s")
#             return result
#         except Exception as e:
#             import traceback

#             print(
#                 f"[meal_plan] batch estimate failed: {e}"
#             )

#             traceback.print_exc()
#             return {}

#     if chunks:
#         with ThreadPoolExecutor(max_workers=min(len(chunks), 4)) as ex:
#             for result in ex.map(run_chunk, chunks):
#                 estimates.update(result)
#     n_batch = len(estimates) - n_plan

#     # 3) anything still missing: one call each (rare)
#     still = [n for n in need if n.strip().lower() not in estimates]
#     if still:
#         with ThreadPoolExecutor(max_workers=MAX_WORKERS) as ex:
#             for n, est in zip(still, ex.map(lambda x: estimate_nutrients_with_gemini(x, 100), still)):
#                 estimates[n.strip().lower()] = est
#     for n in missing:
#         key = n.strip().lower()
#         cache[key] = (None, estimates[key])
#     t2 = time.perf_counter()
#     note = f" ({incomplete} database rows had empty values)" if incomplete else ""
#     print(f"[meal_plan] {len(todo)} ingredients: database lookups {t1 - t0:.1f}s | {len(missing)} not usable from "
#           f"database{note}: {n_plan} from the plan response, {n_batch} by batch, {len(still)} single | "
#           f"extra time {t2 - t1:.1f}s")


# def normalize_day_preferences(dp) -> list[DayPreference] | None:
#     """Accepts a list OR a {day: ...} dictionary of preferences and returns a list."""
#     if not dp:
#         return None
#     items = []
#     if isinstance(dp, dict):
#         for day, v in dp.items():
#             if isinstance(v, DayPreference):
#                 items.append(v)
#             elif isinstance(v, dict):
#                 items.append(DayPreference(**{"day": day, **v}))
#             elif isinstance(v, str):
#                 items.append(DayPreference(day=day, preference=v))
#     else:
#         for v in dp:
#             if isinstance(v, DayPreference):
#                 items.append(v)
#             elif isinstance(v, dict):
#                 items.append(DayPreference(**v))
#     return items or None