-- Named query: Interlock/GetHeadsForAssignment   (SAP-MII project, assignment view)
-- Only offer heads of the SAME container type as the verified vessel -
-- a Tote can only be assigned to a Tote head, a Super sack to a Super-sack head.
-- Params: wc, vesselType
SELECT dm.ID, dm.NAME, COALESCE(dm.CONTAINER_TYPE, dm.[type]) AS CONTAINER_TYPE
FROM dbo.tblDeviceMaster dm
WHERE dm.WC_ID = (SELECT ID FROM dbo.tblWorkCenterMaster WHERE RESOURCE_NAME = :wc)
  AND dm.IsDeleted = 0
  AND COALESCE(dm.CONTAINER_TYPE, dm.[type]) = :vesselType
