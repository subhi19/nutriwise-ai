"""
Shared data models for the AI module (ai-services).

This file is the single source of truth for the data shapes passed between
the backend, the AI functions, and (via the backend's API) the Flutter app.

Do not rename or remove a field here without telling the team first.
"""
import json
from typing import Any, Literal, Optional, Union
from pydantic import BaseModel, ConfigDict, field_validator, model_validator

Confidence = Literal["low", "medium", "high"]

# ---------------------------------------------------------------------------
# Family profile
# ---------------------------------------------------------------------------

class FamilyMember(BaseModel):
    id: Optional[str] = None
    name: str
    age: int
    gender: str
    allergies: list[str] = []            # e.g. "milk", "peanut", "egg"
    # free-text allergies not covered by the fixed list
    anyother_specific_allergy: list[str] = []
    food_preferences: list[str] = []     # e.g. "vegetarian"
    # e.g. "Indian", "Italian", "Chinese"; empty = any cuisine
    cuisine_preferences: list[str] = []

    @field_validator("id", mode="before")
    @classmethod
    def coerce_id_to_str(cls, v: Any) -> Optional[str]:
        if v is None:
            return None
        return str(v)

    @field_validator(
        "allergies",
        "anyother_specific_allergy",
        "food_preferences",
        "cuisine_preferences",
        mode="before",
    )
    @classmethod
    def coerce_to_list(cls, v: Any) -> list[str]:
        if v is None:
            return []
        if isinstance(v, list):
            return [str(x).strip() for x in v if str(x).strip()]
        if isinstance(v, str):
            text = v.strip()
            if not text:
                return []
            try:
                parsed = json.loads(text)
                if isinstance(parsed, list):
                    return [str(x).strip() for x in parsed if str(x).strip()]
            except (ValueError, json.JSONDecodeError):
                pass
            return [p.strip() for p in text.split(",") if p.strip()]
        return []


class DayPreference(BaseModel):
    # Keep any extra field the app sends instead of silently dropping it.
    model_config = ConfigDict(extra="allow")

    day: str                          # "Monday" ... "Sunday"
    # a meal type code/label, or a list of them (the app allows 1 to 2)
    meal_type: Optional[Union[str, list[str]]] = None
    # cuisine override for this day only; the app allows up to 2
    cuisine: Optional[Union[str, list[str]]] = None
    # free text, e.g. "light dinner, low oil"
    preference: Optional[str] = None

    @model_validator(mode="before")
    @classmethod
    def map_app_field_names(cls, data: Any) -> Any:
        """The Flutter app sends `cuisine_preferences` and `notes`, while this
        schema uses `cuisine` and `preference`. Map the app's names onto the
        schema's names so nothing is lost."""
        if not isinstance(data, dict):
            return data
        data = dict(data)

        def pick(*keys):
            for k in keys:
                v = data.get(k)
                if v not in (None, "", [], {}):
                    return v
            return None

        if not data.get("meal_type"):
            data["meal_type"] = pick("mealType", "meal_type_code",
                                     "meal_type_codes", "mealTypeCodes")
        if not data.get("cuisine"):
            data["cuisine"] = pick("cuisines", "cuisine_preferences",
                                   "cuisinePreferences")
        if not data.get("preference"):
            note = pick("notes", "note", "preferences", "request", "text")
            if isinstance(note, list):
                note = ", ".join(str(n) for n in note)
            data["preference"] = note
        return data


# ---------------------------------------------------------------------------
# Meal analysis
# ---------------------------------------------------------------------------

class NutrientTotals(BaseModel):
    calories: float = 0         # kcal
    protein_g: float = 0
    carbs_g: float = 0
    fat_g: float = 0
    fiber_g: float = 0
    iron_mg: float = 0
    calcium_mg: float = 0
    vitamin_a_mcg: float = 0
    vitamin_c_mg: float = 0


