# Prototype Performance Report

Run: 2026-10-21 11:00  |  Model: `gemini-2.5-flash`  |  Calls made: 21  |  Repeat: 1

## Results against targets

| Metric | Result | Target | Status |
|---|---|---|---|
| Meal photo analysis time (avg) | 23.22 s | under 20 s | FAIL |
| Fridge photo analysis time (avg) | 11.92 s | under 20 s | PASS |
| Recipe suggestion time (avg) | 33.8 s | under 40 s | PASS |
| Weekly plan generation time (avg) | 73.92 s | under 300 s | PASS |
| Grocery list generation time (avg) | 29.94 s | under 40 s | PASS |
| End-to-end journey: fridge to grocery list | 149.6 s | under 300 s | PASS |
| Meal foods correctly identified | 44 of 51 (86%) | 80% | PASS |
| Meal items matched to foods database | 46 of 53 (87%) | 70% | PASS |
| Fridge items correctly identified | 60 of 63 (95%) | 80% | PASS |
| Plan ingredients matched to database | 354 of 431 (82%) | 70% | PASS |
| Plans with valid 7-day structure | 3 of 3 | 100% | PASS |
| Calls finished without error | 21 of 21 (100%) | 95% | PASS |
| Real allergen hits flagged by plan check | 4 of 4 (100%) | 100% | PASS |

## Speed (seconds, successful calls only)

| Function | Calls | Succeeded | Average | Median | 95th percentile | Slowest |
|---|---|---|---|---|---|---|
| meal | 9 | 9 | 23.22 | 22.57 | 45.01 | 45.01 |
| fridge | 5 | 5 | 11.92 | 13.37 | 17.43 | 17.43 |
| recipes | 1 | 1 | 33.8 | 33.8 | 33.8 | 33.8 |
| plan | 3 | 3 | 73.92 | 76.61 | 82.2 | 82.2 |
| grocery | 3 | 3 | 29.94 | 32.57 | 44.91 | 44.91 |

## Reliability

No call failed.

## Allergen safety

- Plans generated for allergic families: 2
- Plans that contained a real allergen or related ingredient: 2
- Real hits in total: 4; flagged by the plan's own check: 4
- Allergen hits found in grocery lists (no check exists there): 2

- Milk allergy, vegetarian: Thursday: Coconut milk (milk), Saturday: Soy milk (milk)
- Peanut and egg allergy: Wednesday: Mayonnaise (egg-free) (egg), Saturday: Caesar dressing (egg-free) (egg)

Hits are found with a related-ingredient list (for example milk includes paneer, curd, ghee), so they show what the current substring check can miss.

## Test set

- Meal photos analysed: 9
- Fridge photos analysed: 5
- Recipes returned: 3 (unmatched ingredients: 3 of 36)
- Weekly plans generated: 3; grocery lists: 3
