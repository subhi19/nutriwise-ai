import json
from fastapi import FastAPI, Depends, HTTPException, UploadFile, File, Form, status, Request
from fastapi.responses import JSONResponse
from fastapi.concurrency import run_in_threadpool
from sqlalchemy.orm import Session
from pydantic import BaseModel, EmailStr
from passlib.context import CryptContext

import ai_services
from ai_services.schemas import (
    FamilyMember,
    MealAnalysis,
    MealCorrectionRequest,
    FridgeInventory,
    RecipeSuggestions,
    WeeklyPlan,
    GroceryList,
    GroceryListRequest,
)
from ai_services.errors import AIServiceError, STATUS_BY_CODE

from app.database import engine, Base, get_db
from app.models.user import User, FamilyMemberModel

# Auto-create tables in Supabase / SQLite
Base.metadata.create_all(bind=engine)

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

app = FastAPI(
    title="NutriWise AI API",
    version="1.0.0",
    docs_url="/docs"
)

# ----------------- GLOBAL EXCEPTION HANDLER -----------------


@app.exception_handler(AIServiceError)
async def ai_service_error_handler(request: Request, exc: AIServiceError):
    """
    Catches any AIServiceError and outputs the exact JSON structure
    documented in errors.py.
    """
    http_status = STATUS_BY_CODE.get(exc.code, 500)
    return JSONResponse(
        status_code=http_status,
        content={
            "error": {
                "code": exc.code,
                "message": exc.message,
                "retry": exc.retry
            }
        }
    )

# ----------------- AUTH & USER MODELS -----------------


class UserCreate(BaseModel):
    name: str
    email: EmailStr
    password: str


class UserResponse(BaseModel):
    id: int
    name: str
    email: str

    class Config:
        from_attributes = True


@app.get("/")
def health_check():
    return {"status": "ok", "app": "NutriWise AI Backend running"}


@app.post("/auth/register", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
def register_user(payload: UserCreate, db: Session = Depends(get_db)):
    if db.query(User).filter(User.email == payload.email).first():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A user with this email is already registered."
        )
    hashed_password = pwd_context.hash(payload.password)
    user_record = User(name=payload.name, email=payload.email,
                       password_hash=hashed_password)
    db.add(user_record)
    db.commit()
    db.refresh(user_record)
    return user_record

# ----------------- AI CONTRACT ENDPOINTS -----------------


@app.post("/api/meal/analyze", response_model=MealAnalysis)
async def analyze_meal_endpoint(
    image: UploadFile = File(...),
    member_data: str = Form(..., description="JSON-serialized FamilyMember"),
):
    """Takes a meal photo and target family member, returning nutrition data."""
    try:
        member_dict = json.loads(member_data)
        member = FamilyMember(**member_dict)
    except Exception:
        raise HTTPException(
            status_code=400, detail="Invalid JSON format for member_data")

    contents = await image.read()
    if len(contents) > 5 * 1024 * 1024:
        raise HTTPException(
            status_code=400, detail="Image exceeds 5 MB limit.")

    result = await run_in_threadpool(
        ai_services.analyze_meal,
        image_bytes=contents,
        mime_type=image.content_type or "image/jpeg",
        member=member,
    )
    return result


class MealCorrectionPayload(BaseModel):
    request_data: MealCorrectionRequest
    member: FamilyMember


@app.post("/api/meal/correct", response_model=MealAnalysis)
async def correct_meal_endpoint(payload: MealCorrectionPayload):
    """Recomputes nutrition analysis after user text corrections."""
    result = await run_in_threadpool(
        ai_services.correct_meal,
        previous=payload.request_data.previous,
        corrections=payload.request_data.corrections,
        member=payload.member,
    )
    return result


@app.post("/api/fridge/analyze", response_model=FridgeInventory)
async def analyze_fridge_endpoint(image: UploadFile = File(...)):
    """Analyzes a fridge photo to identify ingredients."""
    contents = await image.read()
    if len(contents) > 5 * 1024 * 1024:
        raise HTTPException(
            status_code=400, detail="Image exceeds 5 MB limit.")

    result = await run_in_threadpool(
        ai_services.analyze_fridge,
        image_bytes=contents,
        mime_type=image.content_type or "image/jpeg",
    )
    return result


class RecipeSuggestionPayload(BaseModel):
    inventory: FridgeInventory
    family: list[FamilyMember]


@app.post("/api/recipes/suggest", response_model=RecipeSuggestions)
async def suggest_recipes_endpoint(payload: RecipeSuggestionPayload):
    """Suggests recipes based on fridge inventory and family dietary needs."""
    result = await run_in_threadpool(
        ai_services.suggest_recipes,
        inventory=payload.inventory,
        family=payload.family,
    )
    return result


class MealPlanPayload(BaseModel):
    family: list[FamilyMember]
    inventory: FridgeInventory | None = None


@app.post("/api/meal-plan/generate", response_model=WeeklyPlan)
async def generate_meal_plan_endpoint(payload: MealPlanPayload):
    """Generates a 7-day personalized weekly meal plan."""
    result = await run_in_threadpool(
        ai_services.generate_meal_plan,
        family=payload.family,
        inventory=payload.inventory,
    )
    return result


@app.post("/api/grocery-list/generate", response_model=GroceryList)
async def generate_grocery_list_endpoint(payload: GroceryListRequest):
    """Creates a consolidated shopping list based on plan and preferences."""
    result = await run_in_threadpool(
        ai_services.generate_grocery_list,
        family=payload.family,
        plan=payload.plan,
        inventory=payload.inventory,
        user_requirements=payload.user_requirements,
    )
    return result
