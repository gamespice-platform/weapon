class_name GSWeaponAttachments
extends RefCounted

## The attachment catalogue: every attachment a game offers, and the rules for what may go
## on which weapon.
##
## [b]Both machines must hold the same catalogue[/b], like the weapon catalogue. What
## travels is ids (or the packed [method encode] index into [method choices_for]), so two
## catalogues that differ decode the same bits into different attachments.
##
## Failure codes of [method validate_fitting], to branch on: [code]CODE_INVALID[/code] unknown
## attachment id, [code]CODE_CONFLICT[/code] the attachment or the mount is not that weapon's,
## [code]CODE_FORBIDDEN[/code] the attachment does not fit this weapon, [code]CODE_STATE[/code]
## the fitting is for another weapon.

const KIND := "attachment"

var _by_id: Dictionary = {}  ## StringName -> GSWeaponAttachment
var _layouts: Dictionary = {}  ## [id, slot, mounts, tags] -> [method _layout]'s entry
## [base def, its revision, fitting key] -> fitted copy, see [method apply]. [method add] and
## [method forget_fitted] drop them all.
var _fitted: Dictionary = {}


## Fields of an `attachment` profile; a pack ships these as data. Lists are comma-separated.
static func schema() -> Array:
	var f := GSProfileSet.field
	return [
		f.call("name", "string", ""),
		f.call("description", "string", ""),
		f.call("mount", "string", ""),
		f.call("item", "string", ""),
		f.call("model", "string", ""),
		f.call("fits_tags", "string", ""),
		f.call("fits_weapons", "string", ""),
		f.call("fits_slots", "string", ""),
		f.call("excludes_tags", "string", ""),
		f.call("blocks", "string", ""),
		f.call("tags_added", "string", ""),
		f.call("scale", "dict", {}),
		f.call("add", "dict", {}),
		f.call("params", "dict", {}),
	]


## Kind to schema, for GameSpice Core's `profile_check`.
static func profile_schemas() -> Dictionary:
	return {KIND: {"schema": schema()}}


static func make_set(addon: String, game: String, roots: PackedStringArray = PackedStringArray()) -> GSProfileSet:
	var s := GSProfileSet.create(addon, game, KIND, schema())
	s.roots = roots
	return s


## Adds every profile of [param profiles]; fails on the first that does not load or validate.
func load_set(profiles: GSProfileSet) -> GSResult:
	var n := 0
	for id in profiles.list_ids():
		var res := profiles.load_profile(id)
		if not res.ok:
			return res
		var d := (res.value as GSProfile).to_dictionary()
		var added := add(GSWeaponAttachment.from_flat(StringName(id), d.get("values", d)))
		if not added.ok:
			return added
		n += 1
	return GSResult.success(n)


func add(att: GSWeaponAttachment) -> GSResult:
	if att == null:
		return GSResult.fail(GSError.CODE_INVALID, "No attachment given.")
	var res := att.validate()
	if not res.ok:
		return res
	if _by_id.has(att.id):
		return GSResult.fail(
			GSError.CODE_CONFLICT, "Attachment %s is already in the catalogue." % String(att.id),
			String(att.id)
		)
	_by_id[att.id] = att
	_layouts.clear()
	_fitted.clear()
	return GSResult.success(att)


func get_attachment(id: StringName) -> GSWeaponAttachment:
	return _by_id.get(id, null)


## The attachment an inventory item grants, or null.
func for_item(item_id: StringName) -> GSWeaponAttachment:
	for id in ids():
		if (_by_id[id] as GSWeaponAttachment).item() == item_id:
			return _by_id[id]
	return null


## Every id, in text order.
func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: StringName in _by_id.keys():
		out.append(key)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


## Mount -> text-ordered ids that fit, for every mount of [param def] (possibly empty lists).
func choices_for(def: GSWeaponDef) -> Dictionary:
	var out: Dictionary = {}
	for m in def.mounts:
		out[m] = [] as Array[StringName]
	for id in ids():
		var att: GSWeaponAttachment = _by_id[id]
		if att.fits(def):
			(out[att.mount] as Array[StringName]).append(id)
	return out


