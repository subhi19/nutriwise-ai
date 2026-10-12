from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, JSON
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from datetime import datetime, timezone
from app.database import Base


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False)
    email = Column(String(255), unique=True, index=True, nullable=False)
    password_hash = Column(String(255), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    # Password Reset Tracking
    reset_token = Column(String(255), nullable=True)
    reset_token_expires_at = Column(DateTime(timezone=True), nullable=True)

    # Relationship to link multiple family members to one user account
    family_members = relationship("FamilyMemberModel", back_populates="user")


class FamilyMemberModel(Base):
    __tablename__ = "family_members"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    name = Column(String(100), nullable=False)
    age = Column(Integer, nullable=False)
    gender = Column(String(20), nullable=False)

    # Store lists like ["milk", "peanut"] directly as JSON columns
    allergies = Column(JSON, default=list)
    health_conditions = Column(JSON, default=list)
    food_preferences = Column(JSON, default=list)
    cuisine_preferences = Column(JSON, default=list)

    user = relationship("User", back_populates="family_members")
