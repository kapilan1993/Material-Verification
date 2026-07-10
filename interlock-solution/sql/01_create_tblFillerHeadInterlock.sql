-- =============================================================================
-- Interlock between DPHF-MaterialVerification and SAP-MII (IGNPEDB)
-- One row per (Process Order, Material, Filler Head) assignment.
-- Fail-safe: rows are created LOCKED and only the evaluator may unlock them.
-- =============================================================================

CREATE TABLE dbo.tblFillerHeadInterlock (
    ID                  INT IDENTITY(1,1)  PRIMARY KEY,
    PO_NUMBER           NVARCHAR(20)       NOT NULL,
    MATERIAL_NUMBER     NVARCHAR(20)       NOT NULL,
    BATCH_NUMBER        NVARCHAR(20)       NULL,
    WORK_CENTER         NVARCHAR(20)       NOT NULL,

    -- What was verified in Material-Verification
    VESSEL_ID           NVARCHAR(20)       NULL,          -- tote no / 'N/A' for label scan
    VESSEL_TYPE         NVARCHAR(12)       NOT NULL,      -- 'TOTE' | 'SUPER_SACK'

    -- Where it must go (explicit operator assignment in SAP-MII)
    DEVICE_ID           INT                NULL,          -- FK -> tblDeviceMaster.ID
    DEVICE_NAME         NVARCHAR(50)       NULL,          -- filler head name
    DEVICE_TYPE         NVARCHAR(12)       NULL,          -- head type: 'TOTE' | 'SUPER_SACK'
    HEAD_TAG_PATH       NVARCHAR(255)      NULL,          -- Ignition tag path of FillerHead UDT

    -- Interlock evaluation results (written ONLY by the gateway evaluator)
    MATERIAL_VERIFIED   BIT                NOT NULL DEFAULT 0,  -- tblBatchManagement.IS_VERIFIED
    TYPE_MATCH          BIT                NOT NULL DEFAULT 0,  -- VESSEL_TYPE == DEVICE_TYPE
    TAG_MATCH           BIT                NOT NULL DEFAULT 0,  -- PLC FillerHead.materialNumber == MATERIAL_NUMBER
    INTERLOCK_STATUS    NVARCHAR(10)       NOT NULL DEFAULT 'LOCKED',  -- 'LOCKED' | 'UNLOCKED'

    -- Audit
    ASSIGNED_BY         NVARCHAR(50)       NULL,
    ASSIGNED_AT         DATETIME           NULL,
    LAST_EVALUATED_AT   DATETIME           NULL,
    LAST_EVAL_MESSAGE   NVARCHAR(500)      NULL,
    IS_DELETED          BIT                NOT NULL DEFAULT 0,

    CONSTRAINT CK_Interlock_Status  CHECK (INTERLOCK_STATUS IN ('LOCKED','UNLOCKED')),
    CONSTRAINT CK_Vessel_Type       CHECK (VESSEL_TYPE IN ('TOTE','SUPER_SACK')),
    CONSTRAINT UQ_PO_Mat_Head       UNIQUE (PO_NUMBER, MATERIAL_NUMBER, DEVICE_NAME)
);

CREATE INDEX IX_Interlock_PO_WC ON dbo.tblFillerHeadInterlock (PO_NUMBER, WORK_CENTER)
    WHERE IS_DELETED = 0;

-- Audit trail of every state transition (who/what/why)
CREATE TABLE dbo.tblFillerHeadInterlockLog (
    ID                INT IDENTITY(1,1) PRIMARY KEY,
    INTERLOCK_ID      INT           NOT NULL,
    OLD_STATUS        NVARCHAR(10)  NULL,
    NEW_STATUS        NVARCHAR(10)  NOT NULL,
    REASON            NVARCHAR(500) NULL,
    CHANGED_BY        NVARCHAR(50)  NULL,     -- user id or 'GATEWAY_EVALUATOR'
    CHANGED_AT        DATETIME      NOT NULL DEFAULT GETDATE()
);

-- Vessel type on the verification side: extend the existing log so every
-- verification records HOW the material arrived (Tote vs Super sack).
ALTER TABLE dbo.MatVerificationLogs ADD VESSEL_TYPE NVARCHAR(12) NULL;

-- Head "container type" on the device side. Skip if tblDeviceMaster.[type]
-- already distinguishes Tote vs Super-sack heads - then map it in the queries.
ALTER TABLE dbo.tblDeviceMaster ADD CONTAINER_TYPE NVARCHAR(12) NULL; -- 'TOTE' | 'SUPER_SACK'