func validate_fitting(def: GSWeaponDef, fitting: GSWeaponFitting) -> GSResult:
	if fitting.weapon_id != def.id:
		return GSResult.fail(
			GSError.CODE_STATE,
			"The fitting is for %s, not %s." % [String(fitting.weapon_id), String(def.id)]
		)
	for m in fitting.mounts():
		var id := fitting.attachment_on(m)
		var att: GSWeaponAttachment = _by_id.get(id, null)
		if att == null:
			return GSResult.fail(
				GSError.CODE_INVALID, "There is no attachment %s." % String(id), String(id)
			)
		if att.mount != m or not def.mounts.has(m):
			return GSResult.fail(
				GSError.CODE_CONFLICT,
				"%s cannot go on mount %s of %s." % [String(id), String(m), String(def.id)],
				String(id)
			)
		if not att.fits(def):
			return GSResult.fail(
				GSError.CODE_FORBIDDEN,
				"%s does not fit %s." % [String(id), String(def.id)], String(id)
			)
		for blocked in att.blocks:
			if fitting.attachment_on(blocked) != &"":
				return GSResult.fail(
					GSError.CODE_CONFLICT,
					"%s blocks mount %s." % [String(id), String(blocked)], String(id)
				)
	return GSResult.success(fitting)


## A copy of [param fitting] with everything illegal dropped. Never fails: a replicated code
## or a saved loadout from another version should degrade, not refuse.
func conform(def: GSWeaponDef, fitting: GSWeaponFitting) -> GSWeaponFitting:
	var out := GSWeaponFitting.make(def.id)
	for m in fitting.mounts():
		var id := fitting.attachment_on(m)
		var att: GSWeaponAttachment = _by_id.get(id, null)
		if att != null and att.mount == m and att.fits(def) and not _clashes(out, att):
			out.fit(m, id)
	return out


## Whether [param att] blocks a mount [param fitting] uses, or a fitted one blocks its mount.
func _clashes(fitting: GSWeaponFitting, att: GSWeaponAttachment) -> bool:
	for m in fitting.mounts():
		var other: GSWeaponAttachment = _by_id.get(fitting.attachment_on(m), null)
		if att.blocks.has(m) or (other != null and other.blocks.has(att.mount)):
			return true
	return false


## [param fitting] with [param id] put on [param mount], or taken off when it is already there or
## [param id] is empty. Whatever the new one clashes with comes off. Fails like [method validate_fitting].
func toggle(def: GSWeaponDef, fitting: GSWeaponFitting, mount: StringName, id: StringName) -> GSResult:
	var out := fitting.duplicate_fitting()
	if id == &"" or fitting.attachment_on(mount) == id:
		out.remove(mount)
		return GSResult.success(out)
	var att: GSWeaponAttachment = _by_id.get(id, null)
	if att != null:
		out.remove(mount)
		for m in out.mounts():
			var other: GSWeaponAttachment = _by_id.get(out.attachment_on(m), null)
			if att.blocks.has(m) or (other != null and other.blocks.has(mount)):
				out.remove(m)
	out.fit(mount, id)
	var res := validate_fitting(def, out)
	return res if not res.ok else GSResult.success(out)


## Field -> [before, after] for every number that differs between [param base] and [param fitted]
## (the definition, its tuning, and numeric params), in text order. For a menu's stat lines.
static func stat_delta(base: GSWeaponDef, fitted: GSWeaponDef) -> Dictionary:
	var out: Dictionary = {}
	var fields: Array[String] = []
	var before := _numbers(base)
	var after := _numbers(fitted)
	for k: String in after.keys():
		if not is_equal_approx(float(before.get(k, 0.0)), float(after[k])):
			fields.append(k)
	fields.sort()
	for k in fields:
		out[k] = [before.get(k, 0.0), after[k]]
	return out


static func _numbers(def: GSWeaponDef) -> Dictionary:
	var out: Dictionary = {}
	for candidate: Object in [def, def.tuning]:
		if candidate == null:
			continue
		for prop: Dictionary in candidate.get_property_list():
			# A leading underscore is a private cache (GSWeaponDef._modes_from_fire), never a stat: the attachments menu
			# showed "_modes_from_fire +100%" beside the Laser Sight.
			if int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 or str(prop["name"]).begins_with("_"):
				continue
			var v: Variant = candidate.get(StringName(prop["name"]))
			if v is int or v is float:
				out[str(prop["name"])] = v
	for k: Variant in def.params.keys():
		if def.params[k] is int or def.params[k] is float:
			out[GSWeaponAttachment.PARAMS_PREFIX + str(k)] = def.params[k]
	return out


