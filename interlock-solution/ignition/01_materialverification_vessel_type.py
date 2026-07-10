# =============================================================================
# DPHF-MaterialVerification changes
# =============================================================================
#
# 1) New session custom property:  session.custom.VesselType  ('' | 'TOTE' | 'SUPER_SACK')
#    Add it in Perspective session props alongside VesselId / VesselMaterialNumber.
#
# 2) Session key-handler scripts: each scan handler already knows what kind of
#    vessel it decoded, so it just stamps the type.
#
#    In the TOTE handlers (1/2/3/4-digit tote regexes), add:
#        page.session.custom.VesselType = 'TOTE'
#
#    In the GS1 material-label handlers (17-digit, 38-digit, 36-digit '240...'
#    and '(240)...(10)...') - these are the Super-sack labels - add:
#        page.session.custom.VesselType = 'SUPER_SACK'
#
# 3) MaterialValidationWithLot "Verify" button: inside the SUCCESS branch
#    (right after UpdateBatchTable sets IS_VERIFIED = 1), publish the result to
#    the interlock layer.  DB write stays authoritative; the tag mirror gives
#    SAP-MII a real-time signal without polling.

def publishVerificationResult(self):
	po        = self.session.custom.PONumber
	material  = self.session.custom.ExpectedMaterialNumber
	vesselId  = self.session.custom.VesselId
	vType     = self.session.custom.VesselType or 'TOTE'
	lot       = self.session.custom.VesselLotNumber

	# --- Tag mirror (real-time hand-off to SAP-MII) ------------------------
	# Memory tags created once under [default]Interlock/Verified/ - see
	# tags/interlock-tags.json.  Overwritten on every successful verification.
	base = '[default]Interlock/Verified/'
	system.tag.writeBlocking(
		[base + 'PONumber', base + 'MaterialNumber', base + 'BatchNumber',
		 base + 'VesselId', base + 'VesselType',     base + 'VerifiedAt'],
		[po, material, lot, vesselId, vType, system.date.now()]
	)

	# --- DB audit: record the vessel type with the verification ------------
	# Extend the existing AddMatVerificationLog named query with the new
	# :vesselType parameter (column added by 01_create_tblFillerHeadInterlock.sql):
	#   INSERT INTO MatVerificationLogs (..., VESSEL_TYPE)
	#   VALUES (..., :vesselType)
	system.db.runNamedQuery("AddMatVerificationLog", {
		"processOrder":           po,
		"materialNumber":         self.session.custom.VesselMaterialNumber,
		"expectedMaterialNumber": material,
		"userId":                 self.session.props.auth.user.id,
		"vesselId":               vesselId,
		"vesselType":             vType,
		"message":                "User Verified Material (%s)" % vType,
	})
