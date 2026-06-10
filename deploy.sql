-- =============================================================================
-- Equipment Reconciliation Demo - Deploy
-- =============================================================================
-- Run this AFTER setup.sql to generate data and deploy the Streamlit app.
-- =============================================================================

USE ROLE EQUIPMENT_RECON_ROLE;
USE WAREHOUSE EQUIPMENT_RECON_WH;
USE DATABASE EQUIPMENT_RECON_DEMO;

-- =============================================================================
-- Generate Data
-- =============================================================================

-- Generate synthetic ENM physical inventory (~5,700 rows)
CALL RAW.GENERATE_ENM_DATA();

-- Generate BOM records with ~8% discrepancies (~5,700 rows)
CALL RAW.GENERATE_BOM_DATA();

-- Materialize discrepancies (~400-500 records)
CALL RECONCILED.RUN_RECONCILIATION();

-- =============================================================================
-- Deploy Streamlit App
-- =============================================================================

-- Deploy the Streamlit app from GitHub
CALL RECONCILED.DEPLOY_STREAMLIT();

-- =============================================================================
-- Verify
-- =============================================================================

SELECT 'ENM' AS SOURCE, COUNT(*) AS ROWS FROM RAW.ENM_SERIAL_NUMBERS
UNION ALL
SELECT 'BOM', COUNT(*) FROM RAW.BOM_INVENTORY
UNION ALL
SELECT 'DISCREPANCIES', COUNT(*) FROM RECONCILED.RECONCILIATION_INSIGHTS;

SELECT DISCREPANCY_TYPE, SEVERITY, COUNT(*) AS COUNT, SUM(ESTIMATED_CAPITAL_AT_RISK) AS CAPITAL_AT_RISK
FROM RECONCILED.RECONCILIATION_INSIGHTS
GROUP BY 1, 2
ORDER BY CAPITAL_AT_RISK DESC;