## The definition with [param fitting] applied, as a separate definition so the shared one is never mutated; an empty
## fitting returns [param def] itself. Memoed per (definition, [member GSWeaponDef.revision], fitting) and shared by every
## holder: [b]read it, never edit it[/b]; touch a base definition edited in place (docs/attachments.md#the-fitted-copy).
func apply(def: GSWeaponDef, fitting: GSWeaponFitting) -> GSResult:
	var res := validate_fitting(def, fitting)
	if not res.ok:
		return res
	if fitting.is_empty():
		return GSResult.success(def)
	var key := [def, def.revision, fitting.key()]
	var hit: GSWeaponDef = _fitted.get(key, null)
	if hit != null:
		return GSResult.success(hit)
	var made := fit_fresh(def, fitting)
	if made.ok:
		_fitted[key] = made.value
	return made


## Drops every memoed fitted copy (see [method apply]), e.g. after an attachment was edited in place.
func forget_fitted() -> void:
	_fitted.clear()


## How many fitted copies [method apply] holds.
func fitted_count() -> int:
	return _fitted.size()


## [method apply] without the memo or the checks: always a new copy. For a check that a memoed
## copy still matches, or a caller that means to edit what it gets ([param fitting] must be valid).
func fit_fresh(def: GSWeaponDef, fitting: GSWeaponFitting) -> GSResult:
	var copy := def.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as GSWeaponDef
	for m in fitting.mounts():
		var applied := (_by_id[fitting.attachment_on(m)] as GSWeaponAttachment).apply_to(copy)
		if not applied.ok:
			return applied
	return GSResult.success(copy)


# --- Replication ------------------------------------------------------------

## Bits one mount needs: enough for 0 (none) to the number of choices.
static func _bits_for(choices: int) -> int:
	var bits := 0
	while (1 << bits) < choices + 1:
		bits += 1
	return bits


func _sorted_mounts(def: GSWeaponDef) -> Array[StringName]:
	var out: Array[StringName] = def.mounts.duplicate()
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


## The wire layout of [param def]: [code][mounts in text order, choice list per mount, bits per mount][/code], memoed per
## value of what [method GSWeaponAttachment.fits] reads (id, slot, mounts, tags); [method add] drops them all. A server
## pulls it twice a player a tick, and building it sorts every id (about 25 us a pull).
func _layout(def: GSWeaponDef) -> Array:
	var hit: Array = _layouts.get([def.id, def.slot, def.mounts, def.tags], [])
	if not hit.is_empty():
		return hit
	# Stored with copies: a key that changed under the dictionary would never be found again.
	var key := [def.id, def.slot, def.mounts.duplicate(), def.tags.duplicate()]
	var choices := choices_for(def)
	var mounts := _sorted_mounts(def)
	var lists: Array = []
	var bits := PackedInt32Array()
	for m in mounts:
		var list: Array = choices[m]
		lists.append(list)
		bits.append(_bits_for(list.size()))
	hit = [mounts, lists, bits]
	_layouts[key] = hit
	return hit


## Bits [method encode] uses for [param def]. Compare with [constant GSWeaponNetSync.FITTED_BITS].
func code_bits(def: GSWeaponDef) -> int:
	var total := 0
	for bits in (_layout(def)[2] as PackedInt32Array):
		total += bits
	return total


## The fitting as one integer: per mount of [member GSWeaponDef.mounts] in text order, the
## 1-based index in [method choices_for] (0 = none), each in just enough bits, first mount in
## the low bits. Anything that does not fit is encoded as none.
func encode(def: GSWeaponDef, fitting: GSWeaponFitting) -> int:
	var layout := _layout(def)
	var mounts: Array[StringName] = layout[0]
	var lists: Array = layout[1]
	var bits: PackedInt32Array = layout[2]
	var code := 0
	var shift := 0
	for i in mounts.size():
		var index := (lists[i] as Array).find(fitting.attachment_on(mounts[i])) + 1
		code |= index << shift
		shift += bits[i]
	return code


## The inverse of [method encode]. An index past the choices decodes as none.
func decode(def: GSWeaponDef, code: int) -> GSWeaponFitting:
	var layout := _layout(def)
	var mounts: Array[StringName] = layout[0]
	var lists: Array = layout[1]
	var bits: PackedInt32Array = layout[2]
	var out := GSWeaponFitting.make(def.id)
	var shift := 0
	for i in mounts.size():
		var list: Array = lists[i]
		var index := (code >> shift) & ((1 << bits[i]) - 1)
		shift += bits[i]
		if index >= 1 and index <= list.size():
			out.fit(mounts[i], list[index - 1])
	return out


func describe() -> Dictionary:
	return {"attachments": ids().map(func(i: StringName) -> String: return String(i))}
