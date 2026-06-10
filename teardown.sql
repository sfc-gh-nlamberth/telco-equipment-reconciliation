-- =============================================================================
-- Equipment Reconciliation Demo - Teardown
-- =============================================================================
-- Removes all objects created by this demo.
-- Run with ACCOUNTADMIN.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

DROP STREAMLIT IF EXISTS EQUIPMENT_RECON_DEMO.RECONCILED.EQUIPMENT_RECONCILIATION_APP;
DROP DATABASE IF EXISTS EQUIPMENT_RECON_DEMO;
DROP WAREHOUSE IF EXISTS EQUIPMENT_RECON_WH;
DROP ROLE IF EXISTS EQUIPMENT_RECON_ROLE;

-- Optional: remove the API integration if no longer needed
-- DROP INTEGRATION IF EXISTS github_api_integration;
