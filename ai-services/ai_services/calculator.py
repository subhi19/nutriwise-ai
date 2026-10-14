"""
calculator.py

Takes a food row from the database (nutrition per 100g) and a weight in
grams, and calculates the actual nutrition for that amount.

Example: Chicken curry has 220 kcal per 100g. If the plate has 150g,
the real amount eaten is 220 * (150 / 100) = 330 kcal.
"""


def calculate_nutrients(food: dict, weight_g: float) -> dict:
    """
    food: a row from the foods table (a dictionary with calories,
          protein_g, carbs_g, etc. — all per 100g)
    weight_g: how many grams were actually eaten

    Returns a dictionary with the same nutrient names, but scaled
    to the actual weight instead of per 100g.
    """
    # This is the same multiplier for every nutrient, so we calculate it once
    scale = weight_g / 100

    return {
        "calories": round(food["calories"] * scale, 1),
        "protein_g": round(food["protein_g"] * scale, 1),
        "carbs_g": round(food["carbs_g"] * scale, 1),
        "fat_g": round(food["fat_g"] * scale, 1),
        "fiber_g": round(food["fiber_g"] * scale, 1),
        "iron_mg": round(food["iron_mg"] * scale, 1),
        "calcium_mg": round(food["calcium_mg"] * scale, 1),
        "vitamin_a_mcg": round(food["vitamin_a_mcg"] * scale, 1),
        "vitamin_c_mg": round(food["vitamin_c_mg"] * scale, 1),
    }


def add_totals(list_of_nutrients: list[dict]) -> dict:
    """
    Adds up nutrients across several food items, to get the meal total.

    Example: rice nutrients + dal nutrients + curry nutrients = total.
    """
    total = {
        "calories": 0, "protein_g": 0, "carbs_g": 0, "fat_g": 0,
        "fiber_g": 0, "iron_mg": 0, "calcium_mg": 0,
        "vitamin_a_mcg": 0, "vitamin_c_mg": 0,
    }
    for nutrients in list_of_nutrients:
        for key in total:
            total[key] += nutrients[key]
            total[key] = round(total[key], 1)
    return total


# --- Quick test you can run directly ---------------------------------------
# python calculator.py

if __name__ == "__main__":
    # Pretend we already looked this up from nutrition_repo.py
    chicken_curry = {
        "name": "Chicken curry", "calories": 220, "protein_g": 18,
        "carbs_g": 6, "fat_g": 14, "fiber_g": 1, "iron_mg": 1.5,
        "calcium_mg": 20, "vitamin_a_mcg": 10, "vitamin_c_mg": 3,
    }
    roti = {
        "name": "Roti", "calories": 120, "protein_g": 3.1,
        "carbs_g": 18, "fat_g": 3.7, "fiber_g": 2.2, "iron_mg": 1.2,
        "calcium_mg": 10, "vitamin_a_mcg": 0, "vitamin_c_mg": 0,
    }

    curry_150g = calculate_nutrients(chicken_curry, 150)
    roti_80g = calculate_nutrients(roti, 80)  # 2 rotis, ~40g each

    print("Chicken curry (150g):", curry_150g)
    print("Roti (80g):", roti_80g)

    meal_total = add_totals([curry_150g, roti_80g])
    print("\nMeal total:", meal_total)