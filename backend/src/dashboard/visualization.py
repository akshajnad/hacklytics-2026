"""
Streamlit dashboard for visualizing Snowflake data.
Run with: streamlit run backend.src.dashboard.visualization
"""
from backend.src.tone_analysis.client import summarize
import os
import sys
import logging
import base64
import re
from pathlib import Path

# Ensure repo root is on path for backend.src imports
sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

import io
from PIL import Image, ImageDraw

import streamlit as st
import pandas as pd
from dotenv import load_dotenv
from backend.src.tone_analysis.client import get_connection



# Load .env from backend directory
load_dotenv(Path(__file__).resolve().parents[2] / ".env")

logger = logging.getLogger(__name__)

show_actual_data = False
images = []


def _safe_face_id_filename(face_id: object, fallback: str) -> str:
    raw = str(face_id).strip()
    if not raw:
        raw = fallback
    return re.sub(r"[^A-Za-z0-9._-]", "_", raw)


def _save_participant_images(participants: list[dict]) -> int:
    images_dir = Path(__file__).resolve().parent / "images"
    images_dir.mkdir(parents=True, exist_ok=True)

    saved = 0
    for idx, participant in enumerate(participants):
        face_id = participant.get("speaker_id") or participant.get("face_id") or f"face_{idx}"
        image_b64 = participant.get("image_base64_jpeg") or participant.get("image_base64")
        if not image_b64:
            continue

        try:
            image_bytes = base64.b64decode(image_b64, validate=True)
            with Image.open(io.BytesIO(image_bytes)) as img:
                out_path = images_dir / f"{_safe_face_id_filename(face_id, f'face_{idx}')}.png"
                img.convert("RGB").save(out_path, format="PNG")
            saved += 1
        except Exception as exc:
            logger.warning("Failed to save participant image for face_id=%s: %s", face_id, exc)
    return saved

def handle_meeting_payload_placeholder(payload: dict) -> None:
    """Temporary sink for meeting payloads sent from iOS.

    This is intentionally lightweight until dashboard persistence/processing is added.
    """
    transcripts = payload.get("transcripts", [])
    participants = payload.get("participants", [])
    started_at = payload.get("started_at_ms")
    ended_at = payload.get("ended_at_ms")

    logger.info(
        "Received meeting_payload: %s transcripts, %s participants, started_at=%s ended_at=%s",
        len(transcripts),
        len(participants),
        started_at,
        ended_at,
    )
    saved_count = _save_participant_images(participants)
    logger.info("Saved %s participant images as PNG in backend/src/dashboard/images", saved_count)


@st.cache_resource(ttl=300)
def test_connection():
    """Test Snowflake connection and return status."""
    try:
        with get_connection() as conn:
            cur = conn.cursor()
            cur.execute("SELECT CURRENT_VERSION(), CURRENT_ACCOUNT(), CURRENT_DATABASE(), CURRENT_SCHEMA()")
            row = cur.fetchone()
            cur.close()
        return True, {
            "version": row[0] if row else "unknown",
            "account": row[1] if row else "unknown",
            "database": row[2] if row else "unknown",
            "schema": row[3] if row else "unknown",
        }
    except Exception as e:
        return False, str(e)


@st.cache_data(ttl=60)
def run_query(sql: str) -> pd.DataFrame | str:
    """Execute a Snowflake query and return results as a DataFrame or error string."""
    try:
        with get_connection() as conn:
            df = pd.read_sql(sql, conn)
            return df
    except Exception as e:
        return str(e)


@st.cache_data(ttl=60)
def list_tables(database: str, schema: str) -> pd.DataFrame | str:
    """List tables in the given database and schema."""
    sql = f"""
        SELECT TABLE_NAME, ROW_COUNT, CREATED, LAST_ALTERED
        FROM "{database}".INFORMATION_SCHEMA.TABLES
        WHERE TABLE_SCHEMA = '{schema}'
        AND TABLE_TYPE = 'BASE TABLE'
        ORDER BY TABLE_NAME
    """
    return run_query(sql)


