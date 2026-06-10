-- =============================================================================
-- Equipment Reconciliation Demo - Setup Script
-- =============================================================================
-- This script creates all objects needed for a standalone equipment
-- reconciliation demo comparing ENM (network management) physical inventory
-- against BOM (Bill of Materials) system records.
--
-- All data is generated synthetically — no external files required.
--
-- Usage:
--   1. Run this entire script (creates infrastructure + empty tables)
--   2. CALL EQUIPMENT_RECON_DEMO.RAW.GENERATE_ENM_DATA();
--   3. CALL EQUIPMENT_RECON_DEMO.RAW.GENERATE_BOM_DATA();
--   4. CALL EQUIPMENT_RECON_DEMO.RECONCILED.RUN_RECONCILIATION();
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- =============================================================================
-- Role
-- =============================================================================

CREATE ROLE IF NOT EXISTS EQUIPMENT_RECON_ROLE
    COMMENT = 'Role for equipment reconciliation demo';

GRANT ROLE EQUIPMENT_RECON_ROLE TO ROLE SYSADMIN;

-- =============================================================================
-- Warehouse
-- =============================================================================

CREATE WAREHOUSE IF NOT EXISTS EQUIPMENT_RECON_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Warehouse for equipment reconciliation demo';

GRANT USAGE ON WAREHOUSE EQUIPMENT_RECON_WH TO ROLE EQUIPMENT_RECON_ROLE;

-- =============================================================================
-- Git Integration (for deploying Streamlit app from GitHub)
-- =============================================================================

CREATE API INTEGRATION IF NOT EXISTS github_api_integration
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-nlamberth/')
  ENABLED = TRUE;

GRANT USAGE ON INTEGRATION github_api_integration TO ROLE EQUIPMENT_RECON_ROLE;

-- =============================================================================
-- Database & Schemas
-- =============================================================================

CREATE DATABASE IF NOT EXISTS EQUIPMENT_RECON_DEMO
    COMMENT = 'Equipment reconciliation demo - ENM vs BOM discrepancy analysis';

GRANT OWNERSHIP ON DATABASE EQUIPMENT_RECON_DEMO TO ROLE EQUIPMENT_RECON_ROLE;

USE DATABASE EQUIPMENT_RECON_DEMO;

CREATE SCHEMA IF NOT EXISTS RAW
    COMMENT = 'Raw source data from ENM and BOM systems';

CREATE SCHEMA IF NOT EXISTS RECONCILED
    COMMENT = 'Reconciliation outputs and analytics';

-- =============================================================================
-- Grants
-- =============================================================================

GRANT CREATE SEMANTIC VIEW ON SCHEMA EQUIPMENT_RECON_DEMO.RECONCILED TO ROLE EQUIPMENT_RECON_ROLE;
GRANT CREATE STREAMLIT ON SCHEMA EQUIPMENT_RECON_DEMO.RECONCILED TO ROLE EQUIPMENT_RECON_ROLE;
GRANT USAGE ON WAREHOUSE EQUIPMENT_RECON_WH TO ROLE EQUIPMENT_RECON_ROLE;
GRANT USAGE ON DATABASE EQUIPMENT_RECON_DEMO TO ROLE EQUIPMENT_RECON_ROLE;
GRANT USAGE ON ALL SCHEMAS IN DATABASE EQUIPMENT_RECON_DEMO TO ROLE EQUIPMENT_RECON_ROLE;
GRANT ALL PRIVILEGES ON SCHEMA EQUIPMENT_RECON_DEMO.RAW TO ROLE EQUIPMENT_RECON_ROLE;
GRANT ALL PRIVILEGES ON SCHEMA EQUIPMENT_RECON_DEMO.RECONCILED TO ROLE EQUIPMENT_RECON_ROLE;

USE ROLE EQUIPMENT_RECON_ROLE;
USE WAREHOUSE EQUIPMENT_RECON_WH;
USE DATABASE EQUIPMENT_RECON_DEMO;

-- =============================================================================
-- RAW Schema Objects
-- =============================================================================

USE SCHEMA RAW;

-- ENM serial numbers table (physical network inventory)
CREATE OR REPLACE TABLE ENM_SERIAL_NUMBERS (
    MARKET VARCHAR,
    ENM VARCHAR,
    SITE_ID NUMBER(38,0),
    SITE_NAME VARCHAR,
    RRU_NUMBER VARCHAR,
    ADMIN_STATE VARCHAR,
    OPER_STATE VARCHAR,
    PRODUCT_NAME VARCHAR,
    PRODUCT_NUMBER VARCHAR,
    PRODUCT_REVISION VARCHAR,
    SERIAL_NUMBER VARCHAR
)
COMMENT = 'Physical radio inventory from ENM (Ericsson Network Manager)';

