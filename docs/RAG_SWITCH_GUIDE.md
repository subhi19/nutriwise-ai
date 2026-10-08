# Switching to RAG (Vector Search) — Step by Step

Do these in order. Don't skip ahead — each step depends on the one before it.
Total time: roughly 15-20 minutes, mostly waiting for the backfill script.

---

## ☐ Step 0 — Before you start

Confirm these still work (if not, fix them first — don't build RAG on top of
a broken foundation):
```
python nutrition_repo.py
```
Should show your normal word-matching results (chicken curry, roti, etc. all matching).

---

## ☐ Step 1 — Check your embedding size

```
python check_embedding_size.py
```

**Expected output:**
```
This model produces embeddings of length: 768
Use this number in your SQL: vector(768)
```

**Write down the number it prints** — you need it in Step 3. (It may not be 768 — use whatever it actually prints.)

---

## ☐ Step 2 — Turn on vector search in Supabase

1. Open your Supabase project
2. Go to **Database → Extensions**
3. Find **"vector"** in the list
4. Click to enable it

---

## ☐ Step 3 — Create the column and search function

1. Open `supabase_vector_setup.sql`
2. If Step 1's number was NOT 768, find both places that say `vector(768)` and change them to your actual number
3. Copy the whole file
4. In Supabase, go to **SQL Editor → New query**
5. Paste it in and click **Run**

**Expected result:** no errors. You should now see an `embedding` column on your `foods` table (Table Editor → foods — scroll right).

---

## ☐ Step 4 — Fill in embeddings for your existing foods

```
python backfill_embeddings.py
```

**Expected output:**
```
Found 128 foods to process.
  [1/128] Cooked basmati rice — done
  [2/128] Cooked brown rice — done
  ...
All foods now have embeddings.
```

This takes a few minutes (128 foods × half-second pause each ≈ 1-2 minutes). **Let it finish completely** — don't interrupt it partway, or some foods will be left without embeddings.

---

## ☐ Step 5 — Switch your code over

Replace your current `nutrition_repo.py` with the updated version (the one with `vector_search_food` added).

---

## ☐ Step 6 — Test the upgrade actually works

```
python nutrition_repo.py
```

**First check:** everything that worked before still works (chicken curry, roti, etc.)

**Second check — the real test:** add a line to the test list that word-matching would genuinely fail on, something with NO shared words but the same meaning, e.g.:
```python
"murgh makhani"   # should still match "Chicken curry" or "Butter chicken" via vector search
```

If this now finds a match where it wouldn't have before, vector search is working.

---

## ☐ Step 7 — Run your full test suite again

Go through `TESTING_GUIDE.md` sections 3, 6, 7, 8 again (meal analyzer, recipes, meal plan, grocery list) — these all use `search_food()` underneath, so confirm nothing broke for them either.

---

## ☐ Step 8 — Going forward: new foods need embeddings too

Every time you add new rows to your foods table (new cuisine, new dish), run:
```
python backfill_embeddings.py
```
again. It's safe to re-run — it just updates every row's embedding each time (a few seconds of wasted work for already-done rows, not a problem).

---

## If something breaks and you need to roll back fast

You don't need to undo anything in Supabase. Just disable the fallback in code — open `nutrition_repo.py` and find this line near the end of `search_food()`:

```python
return vector_search_food(name)
```

Change it to:
```python
return None
```

This instantly goes back to word-matching only, with zero risk, while you investigate. Nothing else in your app needs to change.
