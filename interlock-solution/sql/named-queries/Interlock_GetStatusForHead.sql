-- Named query: Interlock/GetStatusForHead   (SAP-MII project, UI bindings)
-- Fail-safe: no row for this head+PO means LOCKED.
-- Params: poNumber, deviceName
SELECT TOP 1 ISNULL(INTERLOCK_STATUS, 'LOCKED') AS INTERLOCK_STATUS,
       MATERIAL_VERIFIED, TYPE_MATCH, TAG_MATCH, LAST_EVAL_MESSAGE
FROM dbo.tblFillerHeadInterlock
WHERE PO_NUMBER = :poNumber AND DEVICE_NAME = :deviceName AND IS_DELETED = 0
