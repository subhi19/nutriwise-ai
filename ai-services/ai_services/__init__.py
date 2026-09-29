"""
ai_services entry point providing the 6 AI functions.
Currently returns mock data adhering to schemas.py.
"""
from ai_services.schemas import (
    FamilyMember,
    MealAnalysis,
    MealItem,
    NutrientTotals,
    ItemCorrection,
    FridgeInventory,
    InventoryItem,
    Recipe,
    RecipeSuggestions,
    PlannedMeal,
    DayPlan,
    WeeklyPlan,
    GroceryItem,
    GroceryList,
)
from ai_services.errors import no_food_detected


def analyze_meal(image_bytes: bytes, mime_type: str, member: FamilyMember) -> MealAnalysis:
    # Example check for invalid data
    if not image_bytes:
        raise no_food_detected()

    mock_nutrients = NutrientTotals(
        calories=305, protein_g=10, carbs_g=57, fat_g=3.4,
        fiber_g=3.6, iron_mg=2.1, calcium_mg=40, vitamin_a_mcg=5, vitamin_c_mg=1
    )
    items = [
        MealItem(
            name="Cooked basmati rice",
            food_id=12,
            weight_g=150.0,
            nutrients=NutrientTotals(
                calories=195, protein_g=4, carbs_g=42, fat_g=0.4, fiber_g=0.6),
            confidence="high"
        ),
        MealItem(
            name="Yellow dal",
            food_id=48,
            weight_g=100.0,
            nutrients=NutrientTotals(
                calories=110, protein_g=6, carbs_g=15, fat_g=3.0, fiber_g=3.0),
            confidence="medium"
        )
    ]
    return MealAnalysis(
        items=items,
        total=mock_nutrients,
        missing_nutrients=["Vitamin C", "Fiber"],
        suggestions=[
            "Add a cucumber and tomato salad to increase fiber and vitamin C."]
    )


def correct_meal(previous: MealAnalysis, corrections: list[ItemCorrection], member: FamilyMember) -> MealAnalysis:
    # Return previous analysis marked as corrected
    for item in previous.items:
        item.user_corrected = True
    return previous


def analyze_fridge(image_bytes: bytes, mime_type: str) -> FridgeInventory:
    return FridgeInventory(
        items=[
            InventoryItem(name="Spinach", quantity="1 bunch", use_soon=True),
            InventoryItem(name="Eggs", quantity="6", use_soon=False),
            InventoryItem(name="Milk", quantity=None, use_soon=False),
        ]
    )


def suggest_recipes(inventory: FridgeInventory, family: list[FamilyMember]) -> RecipeSuggestions:
    return RecipeSuggestions(
        recipes=[
            Recipe(
                name="Spinach omelette",
                ingredients_from_fridge=["Spinach", "Eggs"],
                extra_ingredients=["Salt", "Pepper"],
                steps=["Chop spinach.", "Whisk eggs.",
                       "Cook in pan for 3 minutes."]
            )
        ]
    )


def generate_meal_plan(family: list[FamilyMember], inventory: FridgeInventory | None = None) -> WeeklyPlan:
    days = ["Monday", "Tuesday", "Wednesday",
            "Thursday", "Friday", "Saturday", "Sunday"]
    plan_days = []
    for d in days:
        plan_days.append(
            DayPlan(
                day=d,
                breakfast=PlannedMeal(name="Oats with banana", ingredients=[
                                      "Oats", "Banana", "Milk"]),
                lunch=PlannedMeal(name="Brown rice with dal", ingredients=[
                                  "Brown rice", "Yellow dal"]),
                dinner=PlannedMeal(name="Vegetable soup", ingredients=[
                                   "Carrots", "Beans", "Tomato"]),
                snack=None,
                ingredients=["Oats", "Banana", "Milk", "Brown rice",
                             "Yellow dal", "Carrots", "Beans", "Tomato"]
            )
        )
    return WeeklyPlan(days=plan_days, notes=["Plan aligns with family preferences."])


def generate_grocery_list(
    family: list[FamilyMember],
    plan: WeeklyPlan,
    inventory: FridgeInventory | None = None,
    user_requirements: list[str] = [],
) -> GroceryList:
    return GroceryList(
        items=[
            GroceryItem(name="Broccoli", food_id=231, quantity="500 g",
                        category="Vegetables", source="missing_ingredient"),
            GroceryItem(name="Yogurt", food_id=87, quantity="1 kg",
                        category="Dairy", source="preference"),
        ],
        not_in_database=[]
    )
