"""
Streamlit dashboard for visualizing Snowflake data.
Run with: streamlit run backend.src.dashboard.visualization
"""
import os
import sys
from pathlib import Path
import streamlit as st
import pandas as pd
from dotenv import load_dotenv
from backend.src.tone_analysis.client import get_connection

# Ensure repo root is on path for backend.src imports
sys.path.insert(0, str(Path(__file__).resolve().parents[3]))



# Load .env from backend directory
load_dotenv(Path(__file__).resolve().parents[2] / ".env")



st.set_page_config(
    page_title="Snowflake Dashboard",
    page_icon="❄️",
    layout="wide",
    initial_sidebar_state="expanded",
)


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
    st.title("❄️ Snowflake Data Dashboard")
    st.markdown("Explore and visualize your Snowflake data.")

    # Sidebar: connection status
    with st.sidebar:
        st.header("Connection")
        ok, result = test_connection()
        if ok:
            st.success("Connected")
            st.caption(f"**Account:** {result['account']}")
            st.caption(f"**Database:** {result.get('database', '-')}")
            st.caption(f"**Schema:** {result.get('schema', '-')}")
        else:
            st.error("Not connected")
            st.caption(str(result))
            st.info("Set SNOWFLAKE_USER, SNOWFLAKE_PASSWORD, SNOWFLAKE_ACCOUNT in .env")

    if not ok:
        st.warning("Configure Snowflake credentials to use the dashboard.")
        return

    # Tabs: Overview, Query, Tables
    tab1, tab2, tab3 = st.tabs(["Overview", "Query & Visualize", "Tables"])

    with tab1:
        st.subheader("Quick stats")
        db = os.getenv("SNOWFLAKE_DATABASE") or ""
        schema = os.getenv("SNOWFLAKE_SCHEMA") or ""
        if not db or not schema:
            st.info("Set SNOWFLAKE_DATABASE and SNOWFLAKE_SCHEMA in .env to list tables here.")
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
        st.subheader("Run SQL & visualize")
        default_sql = """
-- Example: warehouse credit usage (requires ACCOUNT_USAGE role)
-- SELECT DATE_TRUNC('day', START_TIME) AS DAY, SUM(CREDITS_USED) AS CREDITS
-- FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
-- WHERE START_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
-- GROUP BY 1 ORDER BY 1;

-- Or query your own tables, e.g.:
-- SELECT * FROM your_table LIMIT 1000;
"""
        sql = st.text_area("SQL query", value=default_sql, height=120)
        if st.button("Run query"):
            # Extract first non-empty, non-comment line that looks like SELECT
            lines = [l.strip() for l in sql.splitlines() if l.strip() and not l.strip().startswith("--")]
            query = " ".join(lines) if lines else ""
            if not query or "SELECT" not in query.upper():
                st.warning("Enter a valid SELECT query.")
            else:
                with st.spinner("Executing..."):
                    result = run_query(query)
                if isinstance(result, str):
                    st.error(result)
                else:
                    st.success(f"Returned {len(result)} rows")
                    st.dataframe(result, use_container_width=True, hide_index=True)
                    st.divider()
                    st.subheader("Visualization")
                    render_charts(result)

    with tab3:
        st.subheader("Explore tables")
        db = st.text_input("Database", value=os.getenv("SNOWFLAKE_DATABASE", ""))
        schema = st.text_input("Schema", value=os.getenv("SNOWFLAKE_SCHEMA", ""))
        if db and schema:
            if st.button("List tables"):
                tables_result = list_tables(db, schema)
                if isinstance(tables_result, pd.DataFrame):
                    st.dataframe(tables_result, use_container_width=True, hide_index=True)
                    for tn in tables_result["TABLE_NAME"].tolist():
                        with st.expander(f"📋 {tn}"):
                            preview_sql = f'SELECT * FROM "{db}"."{schema}"."{tn}" LIMIT 100'
                            if st.button("Preview", key=f"preview_{tn}"):
                                df = run_query(preview_sql)
                                if isinstance(df, pd.DataFrame):
                                    st.dataframe(df, use_container_width=True, hide_index=True)
                                    render_charts(df)
                                else:
                                    st.error(df)
                else:
                    st.error(str(tables_result))


if __name__ == "__main__":
    main()
