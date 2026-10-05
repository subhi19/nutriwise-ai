from app.models.user import User, FamilyMemberModel
from app.database import engine, Base, get_db
from ai_services.errors import AIServiceError, STATUS_BY_CODE
from ai_services.schemas import (
    FamilyMember,
    MealAnalysis,
    MealCorrectionRequest,
    FridgeInventory,
    RecipeSuggestions,
    WeeklyPlan,
    GroceryList,
    GroceryListRequest,
    DayPreference,
)
import ai_services
import jwt
import bcrypt
from pydantic import BaseModel, EmailStr
from sqlalchemy.orm import Session
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import JSONResponse
from fastapi import FastAPI, Depends, HTTPException, UploadFile, File, Form, status, Request
from datetime import datetime, timedelta, timezone
import json
import os
import sys
from pathlib import Path
from dotenv import load_dotenv

# 1. Load .env first so SUPABASE_URL / GEMINI_API_KEY are available
load_dotenv()

# 2. Add ai-services/ai_services to sys.path BEFORE any ai_services imports
AI_PKG_DIR = str(Path(__file__).resolve(
).parent.parent.parent / "ai-services" / "ai_services")
if AI_PKG_DIR not in sys.path:
    sys.path.insert(0, AI_PKG_DIR)


# 3. NOW it is safe to import ai_services


# Automatically create tables in Supabase if they do not exist
Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="NutriWise AI API",
    version="1.0.0",
    docs_url="/docs"
)

# ----------------- SECURITY & JWT CONFIG -----------------
JWT_SECRET = os.getenv(
    "JWT_SECRET", "supersecretnutriwisekey2026_hackathon_change_in_prod")
JWT_ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_SECONDS = int(
    os.getenv("ACCESS_TOKEN_EXPIRE_SECONDS", 86400))


def hash_password(password: str) -> str:
    pwd_bytes = password.encode("utf-8")[:72]
    salt = bcrypt.gensalt()
    return bcrypt.hashpw(pwd_bytes, salt).decode("utf-8")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    pwd_bytes = plain_password.encode("utf-8")[:72]
    return bcrypt.checkpw(pwd_bytes, hashed_password.encode("utf-8"))


def create_access_token(user_id: int, email: str) -> tuple[str, int]:
    expires_delta = timedelta(seconds=ACCESS_TOKEN_EXPIRE_SECONDS)
    expire = datetime.now(timezone.utc) + expires_delta
    to_encode = {"sub": str(user_id), "email": email, "exp": expire}
    return jwt.encode(to_encode, JWT_SECRET, algorithm=JWT_ALGORITHM), ACCESS_TOKEN_EXPIRE_SECONDS

# ----------------- GLOBAL ERROR HANDLER -----------------


@app.exception_handler(AIServiceError)
async def ai_service_error_handler(request: Request, exc: AIServiceError):
    http_status = STATUS_BY_CODE.get(exc.code, 500)
    return JSONResponse(
        status_code=http_status,
        content={"error": {"code": exc.code,
                           "message": exc.message, "retry": exc.retry}},
    )

# ----------------- AUTH SCHEMAS & ENDPOINTS -----------------


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


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int
    user_id: int
    name: str


@app.get("/")
def health_check():
    return {"status": "ok", "app": "NutriWise AI Backend running"}


