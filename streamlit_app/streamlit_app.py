"""
Equipment Reconciliation Dashboard

Visual interface for viewing reconciliation insights between
the ENM system and the BOM system.

Runs as Streamlit in Snowflake (SiS) or locally with a connection.
"""

import json

import altair as alt
import pandas as pd
import streamlit as st

# =============================================================================
# Snowflake Connection (SiS or local)
# =============================================================================

try:
    conn = st.connection("snowflake")
    session = conn.session()
    IS_SIS = True
except Exception as _e:
    # Running locally — fall back to manual connection
    IS_SIS = False
    import os
    from pathlib import Path
    import snowflake.connector
    try:
        import tomllib
    except ModuleNotFoundError:
        import tomli as tomllib
    from cryptography.hazmat.primitives import serialization


st.set_page_config(
    page_title="Equipment Reconciliation",
    page_icon=":bar_chart:",
    layout="wide",
)

# =============================================================================
# Custom CSS
# =============================================================================

st.markdown("""
<style>
    .app-header {
        background-color: #000000;
        padding: 12px 24px;
        margin: -1rem -1rem 1.5rem -1rem;
        display: flex;
        align-items: center;
        gap: 16px;
    }
    .app-header .brand {
        color: #FFFFFF;
        font-size: 18px;
        font-weight: 700;
        letter-spacing: -0.3px;
    }
    .app-header .brand .app-name {
        color: #FFFFFF;
        font-weight: 400;
    }
    .app-header .nav-links {
        display: flex;
        gap: 24px;
        margin-left: 48px;
    }
    .app-header .nav-links a {
        color: #AAAAAA;
        text-decoration: none;
        font-size: 14px;
        font-weight: 500;
        padding: 4px 0;
        border-bottom: 2px solid transparent;
        transition: color 0.2s, border-color 0.2s;
    }
    .app-header .nav-links a:hover {
        color: #FFFFFF;
    }
    .app-header .nav-links a.active {
        color: #FFFFFF;
        border-bottom: 2px solid #1976D2;
    }
    .badge-high {
        background-color: #FDECEA;
        color: #D32F2F;
        border: 1px solid #F5C6CB;
    }
    .badge-medium {
        background-color: #FFF3E0;
        color: #E65100;
        border: 1px solid #FFE0B2;
    }
    .kpi-card {
        background: #FFFFFF;
        border: 1px solid #E0E0E0;
        border-radius: 8px;
        padding: 20px;
        text-align: center;
    }
    .kpi-card .value {
        font-size: 32px;
        font-weight: 700;
        color: #000000;
        margin-bottom: 4px;
    }
    .kpi-card .label {
        font-size: 13px;
        color: #666666;
        text-transform: uppercase;
        letter-spacing: 0.5px;
    }
    .kpi-card.critical .value {
        color: #D32F2F;
    }
    .section-header {
        font-size: 20px;
        font-weight: 700;
        color: #000000;
        margin-bottom: 16px;
        padding-bottom: 8px;
        border-bottom: 2px solid #000000;
    }
    #MainMenu {visibility: hidden;}
    footer {visibility: hidden;}
    header {visibility: hidden;}
    .stChatMessage [data-testid="stChatMessageAvatarCustom"],
    .stChatMessage [data-testid="stChatMessageAvatarUser"],
    .stChatMessage [data-testid="stChatMessageAvatarAssistant"],
    .stChatMessage .stAvatar {
        display: none !important;
    }
</style>
""", unsafe_allow_html=True)


# =============================================================================
# Query Helper
# =============================================================================


