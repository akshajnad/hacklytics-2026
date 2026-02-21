"""
Snowflake Cortex client for LLM completions and AI functions.
Requires SNOWFLAKE.CORTEX_USER role in Snowflake.
"""
import json
import os
from contextlib import contextmanager
from typing import Any

import snowflake.connector
from dotenv import load_dotenv

load_dotenv()

# Supported models for COMPLETE
DEFAULT_MODEL = "snowflake-arctic"
SUPPORTED_MODELS = [
    "claude-4-opus",
    "claude-4-sonnet",
    "claude-3-7-sonnet",
    "claude-3-5-sonnet",
    "deepseek-r1",
    "llama3-8b",
    "llama3-70b",
    "llama3.1-8b",
    "llama3.1-70b",
    "llama3.1-405b",
    "llama3.3-70b",
    "llama4-maverick",
    "llama4-scout",
    "mistral-large",
    "mistral-large2",
    "mistral-7b",
    "mixtral-8x7b",
    "openai-gpt-4.1",
    "openai-o4-mini",
    "snowflake-arctic",
    "snowflake-llama-3.1-405b",
    "snowflake-llama-3.3-70b",
]


def _get_connection_params() -> dict[str, str]:
    """Load Snowflake connection params from environment."""
    params: dict[str, str] = {}
    for key, val in [
        ("user", os.getenv("SNOWFLAKE_USER")),
        ("password", os.getenv("SNOWFLAKE_PASSWORD")),
        ("account", os.getenv("SNOWFLAKE_ACCOUNT")),
        ("warehouse", os.getenv("SNOWFLAKE_WAREHOUSE")),
        ("database", os.getenv("SNOWFLAKE_DATABASE")),
        ("schema", os.getenv("SNOWFLAKE_SCHEMA")),
        ("role", os.getenv("SNOWFLAKE_ROLE")),
    ]:
        if val:
            params[key] = val
    return params


@contextmanager
def get_connection():
    """Context manager for Snowflake connection."""
    params = _get_connection_params()
    if not all([params.get("user"), params.get("password"), params.get("account")]):
        raise ValueError(
            "Missing required env: SNOWFLAKE_USER, SNOWFLAKE_PASSWORD, SNOWFLAKE_ACCOUNT"
        )
    conn = snowflake.connector.connect(**params)
    try:
        yield conn
    finally:
        conn.close()


def complete(
    prompt: str | list[dict[str, str]],
    *,
    model: str = DEFAULT_MODEL,
    temperature: float | None = None,
    max_tokens: int | None = None,
    top_p: float | None = None,
    guardrails: bool = False,
) -> str | dict[str, Any]:
    """
    Call Snowflake Cortex COMPLETE to generate LLM response.

    Args:
        prompt: Plain string prompt, or list of message dicts with 'role' and 'content'.
        model: Cortex model name (default: snowflake-arctic).
        temperature: 0-1, controls randomness.
        max_tokens: Max output tokens (default 4096, max 8192).
        top_p: Alternative to temperature.
        guardrails: Enable Cortex Guard for safety filtering.

    Returns:
        String response if simple prompt, or JSON dict with choices, usage, etc.
    """
    if model not in SUPPORTED_MODELS:
        raise ValueError(f"Unsupported model. Use one of: {SUPPORTED_MODELS}")

    use_options = temperature is not None or max_tokens is not None or top_p is not None or guardrails

    if use_options and isinstance(prompt, str):
        prompt = [{"role": "user", "content": prompt}]

    options_obj = {}
    if temperature is not None:
        options_obj["temperature"] = temperature
    if max_tokens is not None:
        options_obj["max_tokens"] = max_tokens
    if top_p is not None:
        options_obj["top_p"] = top_p
    if guardrails:
        options_obj["guardrails"] = True

    if options_obj or isinstance(prompt, list):
        sql = """
            SELECT SNOWFLAKE.CORTEX.COMPLETE(
                %s,
                PARSE_JSON(%s),
                PARSE_JSON(%s)
            ) AS response
        """
        bind = (model, json.dumps(prompt), json.dumps(options_obj))
    else:
        sql = "SELECT SNOWFLAKE.CORTEX.COMPLETE(%s, %s) AS response"
        bind = (model, prompt)

    with get_connection() as conn:
        cur = conn.cursor()
        cur.execute(sql, bind)
        row = cur.fetchone()
        cur.close()

    raw = row[0] if row else ""
    try:
        return json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return raw


def sentiment(text: str) -> float:
    """
    Call SNOWFLAKE.CORTEX.SENTIMENT for sentiment score (-1 to 1).
    Best for English text.
    """
    with get_connection() as conn:
        cur = conn.cursor()
        cur.execute(
            "SELECT SNOWFLAKE.CORTEX.SENTIMENT(%s) AS score",
            (text,),
        )
        row = cur.fetchone()
        cur.close()
    return float(row[0]) if row else 0.0


def translate(
    text: str,
    to_lang: str,
    *,
    from_lang: str = "",
) -> str:
    """
    Call SNOWFLAKE.CORTEX.TRANSLATE.
    Use from_lang='' for auto-detect. Best when source or target is English.
    """
    with get_connection() as conn:
        cur = conn.cursor()
        cur.execute(
            "SELECT SNOWFLAKE.CORTEX.TRANSLATE(%s, %s, %s) AS translated",
            (text, from_lang, to_lang),
        )
        row = cur.fetchone()
        cur.close()
    return str(row[0]) if row else ""


def summarize(text: str) -> str:
    """
    Call SNOWFLAKE.CORTEX.SUMMARIZE for English text summarization.
    """
    with get_connection() as conn:
        cur = conn.cursor()
        cur.execute(
            "SELECT SNOWFLAKE.CORTEX.SUMMARIZE(%s) AS summary",
            (text,),
        )
        row = cur.fetchone()
        cur.close()
    return str(row[0]) if row else ""

if __name__ == "__main__":
    transcript = """
    Hi team, here’s the transcript from today’s meeting:
    - Discussed Q1 results
    - Agreed on next steps for the marketing campaign
    - Noted action items for John and Maria
    """

    # 1. Summarize
    summary = summarize(transcript)
    print("Summary:", summary)

    # 2. Sentiment analysis
    score = sentiment(transcript)
    print("Sentiment score:", score)

    # 3. Generate LLM completion (e.g., questions or insights)
    completion = complete(transcript, model="snowflake-arctic", temperature=0.7)
    print("LLM Completion:", completion)