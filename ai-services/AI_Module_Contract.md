# AI Module Contract

Owner: AI module (Gemini Vision on Vertex AI, nutrition database on Cloud SQL with pgvector search, Gemini Flash recommendations)
Folder in repo: `ai-services/`
Read by: Backend and Frontend developers

This document covers only what the AI module takes in and gives back. The API endpoints and the app screens are owned by the backend and frontend developers.

## 1. What the AI module provides

Six Python functions that the backend imports and calls. The mobile app never calls them directly.

| Function | Purpose |
|---|---|
| `analyze_meal` | Meal photo to foods, grams, nutrients, missing nutrients, suggestions |
| `correct_meal` | Recalculate a meal after the user types a corrected or missing dish name |
| `analyze_fridge` | Fridge photo to an ingredient inventory |
| `suggest_recipes` | Recipes based on the fridge inventory and family profile, with real nutrition |
| `generate_meal_plan` | 7-day (or fewer-day) plan with ingredients and nutrition, based on the family profile, inventory, per-day preferences and the user's free-text request |
| `generate_grocery_list` | Grocery list from the plan, inventory, preferences, and user-typed requirements |

## 2. How to use it

```bash
cd ai-services
pip install -r requirements.txt
```

```python
from ai_services import analyze_meal
result = analyze_meal(image_bytes, "image/jpeg", member)   # returns a MealAnalysis
```

**Environment variables** (`backend/.env`)

```
# Gemini through Vertex AI (no API key)
USE_VERTEX=true
GOOGLE_CLOUD_PROJECT=your-project-id
GOOGLE_CLOUD_LOCATION=us-central1
MODEL_NAME=gemini-2.5-flash

# Embeddings for semantic food search. Must be the same model and size
# that created the vectors stored in the foods table.
EMBEDDING_MODEL=text-embedding-004
EMBEDDING_DIM=768

# Google Cloud SQL (PostgreSQL + pgvector)
CLOUDSQL_INSTANCE=your-project:your-region:your-instance
DB_NAME=postgres
DB_USER=postgres
DB_PASSWORD=your-password
```

**Sign-in to Google Cloud**
- Locally: `gcloud auth application-default login`.
- On Cloud Run: use a service account with the Vertex AI User and Cloud SQL Client roles.
- There is no Gemini API key and no Supabase key any more. (`USE_VERTEX=false` falls back to a `GEMINI_API_KEY` for quick local tests only.)

**Notes**
- The functions are synchronous. In FastAPI, use a plain `def` endpoint or `run_in_threadpool`.
- Credentials stay on the server only, never in the mobile app.
- Model names change over time. Update `MODEL_NAME` in `.env` if a model is retired.
- The database connection is created on first use, so importing `ai_services` never needs a database connection.

## 3. Function signatures

```python
analyze_meal(image_bytes: bytes, mime_type: str, member: FamilyMember) -> MealAnalysis

correct_meal(
    previous: MealAnalysis,
    corrections: list[ItemCorrection],
    member: FamilyMember | None = None,
) -> MealAnalysis

analyze_fridge(image_bytes: bytes, mime_type: str) -> FridgeInventory

suggest_recipes(inventory: FridgeInventory, family: list[FamilyMember]) -> RecipeSuggestions

generate_meal_plan(
    family: list[FamilyMember],
    inventory: FridgeInventory | None = None,
    day_preferences: list[DayPreference] | None = None,
    avoid_dishes: list[str] | None = None,
    user_message: str | None = None,
) -> WeeklyPlan

generate_grocery_list(
    family: list[FamilyMember],
    plan: WeeklyPlan,
    inventory: FridgeInventory | None,
    user_requirements: list[str],
) -> GroceryList
```

**`generate_meal_plan` arguments**
- `day_preferences`: one entry per day the user customised (see `DayPreference`). A request applies to every meal of that day only and overrides the profile for that day. Days with no request use the family profile. Allergies always apply.
- `user_message`: the free-text request, for example `"plan only tuesday, chinese"`. The AI module works out which days are asked for in code, so `"plan for monday"` returns only Monday, and `"weekend"` or `"weekdays"` are understood. A cuisine named in the message overrides the profile cuisine. A day request outside the asked days is not applied, and a note says so.
- `avoid_dishes`: dish names from a plan the user just rejected, so "Create new plan" gives different dishes.

## 4. Data models (`ai-services/ai_services/schemas.py`)

This file is the single source of truth for the data shapes. The listing below is a summary; if it differs from `schemas.py`, the file wins.