if not IS_SIS:
    @st.cache_resource
    def _get_local_connection():
        """Get Snowflake connection for local development."""
        connection_name = os.getenv("SNOWFLAKE_DEFAULT_CONNECTION_NAME") or "default"
        toml_path = Path.home() / ".snowflake" / "connections.toml"
        if not toml_path.exists():
            toml_path = Path.home() / ".config" / "snowflake" / "connections.toml"
        with open(toml_path, "rb") as f:
            config = tomllib.load(f)
        conn_cfg = config.get(connection_name, {})
        connect_args = {
            "account": conn_cfg["account"],
            "user": conn_cfg["user"],
            "role": conn_cfg.get("role"),
            "warehouse": conn_cfg.get("warehouse"),
            "database": "EQUIPMENT_RECON_DEMO",
            "schema": "RECONCILED",
        }
        key_path = conn_cfg.get("private_key_path")
        if key_path:
            key_data = Path(key_path).expanduser().read_bytes()
            private_key = serialization.load_pem_private_key(key_data, password=None)
            connect_args["private_key"] = private_key.private_bytes(
                encoding=serialization.Encoding.DER,
                format=serialization.PrivateFormat.PKCS8,
                encryption_algorithm=serialization.NoEncryption(),
            )
        return snowflake.connector.connect(**connect_args)


def run_query(sql):
    """Execute a query and return a DataFrame."""
    if IS_SIS:
        return session.sql(sql).to_pandas()
    else:
        try:
            conn = _get_local_connection()
            with conn.cursor() as cur:
                cur.execute(sql)
                rows = cur.fetchall()
                cols = [c[0] for c in cur.description]
            return pd.DataFrame(rows, columns=cols)
        except Exception as e:
            if "Authentication token has expired" in str(e):
                _get_local_connection.clear()
                conn = _get_local_connection()
                with conn.cursor() as cur:
                    cur.execute(sql)
                    rows = cur.fetchall()
                    cols = [c[0] for c in cur.description]
                return pd.DataFrame(rows, columns=cols)
            raise


# =============================================================================
# Data Loading
# =============================================================================


@st.cache_data(ttl=600, show_spinner="Loading reconciliation data...")
def load_insights():
    return run_query("""
        SELECT
            SITE_ID, SITE_NAME, SECTOR, ENM_REGION, BOM_REGION, RRU_NUMBER,
            DISCREPANCY_TYPE, ENM_PRODUCT_NAME, ENM_PRODUCT_NUMBER, ENM_SERIAL_NUMBER,
            BOM_PRODUCT_NAME, BOM_PRODUCT_NUMBER, BOM_SERIAL_NUMBER,
            PROJECT_ID, PROJECT_STATUS, BOM_STATUS, SEVERITY,
            RECOMMENDED_ACTION, ESTIMATED_CAPITAL_AT_RISK, RECONCILIATION_RUN_TIMESTAMP
        FROM EQUIPMENT_RECON_DEMO.RECONCILED.RECONCILIATION_INSIGHTS
        ORDER BY ESTIMATED_CAPITAL_AT_RISK DESC
    """)


@st.cache_data(ttl=600)
def load_summary_stats():
    df = run_query("""
        SELECT
            COUNT(*) AS TOTAL_DISCREPANCIES,
            COUNT(DISTINCT SITE_ID) AS SITES_AFFECTED,
            SUM(ESTIMATED_CAPITAL_AT_RISK) AS TOTAL_CAPITAL_AT_RISK,
            SUM(CASE WHEN SEVERITY = 'HIGH' THEN 1 ELSE 0 END) AS HIGH_SEVERITY_COUNT,
            SUM(CASE WHEN SEVERITY = 'MEDIUM' THEN 1 ELSE 0 END) AS MEDIUM_SEVERITY_COUNT
        FROM EQUIPMENT_RECON_DEMO.RECONCILED.RECONCILIATION_INSIGHTS
    """)
    return df.iloc[0]


@st.cache_data(ttl=600)
def load_by_type():
    return run_query("""
        SELECT DISCREPANCY_TYPE, SEVERITY, COUNT(*) AS COUNT,
            SUM(ESTIMATED_CAPITAL_AT_RISK) AS CAPITAL_AT_RISK
        FROM EQUIPMENT_RECON_DEMO.RECONCILED.RECONCILIATION_INSIGHTS
        GROUP BY DISCREPANCY_TYPE, SEVERITY ORDER BY COUNT DESC
    """)


