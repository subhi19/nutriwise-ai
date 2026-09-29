"""
Error type for the AI module (ai-services).

Every AI function raises AIServiceError instead of a bare Exception, so the
backend can catch one type and map it to a clean HTTP response for the app.

Usage in the backend:

    from ai_services.errors import AIServiceError, STATUS_BY_CODE

    try:
        result = analyze_meal(image_bytes, mime_type, member)
    except AIServiceError as e:
        raise HTTPException(
            status_code=STATUS_BY_CODE[e.code],
            detail={"error": {"code": e.code, "message": e.message, "retry": e.retry}},
        )
"""

from typing import Literal

ErrorCode = Literal[
    "INVALID_IMAGE",
    "NO_FOOD_DETECTED",
    "AI_BUSY",
    "AI_INVALID_RESPONSE",
    "INVALID_INPUT",
    "INTERNAL",
]


class AIServiceError(Exception):
    """Raised by any ai_services function on a handled failure.

    Attributes:
        code: one of ErrorCode, stable and safe to branch on in the backend.
        message: short text, safe to show directly to the user.
        retry: whether the app should offer a retry button.
    """

    def __init__(self, code: ErrorCode, message: str, retry: bool = False):
        self.code = code
        self.message = message
        self.retry = retry
        super().__init__(f"[{code}] {message}")


# Suggested HTTP status per error code, for the backend to reuse.
STATUS_BY_CODE: dict[str, int] = {
    "INVALID_IMAGE": 400,
    "NO_FOOD_DETECTED": 422,
    "AI_BUSY": 503,
    "AI_INVALID_RESPONSE": 502,
    "INVALID_INPUT": 400,
    "INTERNAL": 500,
}


# --- Convenience constructors, so call sites read clearly ------------------

def invalid_image(message: str = "The image could not be read. Please try a JPEG or PNG under 5 MB.") -> AIServiceError:
    return AIServiceError("INVALID_IMAGE", message, retry=False)


def no_food_detected(message: str = "No food was recognized in this photo. Please try another photo.") -> AIServiceError:
    return AIServiceError("NO_FOOD_DETECTED", message, retry=False)


def ai_busy(message: str = "The AI service is busy, please retry.") -> AIServiceError:
    return AIServiceError("AI_BUSY", message, retry=True)


def ai_invalid_response(message: str = "The AI returned an unexpected response. Please retry.") -> AIServiceError:
    return AIServiceError("AI_INVALID_RESPONSE", message, retry=True)


def invalid_input(message: str) -> AIServiceError:
    return AIServiceError("INVALID_INPUT", message, retry=False)


def internal(message: str = "Something went wrong. Please try again.") -> AIServiceError:
    return AIServiceError("INTERNAL", message, retry=False)