-- BOM inventory table (system of record)
CREATE OR REPLACE TABLE BOM_INVENTORY (
    SITE_ID NUMBER(38,0),
    SITE_NAME VARCHAR,
    PROJECT_ID VARCHAR,
    PROJECT_STATUS VARCHAR,
    SECTOR VARCHAR,
    EQUIPMENT_TYPE VARCHAR,
    MAKE VARCHAR,
    PRODUCT_NAME VARCHAR,
    PRODUCT_NUMBER VARCHAR,
    SERIAL_NUMBER VARCHAR,
    BOM_STATUS VARCHAR,
    INSTALL_DATE DATE,
    LAST_UPDATED TIMESTAMP_NTZ,
    REGION VARCHAR
)
COMMENT = 'Bill of Materials records from the asset management system';

-- =============================================================================
-- Procedure: Generate synthetic ENM data (~5,500 rows across ~1,800 sites)
-- =============================================================================

CREATE OR REPLACE PROCEDURE GENERATE_ENM_DATA()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
BEGIN
    TRUNCATE TABLE ENM_SERIAL_NUMBERS;

    -- Generate ~1,800 sites with 3 primary RRU sectors each,
    -- plus ~10% of sites get 1-3 additional sectors (RRU-410 through 610)
    INSERT INTO ENM_SERIAL_NUMBERS
    WITH
    -- Location name parts for generating realistic site names
    location_prefixes AS (
        SELECT column1 AS prefix, ROW_NUMBER() OVER (ORDER BY column1) - 1 AS idx FROM VALUES
            ('OAKWOOD'), ('PINE_RIDGE'), ('LAKESIDE'), ('CEDAR_CREEK'),
            ('MAPLE_GROVE'), ('RIVER_BEND'), ('HIGHLAND'), ('SUNSET'),
            ('EAGLE_POINT'), ('WILLOW_SPRINGS'), ('STONE_BRIDGE'), ('MEADOW_BROOK'),
            ('HARBOR_VIEW'), ('NORTH_PARK'), ('SOUTH_GATE'), ('EAST_RIDGE'),
            ('WEST_END'), ('CENTRAL_PLAZA'), ('BAYSHORE'), ('HILLCREST'),
            ('PALM_GROVE'), ('SILVER_LAKE'), ('GOLDEN_OAK'), ('IRON_HORSE'),
            ('BLUE_RIDGE'), ('GREEN_VALLEY'), ('RED_ROCK'), ('WHITE_PLAINS'),
            ('BLACK_MOUNTAIN'), ('CORAL_SPRINGS'), ('TWIN_PEAKS'), ('ROLLING_HILLS'),
            ('CRYSTAL_LAKE'), ('SHADOW_CREEK'), ('THUNDER_RIDGE'), ('FALCON_HEIGHTS'),
            ('HAWK_POINT'), ('OSPREY_LANDING'), ('HERON_BAY'), ('PELICAN_COVE'),
            ('DOLPHIN_WAY'), ('PANTHER_CREEK'), ('BEAR_HOLLOW'), ('WOLF_RUN'),
            ('FOX_CHASE'), ('DEER_PARK'), ('ELK_GROVE'), ('BISON_TRAIL'),
            ('MUSTANG_RIDGE'), ('STALLION_CROSSING'), ('RAVEN_WOOD'), ('SPARROW_HILL'),
            ('FINCH_MEADOW'), ('ORIOLE_PARK'), ('CARDINAL_POINT'), ('ROBIN_NEST'),
            ('CRANE_LANDING'), ('SWIFT_CREEK'), ('MARTIN_DALE'), ('WREN_HOLLOW'),
            ('SUMMIT_PARK'), ('VALLEY_FORGE'), ('CANYON_VIEW'), ('CLIFF_SIDE'),
            ('BOULDER_PASS'), ('GRANITE_PEAK'), ('MARBLE_FALLS'), ('SANDSTONE'),
            ('LIMESTONE'), ('SLATE_RIDGE'), ('COBALT_HILL'), ('AMBER_FIELD'),
            ('JADE_SPRINGS'), ('RUBY_CREEK'), ('PEARL_HARBOR'), ('IVORY_TOWER'),
            ('DIAMOND_HEAD'), ('EMERALD_ISLE'), ('SAPPHIRE_BAY'), ('TOPAZ_POINT'),
            ('GARNET_GROVE'), ('OPAL_CREEK'), ('JASPER_RIDGE'), ('ONYX_PEAK'),
            ('QUARTZ_HILL'), ('FLINT_ROCK'), ('COPPER_MINE'), ('BRONZE_AGE'),
            ('SILVER_SPRINGS'), ('GOLD_COAST'), ('PLATINUM_PLAZA'), ('TITANIUM_TOWER')
    ),
    -- Generate base sites (1,800 sites)
    site_base AS (
        SELECT
            ROW_NUMBER() OVER (ORDER BY SEQ4()) + 1000000 AS SITE_ID,
            SEQ4() AS SEQ_NUM
        FROM TABLE(GENERATOR(ROWCOUNT => 1800))
    ),
    -- Assign location names to sites via JOIN on modular index (90 locations)
    sites AS (
        SELECT
            s.SITE_ID,
            s.SEQ_NUM,
            CASE WHEN ABS(HASH(s.SITE_ID || 'region')) % 10 < 6 THEN 'Region_A' ELSE 'Region_B' END AS REGION,
            s.SITE_ID || CASE WHEN ABS(HASH(s.SITE_ID || 'type')) % 5 = 0 THEN '_5GNB_' ELSE '_4G5G_' END
                || lp.prefix AS SITE_NAME
        FROM site_base s
        JOIN location_prefixes lp ON lp.idx = ABS(HASH(s.SITE_ID || 'loc')) % 90
    ),
    -- Generate RRU assignments per site
    -- Every site gets RRU-110, 210, 310; ~10% also get 410-610
    rru_assignments AS (
        -- Primary sectors (all 1,800 sites x 3 RRUs = 5,400 rows)
        SELECT SITE_ID, 'RRU-110' AS RRU_NUMBER FROM sites
        UNION ALL
        SELECT SITE_ID, 'RRU-210' FROM sites
        UNION ALL
        SELECT SITE_ID, 'RRU-310' FROM sites
        UNION ALL
        -- Additional sector 410 (~10% of sites = ~180)
        SELECT SITE_ID, 'RRU-410' FROM sites WHERE ABS(HASH(SITE_ID || 'rru4')) % 10 = 0
        UNION ALL
        -- Additional sector 510 (~4% of sites = ~72)
        SELECT SITE_ID, 'RRU-510' FROM sites WHERE ABS(HASH(SITE_ID || 'rru5')) % 25 = 0
        UNION ALL
        -- Additional sector 610 (~3% of sites = ~54)
        SELECT SITE_ID, 'RRU-610' FROM sites WHERE ABS(HASH(SITE_ID || 'rru6')) % 30 = 0
    ),
    -- Combine sites with RRUs and assign products/serials
    enm_raw AS (
        SELECT
            s.REGION AS MARKET,
            s.REGION AS ENM,
            r.SITE_ID,
            s.SITE_NAME,
            r.RRU_NUMBER,
            'UNLOCKED' AS ADMIN_STATE,
            'ENABLED' AS OPER_STATE,
            CASE
                WHEN ABS(HASH(r.SITE_ID || r.RRU_NUMBER || 'prod')) % 100 < 5 THEN 'Radio 4435 B77D'
                WHEN ABS(HASH(r.SITE_ID || r.RRU_NUMBER || 'prod')) % 100 < 15 THEN 'AIR 6419 B77D'
                WHEN ABS(HASH(r.SITE_ID || r.RRU_NUMBER || 'prod')) % 100 < 30 THEN 'AIR 1652 B77D'
                WHEN ABS(HASH(r.SITE_ID || r.RRU_NUMBER || 'prod')) % 100 < 50 THEN 'AIR 6449 B77D'
                ELSE 'Radio 8863 B77D'
            END AS PRODUCT_NAME,
            CASE
                WHEN ABS(HASH(r.SITE_ID || r.RRU_NUMBER || 'prod')) % 100 < 5 THEN 'KRC 161 904/2'
                WHEN ABS(HASH(r.SITE_ID || r.RRU_NUMBER || 'prod')) % 100 < 15 THEN 'KRD 901 200/21'
                WHEN ABS(HASH(r.SITE_ID || r.RRU_NUMBER || 'prod')) % 100 < 30 THEN 'KRC 161 905/1'
                WHEN ABS(HASH(r.SITE_ID || r.RRU_NUMBER || 'prod')) % 100 < 50 THEN 'KRD 901 206/11'
                ELSE 'KRC 161 907/3'
            END AS PRODUCT_NUMBER,
            -- Product revision
            CASE ABS(HASH(r.SITE_ID || r.RRU_NUMBER || 'rev')) % 4
                WHEN 0 THEN 'R1G'
                WHEN 1 THEN 'R1E/A'
                WHEN 2 THEN 'R2A'
                ELSE 'R1F'
            END AS PRODUCT_REVISION,
            -- Serial number as date-coded YYYYMMDD (install dates between 2021-01 and 2025-06)
            TO_CHAR(
                DATEADD('day',
                    ABS(HASH(r.SITE_ID || r.RRU_NUMBER || 'serial')) % 1600,
                    '2021-01-01'::DATE
                ),
                'YYYYMMDD'
            ) AS SERIAL_NUMBER
        FROM rru_assignments r
        JOIN sites s ON r.SITE_ID = s.SITE_ID
    )
    SELECT
        MARKET,
        ENM,
        SITE_ID,
        SITE_NAME,
        RRU_NUMBER,
        ADMIN_STATE,
        OPER_STATE,
        PRODUCT_NAME,
        PRODUCT_NUMBER,
        PRODUCT_REVISION,
        SERIAL_NUMBER
    FROM enm_raw;

    LET row_count NUMBER := (SELECT COUNT(*) FROM ENM_SERIAL_NUMBERS);
    RETURN 'ENM data generated successfully. Row count: ' || :row_count::VARCHAR;
