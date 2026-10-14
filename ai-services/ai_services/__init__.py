from ai_services.meal_analyzer import analyze_meal
from ai_services.meal_corrector import correct_meal
from ai_services.fridge_analyzer import analyze_fridge
from ai_services.recipes import suggest_recipes
from ai_services.meal_plan import generate_meal_plan
from ai_services.grocery import generate_grocery_list
import sys
from pathlib import Path

# Ensure the ai_services folder itself is on sys.path for internal flat imports
_AI_SERVICES_DIR = str(Path(__file__).resolve().parent)
if _AI_SERVICES_DIR not in sys.path:
    sys.path.insert(0, _AI_SERVICES_DIR)

# Add this folder to sys.path FIRST so that bare sibling imports work
_CURRENT_DIR = str(Path(__file__).resolve().parent)
if _CURRENT_DIR not in sys.path:
    sys.path.insert(0, _CURRENT_DIR)


__all__ = [
    "analyze_meal",
    "correct_meal",
    "analyze_fridge",
    "suggest_recipes",
    "generate_meal_plan",
    "generate_grocery_list",
]