class MealIngredient(BaseModel):
    """One ingredient with its real, calculated nutrition — used inside
    both a meal plan's PlannedMeal and a Recipe, so a single piece of
    code can build either one the same way."""
    name: str
    food_id: Optional[int] = None       # null if not matched in the database
    weight_g: float
    nutrients: NutrientTotals
    # true if this ingredient comes from the fridge; the grocery list only
    # includes ingredients where this is false
    from_fridge: bool = False


class MealItem(BaseModel):
    name: str
    food_id: Optional[int] = None       # null if not matched in the database
    weight_g: float
    nutrients: NutrientTotals
    confidence: Confidence
    # true if confidence is low or the food was not matched
    needs_review: bool = False
    user_corrected: bool = False        # true if the name was typed by the user


class MealAnalysis(BaseModel):
    items: list[MealItem]
    total: NutrientTotals
    # labels: Protein, Fiber, Iron, Calcium, Vitamin A, Vitamin C
    missing_nutrients: list[str]
    suggestions: list[str]
    # foods seen or typed but not in the database
    unmatched_items: list[str] = []


class ItemCorrection(BaseModel):
    # position in MealAnalysis.items; null = add a dish that was missed
    item_index: Optional[int] = None
    name: str                           # dish name typed by the user
    # optional; null keeps the old weight (replace) or uses a standard serving (add)
    weight_g: Optional[float] = None


class MealCorrectionRequest(BaseModel):
    previous: MealAnalysis
    corrections: list[ItemCorrection]


# ---------------------------------------------------------------------------
# Fridge analysis and recipes
# ---------------------------------------------------------------------------

class InventoryItem(BaseModel):
    name: str
    quantity: Optional[str] = None      # e.g. "6", "1 bunch"; may be null
    use_soon: bool = False
    # e.g. "Use within 3 days", "About a week"
    expiry_estimate: Optional[str] = None


class FridgeInventory(BaseModel):
    items: list[InventoryItem]


class Recipe(BaseModel):
    name: str
    # fridge ingredients used, each with real calculated nutrition
    ingredients: list[MealIngredient]
    # salt, oil, common spices — assumed available, not nutrition-tracked
    pantry_staples: list[str] = []
    steps: list[str]
    total_nutrients: NutrientTotals
    # ingredients not found in our database
    unmatched_ingredients: list[str] = []


class RecipeSuggestions(BaseModel):
    recipes: list[Recipe]


# ---------------------------------------------------------------------------
# Weekly meal plan
# ---------------------------------------------------------------------------

class PlannedMeal(BaseModel):
    name: str
    ingredients: list[MealIngredient]    # each with real calculated nutrition
    notes: Optional[str] = None
    nutrients: NutrientTotals            # total for this one meal


class DayPlan(BaseModel):
    day: str                            # "Monday" ... "Sunday"
    breakfast: PlannedMeal
    lunch: PlannedMeal
    dinner: PlannedMeal
    snack: Optional[PlannedMeal] = None
    # all ingredient NAMES for the day, combined, no duplicates (still used by grocery list)
    ingredients: list[str] = []
    nutrients: NutrientTotals           # total for the whole day
    # ingredients this day not found in our database
    unmatched_ingredients: list[str] = []


class WeeklyPlan(BaseModel):
    days: list[DayPlan]                 # always 7 items, Monday to Sunday
    notes: list[str] = []


# ---------------------------------------------------------------------------
# Grocery list
# ---------------------------------------------------------------------------

class GroceryItem(BaseModel):
    name: str
    food_id: Optional[int] = None
    quantity: str
    category: str                       # e.g. "Vegetables", "Dairy", "Grains"
    source: Literal["missing_ingredient", "preference", "user_added"]


class GroceryListRequest(BaseModel):
    family: list[FamilyMember]
    plan: WeeklyPlan
    inventory: Optional[FridgeInventory] = None
    user_requirements: list[str] = []


class GroceryList(BaseModel):
    items: list[GroceryItem]
    not_in_database: list[str] = []