END;
$$;

-- =============================================================================
-- Procedure: Generate synthetic BOM data from ENM with ~8% discrepancies
-- =============================================================================

CREATE OR REPLACE PROCEDURE GENERATE_BOM_DATA()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
BEGIN
    TRUNCATE TABLE BOM_INVENTORY;

    -- Generate BOM records from ENM data
    -- Maps RRU numbers to sector names and introduces controlled discrepancies:
    --   ~4% serial mismatches (HIGH severity)
    --   ~3% product mismatches (MEDIUM severity)
    --   ~0.7% records excluded (NO_ENM_MATCH scenario — BOM-only entries added separately)

    INSERT INTO BOM_INVENTORY
    WITH enm_with_sector AS (
        SELECT
            SITE_ID,
            SITE_NAME,
            RRU_NUMBER,
            PRODUCT_NAME,
            PRODUCT_NUMBER,
            SERIAL_NUMBER,
            ENM AS REGION,
            CASE
                WHEN RRU_NUMBER = 'RRU-110' THEN 'Alpha'
                WHEN RRU_NUMBER = 'RRU-210' THEN 'Beta'
                WHEN RRU_NUMBER = 'RRU-310' THEN 'Gamma'
                WHEN RRU_NUMBER = 'RRU-410' THEN 'Delta'
                WHEN RRU_NUMBER = 'RRU-510' THEN 'Epsilon'
                WHEN RRU_NUMBER = 'RRU-610' THEN 'Zeta'
                WHEN RRU_NUMBER = 'RRU-710' THEN 'Eta'
                WHEN RRU_NUMBER = 'RRU-810' THEN 'Theta'
                WHEN RRU_NUMBER = 'RRU-910' THEN 'Iota'
                ELSE 'Unknown'
            END AS SECTOR,
            ABS(HASH(SITE_ID || RRU_NUMBER || SERIAL_NUMBER)) % 1000 AS RAND_VAL
        FROM ENM_SERIAL_NUMBERS
    ),
    bom_generated AS (
        SELECT
            SITE_ID,
            SITE_NAME,
            ABS(HASH(SITE_ID || 'project')) % 9000000 + 1000000 AS PROJECT_ID,
            CASE ABS(HASH(SITE_ID || 'status')) % 3
                WHEN 0 THEN 'Submitted'
                WHEN 1 THEN 'Partially Submitted'
                ELSE 'Draft'
            END AS PROJECT_STATUS,
            SECTOR,
            CASE
                WHEN PRODUCT_NAME LIKE '%8863%' OR PRODUCT_NAME LIKE '%4435%' THEN 'C-Band Radio'
                ELSE 'Radio Unit'
            END AS EQUIPMENT_TYPE,
            'Ericsson' AS MAKE,
            -- Introduce product mismatches (~3%)
            CASE
                WHEN RAND_VAL BETWEEN 40 AND 68 THEN
                    CASE
                        WHEN PRODUCT_NAME = 'Radio 8863 B77D' THEN 'AIR 6449 B77D'
                        WHEN PRODUCT_NAME = 'AIR 6449 B77D' THEN 'Radio 8863 B77D'
                        WHEN PRODUCT_NAME = 'AIR 1652 B77D' THEN 'AIR 6419 B77D'
                        ELSE 'AIR 6449 B77D'
                    END
                ELSE PRODUCT_NAME
            END AS PRODUCT_NAME,
            CASE
                WHEN RAND_VAL BETWEEN 40 AND 68 THEN
                    CASE
                        WHEN PRODUCT_NUMBER = 'KRC 161 907/3' THEN 'KRD 901 206/11'
                        WHEN PRODUCT_NUMBER = 'KRD 901 206/11' THEN 'KRC 161 907/3'
                        ELSE 'KRD 901 206/11'
                    END
                ELSE PRODUCT_NUMBER
            END AS PRODUCT_NUMBER,
            -- Introduce serial mismatches (~4%)
            CASE
                WHEN RAND_VAL < 40 THEN
                    LEFT(SERIAL_NUMBER, 6) || LPAD((RIGHT(SERIAL_NUMBER, 2)::INT + 26)::VARCHAR, 2, '0')
                ELSE SERIAL_NUMBER
            END AS SERIAL_NUMBER,
            CASE ABS(HASH(SITE_ID || SECTOR || 'bom_status')) % 3
                WHEN 0 THEN 'Placed In Service'
                WHEN 1 THEN 'Installed Not Activated'
                ELSE 'Installed Not Activated'
            END AS BOM_STATUS,
            TRY_TO_DATE(LEFT(SERIAL_NUMBER, 8), 'YYYYMMDD') AS INSTALL_DATE,
            DATEADD('day',
                ABS(HASH(SITE_ID || SECTOR || 'updated')) % 120 + 14,
                TRY_TO_DATE(LEFT(SERIAL_NUMBER, 8), 'YYYYMMDD')
            )::TIMESTAMP_NTZ AS LAST_UPDATED,
            REGION,
            RAND_VAL
        FROM enm_with_sector
        WHERE RAND_VAL < 993
    )
    SELECT
        SITE_ID,
        SITE_NAME,
        PROJECT_ID::VARCHAR,
        PROJECT_STATUS,
        SECTOR,
        EQUIPMENT_TYPE,
        MAKE,
        PRODUCT_NAME,
        PRODUCT_NUMBER,
        SERIAL_NUMBER,
        BOM_STATUS,
        INSTALL_DATE,
        LAST_UPDATED,
        REGION
    FROM bom_generated;

    -- Add BOM-only records (equipment in BOM but not found in ENM)
    INSERT INTO BOM_INVENTORY
    SELECT
        SEQ4() + 2900000 AS SITE_ID,
        (SEQ4() + 2900000) || '_5GNB_DECOMMISSIONED_SITE_' || SEQ4() AS SITE_NAME,
        ABS(HASH(SEQ4() || 'orphan_proj'))::VARCHAR AS PROJECT_ID,
        'Draft' AS PROJECT_STATUS,
        CASE SEQ4() % 3 WHEN 0 THEN 'Alpha' WHEN 1 THEN 'Beta' ELSE 'Gamma' END AS SECTOR,
        'C-Band Radio' AS EQUIPMENT_TYPE,
        'Ericsson' AS MAKE,
        'Radio 8863 B77D' AS PRODUCT_NAME,
        'KRC 161 907/3' AS PRODUCT_NUMBER,
        '2023' || LPAD((SEQ4() % 12 + 1)::VARCHAR, 2, '0') || LPAD((SEQ4() % 28 + 1)::VARCHAR, 2, '0') AS SERIAL_NUMBER,
        'Installed Not Activated' AS BOM_STATUS,
        '2023-06-15'::DATE AS INSTALL_DATE,
        '2023-08-01 00:00:00'::TIMESTAMP_NTZ AS LAST_UPDATED,
        CASE WHEN SEQ4() % 2 = 0 THEN 'Region_A' ELSE 'Region_B' END AS REGION
    FROM TABLE(GENERATOR(ROWCOUNT => 39));

    LET row_count NUMBER := (SELECT COUNT(*) FROM BOM_INVENTORY);
    RETURN 'BOM data generated successfully. Row count: ' || :row_count::VARCHAR;
