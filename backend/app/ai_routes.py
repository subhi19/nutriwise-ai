"""
ai_routes.py

This file goes in the BACKEND folder (backend/app/), not ai-services.
It wires your ai_services functions up to real HTTP endpoints the
Flutter app can call.

HOW TO USE THIS IN main.py:

    from app.ai_routes import router as ai_router
    app.include_router(ai_router)

WHAT YOU (backend developer) STILL NEED TO FILL IN:
  - load_family_member() and load_family() — right now they're stubs.
    Replace them with real Supabase queries that build FamilyMember
    objects from your family_members table.
  - Add authentication/session checks if needed (not included here).

Everything else should work as-is once ai_services is installed.
"""

from fastapi import APIRouter, UploadFile, File, Form, HTTPException
from pydantic import BaseModel

from ai_services import (
    analyze_meal, correct_meal, analyze_fridge, suggest_recipes,
    generate_meal_plan, generate_grocery_list,
)
from ai_services.errors import AIServiceError, STATUS_BY_CODE
from ai_services.schemas import (
    FamilyMember, MealAnalysis, MealCorrectionRequest,
    FridgeInventory, RecipeSuggestions, WeeklyPlan, DayPreference,
    GroceryList,
)

router = APIRouter(prefix="/api", tags=["ai"])


# ---------------------------------------------------------------------------
# TODO (backend): replace these two stubs with real Supabase queries
# ---------------------------------------------------------------------------

def load_family_member(member_id: str) -> FamilyMember:
    """
    STUB — replace with a real query to your family_members table.
    Should return a FamilyMember built from that member's saved data.
    """
    raise NotImplementedError("Wire this up to Supabase: SELECT * FROM family_members WHERE id = member_id")


def load_family(member_ids: list[str]) -> list[FamilyMember]:
    """
    STUB — replace with a real query. member_ids is whichever family
    members the user has checked/selected on the frontend (may be
    fewer than the household's total members).
    """
    raise NotImplementedError("Wire this up to Supabase: SELECT * FROM family_members WHERE id IN member_ids")


# ---------------------------------------------------------------------------
# Shared error handling — every endpoint below uses this the same way
# ---------------------------------------------------------------------------

def _handle_ai_error(e: AIServiceError):
    """Turns an AIServiceError into the standard error JSON shape for the app."""
    raise HTTPException(
        status_code=STATUS_BY_CODE[e.code],
        detail={"error": {"code": e.code, "message": e.message, "retry": e.retry}},
    )


# ---------------------------------------------------------------------------
# 1. Meal analysis
# ---------------------------------------------------------------------------

@router.post("/meal/analyze", response_model=MealAnalysis)
def meal_analyze(
    image: UploadFile = File(...),
    member_id: str = Form(...),
):
    member = load_family_member(member_id)
    image_bytes = image.file.read()

    try:
        return analyze_meal(image_bytes, image.content_type, member)
    except AIServiceError as e:
        _handle_ai_error(e)


# ---------------------------------------------------------------------------
# 2. Meal correction
# ---------------------------------------------------------------------------

class MealCorrectBody(BaseModel):
    member_id: str
    request: MealCorrectionRequest


@router.post("/meal/correct", response_model=MealAnalysis)
def meal_correct(body: MealCorrectBody):
    member = load_family_member(body.member_id)

    try:
        return correct_meal(body.request.previous, body.request.corrections, member)
    except AIServiceError as e:
        _handle_ai_error(e)


# ---------------------------------------------------------------------------
# 3. Fridge analysis
# ---------------------------------------------------------------------------

@router.post("/fridge/analyze", response_model=FridgeInventory)
def fridge_analyze(image: UploadFile = File(...)):
    image_bytes = image.file.read()

    try:
        return analyze_fridge(image_bytes, image.content_type)
    except AIServiceError as e:
        _handle_ai_error(e)


# ---------------------------------------------------------------------------
# 4. Recipe suggestions (Fridge Analyzer tab)
# ---------------------------------------------------------------------------

class RecipeSuggestBody(BaseModel):
    member_ids: list[str]
    inventory: FridgeInventory
    avoid_dishes: list[str] | None = None   # recipe names from the rejected result, for "suggest another"


@router.post("/recipes/suggest", response_model=RecipeSuggestions)
def recipes_suggest(body: RecipeSuggestBody):
    family = load_family(body.member_ids)

    try:
        return suggest_recipes(body.inventory, family, body.avoid_dishes)
    except AIServiceError as e:
        _handle_ai_error(e)


# ---------------------------------------------------------------------------
# 5. Weekly meal plan (Weekly Planner tab)
# ---------------------------------------------------------------------------

class MealPlanBody(BaseModel):
    member_ids: list[str]                               # whichever members the user checked
    inventory: FridgeInventory | None = None              # from a photo, or None if skipped
    day_preferences: list[DayPreference] | None = None
    avoid_dishes: list[str] | None = None                 # dish names from the rejected plan, for "create new plan"


@router.post("/meal-plan/generate", response_model=WeeklyPlan)
def meal_plan_generate(body: MealPlanBody):
    family = load_family(body.member_ids)

    try:
        return generate_meal_plan(family, body.inventory, body.day_preferences, body.avoid_dishes)
    except AIServiceError as e:
        _handle_ai_error(e)


# ---------------------------------------------------------------------------
# 6. Grocery list
# ---------------------------------------------------------------------------

class GroceryListBody(BaseModel):
    member_ids: list[str]
    plan: WeeklyPlan
    inventory: FridgeInventory | None = None
    user_requirements: list[str] = []


@router.post("/grocery-list/generate", response_model=GroceryList)
def grocery_list_generate(body: GroceryListBody):
    family = load_family(body.member_ids)

    try:
        return generate_grocery_list(family, body.plan, body.inventory, body.user_requirements)
    except AIServiceError as e:
        _handle_ai_error(e)