# Demo data for Meeting tab (used when no Snowflake tables)
DEMO_IMAGE_IDS = ["face_001", "face_002", "face_003", "face_004"]
DEMO_SPEAKER_VOLUMES = [
    {"speaker": "Speaker 1", "avg_volume": 0.72},
    {"speaker": "Speaker 2", "avg_volume": 0.58},
    {"speaker": "Speaker 3", "avg_volume": 0.65},
    {"speaker": "Speaker 4", "avg_volume": 0.41},
]
DEMO_HIGHLIGHTS = [
    {"text": "We should prioritize the Q1 marketing campaign launch.", "timestamp": "00:12:34", "tone": "Excited"},
    {"text": "The budget allocation looks solid—let's lock it in.", "timestamp": "00:18:22", "tone": "Calm"},
    {"text": "Action items: John handles design, Maria owns analytics.", "timestamp": "00:24:10", "tone": "Neutral"},
]


def make_placeholder_image(image_id: str, size: int = 50) -> bytes:
    """Create a placeholder avatar image for the given image_id."""
    colors = ["#4a90d9", "#7b68ee", "#50c878", "#e67e22", "#e74c3c", "#9b59b6"]
    idx = hash(image_id) % len(colors)
    img = Image.new("RGB", (size, size), color=colors[idx])
    draw = ImageDraw.Draw(img)
    # Draw a simple face silhouette (circle + eyes)
    margin = size // 6
    draw.ellipse([margin, margin, size - margin, size - margin], outline="white", width=3)
    draw.ellipse([margin + 15, margin + 25, margin + 35, margin + 45], fill="white")  # left eye
    draw.ellipse([size - margin - 35, margin + 25, size - margin - 15, margin + 45], fill="white")  # right eye
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def render_charts(df: pd.DataFrame) -> None:
    """Render appropriate charts based on DataFrame column types."""
    if df.empty or len(df) == 0:
        st.info("No data to visualize.")
        return

    numeric_cols = df.select_dtypes(include=["number"]).columns.tolist()
    datetime_cols = df.select_dtypes(include=["datetime64"]).columns.tolist()
    other_cols = [c for c in df.columns if c not in numeric_cols and c not in datetime_cols]

    col1, col2, col3 = st.columns(3)

    with col1:
        st.subheader("Chart type")
        chart_type = st.selectbox(
            "Choose visualization",
            ["Line", "Bar", "Area", "Scatter"],
            key="chart_type",
        )

    with col2:
        x_col = st.selectbox("X-axis", ["(index)"] + list(df.columns), key="x_col")
    with col3:
        if numeric_cols:
            y_col = st.selectbox("Y-axis (numeric)", numeric_cols, key="y_col")
        else:
            st.warning("No numeric columns for Y-axis.")
            return

    if x_col == "(index)":
        plot_df = df.set_index(df.index)
        x_data = plot_df.index
    else:
        x_data = df[x_col]

    try:
        chart_data = pd.DataFrame({"x": x_data, "y": df[y_col]})
        chart_data = chart_data.dropna()

        if chart_type == "Line":
            st.line_chart(chart_data.set_index("x"))
        elif chart_type == "Bar":
            st.bar_chart(chart_data.set_index("x"))
        elif chart_type == "Area":
            st.area_chart(chart_data.set_index("x"))
        elif chart_type == "Scatter" and len(numeric_cols) >= 2:
            y2 = st.selectbox("Y2 (scatter)", numeric_cols, index=min(1, len(numeric_cols) - 1), key="y2")
            try:
                st.scatter_chart(chart_data.assign(y2=df[y2]).set_index("x"))
            except Exception:
                st.line_chart(chart_data.set_index("x"))
    except Exception as e:
        st.error(f"Could not render chart: {e}")