END;
$$;

-- =============================================================================
-- RECONCILED Schema Objects
-- =============================================================================

USE SCHEMA RECONCILED;

-- =============================================================================
-- Harmonized Reconciliation View
-- =============================================================================

CREATE OR REPLACE VIEW HARMONIZED_RECONCILIATION_VIEW AS
WITH enm_mapped AS (
    SELECT
        e.*,
        CASE
            WHEN RRU_NUMBER = 'RRU-110' THEN 'Alpha'
            WHEN RRU_NUMBER = 'RRU-210' THEN 'Beta'
            WHEN RRU_NUMBER = 'RRU-310' THEN 'Gamma'
            WHEN RRU_NUMBER = 'RRU-410' THEN 'Delta'
            WHEN RRU_NUMBER = 'RRU-510' THEN 'Epsilon'
            WHEN RRU_NUMBER = 'RRU-610' THEN 'Zeta'
            WHEN RRU_NUMBER = 'RRU-710' THEN 'Eta'
            WHEN RRU_NUMBER = 'RRU-810' THEN 'Theta'
            WHEN RRU_NUMBER = 'RRU-910' THEN 'Iota'
            ELSE 'Unknown'
        END AS SECTOR
    FROM EQUIPMENT_RECON_DEMO.RAW.ENM_SERIAL_NUMBERS e
)

