-- Named query: Interlock/AssignHead   (SAP-MII project)
-- Operator explicitly assigns a verified vessel's material to a filler head.
-- Row is (re)created LOCKED; the gateway evaluator is the only thing that unlocks.
-- Params: poNumber, materialNumber, batchNumber, workCenter, vesselId,
--         vesselType, deviceName, headTagPath, userId
MERGE dbo.tblFillerHeadInterlock AS tgt
USING (SELECT :poNumber AS PO, :materialNumber AS MAT, :deviceName AS DEV) AS src
   ON tgt.PO_NUMBER = src.PO AND tgt.MATERIAL_NUMBER = src.MAT AND tgt.DEVICE_NAME = src.DEV
WHEN MATCHED THEN UPDATE SET
    BATCH_NUMBER      = :batchNumber,
    WORK_CENTER       = :workCenter,
    VESSEL_ID         = :vesselId,
    VESSEL_TYPE       = :vesselType,
    DEVICE_ID         = (SELECT TOP 1 ID FROM dbo.tblDeviceMaster
                          WHERE NAME = :deviceName AND IsDeleted = 0),
    DEVICE_TYPE       = (SELECT TOP 1 COALESCE(CONTAINER_TYPE, [type]) FROM dbo.tblDeviceMaster
                          WHERE NAME = :deviceName AND IsDeleted = 0),
    HEAD_TAG_PATH     = :headTagPath,
    INTERLOCK_STATUS  = 'LOCKED',            -- re-assignment always re-locks
    MATERIAL_VERIFIED = 0, TYPE_MATCH = 0, TAG_MATCH = 0,
    ASSIGNED_BY       = :userId,
    ASSIGNED_AT       = GETDATE(),
    IS_DELETED        = 0
WHEN NOT MATCHED THEN INSERT
    (PO_NUMBER, MATERIAL_NUMBER, BATCH_NUMBER, WORK_CENTER, VESSEL_ID, VESSEL_TYPE,
     DEVICE_ID, DEVICE_TYPE, DEVICE_NAME, HEAD_TAG_PATH, INTERLOCK_STATUS,
     ASSIGNED_BY, ASSIGNED_AT)
    VALUES
    (:poNumber, :materialNumber, :batchNumber, :workCenter, :vesselId, :vesselType,
     (SELECT TOP 1 ID FROM dbo.tblDeviceMaster WHERE NAME = :deviceName AND IsDeleted = 0),
     (SELECT TOP 1 COALESCE(CONTAINER_TYPE, [type]) FROM dbo.tblDeviceMaster WHERE NAME = :deviceName AND IsDeleted = 0),
     :deviceName, :headTagPath, 'LOCKED', :userId, GETDATE());
