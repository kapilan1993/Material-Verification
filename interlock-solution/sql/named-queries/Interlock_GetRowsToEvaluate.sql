-- Named query: Interlock/GetRowsToEvaluate   (SAP-MII project, gateway evaluator)
-- Everything the evaluator needs, joined with the live IS_VERIFIED flag
-- from tblBatchManagement (written by DPHF-MaterialVerification).
SELECT
    i.ID,
    i.PO_NUMBER,
    i.MATERIAL_NUMBER,
    i.WORK_CENTER,
    i.VESSEL_TYPE,
    i.DEVICE_TYPE,
    i.DEVICE_NAME,
    i.HEAD_TAG_PATH,
    i.INTERLOCK_STATUS,
    ISNULL(bm.IS_VERIFIED, 0) AS MATERIAL_VERIFIED
FROM dbo.tblFillerHeadInterlock i
LEFT JOIN dbo.tblBatchManagement bm
       ON bm.PROCESS_ORDER   = i.PO_NUMBER
      AND bm.MATERIAL_NUMBER = i.MATERIAL_NUMBER
      AND bm.IS_DELETED      = 0
WHERE i.IS_DELETED = 0