@st.cache_data(ttl=600)
def load_by_region():
    return run_query("""
        SELECT BOM_REGION AS REGION, DISCREPANCY_TYPE, COUNT(*) AS COUNT,
            SUM(ESTIMATED_CAPITAL_AT_RISK) AS CAPITAL_AT_RISK
        FROM EQUIPMENT_RECON_DEMO.RECONCILED.RECONCILIATION_INSIGHTS
        GROUP BY BOM_REGION, DISCREPANCY_TYPE ORDER BY REGION, COUNT DESC
    """)


def load_site_harmonized(site_ids):
    ids_str = ",".join(str(int(sid)) for sid in site_ids)
    return run_query(f"""
        SELECT SITE_ID, SITE_NAME, SECTOR, RRU_NUMBER, DISCREPANCY_TYPE,
            ENM_PRODUCT_NAME, ENM_PRODUCT_NUMBER, ENM_SERIAL_NUMBER,
            BOM_PRODUCT_NAME, BOM_PRODUCT_NUMBER, BOM_SERIAL_NUMBER,
            BOM_STATUS, PROJECT_STATUS
        FROM EQUIPMENT_RECON_DEMO.RECONCILED.HARMONIZED_RECONCILIATION_VIEW
        WHERE SITE_ID IN ({ids_str})
        ORDER BY SITE_NAME, SECTOR
    """)


# =============================================================================
# Page Routing
# =============================================================================

if "current_page" not in st.session_state:
    st.session_state.current_page = "summary"

current_page = st.session_state.current_page

# =============================================================================
# Header
# =============================================================================

nav_cols = st.columns([3, 1, 1, 1])
with nav_cols[0]:
    st.markdown("**Equipment Reconciliation**")
with nav_cols[1]:
    if st.button("Executive Summary", use_container_width=True, type="primary" if current_page == "summary" else "secondary"):
        st.session_state.current_page = "summary"
        st.rerun()
with nav_cols[2]:
    if st.button("Site Details", use_container_width=True, type="primary" if current_page == "details" else "secondary"):
        st.session_state.current_page = "details"
        st.rerun()
with nav_cols[3]:
    if st.button("AI Assistant", use_container_width=True, type="primary" if current_page == "assistant" else "secondary"):
        st.session_state.current_page = "assistant"
        st.rerun()

st.divider()

# =============================================================================
# Load Data
# =============================================================================

insights_df = load_insights()

# =============================================================================
# PAGE: Executive Summary
# =============================================================================

