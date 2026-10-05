import os
from google import genai

GEMINI_API_KEY = os.environ.get(
    "AQ.Ab8RN6KlWcjyGPPiIGTgeI-mO6aRDBfwt0tqGjfGuNLCCSXhyg")
MODEL_NAME = os.environ.get("MODEL_NAME", "gemini-2.5-flash")

client = genai.Client(api_key=GEMINI_API_KEY)
