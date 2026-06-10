# Telco Equipment Reconciliation Demo

Automated equipment reconciliation between an ENM (Ericsson Network Manager) physical inventory and a BOM (Bill of Materials) system. Fully self-contained in Snowflake — synthetic data, reconciliation logic, Streamlit dashboard, and AI agent all deploy from two SQL scripts.

## Prerequisites

- Snowflake account with ACCOUNTADMIN access

## Quick Start

Open a Snowsight SQL worksheet and run these scripts in order:

### 1. Run `setup.sql`

Creates the role, warehouse, database, GitHub integration, tables, procedures, semantic view, Cortex agent, and deploy procedure.

### 2. Run `deploy.sql`

Generates ~5,700 synthetic equipment records, runs the reconciliation (producing ~450 discrepancies), and deploys the Streamlit app from this GitHub repo.

### 3. Open the App

Navigate to **Data Products > Streamlit** in Snowsight and open **EQUIPMENT_RECONCILIATION_APP**.

## What Gets Created

| Object | Purpose |
|--------|---------|
| `EQUIPMENT_RECON_ROLE` | Demo role with minimal privileges |
| `EQUIPMENT_RECON_WH` | XS warehouse (auto-suspends after 60s) |
| `EQUIPMENT_RECON_DEMO` | Database with RAW and RECONCILED schemas |
| `RECONCILED.DEMO_REPO` | Git repository integration pointing to this repo |
| `RECONCILED.RECONCILIATION_AGENT` | Cortex AI agent for natural language queries |
| `RECONCILED.EQUIPMENT_RECONCILIATION_APP` | Streamlit dashboard |

## Cleanup

Run `teardown.sql` to remove all demo objects from the account.

## Files

| File | Purpose |
|------|---------|
| `setup.sql` | Creates all Snowflake objects (run first) |
| `deploy.sql` | Generates data and deploys the Streamlit app (run second) |
| `teardown.sql` | Removes all demo objects |
| `streamlit_app/` | Streamlit dashboard source (deployed via Git integration) |
