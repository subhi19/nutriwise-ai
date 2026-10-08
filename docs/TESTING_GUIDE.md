# Testing Guide — All AI Module Functions

Run these in order. Each one builds on the last, so if an early one fails,
fix it before moving to the next — later ones depend on earlier pieces
working.

Before starting, make sure these are set in your terminal:
```powershell
$env:GEMINI_API_KEY="your_key"
$env:SUPABASE_URL="your_url"
$env:SUPABASE_KEY="your_key"
$env:MODEL_NAME="gemini-flash-lite-latest"
```

---

## 1. Connection check — `gemini_client.py`

```
python gemini_client.py
```

**Expected output:**
```
Connected using: API key (AI Studio)
Model: gemini-flash-lite-latest

Models available to this connection:
 - models/gemini-2.5-flash
 - ... (a long list)
```

**What this confirms:** your API key works and can reach Gemini. No image, no database — just a connectivity check.

**If this fails:** nothing else will work either. Fix your `GEMINI_API_KEY` first.

---

## 2. Database check — `nutrition_repo.py`

```
python nutrition_repo.py
```

**Expected output:**
```
"chicken curry" matched -> Chicken curry (220 kcal per 100g)
"dry chicken curry" matched -> Chicken curry (220 kcal per 100g)
"cooked white rice" matched -> Cooked basmati rice (130 kcal per 100g)
"roti" matched -> Roti (120 kcal per 100g)
"something made up" -> no match found
```

**What this confirms:** your Supabase connection works, and the `foods` table has data in it. "No match found" on nonsense input is correct — it should NOT match everything.

**If everything says "no match found":** check Row Level Security (RLS) policies in Supabase, or confirm the CSV was actually imported into the table.

---

## 3. Meal analysis — `meal_analyzer.py`

