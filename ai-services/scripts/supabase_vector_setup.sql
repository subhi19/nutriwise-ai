-- Run this in Supabase's SQL Editor, AFTER running check_embedding_size.py
-- Replace 768 below with whatever number that script printed, if different.

-- Step 2 (repeated here for convenience): add the column
alter table foods add column if not exists embedding vector(3072);

-- Step 4: the search function itself.
-- Given a query's embedding, this returns the foods whose embeddings
-- are most similar (closest "meaning"), ranked best match first.
create or replace function match_foods(
  query_embedding vector(3072),
  match_count int default 3
)
returns table (
  id int,
  name text,
  calories numeric,
  protein_g numeric,
  carbs_g numeric,
  fat_g numeric,
  fiber_g numeric,
  iron_mg numeric,
  calcium_mg numeric,
  vitamin_a_mcg numeric,
  vitamin_c_mg numeric,
  category text,
  typical_serving_g numeric,
  similarity float
)
language sql stable
as $$
  select
    foods.id, foods.name, foods.calories, foods.protein_g, foods.carbs_g,
    foods.fat_g, foods.fiber_g, foods.iron_mg, foods.calcium_mg,
    foods.vitamin_a_mcg, foods.vitamin_c_mg, foods.category, foods.typical_serving_g,
    1 - (foods.embedding <=> query_embedding) as similarity
  from foods
  where foods.embedding is not null
  order by foods.embedding <=> query_embedding
  limit match_count;
$$;