SELECT
    COALESCE(enm.SITE_ID, bom.SITE_ID) AS SITE_ID,
    COALESCE(enm.SITE_NAME, bom.SITE_NAME) AS SITE_NAME,
    COALESCE(enm.SECTOR, bom.SECTOR) AS SECTOR,
    enm.ENM AS ENM_REGION,
    bom.REGION AS BOM_REGION,
    enm.RRU_NUMBER,
    enm.ADMIN_STATE AS ENM_ADMIN_STATE,
    enm.OPER_STATE AS ENM_OPER_STATE,

    -- ENM values
    enm.PRODUCT_NAME AS ENM_PRODUCT_NAME,
    enm.PRODUCT_NUMBER AS ENM_PRODUCT_NUMBER,
    enm.SERIAL_NUMBER AS ENM_SERIAL_NUMBER,

    -- BOM values
    bom.PRODUCT_NAME AS BOM_PRODUCT_NAME,
    bom.PRODUCT_NUMBER AS BOM_PRODUCT_NUMBER,
    bom.SERIAL_NUMBER AS BOM_SERIAL_NUMBER,
    bom.PROJECT_ID,
    bom.PROJECT_STATUS,
    bom.BOM_STATUS,
    bom.INSTALL_DATE,
    bom.LAST_UPDATED,

    -- Discrepancy classification
    CASE
        WHEN enm.SITE_ID IS NULL AND bom.SITE_ID IS NOT NULL THEN 'NO_ENM_MATCH'
        WHEN enm.PRODUCT_NAME != bom.PRODUCT_NAME THEN 'PRODUCT_MISMATCH'
        WHEN enm.SERIAL_NUMBER != bom.SERIAL_NUMBER THEN 'SERIAL_MISMATCH'
        ELSE 'MATCH'
    END AS DISCREPANCY_TYPE

