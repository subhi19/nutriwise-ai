"""
Shared data models for the AI module (ai-services).

This file is the single source of truth for the data shapes passed between
the backend, the AI functions, and (via the backend's API) the Flutter app.

Do not rename or remove a field here without telling the team first.
"""

from typing import Literal, Optional
from pydantic import BaseModel

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
    anyother_specific_allergy: list[str] = []  # free-text allergies not covered by the fixed list
    food_preferences: list[str] = []     # e.g. "vegetarian"
    cuisine_preferences: list[str] = []  # e.g. "Indian", "Italian", "Chinese"; empty = any cuisine


class DayPreference(BaseModel):
    day: str                          # "Monday" ... "Sunday"
    meal_type: Optional[str] = None   # one of the fixed meal type options (see frontend's meal type list)
    cuisine: Optional[str] = None     # optional cuisine override for this day only
    preference: Optional[str] = None  # free text, e.g. "light dinner, low oil"; combined with the two fields above if both given


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


class MealItem(BaseModel):
    name: str
    food_id: Optional[int] = None       # null if not matched in the database
    weight_g: float
    nutrients: NutrientTotals
    confidence: Confidence
    needs_review: bool = False          # true if confidence is low or the food was not matched
    user_corrected: bool = False        # true if the name was typed by the user


class MealAnalysis(BaseModel):
    items: list[MealItem]
    total: NutrientTotals
    missing_nutrients: list[str]        # labels: Protein, Fiber, Iron, Calcium, Vitamin A, Vitamin C
    suggestions: list[str]
    unmatched_items: list[str] = []     # foods seen or typed but not in the database


class ItemCorrection(BaseModel):
    item_index: Optional[int] = None    # position in MealAnalysis.items; null = add a dish that was missed
    name: str                           # dish name typed by the user
    weight_g: Optional[float] = None    # optional; null keeps the old weight (replace) or uses a standard serving (add)


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
    expiry_estimate: Optional[str] = None  # e.g. "Use within 3 days", "About a week"


class FridgeInventory(BaseModel):
    items: list[InventoryItem]


class Recipe(BaseModel):
    name: str
    ingredients: list[MealIngredient]    # fridge ingredients used, each with real calculated nutrition
    pantry_staples: list[str] = []       # salt, oil, common spices — assumed available, not nutrition-tracked
    steps: list[str]
    total_nutrients: NutrientTotals
    unmatched_ingredients: list[str] = []  # ingredients not found in our database


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
    ingredients: list[str] = []         # all ingredient NAMES for the day, combined, no duplicates (still used by grocery list)
    nutrients: NutrientTotals           # total for the whole day
    unmatched_ingredients: list[str] = []  # ingredients this day not found in our database


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