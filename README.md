# NutriWise AI

> *Knows what's on your plate, what's handy and what's not.* **Eat Healthy. Waste Less.**

NutriWise AI is a household nutrition assistant. Take a photo of a meal or the fridge, and the app works out what is on the plate, which nutrients are missing, what can be cooked tonight, and what to buy this week. It also builds weekly meal plans for the whole family, respecting allergies, diet and cuisine.

Gemini (through Vertex AI) names the dishes and ingredients and estimates weights. **All calories and nutrients come from a curated foods table in Google Cloud SQL, not from the model.**

One Flutter codebase targets **web, Android and iOS**. It talks to a FastAPI backend, which calls the AI module.

- **Live demo:** https://nutriwise-ai-511608.web.app/
- **API docs:** https://nutriwise-backend-688441197651.asia-southeast1.run.app/docs

---

## Contents

- [Features](#features)
- [Architecture](#architecture)
- [Tech stack](#tech-stack)
- [Project structure](#project-structure)
- [Getting started](#getting-started)
- [API](#api)
- [Screens and routes](#screens-and-routes)
- [Design and accessibility](#design-and-accessibility)
- [Security](#security)
- [Deployment](#deployment)
- [Benchmark](#benchmark)
- [Quality checks](#quality-checks)
- [Troubleshooting](#troubleshooting)
- [Known limitations](#known-limitations)
- [Contributing](#contributing)
- [License](#license)

---

## Features

| Feature | What it does |
|---|---|
| **Account** | Sign up, log in, reset a forgotten password, log out. Pages that need a login redirect to Login. |
| **Family profile** | Add, edit and delete family members with age, gender, diet, allergies and cuisine preferences. |
| **Meal photo analysis** (Nutrient Analyzer) | Identifies each dish, estimates its weight, and calculates calories, protein, carbs, fat, fibre, iron, calcium and vitamins A and C. Lists missing nutrients and suggests fixes. The result can be saved as an image card. |
| **Meal corrections** | The user can rename a dish or change its weight, and totals are recalculated. |
| **Fridge scan** (Home Inventory) | Reads a fridge photo into an inventory, lets the user fix the detected ingredients, and flags items to use soon. |
| **Recipe suggestions** | Recipes from the fridge contents, with calculated nutrition and steps for each. Allergens are called out. |
| **Weekly meal plan** (Meal Planner) | A 7-day plan (breakfast, lunch, dinner, snack) for the family. Optionally photograph groceries, choose who is eating, and set a dietary type, cuisine and notes for each day. Respects each member's allergies, diet and cuisine, uses fridge items first, and puts items that are about to spoil in the earliest days. A free-text request can limit the plan, for example "plan only Tuesday, Chinese". Calories are shown per meal and as daily totals, and any meal can be expanded for ingredient weights. The plan can be saved as an image card. |
| **Grocery list** | Lists only what the plan needs that the fridge does not have, grouped by category. The user can add extra items, tick things off, and save the list as an image card. |

### How nutrition is grounded

1. Gemini proposes dishes and ingredients with weights in grams. It never estimates calories.
2. Each ingredient is matched to the foods table: fast word matching first, then semantic vector search (`pgvector`) as a fallback.
3. Matches are validated. "Chicken" is not matched to "Fried chicken", and "chicken curry" is not matched to "Curry powder".
4. Nutrients are calculated from the matched row and the weight.
5. An ingredient with no good match is flagged **not in the database** (shown with `*`) and has no calories, instead of showing an invented number.

---

## Architecture

```
        +-----------------------------+
        |       Flutter Client        |
        |   (web, Android, iOS)       |
        +--------------+--------------+
                       | HTTPS + JWT
                       v
        +-----------------------------+
        |      FastAPI Backend        |
        |        (Cloud Run)          |
        +--------------+--------------+
                       |
          +------------+--------------+
          |                           |
          v                           v
+---------------------+     +-------------------------+
|  Google Cloud SQL   |     |  Gemini on Vertex AI    |
|  PostgreSQL+pgvector|     |  - meal / fridge vision |
|  - users, families  |     |  - plans and recipes    |
|  - foods + nutrients|     |  - food-name embeddings |
|  - food embeddings  |     +-------------------------+
+---------------------+
```

### Client layers

Screens never call the network directly. They read data through Riverpod providers and call the `NutriApi` interface.

```
Screens / Widgets  →  Providers (Riverpod)  →  NutriApi  →  MockApi | RealApi (Dio)  →  Backend
                                                    ↑
                                       Models (typed, tolerant parsing)
```

- **Mock and live share one interface.** `MockApi` and `RealApi` both implement `NutriApi`. `USE_MOCK` chooses between them in `providers.dart`, so no screen changes when you go live.
- **Models parse defensively.** For example an ingredient may arrive as a name or as an object, diets and allergies are normalised to `snake_case`, and numbers may be `int` or `double`.

### State (Riverpod 3)

| Provider | Holds |
|---|---|
| `apiProvider` | The active `NutriApi` (mock or real, with the Bearer token attached) |
| `authProvider` | The logged-in session, in memory only |
| `membersProvider` | The family list for the logged-in user |
| `currentPlanProvider`, `planFamilyProvider`, `fridgeInventoryProvider` | Planner output carried over to the Grocery List |

`performLogout(ref)` clears all of them. If you add a provider that holds user data, reset it there too.

> Riverpod 3 moved `StateProvider` into a separate import: `package:flutter_riverpod/legacy.dart`.

### Navigation (go_router)

- Public paths: `/`, `/login`, `/signup`, `/forgot-password`, `/reset-password`. Everything else redirects to `/login` when nobody is logged in.
- Feature screens are opened with `push`, so the system and browser Back buttons return to the Dashboard.
- `AppBackButton` pops if there is a previous page, otherwise goes to a fallback route. Screens holding unsaved results ask for confirmation before leaving.

### API layer and errors

- Base timeouts are set long enough for the AI endpoints, which can take a while (a weekly plan is the slowest).
- After login, an interceptor adds `Authorization: Bearer <token>` to every request.
- All failures become one typed `ApiException`, shown by a shared `ErrorBox`:

| Server returns | User sees | Retry button |
|---|---|---|
| `{"error": {"code", "message", "retry"}}` | `message` as sent | as `retry` says |
| `{"detail": "text"}` | the text | no |
| `{"detail": [ ... ]}` (422) | "Some details look invalid…" (details go to the console) | no |
| HTTP 429 | "You're going a little fast! Please wait a minute…" | yes |
| Timeout | "This is taking longer than expected…" | yes |
| Anything else | "Network error. Please check your connection…" | yes |

A server crash (HTTP 500) can reach the browser without CORS headers. In that case the browser reports a CORS error and the app shows the generic network message. The real error is in the backend's logs.

---

## Tech stack

| Layer | Technology |
|---|---|
| App | Flutter (stable) and Dart 3.8 or newer. Developed on Flutter 3.47.5. |
| State management | `flutter_riverpod` 3 |
| Navigation | `go_router` |
| Networking | `dio` |
| Media | `image_picker`, `camera` (desktop-browser webcam) |
| Fonts | `google_fonts` (Inter) |
| Local storage | `shared_preferences`, `path_provider` |
| Web downloads | `package:web` |
| API | FastAPI, Python 3.14, SQLAlchemy |
| AI | Gemini Flash through Vertex AI (`google-genai`) |
| Embeddings | `text-embedding-004`, 768 dimensions (set in `.env`) |
| Database | Google Cloud SQL for PostgreSQL 16 with the `pgvector` extension |
| Backend hosting | Google Cloud Run, container built from the repo root |
| Web hosting | Firebase Hosting (a Google Cloud service) |

---

## Project structure

Compare this with your folders and adjust if they differ.

```text
nutriwise-ai/
├── ai-services/
│   ├── ai_services/
│   │   ├── gemini_client.py        # the only file that creates the Gemini client
│   │   ├── schemas.py              # shared data models (single source of truth)
│   │   ├── meal_analyzer.py        # meal photo analysis
│   │   ├── fridge_analyzer.py      # fridge photo analysis
│   │   ├── recipes.py              # recipe suggestions
│   │   ├── meal_plan.py            # weekly plan and prompt rules
│   │   ├── grocery.py              # grocery list
│   │   ├── nutrition_repo.py       # food lookup: word match + pgvector
│   │   ├── cloudsql_db.py          # Cloud SQL connection helper
│   │   └── check_embeddings.py     # finds which model made the stored vectors
│   ├── scripts/
│   │   └── backfill_embeddings.py  # creates embeddings for every food
│   └── benchmark/
│       ├── run_benchmark.py        # speed, accuracy and allergen-safety benchmark
│       ├── test_data/              # your test photos and expected results
│       └── results/                # generated reports
├── backend/
│   ├── app/
│   │   ├── main.py                 # FastAPI routes
│   │   ├── database.py             # SQLAlchemy engine (Cloud SQL)
│   │   └── models/                 # user and family tables
│   └── requirements.txt
├── mobile-app/                     # Flutter app
│   ├── lib/
│   │   ├── main.dart               # app entry, theme, router, text-scale cap
│   │   ├── core/                   # theme, router, constants, validators, suggestion quota
│   │   ├── models/                 # typed data classes with tolerant fromJson/toJson
│   │   ├── providers/providers.dart  # Riverpod providers, mock/live switch, logout
│   │   ├── services/               # NutriApi (MockApi, RealApi), image saving, local storage
│   │   ├── screens/                # one file per screen
│   │   └── widgets/                # reusable UI (brand bar, chips, result cards, dialogs)
│   ├── web/                        # web shell (index.html, manifest, icons)
│   ├── android/  ios/              # platform projects
│   ├── test/                       # placeholder test only
│   ├── firebase.json               # Firebase Hosting settings
│   └── pubspec.yaml
├── Dockerfile                      # at the repo root, see Deployment
└── README.md
```

---

## Getting started

### Prerequisites

- Python 3.14 and the Flutter SDK (stable channel; `flutter doctor` should show no problems for the platforms you target)
- Google Chrome for web development. Android Studio for Android, Xcode for iOS (macOS only).
- The Google Cloud CLI, signed in:

```bash
gcloud auth application-default login
gcloud services enable aiplatform.googleapis.com sqladmin.googleapis.com
```

Your account needs the **Vertex AI User** and **Cloud SQL Client** roles.

### 1. Environment

Create `backend/.env`. Use your own values and never commit this file.

```env
# Gemini through Vertex AI (no API key)
USE_VERTEX=true
GOOGLE_CLOUD_PROJECT=your-project-id
GOOGLE_CLOUD_LOCATION=asia-southeast1      # check the model is available in your region
MODEL_NAME=gemini-2.5-flash

# Embeddings for semantic food search.
# Must be the same model and size that created the stored vectors.
EMBEDDING_MODEL=gemini-embedding-001
EMBEDDING_DIM=768

# Google Cloud SQL (connector; no public IP needed)
CLOUDSQL_INSTANCE=your-project:your-region:your-instance
DB_NAME=postgres
DB_USER=your-db-user
DB_PASSWORD=your-db-password

# App security
JWT_SECRET=a-long-random-secret
ACCESS_TOKEN_EXPIRE_MINUTES=1440
```

Notes:

- Do not set `PORT` here. Cloud Run provides it.
- If your `gemini_client.py` reads `GCP_PROJECT` and `GCP_LOCATION` instead of the `GOOGLE_CLOUD_*` names, use the names your file reads.

### 2. Database setup

1. In Cloud SQL Studio (or `psql`), enable pgvector and create the foods table:

```sql
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS foods (
  id integer PRIMARY KEY,
  name text, aliases text, category text,
  typical_serving_g numeric,
  calories numeric, protein_g numeric, carbs_g numeric, fat_g numeric,
  fiber_g numeric, iron_mg numeric, calcium_mg numeric,
  vitamin_a_mcg numeric, vitamin_c_mg numeric,
  embedding vector(768)
);
```

   No vector index is needed. With a small foods table an exact search is instant, and approximate indexes such as `ivfflat` only help (and need tuning) once the table has many thousands of rows.

2. Load your foods data, then create the embeddings:

```bash
cd ai-services
python scripts/backfill_embeddings.py --all
```

3. Verify:

```sql
SELECT count(*) AS total_foods, count(embedding) AS with_embedding FROM foods;
SELECT vector_dims(embedding) AS dims, count(*) FROM foods GROUP BY 1;
```

4. Check which model the stored vectors match:

```bash
cd ai-services/ai_services
python -m check_embeddings
```

### 3. Run the backend

```bash
python -m venv .venv
.venv\Scripts\activate            # macOS/Linux: source .venv/bin/activate
pip install -r backend/requirements.txt
cd backend
uvicorn app.main:app --reload --port 8000
```

`requirements.txt` must include at least: `fastapi`, `uvicorn`, `sqlalchemy`, `python-dotenv`, `pydantic`, `google-genai`, `cloud-sql-python-connector[pg8000]`, `bcrypt`, `pyjwt`, `python-multipart`.

On start, check these lines:

```
[startup] ai_services loaded from: ...\ai-services\ai_services\__init__.py
[database] Connected through Google Cloud SQL
```

The first path must be the project you are working in. Interactive API docs are at `http://localhost:8000/docs`.

### 4. Test the pieces

From `ai-services/ai_services`:

```bash
python -m cloudsql_db        # connection test, also checks pgvector
python -m nutrition_repo     # sample food searches
```

### 5. Run the app

The app reads two compile-time settings. Pass them with `--dart-define`.

| Setting | Values | Meaning |
|---|---|---|
| `USE_MOCK` | `true` (default) or `false` | `true` uses built-in sample data. `false` calls the real backend. |
| `API_BASE_URL` | for example `https://nutriwise-backend-688441197651.asia-southeast1.run.app` | The backend address. Only used when `USE_MOCK=false`. |

Changing a `--dart-define` needs a full stop and start. Hot reload ignores it.

**With built-in sample data (no backend needed):**

```bash
cd mobile-app
flutter pub get
flutter run -d chrome
```

**Against a live backend:**

```bash
cd mobile-app
flutter pub get
flutter run -d chrome --web-port 3000 \
  --dart-define=USE_MOCK=false \
  --dart-define=API_BASE_URL=https://nutriwise-backend-688441197651.asia-southeast1.run.app
```

Use a fixed `--web-port` (here 3000). Without it Chrome picks a new random port each time, and the backend's CORS settings cannot allow an origin that keeps changing. The backend must allow `http://localhost:3000` in its CORS origins.

---

## API

Sign-in and family profile routes are in `backend/app/main.py`. Request and response shapes are defined in `ai-services/ai_services/schemas.py` and described in `AI_Module_Contract.md`. Interactive docs are at `/docs` on the backend.

| Method | Path | Body |
|---|---|---|
| POST | `/auth/register` | JSON: `name`, `email`, `password` |
| POST | `/auth/login` | JSON: `email`, `password`. Reads `access_token`, `user_id`, `name`, `expires_in`. |
| POST | `/auth/forgot-password` | JSON: `email` |
| POST | `/auth/reset-password` | JSON: `token`, `new_password` |
| POST / GET | `/api/family/members?user_id=` | JSON member / none |
| PUT / DELETE | `/api/family/members/{id}` | JSON member / none |
| POST | `/api/meal/analyze` | multipart: `image`, `member_data` (JSON string) |
| POST | `/api/meal/correct` | JSON: `request_data` (`previous`, `corrections`) and `member` |
| POST | `/api/fridge/analyze` | multipart: `image` |
| POST | `/api/recipes/suggest` | JSON: `inventory`, `family` |
| POST | `/api/meal-plan/generate` | JSON: `family`, `inventory`, `day_preferences`. Weekly or single-day plan. |
| POST | `/api/grocery-list/generate` | JSON: `family`, `plan`, `inventory`, `user_requirements` |

Request notes:

- **Images** go up as binary multipart, never base64.
- **Family member:** `name`, `age` (int), `gender` (lowercase), `allergies`, `anyother_specific_allergy`, `food_preferences` (exactly one value), `cuisine_preferences`. Empty lists are `[]`, never `null`.
- **`day_preferences`** is a list of 7 entries `{day, meal_types, cuisine_preferences, notes}`. `meal_types` is always `["breakfast","lunch","dinner","snack"]`. The dietary types the user picked travel as plain text at the start of `notes` ("Dietary type for this day: ..."), followed by the user's typed request.
- **The typed request** ("plan only Tuesday") currently travels inside each day's `notes`. The backend pulls it out of `notes`, and it also accepts a separate `message` field, which is the cleaner option if the app is changed to send one.
- **`inventory`** is sent as both `items` (name, quantity, use-soon flag) and `detected_items` (names only), so either server shape works. If no inventory is sent, the plan is built without fridge items.
- **`corrections`** is a list of `{item_index, name, weight_g}`. `item_index` is `null` for an added dish.

Allowed values (all lowercase, underscores for spaces):

| Field | Values |
|---|---|
| Diet | `vegetarian`, `non_vegetarian`, `eggetarian`, `vegan` |
| Cuisine | `indian`, `chinese`, `italian`, `continental`, `mexican`, `malaysian` (empty list means any) |
| Allergies | `milk`, `peanut`, `egg`, `tree_nuts`, `soy`, `wheat`, `shellfish`, `fish`, plus free text |
| Gender | `male`, `female`, `other` |

---

## Screens and routes

| Route | Screen | Notes |
|---|---|---|
| `/` | Welcome | App intro and three feature highlights. **Explore Now** goes to Login. |
| `/login` | Login | Inline error on wrong credentials. Goes to Family Profile on success. |
| `/signup` | Sign Up | Name, email, password (8 to 16 characters with a number or symbol), confirmation |
| `/forgot-password` | Forgot Password | Sends a reset request |
| `/reset-password` | Reset Password | Reset code and new password. Also opens from a link with `?token=`. |
| `/profile` | Family Profile | Required fields, up to 2 cuisines, "Any Cuisine" option, discard-changes prompt |
| `/dashboard` | Dashboard | Three feature cards. Account menu has **My family** and **Log out**. |
| `/meal` | Nutrient Analyzer | Photo, results card, Correct Meal, save as card |
| `/plan` | Meal Planner | Optional groceries photo, who is eating, per-day settings, 7-day plan |
| `/fridge` | Home Inventory | Fridge photo, ingredient editing, recipe cards |
| `/grocery` | Grocery List | Needs a generated plan. Grouped checklist with progress. |

Rules worth knowing:

- Meal Planner and Home Inventory allow the **first result plus 2 new ones** per visit. Failed calls do not count. A new photo resets Home Inventory.
- Per day in the planner: up to **2 dietary types** (11 available, for example Halal, Jain, Vegan) and up to **2 cuisines**.
- Flagged foods (low confidence or not matched) show in red until the user confirms or edits them.
- Ingredients that are not in the nutrition database are marked with `*` and show no calories.

---

## Design and accessibility

- **Look:** teal `#1B998B` (primary), coral `#FF7262` (actions), amber `#FFC857` (accents) on a warm cream background. Cards, soft shadows, and food emoji instead of image files, so there are no image assets to download.
- **Type:** Inter throughout, with weight carrying the hierarchy. Taglines are italic.
- **Built for all ages:** primary buttons are at least 52 px tall, text scales with the system font setting up to 1.3x, text is near-black on a light surface, and actions pair an icon with a label. Selected options use solid fills, not faint tints.
- **Responsive:** layouts use `LayoutBuilder` and width limits rather than fixed sizes. The brand bar reflows on narrow screens.
- **Feedback:** loading states appear immediately, buttons disable while a request runs, and errors keep the user's input so a retry is one tap.
- **Saved cards:** results export as a clean PNG with equal padding and no buttons.

---

## Security

What the project does:

- **Sign-in:** passwords are hashed with bcrypt and sessions use JWT tokens.
- **Rate limiting:** the AI endpoints are rate limited in the backend (`AIRateLimitMiddleware` in `main.py`).
- **CORS:** configured through FastAPI's CORS middleware. Restrict the allowed origins to your own app URLs in production.
- **No API keys for Gemini:** Vertex AI uses Google Cloud credentials (Application Default Credentials locally, a service account on Cloud Run).
- **Database access:** the backend connects through the Cloud SQL connector, which encrypts the connection and authorises it with IAM, so the database does not need an open public address.

What you must do:

- Never commit `backend/.env`, passwords, or service account files.
- Store `DB_PASSWORD` and `JWT_SECRET` in Secret Manager for deployment.
- Give the Cloud Run service account only the **Vertex AI User**, **Cloud SQL Client** and **Secret Manager Secret Accessor** roles.
- Use a database user with only the access the app needs, not the default `postgres` superuser, for production.
- If you ever pasted a real password, IP address or key into a file or chat, rotate it.
- **Demo behaviour:** the backend returns the password reset code in its response, and the app pre-fills it. Set `EXPOSE_RESET_TOKEN=false` in the backend for a public deployment.

---

## Deployment

In every setup the browser calls the backend, not the machine that serves the app. So `API_BASE_URL` must be a public **HTTPS** address, normally your Cloud Run URL:

```bash
gcloud run services describe nutriwise-backend --region asia-southeast1 --format "value(status.url)"
```

### Backend on Google Cloud Run

The backend imports the `ai-services` folder, so build the container from the **repository root** and copy both folders in.

`Dockerfile` (repo root):

```dockerfile
FROM python:3.14-slim
WORKDIR /srv
COPY backend/requirements.txt backend/requirements.txt
RUN pip install --no-cache-dir -r backend/requirements.txt
COPY ai-services ai-services
COPY backend backend
WORKDIR /srv/backend
CMD exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080}
```

Add a `.dockerignore` containing `**/.env`, `.venv`, `.git` and `benchmark/results` so secrets and local files are never copied into the image.

Store secrets once:

```bash
echo -n "your-db-password" | gcloud secrets create nutriwise-db-password --data-file=-
echo -n "your-jwt-secret"  | gcloud secrets create nutriwise-jwt-secret  --data-file=-
```

Deploy:

```bash
gcloud run deploy nutriwise-backend \
  --source . \
  --region asia-southeast1 \
  --service-account your-service-account@your-project-id.iam.gserviceaccount.com \
  --add-cloudsql-instances your-project:your-region:your-instance \
  --min-instances 0 --max-instances 3 \
  --allow-unauthenticated \
  --set-env-vars "USE_VERTEX=true,GOOGLE_CLOUD_PROJECT=your-project-id,GOOGLE_CLOUD_LOCATION=asia-southeast1,MODEL_NAME=gemini-2.5-flash,EMBEDDING_MODEL=gemini-embedding-001,EMBEDDING_DIM=768,CLOUDSQL_INSTANCE=your-project:your-region:your-instance,DB_NAME=postgres,DB_USER=your-db-user" \
  --set-secrets "DB_PASSWORD=nutriwise-db-password:latest,JWT_SECRET=nutriwise-jwt-secret:latest"
```

After deploying, point the Flutter app at the Cloud Run URL and limit the CORS allowed origins to your app's addresses. A Cloud Run service set to scale to zero can take a few seconds to wake up, so send one request to the backend before a live demo.

### Web app on Google Cloud

There are three ways to run or serve the Flutter web app. For a real deployment use **Option C (Firebase Hosting)**. Options A and B are for development and demos.

#### Option A: Cloud Shell (no local setup)

Open Cloud Shell in the Google Cloud console, then:

```bash
# 1. Install Flutter (first time only; your home folder is kept between sessions)
git clone https://github.com/flutter/flutter.git -b stable $HOME/flutter
export PATH="$PATH:$HOME/flutter/bin"
flutter config --enable-web
flutter doctor

# 2. Get the code and dependencies
git clone <your-repo-url> nutriwise-ai
cd nutriwise-ai/mobile-app
flutter pub get

# 3. Start the app (sample data)
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080
```

Then click **Web Preview** (top right of Cloud Shell) and choose **Preview on port 8080**.

To use the live backend, add the flags:

```bash
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080 \
  --dart-define=USE_MOCK=false \
  --dart-define=API_BASE_URL=https://<cloud-run-url>
```

Add the Web Preview address (`https://8080-....cloudshell.dev`) to the backend's CORS origins. Cloud Shell sessions are temporary, so this is for development only. On later sessions, only run `export PATH="$PATH:$HOME/flutter/bin"` and the `flutter run` line.

#### Option B: Compute Engine VM (optional)

Use this if you want the app on a VM you control.

```bash
# Create the VM
gcloud compute instances create nutriwise-flutter-vm \
  --zone asia-southeast1-b \
  --machine-type e2-standard-2 \
  --image-family ubuntu-2204-lts --image-project ubuntu-os-cloud \
  --boot-disk-size 30GB \
  --tags http-server

# Open port 80
gcloud compute firewall-rules create allow-http-nutriwise \
  --allow tcp:80 --target-tags http-server

# Log in to the VM
gcloud compute ssh nutriwise-flutter-vm --zone asia-southeast1-b
```

On the VM:

```bash
sudo apt update && sudo apt install -y git curl unzip xz-utils zip libglu1-mesa nginx

git clone https://github.com/flutter/flutter.git -b stable $HOME/flutter
export PATH="$PATH:$HOME/flutter/bin"
flutter config --enable-web

git clone <your-repo-url> nutriwise-ai
cd nutriwise-ai/mobile-app
flutter pub get
flutter build web --release \
  --dart-define=USE_MOCK=false \
  --dart-define=API_BASE_URL=https://<cloud-run-url>

sudo rm -rf /var/www/html/*
sudo cp -r build/web/* /var/www/html/
```

The app is then served at `http://<VM external IP>`. Find the IP with `gcloud compute instances list`.

Limits of this option: it serves plain **HTTP**, and the camera only works on HTTPS (or `localhost`). A public page that calls an HTTPS backend from an HTTP page is also a poor setup. Add a domain with HTTPS (for example a load balancer or Caddy) before real use. Stop or delete the VM when you are done, because it is billed while running:

```bash
gcloud compute instances delete nutriwise-flutter-vm --zone asia-southeast1-b
```

#### Option C: Firebase Hosting (recommended)

Firebase Hosting serves the built app over HTTPS from Google's network. This is how the live demo is served.

One-time setup, from `mobile-app`:

```bash
npm install -g firebase-tools
firebase login
firebase use your-project-id          # or: firebase init hosting
```

`firebase.json` (single-page app, so the `go_router` paths work on refresh):

```json
{
  "hosting": {
    "public": "build/web",
    "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
    "rewrites": [{ "source": "**", "destination": "/index.html" }]
  }
}
```

Build and deploy:

```bash
flutter build web --release \
  --dart-define=USE_MOCK=false \
  --dart-define=API_BASE_URL=https://<cloud-run-url>

firebase deploy --only hosting
```

Firebase prints the live address, for example `https://your-project-id.web.app`. Finally, allow that address in the backend: add `https://your-project-id.web.app` and `https://your-project-id.firebaseapp.com` to the backend's CORS settings, then redeploy the backend.

### Mobile builds

```bash
# Android
flutter build apk --release --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=https://<your-backend-url>
```

> **Always pass both flags for a release build.** Without them the app ships in mock mode and shows sample data.

### Requirements for a public deployment

- The backend must be served over **HTTPS**. Browsers block an `https` page from calling an `http` API, and the camera only works on HTTPS (or `localhost`). Cloud Run and Firebase Hosting both provide HTTPS.
- The backend must allow your site's origin in its CORS settings.
- **Mobile permissions:** Android needs `CAMERA` in the manifest. iOS needs `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` in `Info.plist`. Android debug builds calling a plain `http` backend also need `android:usesCleartextTraffic="true"` in the debug manifest.

---

## Benchmark

Measures speed, accuracy, database matching, reliability and allergen safety by calling the AI functions directly.

```bash
cd ai-services
python benchmark/run_benchmark.py --init                    # create sample test files (once)
python benchmark/run_benchmark.py --skip-plans --pause 3    # lighter run
python benchmark/run_benchmark.py                           # full run
```

Results are written to `benchmark/results/`. Quote only numbers from a real run.

---

## Quality checks

```bash
flutter analyze        # should report no issues
flutter test           # placeholder only, see below
```

There are **no automated tests yet**. `test/widget_test.dart` is a placeholder. Until real tests exist, use this manual check in mock mode, then repeat in live mode:

1. Welcome → Explore Now → Login → Profile
2. Add a family member (try leaving fields empty, using digits in the name, and picking a third cuisine)
3. Dashboard → Nutrient Analyzer: analyse a photo, use Correct Meal, tap Love It → Yes, save
4. Meal Planner: generate a plan, expand a meal, tap Grocery List → generate the list
5. Meal Planner with a typed request such as "plan only Tuesday" returns only that day
6. Home Inventory: detect, remove an ingredient, suggest recipes
7. Back buttons on every screen, then **Log out** and press the browser Back button (you should land on Login)

---

## Troubleshooting

| Problem | Likely cause and fix |
|---|---|
| Red CORS error in the browser console | Either the backend does not allow your origin, or the backend crashed with HTTP 500 (a crash is sent without CORS headers). Check the `500` line in the console and read the traceback in the backend terminal. |
| CORS error only in local development | Chrome picked a new random port. Run with a fixed `--web-port` and allow that origin in the backend. |
| "Network error. Please check your connection" | Backend not running, wrong `API_BASE_URL`, an `http` API called from an `https` page, or a gateway timeout |
| "Please wait a minute and try again" | The backend's AI rate limit was reached. See `AIRateLimitMiddleware` in `main.py`. |
| "This is taking longer than expected" | The request timed out. Weekly plans are the slowest AI call. |
| The deployed site shows sample data | It was built without `USE_MOCK=false`. Rebuild with both flags. |
| `--dart-define` change has no effect | Stop the app and start it again. |
| "Hot reload rejected… const class" | A class structure changed. Use hot restart (`R`). |
| `StateProvider isn't defined` | Import `package:flutter_riverpod/legacy.dart` |
| Camera is blank on web | The page is not HTTPS or `localhost`, or camera permission was denied |
| Cloud Shell preview is blank or slow | Wait for the first compile to finish, check the port matches the preview port, and use `--web-hostname 0.0.0.0` |
| Logged out after a browser refresh | Expected. The session is held in memory only. |
| Page refresh shows "not found" on Firebase | `firebase.json` is missing the rewrite to `/index.html` |
| Windows: "not enough space on the disk" during a run | Free space on `C:` or move the `TEMP` and `TMP` folders to another drive |
| `Cloud SQL setting ... is missing` | A line is missing in `backend/.env`. Run `python -m cloudsql_db` to see which settings are set. |
| `different vector dimensions 768 and 3072` | The query embedding size does not match the stored vectors. Set `EMBEDDING_MODEL` and `EMBEDDING_DIM`, then run `backfill_embeddings.py --all`. |
| Old behaviour after you edited a file | The backend is importing another copy of `ai_services`. Check the `[startup] ai_services loaded from` line. |
| An ingredient shows `*` and no calories | It is not in the foods table. Add a row for it. |
| `USE_VERTEX` warning, or "No API key was provided" | Set `USE_VERTEX=true`. Otherwise the client expects a Gemini API key. |
| Cloud Run fails on start | Check the service account roles, the secrets, and that `ai-services` was copied into the image. |

---

## Known limitations

- **Nutrition depends on the foods table.** A small table means some dishes and ingredients are reported as not in the database. Weights are estimated by Gemini, so values are estimates, not measurements.
- **Allergen checks** use ingredient names and a related-ingredient list, so they can miss unusual names. Treat results as a safety aid, not medical advice.
- **Meal plans can take a while** to generate because they call the model several times. Measure with the benchmark before quoting timings.
- **Session is memory-only.** A refresh or app restart requires logging in again.
- **Tested mainly in Chrome.** Android and iOS projects are present, but device testing is still to do.
- **Cards saved on mobile** go to the app's documents folder, not the photo gallery. On web they download normally.
- **Saved history** (meal cards, plans, lists, recipes) is written to local storage, but no history screen reads it yet.
- **Photo size:** photos from the gallery or phone camera are resized to 1024 px before upload. Desktop webcam captures are not resized.
- **Fonts** are fetched from Google Fonts at runtime, so first load needs internet access. Bundling Inter as an asset removes that dependency.
- **Correct Meal:** the server may answer with its own database name for a food (for example "Prawn" returns as "Shrimp"). The app keeps the name the user typed and adds a note saying which food was counted.
- **Generation limits** (first result plus 2 new ones) are enforced in the app only. They reset when the user leaves the screen.
- **Dietary types** such as Halal or Jain are sent as text in `notes`. Honouring them depends on the AI prompt.
- `supabase_flutter` is listed in `pubspec.yaml` but nothing in `lib/` imports it, and the project no longer uses Supabase. It can be removed.

---

## Contributing

- Work on a feature branch, open a pull request into `frontend-dev`, and open a second pull request from `frontend-dev` into `main`. Do not commit directly to `main`.
- Run `flutter analyze` before pushing.
- Never commit secrets (`.env`, keys, tokens). Do not commit `build/` or `.dart_tool/`.
- When the backend contract changes, update the models in `mobile-app/lib/models/` and the matching `RealApi` method together.
- Flow and business-logic notes are in `docs/`. Check them against this README, since the app has changed since they were written.

---

## License

This project is licensed under the MIT License.