FROM enm_mapped enm
FULL OUTER JOIN EQUIPMENT_RECON_DEMO.RAW.BOM_INVENTORY bom
    ON enm.SITE_ID = bom.SITE_ID
    AND enm.SECTOR = bom.SECTOR;

-- =============================================================================
-- Reconciliation Insights Table
-- =============================================================================

CREATE OR REPLACE TABLE RECONCILIATION_INSIGHTS (
    SITE_ID NUMBER(38,0),
    SITE_NAME VARCHAR,
    SECTOR VARCHAR,
    ENM_REGION VARCHAR,
    RRU_NUMBER VARCHAR,
    DISCREPANCY_TYPE VARCHAR,
    ENM_PRODUCT_NAME VARCHAR,
    ENM_PRODUCT_NUMBER VARCHAR,
    ENM_SERIAL_NUMBER VARCHAR,
    BOM_PRODUCT_NAME VARCHAR,
    BOM_PRODUCT_NUMBER VARCHAR,
    BOM_SERIAL_NUMBER VARCHAR,
    PROJECT_ID VARCHAR,
    PROJECT_STATUS VARCHAR,
    BOM_STATUS VARCHAR,
    SEVERITY VARCHAR,
    RECOMMENDED_ACTION VARCHAR,
    ESTIMATED_CAPITAL_AT_RISK NUMBER(10,0),
    RECONCILIATION_RUN_TIMESTAMP TIMESTAMP_LTZ,
    BOM_REGION VARCHAR
)
COMMENT = 'Materialized discrepancy records with severity classification and recommended actions';

-- =============================================================================
-- Procedure: Run Reconciliation (materialize discrepancies)
-- =============================================================================

CREATE OR REPLACE PROCEDURE RUN_RECONCILIATION()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
BEGIN
    TRUNCATE TABLE RECONCILIATION_INSIGHTS;

    INSERT INTO RECONCILIATION_INSIGHTS
    SELECT
        SITE_ID,
        SITE_NAME,
        SECTOR,
        ENM_REGION,
        RRU_NUMBER,
        DISCREPANCY_TYPE,
        ENM_PRODUCT_NAME,
        ENM_PRODUCT_NUMBER,
        ENM_SERIAL_NUMBER,
        BOM_PRODUCT_NAME,
        BOM_PRODUCT_NUMBER,
        BOM_SERIAL_NUMBER,
        PROJECT_ID,
        PROJECT_STATUS,
        BOM_STATUS,
        -- Severity classification
        CASE
            WHEN DISCREPANCY_TYPE = 'SERIAL_MISMATCH' THEN 'HIGH'
            WHEN DISCREPANCY_TYPE = 'PRODUCT_MISMATCH' THEN 'MEDIUM'
            WHEN DISCREPANCY_TYPE = 'NO_ENM_MATCH' THEN 'MEDIUM'
            ELSE 'LOW'
        END AS SEVERITY,
        -- Recommended action
        CASE
            WHEN DISCREPANCY_TYPE = 'SERIAL_MISMATCH' THEN 'Update BOM serial number to match ENM physical inventory'
            WHEN DISCREPANCY_TYPE = 'PRODUCT_MISMATCH' THEN 'Verify installed equipment and update BOM product record'
            WHEN DISCREPANCY_TYPE = 'NO_ENM_MATCH' THEN 'Investigate missing ENM record - confirm equipment status on site'
            ELSE 'No action required'
        END AS RECOMMENDED_ACTION,
        -- Estimated capital at risk per unit
        CASE
            WHEN DISCREPANCY_TYPE = 'SERIAL_MISMATCH' THEN 22000
            WHEN DISCREPANCY_TYPE = 'PRODUCT_MISMATCH' THEN 18000
            WHEN DISCREPANCY_TYPE = 'NO_ENM_MATCH' THEN 15000
            ELSE 0
        END AS ESTIMATED_CAPITAL_AT_RISK,
        CURRENT_TIMESTAMP() AS RECONCILIATION_RUN_TIMESTAMP,
        BOM_REGION
    FROM HARMONIZED_RECONCILIATION_VIEW
    WHERE DISCREPANCY_TYPE != 'MATCH';

    LET row_count NUMBER := (SELECT COUNT(*) FROM RECONCILIATION_INSIGHTS);
    RETURN 'Reconciliation complete. Discrepancies found: ' || :row_count::VARCHAR;