def main() -> None:
    st.title("Data Dashboard (powered by Snowflake)")
    st.markdown("Explore and visualize your Snowflake data.")

    # Sidebar: connection status
    ok, result = test_connection()
    if not ok:
        st.error("Not connected")
        st.caption(str(result))
        st.info("Set SNOWFLAKE_USER, SNOWFLAKE_PASSWORD, SNOWFLAKE_ACCOUNT in .env")

    # Tabs: Overview, Query, Tables, Meeting
    tab1, tab2 = st.tabs(["Overview", "Meeting"])

    with tab1:
        st.subheader("Quick stats")
        if not ok:
            st.warning("Configure Snowflake credentials to explore tables.")
        db = os.getenv("SNOWFLAKE_DATABASE") or ""
        schema = os.getenv("SNOWFLAKE_SCHEMA") or ""
        if not ok or not db or not schema:
            st.info("Set SNOWFLAKE_DATABASE and SNOWFLAKE_SCHEMA in .env to list tables here." if ok else "Connect to Snowflake first.")
        else:
            tables_result = list_tables(db, schema)
            if isinstance(tables_result, pd.DataFrame) and not tables_result.empty:
                st.metric("Tables in schema", len(tables_result))
                st.dataframe(tables_result, use_container_width=True, hide_index=True)
            elif isinstance(tables_result, str):
                st.info("Run a custom query in the **Query & Visualize** tab.")
            else:
                st.info("No tables found in the configured database/schema.")

    with tab2:
        if not ok:
            st.warning("Configure Snowflake credentials to explore meeting insights.")
        st.subheader("Meeting Insights")

        # 1. Image ID + placeholder images
        st.markdown("#### Participants")
        image_ids = DEMO_IMAGE_IDS
        db, schema = os.getenv("SNOWFLAKE_DATABASE") or "", os.getenv("SNOWFLAKE_SCHEMA") or ""
        if ok and db and schema:
            participants_result = run_query(
                f'SELECT DISTINCT image_id FROM {db}.{schema}.transcript ORDER BY IMAGE_ID'
            )
            most_frequent = run_query(
                f"SELECT IMAGE_ID FROM {db}.{schema}.transcript GROUP BY IMAGE_ID ORDER BY COUNT(*) DESC LIMIT 1"
            )
            most_frequent_id = most_frequent.iloc[0, 0]

            if isinstance(participants_result, pd.DataFrame) and not participants_result.empty:
                image_ids = participants_result["IMAGE_ID"].astype(str).tolist()
        n_cols = min(len(image_ids), 4) or 1
        cols = st.columns(n_cols)
        for i, img_id in enumerate(image_ids):
            with cols[i % n_cols]:
                st.image("jellyfish.jpg", caption=img_id, use_container_width=True)
                if str(img_id) == str(most_frequent_id):
                    st.success("Most Active Speaker!")
                
        st.divider()

        # 2. Summary
        st.markdown("#### Summary")
        if ok and db and schema:
            chunks = run_query(f"SELECT LISTAGG(chunk, ' ') FROM {db}.{schema}.transcript")
            st.text(summarize(chunks.iloc[0, 0]))
            

        # 3. Bar chart: average volume per speaker
        st.markdown("#### Average Volume by Speaker")
        speaker_data = pd.DataFrame(DEMO_SPEAKER_VOLUMES)
        if ok and db and schema:
            vol_result = run_query(f"""
                SELECT speaker_id AS speaker, AVG(volume) AS avg_volume
                FROM {db}.{schema}.transcript
                GROUP BY speaker_id
            """)
            if isinstance(vol_result, pd.DataFrame) and not vol_result.empty:
                speaker_data = vol_result
        if not speaker_data.empty:
            chart_df = speaker_data.set_index(speaker_data.columns[0])
            st.bar_chart(chart_df)
        else:
            st.info("No speaker volume data. Use demo or add a captions table with speaker_id, volume.")

        st.divider()

        # 4. Meeting highlights
        st.markdown("#### Highlights")
        highlights = DEMO_HIGHLIGHTS
        if ok and db and schema:
            hl_result = run_query(f'SELECT text, timestamp, tone FROM "{db}"."{schema}".transcript')
            if isinstance(hl_result, pd.DataFrame) and not hl_result.empty:
                highlights = hl_result.to_dict("records")
        for h in highlights:
            with st.container():
                st.markdown(f"**{h.get('timestamp', '-')}** — *{h.get('tone', '')}*")
                st.markdown(f"> {h.get('text', '')}")
                st.caption("---")

        # 5. Automatic Task Detection
        st.markdown("#### Tasks")
        st.markdown("""
        - 🔥 **Send follow-up email to recruiter**  
        _High Priority_

        - 📊 **Finish Snowflake streaming integration**  
        _Due Tomorrow_

        - 🧠 **Review discrete math notes**  
        _Study Block_

        - 💪 **Workout - 30 min cardio**  
        _Personal Goal_
        """)
if __name__ == "__main__":
    main()
