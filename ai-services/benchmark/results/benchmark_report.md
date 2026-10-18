# Prototype Performance Report

Run: 2026-10-17 22:12  |  Model: `gemini-2.5-flash`  |  Calls made: 21  |  Repeat: 1

## Results against targets

| Metric | Result | Target | Status |
|---|---|---|---|
| Meal photo analysis time (avg) | 12.82 s | under 20 s | PASS |
| Fridge photo analysis time (avg) | 9.21 s | under 20 s | PASS |
| Recipe suggestion time (avg) | 54.51 s | under 40 s | FAIL |
| Weekly plan generation time (avg) | 236.11 s | under 300 s | PASS |
| Grocery list generation time (avg) | 26.48 s | under 40 s | PASS |
| End-to-end journey: fridge to grocery list | 326.3 s | under 300 s | FAIL |
| Meal foods correctly identified | 36 of 46 (78%) | 80% | FAIL |
| Meal items matched to foods database | 50 of 50 (100%) | 70% | PASS |
| Fridge items correctly identified | 60 of 63 (95%) | 80% | PASS |
| Plan ingredients matched to database | 359 of 410 (88%) | 70% | PASS |
| Plans with valid 7-day structure | 3 of 3 | 100% | PASS |
| Calls finished without error | 20 of 21 (95%) | 95% | PASS |
| Real allergen hits flagged by plan check | 6 of 8 (75%) | 100% | FAIL |

## Speed (seconds, successful calls only)

| Function | Calls | Succeeded | Average | Median | 95th percentile | Slowest |
|---|---|---|---|---|---|---|
| meal | 9 | 8 | 12.82 | 9.59 | 31.75 | 31.75 |
| fridge | 5 | 5 | 9.21 | 8.25 | 13.18 | 13.18 |
| recipes | 1 | 1 | 54.51 | 54.51 | 54.51 | 54.51 |
| plan | 3 | 3 | 236.11 | 196.41 | 334.46 | 334.46 |
| grocery | 3 | 3 | 26.48 | 25.44 | 29.2 | 29.2 |

## Reliability

Failures by type:

- JSONDecodeError: 1

## Allergen safety

- Plans generated for allergic families: 2
- Plans that contained a real allergen or related ingredient: 2
- Real hits in total: 8; flagged by the plan's own check: 6
- Allergen hits found in grocery lists (no check exists there): 1

- Milk allergy, vegetarian: Monday: Milk (whole) (milk), Tuesday: Milk (whole) (milk), Thursday: Milk (whole) (milk), Saturday: Milk (whole) (milk), Saturday: Veggie burger patties (milk-free) (milk)
- Peanut and egg allergy: Tuesday: Mayonnaise (egg), Thursday: Mayonnaise (egg)

Hits are found with a related-ingredient list (for example milk includes paneer, curd, ghee), so they show what the current substring check can miss.

## Test set

- Meal photos analysed: 8
- Fridge photos analysed: 5
- Recipes returned: 3 (unmatched ingredients: 2 of 27)
- Weekly plans generated: 3; grocery lists: 3