END;
$$;

-- =============================================================================
-- Semantic View (for Cortex Analyst)
-- =============================================================================

CREATE OR REPLACE SEMANTIC VIEW RECONCILIATION_SEMANTIC_VIEW
    TABLES (
        INSIGHTS AS EQUIPMENT_RECON_DEMO.RECONCILED.RECONCILIATION_INSIGHTS
            PRIMARY KEY (SITE_ID, SECTOR)
    )
    FACTS (
        INSIGHTS.ESTIMATED_CAPITAL_AT_RISK AS ESTIMATED_CAPITAL_AT_RISK
    )
    DIMENSIONS (
        INSIGHTS.SITE_ID AS SITE_ID,
        INSIGHTS.SITE_NAME AS SITE_NAME,
        INSIGHTS.SECTOR AS SECTOR,
        INSIGHTS.ENM_REGION AS ENM_REGION,
        INSIGHTS.RRU_NUMBER AS RRU_NUMBER,
        INSIGHTS.DISCREPANCY_TYPE AS DISCREPANCY_TYPE,
        INSIGHTS.SEVERITY AS SEVERITY,
        INSIGHTS.RECOMMENDED_ACTION AS RECOMMENDED_ACTION,
        INSIGHTS.ENM_PRODUCT_NAME AS ENM_PRODUCT_NAME,
        INSIGHTS.BOM_PRODUCT_NAME AS BOM_PRODUCT_NAME,
        INSIGHTS.ENM_SERIAL_NUMBER AS ENM_SERIAL_NUMBER,
        INSIGHTS.BOM_SERIAL_NUMBER AS BOM_SERIAL_NUMBER,
        INSIGHTS.PROJECT_ID AS PROJECT_ID,
        INSIGHTS.PROJECT_STATUS AS PROJECT_STATUS,
        INSIGHTS.BOM_STATUS AS BOM_STATUS
    )
    METRICS (
        INSIGHTS.TOTAL_CAPITAL_AT_RISK AS SUM(ESTIMATED_CAPITAL_AT_RISK),
        INSIGHTS.DISCREPANCY_COUNT AS COUNT(SITE_ID)
    )
    WITH EXTENSION (CA='{
        "tables": [{
            "name": "INSIGHTS",
            "dimensions": [
                {"name": "SITE_ID", "description": "Unique site identifier - join key between ENM and BOM systems"},
                {"name": "SITE_NAME", "description": "Descriptive name of the cell site including site ID and location"},
                {"name": "SECTOR", "description": "Radio sector: Alpha (110), Beta (210), Gamma (310), Delta (410), Epsilon (510), Zeta (610)"},
                {"name": "ENM_REGION", "description": "ENM management region"},
                {"name": "RRU_NUMBER", "description": "Remote Radio Unit number from ENM"},
                {"name": "DISCREPANCY_TYPE", "description": "Type of mismatch: SERIAL_MISMATCH, PRODUCT_MISMATCH, or NO_ENM_MATCH"},
                {"name": "SEVERITY", "description": "Issue severity: HIGH (serial mismatch) or MEDIUM (product mismatch, no ENM match)"},
                {"name": "RECOMMENDED_ACTION", "description": "Suggested remediation step for the discrepancy"},
                {"name": "ENM_PRODUCT_NAME", "description": "Radio model reported by ENM network management system"},
                {"name": "BOM_PRODUCT_NAME", "description": "Radio model recorded in the BOM system"},
                {"name": "ENM_SERIAL_NUMBER", "description": "Serial number (date-coded YYYYMMDD) from ENM physical network"},
                {"name": "BOM_SERIAL_NUMBER", "description": "Serial number recorded in the BOM system"},
                {"name": "PROJECT_ID", "description": "Project identifier for this site"},
                {"name": "PROJECT_STATUS", "description": "Project status: Submitted, Partially Submitted, or Draft"},
                {"name": "BOM_STATUS", "description": "BOM placement status: Placed In Service, Installed Not Activated, or Pending"}
            ],
            "facts": [
                {"name": "ESTIMATED_CAPITAL_AT_RISK", "description": "Estimated dollar value of capital at risk per unreconciled radio unit"}
            ],
            "metrics": [
                {"name": "TOTAL_CAPITAL_AT_RISK", "description": "Total estimated capital at risk from unreconciled equipment"},
                {"name": "DISCREPANCY_COUNT", "description": "Total number of equipment discrepancies"}
            ]
        }]
    }');

