# AI Module Contract (v3)

Owner: AI module (Gemini Vision, Nutrition DB with RAG, Gemini Flash recommendations)
Folder in repo: `ai-services/ai_services/`
Read by: Backend and Frontend developers

This document covers only what the AI module takes in and gives back. The API endpoints and the app screens are owned by the backend and frontend developers.

**Changes from v2:** `suggest_recipes` is now confirmed used by the Fridge Analyzer tab — restricted to using ONLY fridge ingredients (plus pantry staples), not "mostly". Both `generate_meal_plan` and `suggest_recipes` now calculate REAL nutrients per ingredient, per meal, per day/recipe — previously both only returned ingredient names, no numbers. New shared model `MealIngredient`. `PlannedMeal`, `DayPlan`, and `Recipe` all changed shape as a result.

## 1. Two screens, two functions — how they differ

| | Fridge Analyzer tab → `suggest_recipes` | Weekly Planner tab → `generate_meal_plan` |
|---|---|---|
| Scope | A few recipe suggestions (not a week) | Always 7 days |
| Ingredient rule | ONLY fridge ingredients + pantry staples (salt, oil, spices) | Inventory is a *hint*; Gemini may add other ingredients as needed |
| Family selection | Whole family (as passed in) | User can select a subset (e.g. 2 of 5 members) |
| Per-day customization | None | `day_preferences`: meal type / cuisine / free text, per day |
| Result action | "Love it" or "suggest another" → regenerate | "Create new plan" → regenerate, or proceed to grocery list |
| Nutrients shown | Per recipe | Per meal and per day |

## 2. What the AI module provides

| Function | Purpose | Calls Gemini? |
|---|---|---|
| `analyze_meal` | Meal photo → foods, grams, nutrients, missing nutrients, suggestions | Yes (vision + text) |
| `correct_meal` | Recalculate a meal after the user types a corrected or missing dish name | Yes (text, fallback only) |
| `analyze_fridge` | Fridge/grocery photo → ingredient inventory, with use-soon + expiry estimate | Yes (vision) |
| `suggest_recipes` | Fridge-only recipe suggestions, WITH real calculated nutrients — Fridge Analyzer tab | Yes (text) |
| `generate_meal_plan` | 7-day plan WITH real calculated nutrients per meal/day — Weekly Planner tab | Yes (text) |
| `get_full_week_ingredients` | Combines all 7 days' ingredients into one deduplicated list — no Gemini call | No |
| `generate_grocery_list` | Grocery list from the plan, excluding what's in the fridge inventory, plus user-typed items | RAG first; Gemini only as fallback for items not in the database |

## 3. How to use it

```bash
cd ai-services
pip install -r requirements.txt
cp .env.example .env
```

```python
from ai_services import analyze_meal
result = analyze_meal(image_bytes, "image/jpeg", member)   # returns a MealAnalysis
```

**Environment variables**

```
GEMINI_API_KEY=your_key_here
MODEL_NAME=gemini-flash-lite-latest
SUPABASE_URL=your_supabase_url
SUPABASE_KEY=your_read_only_key
USE_VERTEX=false
GCP_PROJECT=
GCP_LOCATION=us-central1
```

**Notes**
- All functions are synchronous. In FastAPI, use a plain `def` endpoint or `run_in_threadpool`.
- Keep the Gemini key on the server only, never in the mobile app.
- `MODEL_NAME` currently defaults to a lite model to stay within free-tier daily quotas.
- `gemini_client.py` and `nutrition_repo.py` are the only two files that connect externally (Gemini and Supabase). Moving to Google Cloud later only touches those two files and the environment variables above.
- `nutrition_repo.py` currently uses word-overlap matching, NOT a vector database. A true vector search (via pgvector + embeddings) would improve matching further but is a non-trivial addition — recommended only after the Oct 8 deadline, not before.

## 4. Function signatures

```python
analyze_meal(image_bytes: bytes, mime_type: str, member: FamilyMember) -> MealAnalysis

correct_meal(
    previous: MealAnalysis,
    corrections: list[ItemCorrection],
    member: FamilyMember,
) -> MealAnalysis

analyze_fridge(image_bytes: bytes, mime_type: str) -> FridgeInventory

suggest_recipes(inventory: FridgeInventory, family: list[FamilyMember]) -> RecipeSuggestions

generate_meal_plan(
    family: list[FamilyMember],
    inventory: FridgeInventory | None = None,
    day_preferences: list[DayPreference] | None = None,
) -> WeeklyPlan

get_full_week_ingredients(plan: WeeklyPlan) -> list[str]

generate_grocery_list(
    family: list[FamilyMember],
    plan: WeeklyPlan,
    inventory: FridgeInventory | None = None,
    user_requirements: list[str] | None = None,
) -> GroceryList
```