```
python meal_analyzer.py
```
(Type a food photo's filename when asked)

**Expected output (shape):**
```
--- What Gemini detected (before database matching) ---
  chicken curry (150g, high confidence)
  roti (80g, medium confidence)

--- Items ---
Chicken curry (150.0g): 330.0 kcal
Roti (80.0g): 96.0 kcal

--- Total ---
{'calories': 426.0, 'protein_g': ..., ...}

--- Missing nutrients ---
['Vitamin C', 'Fiber']

--- Suggestions ---
- Add orange, lemon, amla, or tomato for vitamin C.
```

**What to check:**
- Calories per item look reasonable (not 0 unless genuinely unmatched)
- Suggestions name real foods, not just "foods rich in X"
- Run the SAME photo twice — the numbers should be IDENTICAL both times (this is the fix for the inconsistency problem from early testing)

---

## 4. Meal correction — `meal_corrector.py`

```
python meal_corrector.py
```
(No photo needed — has built-in fake data)

**Expected output:**
```
--- Corrected items ---
Chicken curry (150g): 330.0 kcal [database]
(if not gemini should suggest)------------------------------------------------------*-------
--- Total ---
{'calories': 330.0, ...}
```

**What this confirms:** typing a corrected dish name looks it up in the database and gets real numbers, without needing to re-analyze a photo.

---

## 5. Fridge analysis — `fridge_analyzer.py`

```
python fridge_analyzer.py
```
(Type a fridge/vegetable photo's filename — put it in the `images/` folder first)

**Expected output:**
```
--- Fridge inventory ---
Tomatoes (4)
Spinach (1 bunch) [USE SOON — Use within 2 days]
Eggs (6)
```

**What to check:**
- Items that look fresh have NO flag
- Items that look wilting/near empty show `[USE SOON — <estimate>]`

---

## 6. Fridge-only recipes — `recipes.py` (UPDATED — now has real nutrients)

```
python recipes.py
```
(No photo needed — has built-in fake inventory)

**Expected output:**
```
--- Suggested recipes (fridge-only, with real nutrients) ---

Palak Paneer  —  total: 325.0 kcal, protein: 23.7g
  - Spinach: 150.0g, 60.0 kcal
  - Paneer: 100.0g, 265.0 kcal
  Pantry staples: Salt, Oil, Garam masala
  1. Blanch and puree the spinach.
  2. Cook with cubed paneer and spices.
```

**What to check:**
- Every listed ingredient actually came from the fake fridge inventory (Spinach, Paneer, Tomatoes, Eggs) — NOT random extra ingredients
- Only "pantry staples" (salt, oil, spices) appear as unlisted extras — nothing else
- Each ingredient shows real calories, and they add up to the recipe's total

---

## 7. Weekly meal plan — `meal_plan.py` (UPDATED — now has real nutrients)

```
python meal_plan.py
```
(No photo needed — has built-in fake family/inventory)

**Expected output (3 scenarios run automatically):**
```
=== Plan without inventory (Weekly Planner, no photo) ===

Monday  —  total: 1450.0 kcal
  Breakfast: Masala Oats (194.0 kcal)
    - Rolled oats: 50g, 194.0 kcal
  Lunch: Dal Tadka with Rice (... kcal)
  Dinner: Aloo Gobi (... kcal)

Plan notes: ['All meals are vegetarian and peanut-free.']


=== Plan with fridge inventory (Fridge screen) ===

Monday  —  total: ... kcal, protein: ...g
  Breakfast: Spinach Paratha
  ...
Plan notes: [..., 'Spinach prioritized Monday before it spoils.']


=== Plan with day-specific preferences ===

Friday  —  total: ... kcal
  Dinner: Chicken Tikka  (should be non-veg, since Friday was overridden)

Sunday  —  total: ... kcal
  Dinner: (should be something light/low-oil)
```

**What to check:**
- Every meal shows a real kcal number (not 0, not missing)
- Day total = sum of breakfast + lunch + dinner (roughly — check the math makes sense)
- In the inventory scenario, spinach shows up in Monday's meals and the plan notes mention it
- In the day-preferences scenario, only Friday and Sunday changed; other days stayed vegetarian

**This test is slower than the others** — it makes several Gemini calls (one per day's plan generation, plus any fallback calls for unmatched ingredients). Expect it to take a minute or two.

---

## 8. Grocery list — `grocery.py`

```
python grocery.py
```
(No photo needed — has built-in fake plan/inventory)

**Expected output:**
```
=== CASE A: No photo uploaded — buy everything the plan needs ===
Items to buy: 15
  [Grains] Rolled oats — 350 g
  ...

=== CASE B: Photo uploaded — exclude items already at home ===
Items to buy: 12 (onion, tomatoes, and dal should be MISSING from this list)
  [Vegetables] Spinach — ...
  ...
Used Gemini fallback for (not in our database yet): ['Almond flour']
```

**What to check:**
- Case A has MORE items than Case B (since Case B excludes fridge items)
- Onion, Tomatoes, Yellow dal do NOT appear anywhere in Case B's list
- "Almond flour" (user-typed, not in your database) still appears, with a sensible guessed category — this confirms the Gemini fallback works

---

## 9. Full chain — `test_full_flow.py`

```
python test_full_flow.py
```
Say **y** when asked for a photo, and provide a real fridge photo.

**Expected final line:**
```
✅ Confirmed: nothing from the fridge photo appears in the grocery list.
```

**What this proves:** the entire real flow works end-to-end — photo → inventory → meal plan → grocery list — not just the individual pieces in isolation.

---

## 10. Fridge → recipes chain — `test_fridge_to_recipes.py`

```
python test_fridge_to_recipes.py
```
Provide a real fridge photo.

**What to check:** the recipes generated only use ingredients that were actually detected in your photo (plus pantry staples) — this is the real-photo version of test #6 above.

---

## If something fails partway through

- **429 quota error:** you've hit the daily limit for that model. Switch models: `$env:MODEL_NAME="gemini-2.5-flash-lite"` and try again.
- **503 busy:** should auto-retry up to ~46 seconds. If it still fails, just run the command again.
- **ImportError:** usually means a file on your computer is an older version. Compare line counts or re-copy the file from the latest version I gave you.
- **KeyError or validation error:** usually means Gemini's JSON response didn't match the expected shape exactly — paste the full error and I'll adjust the prompt or parsing.