```python
from typing import Literal, Optional, Union
from pydantic import BaseModel

Confidence = Literal["low", "medium", "high"]

class FamilyMember(BaseModel):
    id: Optional[str] = None
    name: str
    age: int
    gender: str
    allergies: list[str] = []                   # e.g. "milk", "peanut", "egg"
    anyother_specific_allergy: list[str] = []   # free-text allergies not in the fixed list
    food_preferences: list[str] = []            # e.g. "vegetarian"
    cuisine_preferences: list[str] = []         # e.g. "Indian", "Chinese"; empty = any cuisine

class DayPreference(BaseModel):
    day: str                                    # "Monday" ... "Sunday"
    meal_type: Optional[Union[str, list[str]]] = None   # dietary type code or label
    cuisine: Optional[Union[str, list[str]]] = None     # up to 2; this day only
    preference: Optional[str] = None            # free text, e.g. "light dinner, low oil"
    # Extra fields are kept. The app's names are mapped automatically:
    #   cuisine_preferences -> cuisine,  notes -> preference

class NutrientTotals(BaseModel):
    calories: float = 0        # kcal
    protein_g: float = 0
    carbs_g: float = 0
    fat_g: float = 0
    fiber_g: float = 0
    iron_mg: float = 0
    calcium_mg: float = 0
    vitamin_a_mcg: float = 0
    vitamin_c_mg: float = 0

class MealIngredient(BaseModel):          # used in meal plans and recipes
    name: str
    food_id: Optional[int] = None         # null if not matched in the database
    weight_g: float
    nutrients: NutrientTotals
    from_fridge: bool = False             # true if it comes from the fridge

class MealItem(BaseModel):
    name: str
    food_id: Optional[int] = None         # null if not matched in the database
    weight_g: float
    nutrients: NutrientTotals
    confidence: Confidence
    needs_review: bool = False            # true if confidence is low or the food was not matched
    user_corrected: bool = False          # true if the name was typed by the user

class MealAnalysis(BaseModel):
    items: list[MealItem]
    total: NutrientTotals
    missing_nutrients: list[str]          # labels: Protein, Fiber, Iron, Calcium, Vitamin A, Vitamin C
    suggestions: list[str]
    unmatched_items: list[str] = []       # foods seen or typed but not in the database

class ItemCorrection(BaseModel):
    item_index: Optional[int] = None      # position in MealAnalysis.items; null = add a dish that was missed
    name: str                             # dish name typed by the user
    weight_g: Optional[float] = None      # optional; null keeps the old weight (replace) or uses a standard serving (add)

class MealCorrectionRequest(BaseModel):
    previous: MealAnalysis
    corrections: list[ItemCorrection]

class InventoryItem(BaseModel):
    name: str
    quantity: Optional[str] = None        # e.g. "6", "1 bunch"; may be null
    use_soon: bool = False
    expiry_estimate: Optional[str] = None # e.g. "Use within 3 days"

class FridgeInventory(BaseModel):
    items: list[InventoryItem]

class Recipe(BaseModel):
    name: str
    ingredients: list[MealIngredient]     # fridge ingredients used, with calculated nutrition
    pantry_staples: list[str] = []        # salt, oil, spices: assumed available, not tracked
    steps: list[str]
    total_nutrients: NutrientTotals
    unmatched_ingredients: list[str] = [] # not found in the database

class RecipeSuggestions(BaseModel):
    recipes: list[Recipe]

class PlannedMeal(BaseModel):
    name: str
    ingredients: list[MealIngredient]     # each with calculated nutrition
    notes: Optional[str] = None
    nutrients: NutrientTotals             # total for this meal

class DayPlan(BaseModel):
    day: str                              # "Monday" ... "Sunday"
    breakfast: PlannedMeal
    lunch: PlannedMeal
    dinner: PlannedMeal
    snack: Optional[PlannedMeal] = None
    ingredients: list[str] = []           # all ingredient names for the day, no duplicates
    nutrients: NutrientTotals             # total for the whole day
    unmatched_ingredients: list[str] = [] # not found in the database

class WeeklyPlan(BaseModel):
    days: list[DayPlan]                   # Monday to Sunday; fewer days if the request limits the scope
    notes: list[str] = []

class GroceryItem(BaseModel):
    name: str
    food_id: Optional[int] = None
    quantity: str
    category: str                         # e.g. "Vegetables", "Dairy", "Grains"
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

## 5. Sample outputs

These values are sample data only.

**`analyze_meal` returns `MealAnalysis`**

```json
{
  "items": [
    {
      "name": "Cooked basmati rice",
      "food_id": 12,
      "weight_g": 150,
      "nutrients": {"calories": 195, "protein_g": 4, "carbs_g": 42, "fat_g": 0.4,
                    "fiber_g": 0.6, "iron_mg": 0.5, "calcium_mg": 15,
                    "vitamin_a_mcg": 0, "vitamin_c_mg": 0},
      "confidence": "high",
      "needs_review": false,
      "user_corrected": false
    }
  ],
  "total": {"calories": 195, "protein_g": 4, "carbs_g": 42, "fat_g": 0.4,
            "fiber_g": 0.6, "iron_mg": 0.5, "calcium_mg": 15,
            "vitamin_a_mcg": 0, "vitamin_c_mg": 0},
  "missing_nutrients": ["Vitamin C", "Fiber"],
  "suggestions": ["Add a cucumber and tomato salad to increase fiber and vitamin C."],
  "unmatched_items": []
}
```

**`correct_meal` input and behavior**

```json
{
  "previous": { "...": "the full MealAnalysis returned earlier" },
  "corrections": [
    {"item_index": 1, "name": "Chana dal", "weight_g": null},
    {"item_index": null, "name": "Cucumber salad", "weight_g": 60}
  ]
}
```

- `item_index` set: that dish is replaced by the typed name. The old weight is kept unless `weight_g` is given.
- `item_index` null: a new dish is added. If `weight_g` is null, a standard serving from the database is used.
- The output is a full `MealAnalysis` with everything recalculated. Corrected items have `user_corrected: true`.
- If a typed dish is not in the database, it stays in the list with zero nutrients, `food_id: null`, `needs_review: true`, and its name is added to `unmatched_items`.
- This function does not use the photo, so it is fast.

**`analyze_fridge` returns `FridgeInventory`**

```json
{
  "items": [
    {"name": "Spinach", "quantity": "1 bunch", "use_soon": true, "expiry_estimate": "Use within 2 days"},
    {"name": "Eggs", "quantity": "6", "use_soon": false, "expiry_estimate": "About a week"}
  ]
}
```

**`suggest_recipes` returns `RecipeSuggestions`**

```json
{
  "recipes": [
    {
      "name": "Spinach omelette",
      "ingredients": [
        {"name": "Spinach", "food_id": 301, "weight_g": 60, "from_fridge": true,
         "nutrients": {"calories": 14, "protein_g": 1.7, "carbs_g": 2.2, "fat_g": 0.2,
                       "fiber_g": 1.3, "iron_mg": 1.6, "calcium_mg": 59,
                       "vitamin_a_mcg": 281, "vitamin_c_mg": 17}},
        {"name": "Eggs", "food_id": 44, "weight_g": 100, "from_fridge": true,
         "nutrients": {"calories": 155, "protein_g": 13, "carbs_g": 1.1, "fat_g": 11,
                       "fiber_g": 0, "iron_mg": 1.8, "calcium_mg": 50,
                       "vitamin_a_mcg": 160, "vitamin_c_mg": 0}}
      ],
      "pantry_staples": ["Salt", "Oil"],
      "steps": ["Chop the spinach.", "Beat the eggs and mix in the spinach.", "Cook in a pan for 3 minutes."],
      "total_nutrients": {"calories": 169, "protein_g": 14.7, "carbs_g": 3.3, "fat_g": 11.2,
                          "fiber_g": 1.3, "iron_mg": 3.4, "calcium_mg": 109,
                          "vitamin_a_mcg": 441, "vitamin_c_mg": 17},
      "unmatched_ingredients": []
    }
  ]
}
```

**`generate_meal_plan` returns `WeeklyPlan`** (shortened: one day, one meal shown in full; nutrient objects shortened to calories)

```json
{
  "days": [
    {
      "day": "Tuesday",
      "breakfast": {
        "name": "Vegetable congee",
        "ingredients": [
          {"name": "Rice", "food_id": 12, "weight_g": 60, "from_fridge": false,
           "nutrients": {"calories": 78}},
          {"name": "Spinach", "food_id": 301, "weight_g": 40, "from_fridge": true,
           "nutrients": {"calories": 9}}
        ],
        "notes": "Uses spinach before it spoils.",
        "nutrients": {"calories": 87}
      },
      "lunch": {"name": "...", "ingredients": [], "notes": null, "nutrients": {"calories": 0}},
      "dinner": {"name": "...", "ingredients": [], "notes": null, "nutrients": {"calories": 0}},
      "snack": null,
      "ingredients": ["Rice", "Spinach"],
      "nutrients": {"calories": 87},
      "unmatched_ingredients": []
    }
  ],
  "notes": ["Plan avoids peanuts."]
}
```

**`generate_grocery_list` returns `GroceryList`**

```json
{
  "items": [
    {"name": "Broccoli", "food_id": 231, "quantity": "500 g", "category": "Vegetables", "source": "missing_ingredient"},
    {"name": "Yogurt", "food_id": 87, "quantity": "1 kg", "category": "Dairy", "source": "preference"},
    {"name": "Almond flour", "food_id": null, "quantity": "1 pack", "category": "Other", "source": "user_added"}
  ],
  "not_in_database": ["Almond flour"]
}
```

## 6. Errors

The functions raise `AIServiceError(code, message, retry)` (from `ai_services.errors`).

| Code | Meaning | Retry |
|---|---|---|
| `INVALID_IMAGE` | Unsupported format, too large, or unreadable | No |
| `NO_FOOD_DETECTED` | The photo has no recognizable food | No, ask for another photo |
| `AI_BUSY` | Gemini is overloaded or rate limited | Yes |
| `AI_INVALID_RESPONSE` | The model returned unusable output after internal retries | Yes |
| `INVALID_INPUT` | A correction has an empty name or a bad item index | No |
| `INTERNAL` | Any other error | No |

`message` is a short text that is safe to show to the user.

Any other exception (for example a database or Google Cloud error) is not an `AIServiceError`. The backend should catch it, log it, and return a normal HTTP error. Note that an unhandled crash is sent by the server without CORS headers, so a browser shows it as a CORS error instead of the real message.

## 7. Behavior and limits

**Where the numbers come from**
- The AI names ingredients and estimates weights. It never estimates calories or nutrients. All nutrient values are calculated from the foods table in Cloud SQL.
- Each ingredient is matched to the foods table by word matching first, then by vector (meaning) search with pgvector as a fallback. Vector matches below the strong-match threshold are flagged `needs_review`.
- A match is accepted only if it really is the same food. Prepared dishes and different products are rejected, so "chicken" is not matched to "Fried chicken", "green onion" is not matched to "Green tea", and "chicken curry" is not matched to "Curry powder".
- An ingredient with no good match has `food_id: null` and zero nutrients, and its name is listed in `unmatched_ingredients` (or `unmatched_items`, or `not_in_database` for grocery lists). It is never given an invented number.
- The same ingredient listed twice in one meal is merged into one line with the weights added up.
- Ingredient names shown to the user are the plain ingredient names, not the database row's label.
- Grocery lists contain only ingredients that are not already in the fridge (`from_fridge` is false), plus preference and user-added items.

**Safety**
- Items that match a member's allergies are removed in code after generation.
- Suggestions are general nutrition guidance, not medical advice.

**Scope and preferences**
- `cuisine_preferences` on each `FamilyMember` is used by `suggest_recipes`, `generate_meal_plan`, and `generate_grocery_list`. If the list is empty, any cuisine can be used.
- Per-day preferences and the `user_message` follow the rules in section 3. Priority for a cuisine, highest first: a day-specific request, then the cuisine named in the message, then the profile.
- Meal and fridge photo analysis does not depend on cuisine and works for any dish.

**Input limits**
- Images: JPEG or PNG (WebP also works), up to 5 MB. Pass raw bytes and the MIME type, not base64.
- Expected time is about 5 to 30 seconds per call. A full weekly plan is the slowest and can take several minutes in the worst case. Use a long timeout for it (the benchmark target is 300 seconds), and 90 seconds for the other functions.

**Output format**
- Weights in grams, calories in kcal, iron, calcium, and vitamin C in mg, vitamin A in mcg.
- `suggestions`, `notes`, and recipe `steps` are plain text with no markdown.
- Lists are never `null`. `food_id`, `quantity`, and `notes` can be `null`.

## 8. What the AI module needs from the team

- **Backend:** pass the image as bytes plus the MIME type, and pass the family member data as `FamilyMember` objects loaded from the database.
- **Backend:** run with Google Cloud credentials and the Cloud SQL settings above. The foods table (with its embeddings) lives in Cloud SQL. The backend keeps ownership of profiles, history, and saved plans.
- **Backend:** make sure the backend imports the `ai_services` folder of the same project (the `[startup] ai_services loaded from` line shows which one).
- **Backend and frontend:** for corrections, send back the previous `MealAnalysis` and the list of `ItemCorrection` items.
- **Backend and frontend:** for the meal plan, send `day_preferences` and the user's free-text request. The request is best sent as its own `message` field. If it is not, the backend extracts it from the days' `notes`.
- **Backend and frontend:** for the grocery list, send the meal plan, the inventory (optional), and any items or requirements the user typed as `user_requirements`.

## 9. Change rule

- Do not rename or remove a field in `schemas.py` without telling the others first.
- Any schema change is announced in the team chat and updated in the repo the same day.
- Send bug reports with the function name, the input, the output you got, and the output you expected.