if current_page == "summary":

    stats = load_summary_stats()
    st.markdown('<div class="section-header">Executive Summary</div>', unsafe_allow_html=True)

    kpi_cols = st.columns(4)
    with kpi_cols[0]:
        st.markdown(f'<div class="kpi-card"><div class="value">{int(stats["TOTAL_DISCREPANCIES"]):,}</div><div class="label">Total Discrepancies</div></div>', unsafe_allow_html=True)
    with kpi_cols[1]:
        st.markdown(f'<div class="kpi-card critical"><div class="value">${int(stats["TOTAL_CAPITAL_AT_RISK"]):,.0f}</div><div class="label">Capital at Risk</div></div>', unsafe_allow_html=True)
    with kpi_cols[2]:
        st.markdown(f'<div class="kpi-card"><div class="value">{int(stats["SITES_AFFECTED"]):,}</div><div class="label">Sites Affected</div></div>', unsafe_allow_html=True)
    with kpi_cols[3]:
        st.markdown(f'<div class="kpi-card critical"><div class="value">{int(stats["HIGH_SEVERITY_COUNT"]):,}</div><div class="label">HIGH Severity</div></div>', unsafe_allow_html=True)

    st.markdown("")

    # Charts
    st.markdown('<div class="section-header">Discrepancy Analysis</div>', unsafe_allow_html=True)
    chart_cols = st.columns(2)

    with chart_cols[0]:
        st.markdown("**By Discrepancy Type**")
        type_data = load_by_type()
        bar_chart = (
            alt.Chart(type_data)
            .mark_bar(cornerRadiusTopLeft=4, cornerRadiusTopRight=4)
            .encode(
                x=alt.X("DISCREPANCY_TYPE:N", title=None, sort="-y", axis=alt.Axis(labelAngle=-45)),
                y=alt.Y("COUNT:Q", title="Count"),
                color=alt.Color("SEVERITY:N", scale=alt.Scale(domain=["HIGH", "MEDIUM"], range=["#D32F2F", "#F57C00"]), title="Severity"),
                tooltip=[alt.Tooltip("DISCREPANCY_TYPE:N", title="Type"), alt.Tooltip("COUNT:Q", title="Count"), alt.Tooltip("CAPITAL_AT_RISK:Q", title="Capital at Risk", format="$,.0f")],
            )
            .properties(height=300)
        )
        st.altair_chart(bar_chart, use_container_width=True)

    with chart_cols[1]:
        st.markdown("**Capital at Risk by Type**")
        donut_chart = (
            alt.Chart(type_data)
            .mark_arc(innerRadius=60, outerRadius=120)
            .encode(
                theta=alt.Theta("CAPITAL_AT_RISK:Q"),
                color=alt.Color("DISCREPANCY_TYPE:N", scale=alt.Scale(domain=["SERIAL_MISMATCH", "PRODUCT_MISMATCH", "NO_ENM_MATCH"], range=["#D32F2F", "#F57C00", "#757575"]), title="Type"),
                tooltip=[alt.Tooltip("DISCREPANCY_TYPE:N", title="Type"), alt.Tooltip("CAPITAL_AT_RISK:Q", title="Capital at Risk", format="$,.0f")],
            )
            .properties(height=300)
        )
        st.altair_chart(donut_chart, use_container_width=True)

    # Regional breakdown
    st.markdown("**By Region**")
    region_data = load_by_region()
    region_chart = (
        alt.Chart(region_data)
        .mark_bar(cornerRadiusTopLeft=4, cornerRadiusTopRight=4)
        .encode(
            x=alt.X("REGION:N", title=None),
            y=alt.Y("COUNT:Q", title="Count"),
            color=alt.Color("DISCREPANCY_TYPE:N", scale=alt.Scale(domain=["SERIAL_MISMATCH", "PRODUCT_MISMATCH", "NO_ENM_MATCH"], range=["#D32F2F", "#F57C00", "#757575"]), title="Type"),
            xOffset="DISCREPANCY_TYPE:N",
            tooltip=[alt.Tooltip("REGION:N", title="Region"), alt.Tooltip("DISCREPANCY_TYPE:N", title="Type"), alt.Tooltip("COUNT:Q", title="Count"), alt.Tooltip("CAPITAL_AT_RISK:Q", title="Capital at Risk", format="$,.0f")],
        )
        .properties(height=250)
    )
    st.altair_chart(region_chart, use_container_width=True)

    # Detail table
    st.markdown('<div class="section-header">Site-Level Discrepancies</div>', unsafe_allow_html=True)

    filter_cols = st.columns(3)
    with filter_cols[0]:
        region_options = ["All"] + sorted(insights_df["BOM_REGION"].dropna().unique().tolist())
        selected_region = st.selectbox("Region", region_options)
    with filter_cols[1]:
        severity_options = ["All"] + sorted(insights_df["SEVERITY"].dropna().unique().tolist())
        selected_severity = st.selectbox("Severity", severity_options)
    with filter_cols[2]:
        type_options = ["All"] + sorted(insights_df["DISCREPANCY_TYPE"].unique().tolist())
        selected_type = st.selectbox("Discrepancy Type", type_options)

    filtered_df = insights_df.copy()
    if selected_region != "All":
        filtered_df = filtered_df[filtered_df["BOM_REGION"] == selected_region]
    if selected_severity != "All":
        filtered_df = filtered_df[filtered_df["SEVERITY"] == selected_severity]
    if selected_type != "All":
        filtered_df = filtered_df[filtered_df["DISCREPANCY_TYPE"] == selected_type]

    st.markdown(f"Showing **{len(filtered_df):,}** of {len(insights_df):,} records ({len(filtered_df['SITE_ID'].unique()):,} sites)")
    filtered_df = filtered_df.reset_index(drop=True)

    def build_html_table(df):
        severity_colors = {"HIGH": "#D32F2F", "MEDIUM": "#E65100"}
        rows_html = ""
        for _, r in df.iterrows():
            sev_color = severity_colors.get(r["SEVERITY"], "#333")
            site_id = int(r["SITE_ID"])
            rows_html += f"""<tr>
                <td style="padding:6px 12px;border-bottom:1px solid #EEE;">{site_id}</td>
                <td style="padding:6px 12px;border-bottom:1px solid #EEE;">{r['SITE_NAME']}</td>
                <td style="padding:6px 12px;border-bottom:1px solid #EEE;">{r['SECTOR']}</td>
                <td style="padding:6px 12px;border-bottom:1px solid #EEE;">{r['BOM_REGION'] or '—'}</td>
                <td style="padding:6px 12px;border-bottom:1px solid #EEE;">{r['DISCREPANCY_TYPE']}</td>
                <td style="padding:6px 12px;border-bottom:1px solid #EEE;color:{sev_color};font-weight:600;">{r['SEVERITY']}</td>
                <td style="padding:6px 12px;border-bottom:1px solid #EEE;">${int(r['ESTIMATED_CAPITAL_AT_RISK']):,}</td>
            </tr>"""
        return f"""<div style="max-height:400px;overflow-y:auto;border:1px solid #E0E0E0;border-radius:4px;">
        <table style="width:100%;border-collapse:collapse;font-size:13px;">
            <thead><tr style="background:#F5F5F5;position:sticky;top:0;">
                <th style="padding:8px 12px;text-align:left;border-bottom:2px solid #E0E0E0;">Site ID</th>
                <th style="padding:8px 12px;text-align:left;border-bottom:2px solid #E0E0E0;">Site Name</th>
                <th style="padding:8px 12px;text-align:left;border-bottom:2px solid #E0E0E0;">Sector</th>
                <th style="padding:8px 12px;text-align:left;border-bottom:2px solid #E0E0E0;">Region</th>
                <th style="padding:8px 12px;text-align:left;border-bottom:2px solid #E0E0E0;">Discrepancy</th>
                <th style="padding:8px 12px;text-align:left;border-bottom:2px solid #E0E0E0;">Severity</th>
                <th style="padding:8px 12px;text-align:left;border-bottom:2px solid #E0E0E0;">Capital at Risk</th>
            </tr></thead>
            <tbody>{rows_html}</tbody>
        </table></div>"""

    st.markdown(build_html_table(filtered_df), unsafe_allow_html=True)


