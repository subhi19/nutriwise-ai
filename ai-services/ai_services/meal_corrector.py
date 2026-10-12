"""
meal_corrector.py

This is correct_meal() — used when the user edits a wrong dish name or
adds one Gemini Vision missed. It does NOT use the photo again, so it's
fast. It reuses the same database lookup and Gemini fallback as
meal_analyzer.py, so a corrected item is calculated exactly the same way
as a normal one.
"""

from nutrition_repo import search_food
from calculator import calculate_nutrients, add_totals
from schemas import MealAnalysis, MealItem, NutrientTotals, ItemCorrection
from meal_analyzer import estimate_nutrients_with_gemini, _find_missing_nutrients, _get_suggestions
from errors import invalid_input


def _resolve_item(name: str, weight_g: float | None) -> MealItem:
    """
    Looks up one food name. If it's in our database, use the real numbers.
    If not, fall back to a Gemini estimate (same as meal_analyzer.py does).

    weight_g can be None when the user added a dish without a weight. Then
    we use that food's typical serving from the database, or 100 g only if
    the food isn't in the database at all.
    """
    food = search_food(name)

    if weight_g is None:
        weight_g = (food.get("typical_serving_g") if food else None) or 100

    if food is not None:
        nutrients = calculate_nutrients(food, weight_g)
        return MealItem(
            name=food["name"],
            food_id=food["id"],
            weight_g=weight_g,
            nutrients=NutrientTotals(**nutrients),
            confidence="high",  # the user confirmed this name themselves
            needs_review=False,
            user_corrected=True,
        )
    else:
        estimated = estimate_nutrients_with_gemini(name, weight_g)
        return MealItem(
            name=name,
            food_id=None,
            weight_g=weight_g,
            nutrients=NutrientTotals(**estimated),
            confidence="low",  # still an estimate, not from our database
            needs_review=True,  # keep flagged so it can be added to the database later
            user_corrected=True,
        )


def correct_meal(
    previous: MealAnalysis,
    corrections: list[ItemCorrection],
    member=None,
) -> MealAnalysis:
    """
    previous: the MealAnalysis the user is correcting
    corrections: what the user typed (see ItemCorrection in schemas.py)

    Returns a brand new MealAnalysis with the corrections applied and
    everything recalculated.
    """
    # Start from a copy of the previous items, so we can edit or add to it
    items = list(previous.items)

    for correction in corrections:
        # Basic input checks, reported with the standard INVALID_INPUT error
        if not correction.name or not correction.name.strip():
            raise invalid_input("Please type a dish name.")
        if correction.item_index is not None and not (0 <= correction.item_index < len(items)):
            raise invalid_input(
                "That dish no longer exists in this meal. Please refresh and try again.")

        # Keep the old weight if the user didn't give a new one.
        # For a brand new dish with no weight, stay None so _resolve_item
        # can use that food's typical serving from the database.
        if correction.weight_g is not None:
            weight_g = correction.weight_g
        elif correction.item_index is not None:
            weight_g = items[correction.item_index].weight_g
        else:
            weight_g = None

        new_item = _resolve_item(correction.name, weight_g)

        if correction.item_index is not None:
            # Replace the existing item at this position
            items[correction.item_index] = new_item
        else:
            # Add as a new item (a dish the photo missed)
            items.append(new_item)

    # Recalculate everything from scratch, same as a fresh analysis would
    total_dict = add_totals([item.nutrients.model_dump() for item in items])
    total = NutrientTotals(**total_dict)

    missing = _find_missing_nutrients(total_dict)
    suggestions = _get_suggestions(total_dict, missing)

    unmatched = [item.name for item in items if item.food_id is None]

    return MealAnalysis(
        items=items,
        total=total,
        missing_nutrients=missing,
        suggestions=suggestions,
        unmatched_items=unmatched,
    )


# --- Quick test you can run directly ----------------------------------------
# python meal_corrector.py
# (This uses a fake "previous" result so you don't need to run the whole
#  Gemini Vision step just to test corrections.)

if __name__ == "__main__":
    from schemas import MealItem as _MealItem

    fake_previous = MealAnalysis(
        items=[
            _MealItem(
                name="dry chicken curry", food_id=None, weight_g=150,
                nutrients=NutrientTotals(), confidence="low",
                needs_review=True, user_corrected=False,
            ),
        ],
        total=NutrientTotals(),
        missing_nutrients=[],
        suggestions=[],
        unmatched_items=["dry chicken curry"],
    )

    corrections = [
        ItemCorrection(item_index=0, name="chicken curry", weight_g=None),
    ]

    result = correct_meal(fake_previous, corrections)

    print("--- Corrected items ---")
    for item in result.items:
        source = "database" if item.food_id else "AI estimate (not in database)"
        print(
            f"{item.name} ({item.weight_g}g): {item.nutrients.calories} kcal [{source}]")

    print("\n--- Total ---")
    print(result.total.model_dump())
