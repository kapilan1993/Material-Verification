-- Named query: Interlock/UpdateEvaluation   (SAP-MII project, gateway evaluator)
-- Params: id, materialVerified, typeMatch, tagMatch, status, message
UPDATE dbo.tblFillerHeadInterlock
SET MATERIAL_VERIFIED = :materialVerified,
    TYPE_MATCH        = :typeMatch,
    TAG_MATCH         = :tagMatch,
    INTERLOCK_STATUS  = :status,
    LAST_EVALUATED_AT = GETDATE(),
    LAST_EVAL_MESSAGE = :message
WHERE ID = :id
