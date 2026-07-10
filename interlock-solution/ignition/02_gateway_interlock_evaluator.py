# =============================================================================
# SAP-MII project - Gateway Timer Script:  "InterlockEvaluator"
# Suggested rate: 5000 ms, dedicated thread.
#
# The ONLY writer of INTERLOCK_STATUS.  Fail-safe by construction:
#   - a head with no assignment row has no row to unlock -> UI reads LOCKED
#   - any exception, bad tag quality, or failed condition -> LOCKED
#   - there is no override path; only a passing evaluation unlocks
#
# Unlock requires ALL of:
#   1. MATERIAL_VERIFIED : tblBatchManagement.IS_VERIFIED = 1
#                          (set only by DPHF-MaterialVerification scan-verify)
#   2. TYPE_MATCH        : vessel type == filler-head container type
#                          (Tote -> Tote head, Super sack -> Super-sack head)
#   3. TAG_MATCH         : the head's live PLC materialNumber tag equals the
#                          verified material ("correct material went into the
#                          correct filler head, based on the tag")
# =============================================================================

logger = system.util.getLogger("InterlockEvaluator")

def normalise(mat):
	return str(mat or '').strip().lstrip('0')

def mirrorToTags(row, status, message):
	"""Mirror per-head state to [default]Interlock/Heads/<WC>/<Head>/ so
	Perspective bindings react instantly and survive DB slowness."""
	base = '[default]Interlock/Heads/%s/%s/' % (row['WORK_CENTER'], row['DEVICE_NAME'])
	system.tag.writeBlocking(
		[base + 'Status', base + 'PONumber', base + 'MaterialNumber',
		 base + 'VesselType', base + 'Message', base + 'LastEvaluated'],
		[status, row['PO_NUMBER'], row['MATERIAL_NUMBER'],
		 row['VESSEL_TYPE'], message, system.date.now()]
	)

rows = system.db.runNamedQuery("Interlock/GetRowsToEvaluate", {})

for r in system.dataset.toPyDataSet(rows):
	row = dict(zip(rows.getColumnNames(), [r[c] for c in rows.getColumnNames()]))
	try:
		# -- Condition 1: material verified in Material-Verification --------
		materialVerified = int(row['MATERIAL_VERIFIED'] or 0) == 1

		# -- Condition 2: container type matches -----------------------------
		typeMatch = (str(row['VESSEL_TYPE'] or '').upper()
		             == str(row['DEVICE_TYPE'] or '').upper()
		             and row['VESSEL_TYPE'] is not None)

		# -- Condition 3: live PLC tag on the head holds the same material --
		tagMatch = False
		tagDetail = 'no head tag path configured'
		if row['HEAD_TAG_PATH']:
			qv = system.tag.readBlocking([row['HEAD_TAG_PATH'] + '/materialNumber'])[0]
			if qv.quality.isGood():
				plcMat  = normalise(qv.value)
				tagMatch = plcMat != '' and plcMat == normalise(row['MATERIAL_NUMBER'])
				tagDetail = 'PLC=%s expected=%s' % (plcMat, normalise(row['MATERIAL_NUMBER']))
			else:
				tagDetail = 'bad tag quality: %s' % qv.quality   # fail-safe: stays False

		newStatus = 'UNLOCKED' if (materialVerified and typeMatch and tagMatch) else 'LOCKED'
		message = 'verified=%s typeMatch=%s tagMatch=%s (%s)' % (
			materialVerified, typeMatch, tagMatch, tagDetail)

		system.db.runNamedQuery("Interlock/UpdateEvaluation", {
			"id": row['ID'],
			"materialVerified": 1 if materialVerified else 0,
			"typeMatch": 1 if typeMatch else 0,
			"tagMatch": 1 if tagMatch else 0,
			"status": newStatus,
			"message": message,
		})
		mirrorToTags(row, newStatus, message)

		# Log + alert only on state transitions (incl. UNLOCKED -> LOCKED,
		# e.g. the PLC tag changed to a different material mid-run)
		if newStatus != row['INTERLOCK_STATUS']:
			system.db.runNamedQuery("Interlock/InsertLog", {
				"interlockId": row['ID'],
				"oldStatus": row['INTERLOCK_STATUS'],
				"newStatus": newStatus,
				"reason": message,
				"changedBy": "GATEWAY_EVALUATOR",
			})
			if newStatus == 'LOCKED':
				logger.warn("RE-LOCKED head %s for PO %s: %s"
				            % (row['DEVICE_NAME'], row['PO_NUMBER'], message))

	except Exception, e:
		# Fail-safe: on any error force LOCKED rather than leaving stale UNLOCKED
		logger.error("Evaluator error on interlock ID %s: %s" % (row.get('ID'), e))
		try:
			system.db.runNamedQuery("Interlock/UpdateEvaluation", {
				"id": row['ID'], "materialVerified": 0, "typeMatch": 0,
				"tagMatch": 0, "status": 'LOCKED',
				"message": 'evaluator error: %s' % e})
			mirrorToTags(row, 'LOCKED', 'evaluator error')
		except Exception:
			pass
