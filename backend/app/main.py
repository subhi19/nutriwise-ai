import os
from dotenv import load_dotenv
load_dotenv() # isort: skip

from dotenv import load_dotenv
import os
import json
from datetime import datetime, timedelta, timezone
from fastapi.middleware.cors import CORSMiddleware
from fastapi import FastAPI, Depends, HTTPException, UploadFile, File, Form, status, Request
from fastapi.responses import JSONResponse
from fastapi.concurrency import run_in_threadpool
from sqlalchemy.orm import Session
from pydantic import BaseModel, EmailStr
import bcrypt
import jwt
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
    DayPreference,
)
from app.database import engine, Base, get_db
from app.models.user import User, FamilyMemberModel
import secrets
from ai_services.errors import AIServiceError, STATUS_BY_CODE
import sys
from pathlib import Path
import json
from typing import Any


def as_list(value: Any) -> list:
  """Convert DB value (list, JSON string, or comma-separated string) into a clean Python list."""
  if value is None:
    return []
  if isinstance(value, list):
    return value
  if isinstance(value, str):
    text = value.strip()
    if not text:
      return []
    try:
      parsed = json.loads(text)
      return as_list(parsed)
    except (ValueError, json.JSONDecodeError):
      return [p.strip() for p in text.split(',') if p.strip()]
  return []

# Add ai_services directory to sys.path BEFORE any other project imports
_AI_DIR = str(Path(__file__).resolve().parent.parent.parent /
              "ai-services" / "ai_services")
if _AI_DIR not in sys.path:
    sys.path.insert(0, _AI_DIR)


# 2. Add ai-services/ai_services to sys.path BEFORE any ai_services imports
AI_PKG_DIR = str(Path(__file__).resolve(
).parent.parent.parent / "ai-services" / "ai_services")
if AI_PKG_DIR not in sys.path:
    sys.path.insert(0, AI_PKG_DIR)




# Automatically create tables in Supabase if they do not exist
Base.metadata.create_all(bind=engine)

# ----------------- RATE LIMITING DEFINITION -----------------
import time
from starlette.middleware.base import BaseHTTPMiddleware

AI_ENDPOINTS = {
    "/api/meal/analyze",
    "/api/meal/correct",
    "/api/fridge/analyze",
    "/api/recipes/suggest",
    "/api/meal-plan/generate",
    "/api/grocery-list/generate",
}
_RATE_LIMIT_STORE: dict[str, list[float]] = {}

# Demo day friendly: 30 calls per minute, keyed by User Token (fallback to IP)
MAX_REQUESTS_PER_MINUTE = 30 

class AIRateLimitMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if request.method == "POST" and request.url.path in AI_ENDPOINTS:
            # Key by Bearer token if logged in, else client IP
            auth_header = request.headers.get("Authorization", "")
            client_key = auth_header if auth_header.startswith("Bearer ") else (request.client.host if request.client else "127.0.0.1")

            now = time.time()
            timestamps = _RATE_LIMIT_STORE.setdefault(client_key, [])
            timestamps = [t for t in timestamps if now - t < 60]
            _RATE_LIMIT_STORE[client_key] = timestamps

            if len(timestamps) >= MAX_REQUESTS_PER_MINUTE:
                raise HTTPException(
                    status_code=429,
                    detail="AI rate limit reached (max 30 requests/min). Please try again shortly."
                )
            timestamps.append(now)

        return await call_next(request)

# ----------------- CREATE APP INSTANCE -----------------
app = FastAPI(
    title="NutriWise AI API",
    version="2.0.0",
    docs_url="/docs"
)

# ----------------- ATTACH MIDDLEWARES -----------------
# Enable CORS for Flutter Web local testing
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Attach rate limiter AFTER app is defined
app.add_middleware(AIRateLimitMiddleware)

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


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class ForgotPasswordResponse(BaseModel):
    message: str
    # In development/hackathons, returning the token lets the frontend/tester
    # test immediately without configuring an SMTP/SendGrid mailer.
    reset_token: str | None = None


class ResetPasswordRequest(BaseModel):
    token: str
    new_password: str


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


# Check environment flag (defaults to True for local testing/hackathon demo)
EXPOSE_RESET_TOKEN = os.getenv("EXPOSE_RESET_TOKEN", "true").lower() == "true"

@app.post("/auth/forgot-password", response_model=ForgotPasswordResponse)
def forgot_password(payload: ForgotPasswordRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == payload.email).first()

    if not user:
        return ForgotPasswordResponse(
            message="If this email is registered, password reset instructions have been generated."
        )

    token = secrets.token_urlsafe(32)
    user.reset_token = token
    user.reset_token_expires_at = datetime.now(timezone.utc) + timedelta(minutes=15)
    db.commit()

    print(f"\n[AUTH] Password reset requested for {user.email}")
    print(f"[AUTH] Reset Token: {token}\n")

    return ForgotPasswordResponse(
        message="If this email is registered, password reset instructions have been generated.",
        reset_token=token if EXPOSE_RESET_TOKEN else None  # Hidden when EXPOSE_RESET_TOKEN=false
    )


@app.post("/auth/reset-password")
def reset_password(payload: ResetPasswordRequest, db: Session = Depends(get_db)):
    # Find user with matching active reset token
    user = db.query(User).filter(User.reset_token == payload.token).first()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired reset token."
        )

    # Verify expiration timestamp
    now = datetime.now(timezone.utc)
    if user.reset_token_expires_at is None or user.reset_token_expires_at < now:
        # Clear expired token
        user.reset_token = None
        user.reset_token_expires_at = None
        db.commit()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Reset token has expired. Please request a new one."
        )

    # Hash new password (72-byte safe limit for bcrypt)
    user.password_hash = hash_password(payload.new_password)

    # Clear reset token so it cannot be re-used
    user.reset_token = None
    user.reset_token_expires_at = None
    db.commit()

    return {"message": "Password successfully reset. You can now log in with your new password."}

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
        cuisine_preferences=db_member.cuisine_preferences or [],
    )
    db.add(db_member)
    db.commit()
    db.refresh(db_member)

    return FamilyMember(
        id=db_member.id,
        name=db_member.name,
        age=db_member.age,
        gender=db_member.gender,
        allergies=as_list(db_member.allergies),
        anyother_specific_allergy=as_list(db_member.anyother_specific_allergy),
        food_preferences=as_list(db_member.food_preferences),
        cuisine_preferences=as_list(db_member.cuisine_preferences),
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
    db_member.allergies = as_list(payload.allergies)
    db_member.anyother_specific_allergy = as_list(payload.anyother_specific_allergy)
    db_member.food_preferences = as_list(payload.food_preferences)
    db_member.cuisine_preferences = as_list(payload.cuisine_preferences)

    db.commit()
    db.refresh(db_member)

    return FamilyMember(
        id=db_member.id,
        name=db_member.name,
        age=db_member.age,
        gender=db_member.gender,
        allergies=as_list(db_member.allergies),
        anyother_specific_allergy=as_list(db_member.anyother_specific_allergy),
        food_preferences=as_list(db_member.food_preferences),
        cuisine_preferences=as_list(db_member.cuisine_preferences),
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

from typing import Union, Dict, List, Any
class MealPlanPayload(BaseModel):
    family: list[FamilyMember]
    inventory: FridgeInventory | None = None
    day_preferences: Union[List[DayPreference], Dict[str, Any], None] = None

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