# =============================================================================
# PAGE: Site Details
# =============================================================================

elif current_page == "details":

    st.markdown('<div class="section-header">Site Details</div>', unsafe_allow_html=True)

    site_df = insights_df[["SITE_ID", "SITE_NAME"]].drop_duplicates().sort_values("SITE_NAME")
    site_options = site_df["SITE_ID"].tolist()
    site_labels = {row["SITE_ID"]: f"{int(row['SITE_ID'])} — {row['SITE_NAME']}" for _, row in site_df.iterrows()}

    default_selection = []

    selected_sites = st.multiselect(
        "Select Sites", options=site_options, default=default_selection,
        format_func=lambda x: site_labels.get(x, str(x)),
        placeholder="Search and select sites...",
    )

    if selected_sites:
        harmonized_df = load_site_harmonized(selected_sites)
        site_records = insights_df[insights_df["SITE_ID"].isin(selected_sites)]

        total_sectors = len(harmonized_df)
        reconciled_count = len(harmonized_df[harmonized_df["DISCREPANCY_TYPE"] == "MATCH"])
        discrepancy_count = total_sectors - reconciled_count

        st.markdown(f"**{len(selected_sites)} site(s)** — {total_sectors} sectors: **{reconciled_count}** reconciled, **{discrepancy_count}** with discrepancies")

        st.markdown('<div class="section-header" style="font-size:16px;margin-top:24px;">Equipment Summary</div>', unsafe_allow_html=True)

        summary_rows_html = ""
        for _, r in harmonized_df.iterrows():
            is_match = r["DISCREPANCY_TYPE"] == "MATCH"
            icon = '<span style="color:#2E7D32;font-size:16px;">&#x2714;</span>' if is_match else '<span style="color:#D32F2F;font-size:16px;">&#x2718;</span>'
            status_text = "Reconciled" if is_match else r["DISCREPANCY_TYPE"].replace("_", " ").title()
            row_bg = "" if is_match else "background-color:#FFF8F8;"
            summary_rows_html += f"""<tr style="{row_bg}">
                <td style="padding:6px 12px;border-bottom:1px solid #EEE;text-align:center;">{icon}</td>
                <td style="padding:6px 12px;border-bottom:1px solid #EEE;">{r['SITE_NAME'] or '—'}</td>
                <td style="padding:6px 12px;border-bottom:1px solid #EEE;font-weight:600;">{r['SECTOR']}</td>
                <td style="padding:6px 12px;border-bottom:1px solid #EEE;">{r['BOM_PRODUCT_NAME'] or '—'}</td>
                <td style="padding:6px 12px;border-bottom:1px solid #EEE;font-family:monospace;">{r['BOM_SERIAL_NUMBER'] or '—'}</td>
                <td style="padding:6px 12px;border-bottom:1px solid #EEE;">{r['ENM_PRODUCT_NAME'] or '—'}</td>
                <td style="padding:6px 12px;border-bottom:1px solid #EEE;font-family:monospace;">{r['ENM_SERIAL_NUMBER'] or '—'}</td>
                <td style="padding:6px 12px;border-bottom:1px solid #EEE;">{status_text}</td>
            </tr>"""

        st.markdown(f"""<div style="max-height:500px;overflow-y:auto;border:1px solid #E0E0E0;border-radius:4px;">
        <table style="width:100%;border-collapse:collapse;font-size:13px;">
            <thead><tr style="background:#F5F5F5;position:sticky;top:0;">
                <th style="padding:8px 12px;text-align:center;border-bottom:2px solid #E0E0E0;width:40px;"></th>
                <th style="padding:8px 12px;text-align:left;border-bottom:2px solid #E0E0E0;">Site</th>
                <th style="padding:8px 12px;text-align:left;border-bottom:2px solid #E0E0E0;">Sector</th>
                <th style="padding:8px 12px;text-align:left;border-bottom:2px solid #E0E0E0;">BOM Product</th>
                <th style="padding:8px 12px;text-align:left;border-bottom:2px solid #E0E0E0;">BOM Serial</th>
                <th style="padding:8px 12px;text-align:left;border-bottom:2px solid #E0E0E0;">ENM Product</th>
                <th style="padding:8px 12px;text-align:left;border-bottom:2px solid #E0E0E0;">ENM Serial</th>
                <th style="padding:8px 12px;text-align:left;border-bottom:2px solid #E0E0E0;">Status</th>
            </tr></thead>
            <tbody>{summary_rows_html}</tbody>
        </table></div>""", unsafe_allow_html=True)

        # Discrepancy details
        if discrepancy_count > 0:
            st.markdown('<div class="section-header" style="font-size:16px;margin-top:32px;">Discrepancy Details</div>', unsafe_allow_html=True)

            for _, row in site_records.iterrows():
                with st.expander(f"{row['SITE_NAME']} / {row['SECTOR']} — {row['DISCREPANCY_TYPE']} ({row['SEVERITY']})", expanded=True):
                    detail_cols = st.columns(2)
                    with detail_cols[0]:
                        st.markdown("**BOM (System of Record)**")
                        st.text(f"Product:  {row['BOM_PRODUCT_NAME'] or '—'}")
                        st.text(f"Part No:  {row['BOM_PRODUCT_NUMBER'] or '—'}")
                        st.text(f"Serial:   {row['BOM_SERIAL_NUMBER'] or '—'}")
                        if row["PROJECT_ID"]:
                            st.text(f"Project:  {row['PROJECT_ID']}")
                            st.text(f"Status:   {row['PROJECT_STATUS'] or '—'}")
                    with detail_cols[1]:
                        st.markdown("**ENM (Physical Inventory)**")
                        st.text(f"Product:  {row['ENM_PRODUCT_NAME'] or '—'}")
                        st.text(f"Part No:  {row['ENM_PRODUCT_NUMBER'] or '—'}")
                        st.text(f"Serial:   {row['ENM_SERIAL_NUMBER'] or '—'}")
                    st.divider()
                    st.markdown(f"**Action:** {row['RECOMMENDED_ACTION']}")
                    st.markdown(f"**Capital at Risk:** ${int(row['ESTIMATED_CAPITAL_AT_RISK']):,}")