@app.post("/auth/register", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
def register_user(payload: UserCreate, db: Session = Depends(get_db)):
    if db.query(User).filter(User.email == payload.email).first():
        raise HTTPException(
            status_code=400, detail="A user with this email is already registered.")

    hashed_pwd = hash_password(payload.password)
    user_record = User(name=payload.name, email=payload.email,
                       password_hash=hashed_pwd)
    db.add(user_record)
    db.commit()
    db.refresh(user_record)
    return user_record


@app.post("/auth/login", response_model=TokenResponse)
def login_user(payload: LoginRequest, db: Session = Depends(get_db)):
    db_user = db.query(User).filter(User.email == payload.email).first()
    if not db_user or not verify_password(payload.password, db_user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    token, expires_in = create_access_token(
        user_id=db_user.id, email=db_user.email)
    return TokenResponse(
        access_token=token,
        token_type="bearer",
        expires_in=expires_in,
        user_id=db_user.id,
        name=db_user.name,
    )

# ----------------- FAMILY MEMBER CRUD ENDPOINTS -----------------


@app.post("/api/family/members", response_model=FamilyMember, status_code=status.HTTP_201_CREATED)
def create_family_member(member: FamilyMember, user_id: int, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User account not found")

    db_member = FamilyMemberModel(
        user_id=user_id,
        name=member.name,
        age=member.age,
        gender=member.gender,
        allergies=member.allergies,
        anyother_specific_allergy=member.anyother_specific_allergy,
        food_preferences=member.food_preferences,
        cuisine_preferences=member.cuisine_preferences,
    )
    db.add(db_member)
    db.commit()
    db.refresh(db_member)

    return FamilyMember(
        id=str(db_member.id),
        name=db_member.name,
        age=db_member.age,
        gender=db_member.gender,
        allergies=db_member.allergies or [],
        anyother_specific_allergy=db_member.anyother_specific_allergy or [],
        food_preferences=db_member.food_preferences or [],
        cuisine_preferences=db_member.cuisine_preferences or [],
    )


@app.get("/api/family/members", response_model=list[FamilyMember])
def list_family_members(user_id: int, db: Session = Depends(get_db)):
    members = db.query(FamilyMemberModel).filter(
        FamilyMemberModel.user_id == user_id).all()
    return [
        FamilyMember(
            id=str(m.id),
            name=m.name,
            age=m.age,
            gender=m.gender,
            allergies=m.allergies or [],
            anyother_specific_allergy=m.anyother_specific_allergy or [],
            food_preferences=m.food_preferences or [],
            cuisine_preferences=m.cuisine_preferences or [],
        )
        for m in members
    ]


@app.put("/api/family/members/{member_id}", response_model=FamilyMember)
def update_family_member(member_id: int, payload: FamilyMember, db: Session = Depends(get_db)):
    db_member = db.query(FamilyMemberModel).filter(
        FamilyMemberModel.id == member_id).first()
    if not db_member:
        raise HTTPException(status_code=404, detail="Family member not found")

    db_member.name = payload.name
    db_member.age = payload.age
    db_member.gender = payload.gender
    db_member.allergies = payload.allergies
    db_member.anyother_specific_allergy = payload.anyother_specific_allergy
    db_member.food_preferences = payload.food_preferences
    db_member.cuisine_preferences = payload.cuisine_preferences

    db.commit()
    db.refresh(db_member)

    return FamilyMember(
        id=str(db_member.id),
        name=db_member.name,
        age=db_member.age,
        gender=db_member.gender,
        allergies=db_member.allergies or [],
        anyother_specific_allergy=db_member.anyother_specific_allergy or [],
        food_preferences=db_member.food_preferences or [],
        cuisine_preferences=db_member.cuisine_preferences or [],
    )


@app.delete("/api/family/members/{member_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_family_member(member_id: int, db: Session = Depends(get_db)):
    db_member = db.query(FamilyMemberModel).filter(
        FamilyMemberModel.id == member_id).first()
    if not db_member:
        raise HTTPException(status_code=404, detail="Family member not found")
    db.delete(db_member)
    db.commit()
    return None

# ----------------- AI CONTRACT ENDPOINTS -----------------


@app.post("/api/meal/analyze", response_model=MealAnalysis)
async def analyze_meal_endpoint(
    image: UploadFile = File(...),
    member_data: str = Form(..., description="JSON-serialized FamilyMember"),
):
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
    member: FamilyMember | None = None


@app.post("/api/meal/correct", response_model=MealAnalysis)
async def correct_meal_endpoint(payload: MealCorrectionPayload):
    result = await run_in_threadpool(
        ai_services.correct_meal,
        previous=payload.request_data.previous,
        corrections=payload.request_data.corrections,
        member=payload.member,
    )
    return result


@app.post("/api/fridge/analyze", response_model=FridgeInventory)
async def analyze_fridge_endpoint(image: UploadFile = File(...)):
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
    result = await run_in_threadpool(
        ai_services.suggest_recipes,
        inventory=payload.inventory,
        family=payload.family,
    )
    return result


class MealPlanPayload(BaseModel):
    family: list[FamilyMember]
    inventory: FridgeInventory | None = None
    day_preferences: list[DayPreference] | None = None


@app.post("/api/meal-plan/generate", response_model=WeeklyPlan)
async def generate_meal_plan_endpoint(payload: MealPlanPayload):
    result = await run_in_threadpool(
        ai_services.generate_meal_plan,
        family=payload.family,
        inventory=payload.inventory,
        day_preferences=payload.day_preferences,
    )
    return result


@app.post("/api/grocery-list/generate", response_model=GroceryList)
async def generate_grocery_list_endpoint(payload: GroceryListRequest):
    result = await run_in_threadpool(
        ai_services.generate_grocery_list,
        family=payload.family,
        plan=payload.plan,
        inventory=payload.inventory,
        user_requirements=payload.user_requirements,
    )
    return result
