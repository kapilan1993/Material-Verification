-- Named query: Interlock/CheckPOFullyUnlocked   (SAP-MII project)
-- Gate for PO status changes (start phase / production report / goods issue):
-- returns 1 only when the PO has at least one assignment and NONE are locked.
-- Params: poNumber
SELECT CASE
    WHEN COUNT(*) = 0 THEN 0                                        -- nothing assigned yet -> LOCKED
    WHEN SUM(CASE WHEN INTERLOCK_STATUS = 'UNLOCKED' THEN 1 ELSE 0 END) = COUNT(*) THEN 1
    ELSE 0
END AS PO_UNLOCKED
FROM dbo.tblFillerHeadInterlock
WHERE PO_NUMBER = :poNumber AND IS_DELETED = 0
