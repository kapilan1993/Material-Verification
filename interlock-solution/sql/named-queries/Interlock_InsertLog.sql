-- Named query: Interlock/InsertLog   (both projects)
-- Params: interlockId, oldStatus, newStatus, reason, changedBy
INSERT INTO dbo.tblFillerHeadInterlockLog
    (INTERLOCK_ID, OLD_STATUS, NEW_STATUS, REASON, CHANGED_BY)
VALUES
    (:interlockId, :oldStatus, :newStatus, :reason, :changedBy)