**Important behavior notes:**
- **`suggest_recipes`** uses ONLY the fridge inventory's ingredients, except pantry staples (salt, oil, basic spices, water), which are listed separately and not nutrition-tracked.
- **`generate_meal_plan`** treats `inventory` as a hint, not a hard limit — Gemini may add other ingredients to complete a sensible meal. Works identically whether `inventory` is `None` (no photo) or populated (photo confirmed).
- Both functions calculate REAL nutrients the same way: Gemini names each ingredient and estimates its weight in grams (never estimates calories itself); the code looks up each ingredient in the nutrition database and scales the real per-100g values to that weight; anything not found falls back to a Gemini text estimate, flagged in `unmatched_ingredients`.
- `generate_grocery_list` always excludes anything already matched in `inventory`. If `inventory` is `None`, nothing is excluded.
- `family` can be any subset of the household — pass fewer members for a plan covering only some people.
- `day_preferences` applies ONLY to the named day; every other day follows the general family preferences.

## 5. Data models (`ai_services/schemas.py`)

```python
from typing import Literal, Optional
from pydantic import BaseModel

Confidence = Literal["low", "medium", "high"]

class FamilyMember(BaseModel):
    id: Optional[str] = None
    name: str
    age: int
    gender: str
    allergies: list[str] = []
    food_preferences: list[str] = []
    cuisine_preferences: list[str] = []  # empty = any cuisine

class DayPreference(BaseModel):
    day: str
    meal_type: Optional[str] = None   # one of the fixed meal type dropdown options (§8)
    cuisine: Optional[str] = None
    preference: Optional[str] = None  # free text fallback

class NutrientTotals(BaseModel):
    calories: float = 0
    protein_g: float = 0
    carbs_g: float = 0
    fat_g: float = 0
    fiber_g: float = 0
    iron_mg: float = 0
    calcium_mg: float = 0
    vitamin_a_mcg: float = 0
    vitamin_c_mg: float = 0

class MealIngredient(BaseModel):
    """NEW in v3 — one ingredient with its real calculated nutrition.
    Used inside both PlannedMeal (meal plan) and Recipe (fridge suggestions)."""
    name: str
    food_id: Optional[int] = None     # null if not matched in the database
    weight_g: float
    nutrients: NutrientTotals

class MealItem(BaseModel):
    name: str
    food_id: Optional[int] = None
    weight_g: float
    nutrients: NutrientTotals
    confidence: Confidence
    needs_review: bool = False
    user_corrected: bool = False

class MealAnalysis(BaseModel):
    items: list[MealItem]
    total: NutrientTotals
    missing_nutrients: list[str]
    suggestions: list[str]
    unmatched_items: list[str] = []

class ItemCorrection(BaseModel):
    item_index: Optional[int] = None
    name: str
    weight_g: Optional[float] = None

class MealCorrectionRequest(BaseModel):
    previous: MealAnalysis
    corrections: list[ItemCorrection]

class InventoryItem(BaseModel):
    name: str
    quantity: Optional[str] = None
    use_soon: bool = False
    expiry_estimate: Optional[str] = None

class FridgeInventory(BaseModel):
    items: list[InventoryItem]

class Recipe(BaseModel):
    """CHANGED in v3 — ingredients now carry real nutrition; total_nutrients added."""
    name: str
    ingredients: list[MealIngredient]     # fridge ingredients used, each with calculated nutrition
    pantry_staples: list[str] = []        # salt, oil, spices — assumed available, not tracked
    steps: list[str]
    total_nutrients: NutrientTotals
    unmatched_ingredients: list[str] = []

class RecipeSuggestions(BaseModel):
    recipes: list[Recipe]

class PlannedMeal(BaseModel):
    """CHANGED in v3 — ingredients now carry real nutrition; nutrients field added."""
    name: str
    ingredients: list[MealIngredient]
    notes: Optional[str] = None
    nutrients: NutrientTotals             # total for this one meal

class DayPlan(BaseModel):
    """CHANGED in v3 — nutrients and unmatched_ingredients added."""
    day: str
    breakfast: PlannedMeal
    lunch: PlannedMeal
    dinner: PlannedMeal
    snack: Optional[PlannedMeal] = None
    ingredients: list[str] = []           # ingredient NAMES for the day, combined (unchanged — still used by grocery list)
    nutrients: NutrientTotals             # total for the whole day
    unmatched_ingredients: list[str] = []

class WeeklyPlan(BaseModel):
    days: list[DayPlan]
    notes: list[str] = []

class GroceryItem(BaseModel):
    name: str
    food_id: Optional[int] = None
    quantity: str
    category: str
    source: Literal["missing_ingredient", "preference", "user_added"]

class GroceryListRequest(BaseModel):
    family: list[FamilyMember]
    plan: WeeklyPlan
    inventory: Optional[FridgeInventory] = None
    user_requirements: list[str] = []

class GroceryList(BaseModel):
    items: list[GroceryItem]
    not_in_database: list[str] = []
```

## 6. Sample outputs

