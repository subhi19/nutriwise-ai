"""
retry_utils.py

One shared retry helper, used everywhere we call Gemini. This way, if
you ever want to change how retries work (more attempts, longer waits),
you only change it here instead of in every file.

Wait times with the defaults below: 2s, 4s, 8s, 16s, 32s, 60s (capped)
across 6 attempts — about 2 minutes total before giving up.
"""

import time
from google.genai import errors


def call_with_retry(make_request, max_attempts: int = 5, base_wait: int = 2, max_wait: int = 16, label: str = "Gemini"):
    """
    make_request: a function with NO arguments that makes the Gemini call
    and returns whatever you need. Call it like:

        response = call_with_retry(lambda: client.models.generate_content(...))

    Retries only on "server busy" (503) errors, where trying again shortly
    after usually works. Does NOT retry on quota errors (429) — those mean
    you've used up your allowed requests (often a DAILY limit), so retrying
    just wastes time waiting for something that won't succeed until the
    quota resets or you switch models.

    Default timing: waits of 2s, 4s, 8s, 16s, 16s = 46s of sleep, plus the
    request time itself each attempt. Kept under the frontend's 90-second
    timeout on purpose — if this ever takes longer than 90s total, the
    frontend gives up and shows its own retry banner while this function
    is still silently retrying in the background, which can fire off two
    requests for the same action. Don't raise these numbers without
    checking the frontend's timeout first.
    """
    last_error = None

    for attempt in range(max_attempts):
        try:
            return make_request()
        except errors.ServerError as e:
            last_error = e
            wait = min(base_wait * (2 ** attempt), max_wait)
            print(f"{label} busy (attempt {attempt + 1}/{max_attempts}), retrying in {wait}s...")
            time.sleep(wait)
        except errors.ClientError as e:
            if "RESOURCE_EXHAUSTED" in str(e) or "429" in str(e):
                raise RuntimeError(
                    f"{label}: you've used up your free-tier quota for this model today. "
                    f"Either wait for it to reset, or switch models by setting the "
                    f"MODEL_NAME environment variable (e.g. gemini-2.5-flash)."
                ) from e
            raise  # a different client error (like a bad request) — don't retry, show it directly

    raise RuntimeError(
        f"{label} is busy right now after {max_attempts} attempts. "
        f"Please try again in a few minutes."
    ) from last_error