# =============================================================================
# PAGE: AI Assistant
# =============================================================================

elif current_page == "assistant":

    st.markdown('<div class="section-header">AI Assistant</div>', unsafe_allow_html=True)
    st.markdown("Ask questions about equipment reconciliation data — discrepancies, capital at risk, site details, and more.")

    AGENT_FQN = "EQUIPMENT_RECON_DEMO.RECONCILED.RECONCILIATION_AGENT"

    if "messages" not in st.session_state:
        st.session_state.messages = []

    for msg in st.session_state.messages:
        with st.chat_message(msg["role"]):
            st.markdown(msg["content"])
            if msg.get("sql"):
                with st.expander("Generated SQL"):
                    st.code(msg["sql"], language="sql")

    if not st.session_state.messages:
        st.markdown("**Try asking:**")
        sample_cols = st.columns(2)
        samples = [
            "How many sites have serial number mismatches?",
            "What is the total capital at risk?",
            "Show HIGH severity discrepancies",
            "Break down discrepancies by type and severity",
        ]
        for i, sample in enumerate(samples):
            with sample_cols[i % 2]:
                if st.button(sample, key=f"sample_{i}", use_container_width=True):
                    st.session_state._pending_question = sample
                    st.rerun()

    pending = st.session_state.pop("_pending_question", None)
    user_input = st.chat_input("Ask about reconciliation data...")
    question = pending or user_input

    if question:
        st.session_state.messages.append({"role": "user", "content": question})
        with st.chat_message("user"):
            st.markdown(question)

        agent_messages = [{"role": m["role"], "content": [{"type": "text", "text": m["content"]}]} for m in st.session_state.messages]
        request_body = json.dumps({"messages": agent_messages})

        with st.chat_message("assistant"):
            with st.spinner("Analyzing..."):
                try:
                    result = run_query(f"""
                        SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
                            '{AGENT_FQN}',
                            $${request_body}$$
                        )
                    """)
                    raw_response = result.iloc[0, 0]
                    response_data = json.loads(raw_response)

                    answer_text = ""
                    generated_sql = ""
                    suggested = []

                    if isinstance(response_data, dict):
                        content_list = response_data.get("content", [])
                        for block in content_list:
                            if block.get("type") == "text":
                                answer_text += block.get("text", "")
                            elif block.get("type") == "tool_result":
                                for tc in block.get("content", []):
                                    if tc.get("type") == "json":
                                        sql_val = tc.get("json", {}).get("sql", "")
                                        if sql_val and "Generated by Cortex" in sql_val:
                                            generated_sql = sql_val
                            elif block.get("type") == "suggested_queries":
                                for sq in block.get("suggested_queries", []):
                                    suggested.append(sq.get("query", ""))

                    if not answer_text:
                        answer_text = response_data.get("message", "I wasn't able to generate a response.")

                    st.markdown(answer_text)
                    if generated_sql:
                        with st.expander("Generated SQL"):
                            st.code(generated_sql, language="sql")

                    st.session_state.messages.append({"role": "assistant", "content": answer_text, "sql": generated_sql})

                    if suggested:
                        st.markdown("**Suggested follow-ups:**")
                        for sq in suggested:
                            if st.button(sq, key=f"sugg_{hash(sq)}", use_container_width=True):
                                st.session_state._pending_question = sq
                                st.rerun()

                except Exception as e:
                    error_msg = f"Error communicating with agent: {e}"
                    st.error(error_msg)
                    st.session_state.messages.append({"role": "assistant", "content": error_msg})

    if st.session_state.messages:
        if st.button("Clear conversation", type="secondary"):
            st.session_state.messages = []
            st.rerun()