-- =============================================================================
-- Cortex Agent
-- =============================================================================

CREATE OR REPLACE AGENT RECONCILIATION_AGENT
COMMENT = 'Conversational AI for equipment reconciliation - analyzes ENM vs BOM discrepancies'
FROM SPECIFICATION
$$
models:
  orchestration: "auto"
instructions:
  response: "You are the Equipment Reconciliation Assistant. You help network engineers and asset managers understand equipment discrepancies between the ENM (Ericsson Network Manager) physical inventory and the BOM (Bill of Materials) system. Answer questions about serial number mismatches, product mismatches, missing ENM records, capital at risk, and site-level reconciliation status. Be concise and data-driven."
  orchestration: "Use the reconciliation_analyst tool for all data questions about discrepancies, sites, severity, capital at risk, regions, and equipment status. The data contains discrepancy records across multiple sites."
  sample_questions:
    - question: "How many sites have serial number mismatches?"
    - question: "What is the total capital at risk?"
    - question: "Show me HIGH severity discrepancies"
    - question: "Which sites have the most discrepancies?"
    - question: "Break down discrepancies by type and severity"
tools:
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "reconciliation_analyst"
      description: "Query equipment reconciliation data including discrepancies between ENM physical inventory and BOM system. Contains discrepancy types (SERIAL_MISMATCH, PRODUCT_MISMATCH, NO_ENM_MATCH), severity levels (HIGH, MEDIUM), capital at risk estimates, site details, ENM regions, and recommended actions."
tool_resources:
  reconciliation_analyst:
    semantic_view: "EQUIPMENT_RECON_DEMO.RECONCILED.RECONCILIATION_SEMANTIC_VIEW"
    execution_environment:
      type: "warehouse"
      warehouse: "EQUIPMENT_RECON_WH"
$$;

-- =============================================================================
-- Streamlit App (deployed from GitHub via Git Repository integration)
-- =============================================================================

-- Git repository pointing to the public demo repo
CREATE OR REPLACE GIT REPOSITORY RECONCILED.DEMO_REPO
  API_INTEGRATION = github_api_integration
  ORIGIN = 'https://github.com/sfc-gh-nlamberth/telco-equipment-reconciliation.git';

CREATE OR REPLACE PROCEDURE RECONCILED.DEPLOY_STREAMLIT()
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'Deploy the Streamlit app from GitHub repository'
EXECUTE AS CALLER
AS
$$
BEGIN
    -- Fetch latest from GitHub
    ALTER GIT REPOSITORY RECONCILED.DEMO_REPO FETCH;

    -- Create the Streamlit app directly from the git repo
    CREATE OR REPLACE STREAMLIT RECONCILED.EQUIPMENT_RECONCILIATION_APP
        FROM @RECONCILED.DEMO_REPO/branches/main/streamlit_app/
        MAIN_FILE = 'streamlit_app.py'
        QUERY_WAREHOUSE = EQUIPMENT_RECON_WH
        TITLE = 'Equipment Reconciliation'
        COMMENT = 'Equipment reconciliation dashboard - ENM vs BOM discrepancy analysis';

    -- Initialize the app
    ALTER STREAMLIT RECONCILED.EQUIPMENT_RECONCILIATION_APP ADD LIVE VERSION FROM LAST;

    RETURN 'Streamlit app deployed successfully. Open it from Data Products > Streamlit in Snowsight.';
END;
$$;

-- =============================================================================
-- Grant access to future objects
-- =============================================================================

GRANT SELECT ON ALL TABLES IN SCHEMA EQUIPMENT_RECON_DEMO.RAW TO ROLE EQUIPMENT_RECON_ROLE;
GRANT SELECT ON ALL TABLES IN SCHEMA EQUIPMENT_RECON_DEMO.RECONCILED TO ROLE EQUIPMENT_RECON_ROLE;
GRANT SELECT ON ALL VIEWS IN SCHEMA EQUIPMENT_RECON_DEMO.RECONCILED TO ROLE EQUIPMENT_RECON_ROLE;

-- =============================================================================
-- Setup complete! Now run deploy.sql to generate data and deploy the Streamlit app.
-- =============================================================================
