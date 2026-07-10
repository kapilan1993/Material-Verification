# =============================================================================
# SAP-MII project - UI hooks (soft enforcement)
# =============================================================================

# -----------------------------------------------------------------------------
# A) Assignment action - OperationalScenario / head-selection view.
#    Dropdown is populated by Interlock/GetHeadsForAssignment, which already
#    filters heads to the vessel's container type, so a Tote can never be
#    assigned to a Super-sack head in the first place.
# -----------------------------------------------------------------------------
def onAssignHeadClicked(self):
	# Vessel info arrives via the tag mirror written by Material-Verification
	base = '[default]Interlock/Verified/'
	vals = system.tag.readBlocking([base + 'PONumber', base + 'MaterialNumber',
	                                base + 'BatchNumber', base + 'VesselId',
	                                base + 'VesselType'])
	po, material, batch, vesselId, vesselType = [v.value for v in vals]

	head = self.getSibling("HeadDropdown").props.value          # device NAME
	headTagPath = self.getSibling("HeadDropdown").props.selectedTagPath

	if not po or not material:
		system.perspective.openPopup("NoVerifiedVessel", "Popup/Error",
			params={"message": "No verified vessel found. Verify the material "
			                   "in Material-Verification first."})
		return

	system.db.runNamedQuery("Interlock/AssignHead", {
		"poNumber": po, "materialNumber": material, "batchNumber": batch,
		"workCenter": self.session.custom.workCenter,
		"vesselId": vesselId, "vesselType": vesselType,
		"deviceName": head, "headTagPath": headTagPath,
		"userId": self.session.props.auth.user.id,
	})
	# Row is created LOCKED; the gateway evaluator unlocks it within one cycle
	# once IS_VERIFIED, type and the live PLC tag all agree.


# -----------------------------------------------------------------------------
# B) Status gate - POExecution view.
#    Bind the enabled-state of every status-changing control (Start Phase,
#    Production Report, Goods Issue post, head Start) to the interlock.
#
#    Property binding (expression) on e.g. StartButton.props.enabled,
#    reacting in real time via the mirrored tag:
#
#      {[default]Interlock/Heads/{session.custom.workCenter}/{view.params.headName}/Status} = "UNLOCKED"
#
#    Belt-and-braces: re-check the DB at the moment of action, so a stale tag
#    can never let a status change through.
# -----------------------------------------------------------------------------
def onStatusChangeClicked(self):
	po = self.session.custom.selectedPO
	unlocked = system.db.runNamedQuery("Interlock/CheckPOFullyUnlocked",
	                                   {"poNumber": po})[0][0]
	if unlocked != 1:
		system.perspective.openPopup("InterlockActive", "Popup/Error", params={
			"message": "### Interlock Active\n\nPO %s cannot change status: one "
			           "or more filler heads have unverified material.\n\n"
			           "Verify each Tote / Super sack in Material-Verification "
			           "and confirm it is loaded on its assigned head." % po})
		return

	proceedWithStatusChange(self)   # existing POExecution status logic


# -----------------------------------------------------------------------------
# C) Head status card - visual state on the filler-head display.
#    Bind card background/badge to the same Status tag:
#      LOCKED   -> red    "INTERLOCKED - material not verified"
#      UNLOCKED -> green  "Verified: <material> (<vessel type>)"
#    The Message tag explains exactly which condition failed
#    (verified / typeMatch / tagMatch) for operator troubleshooting.
# -----------------------------------------------------------------------------