**`suggest_recipes` → `RecipeSuggestions`** (Fridge Analyzer tab)
```json
{
  "recipes": [
    {
      "name": "Palak Paneer",
      "ingredients": [
        {"name": "Spinach", "food_id": 27, "weight_g": 150,
         "nutrients": {"calories": 60, "protein_g": 5.4, "carbs_g": 6.4, "fat_g": 0.75,
                       "fiber_g": 3.6, "iron_mg": 5.4, "calcium_mg": 225,
                       "vitamin_a_mcg": 705, "vitamin_c_mg": 15}},
        {"name": "Paneer", "food_id": 25, "weight_g": 100,
         "nutrients": {"calories": 265, "protein_g": 18.3, "carbs_g": 1.2, "fat_g": 20.8,
                       "fiber_g": 0, "iron_mg": 0.2, "calcium_mg": 208,
                       "vitamin_a_mcg": 90, "vitamin_c_mg": 0}}
      ],
      "pantry_staples": ["Salt", "Oil", "Garam masala"],
      "steps": ["Blanch and puree the spinach.", "Cook with cubed paneer and spices."],
      "total_nutrients": {"calories": 325, "protein_g": 23.7, "carbs_g": 7.6, "fat_g": 21.55,
                           "fiber_g": 3.6, "iron_mg": 5.6, "calcium_mg": 433,
                           "vitamin_a_mcg": 795, "vitamin_c_mg": 15},
      "unmatched_ingredients": []
    }
  ]
}
```

**`generate_meal_plan` → `WeeklyPlan`** (1 of 7 days, breakfast only shown)
```json
{
  "days": [
    {
      "day": "Monday",
      "breakfast": {
        "name": "Masala Oats",
        "ingredients": [
          {"name": "Rolled oats", "food_id": 5, "weight_g": 50,
           "nutrients": {"calories": 194, "protein_g": 8.5, "carbs_g": 33, "fat_g": 3.4,
                         "fiber_g": 5, "iron_mg": 2.1, "calcium_mg": 26,
                         "vitamin_a_mcg": 0, "vitamin_c_mg": 0}}
        ],
        "notes": null,
        "nutrients": {"calories": 194, "protein_g": 8.5, "carbs_g": 33, "fat_g": 3.4,
                      "fiber_g": 5, "iron_mg": 2.1, "calcium_mg": 26,
                      "vitamin_a_mcg": 0, "vitamin_c_mg": 0}
      },
      "lunch": "...",
      "dinner": "...",
      "snack": null,
      "ingredients": ["Rolled oats", "Onion", "..."],
      "nutrients": {"calories": 1450, "protein_g": 52, "...": "day total"},
      "unmatched_ingredients": []
    }
  ],
  "notes": ["All meals are vegetarian and peanut-free."]
}
```

**`generate_grocery_list` → `GroceryList`** — unchanged from v2, still reads `day.ingredients` (plain names), unaffected by the nutrient changes above.

## 7. Still needed from the team

- **The exact list of meal type dropdown options** ("11 meal types", frontend doc §12). `DayPreference.meal_type` currently accepts any string.
- **Confirm the shared vocabulary strings** for `allergies`, `food_preferences`, and `cuisine_preferences` — needed for frontend's chip UI and the allergy-safety filter.

*(Resolved in v3: `suggest_recipes` is confirmed needed — it's the Fridge Analyzer tab's function.)*

## 8. Errors

| Code | Meaning | Retry |
|---|---|---|
| `INVALID_IMAGE` | Unsupported format, too large, or unreadable | No |
| `NO_FOOD_DETECTED` | The photo has no recognizable food | No, ask for another photo |
| `AI_BUSY` | Gemini is overloaded (503) or hit a daily quota (429) | Yes for 503; No for 429 |
| `AI_INVALID_RESPONSE` | The model returned unusable output after internal retries | Yes |
| `INVALID_INPUT` | A correction has an empty name or a bad item index | No |
| `INTERNAL` | Any other error | No |

**Retry timing:** capped at roughly 46 seconds total, kept under the frontend's 90-second request timeout.

## 9. Behavior and limits

- **Numbers come from the database, not the model.** True for meal analysis, meal plans, and recipes alike — Gemini identifies foods/weights, the database supplies nutrient values.
- **Grocery list is hybrid RAG + Gemini.** Items found in the nutrition table use real data; items not found fall back to a Gemini guess, flagged in `not_in_database`.
- **Safety net, not a guarantee.** `generate_meal_plan` scans the final plan for allergen keywords that may have slipped through the prompt.
- **Real profile data:** the backend loads `FamilyMember` objects from the database (not hand-typed test data) and passes them in — no change needed on the AI side either way, as long as the shape matches §5.
- **Images:** JPEG or PNG, up to 5 MB, raw bytes + MIME type, not base64.
- **Lists are never `null`**; `food_id`, `quantity`, `notes`, and `expiry_estimate` can be.

## 10. Change rule

- Do not rename or remove a field in `schemas.py` without telling the others first.
- Any schema change is announced in the team chat and updated in the repo the same day.
- Send bug reports with the function name, the input, the output you got, and the output you expected.