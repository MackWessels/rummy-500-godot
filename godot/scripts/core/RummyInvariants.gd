extends RefCounted
class_name RummyInvariants

static func _check_card(cid: String, loc: String, seen: Dictionary, errs: Array[String], registry: CardRegistry) -> void:
	if cid == "":
		errs.append("empty card_id in " + loc)
		return
	if registry.get_card(cid).is_empty():
		errs.append("unknown card_id " + cid + " in " + loc)
		return
	if seen.has(cid):
		errs.append("duplicate card_id " + cid + " in " + loc + " and " + str(seen[cid]))
	else:
		seen[cid] = loc

static func _meld_card_id(raw_card) -> String:
	if raw_card is Dictionary:
		return str(raw_card.get("card_id", raw_card.get("id", "")))
	return str(raw_card)

static func _meld_card_played_by(raw_card) -> int:
	if raw_card is Dictionary:
		return int(raw_card.get("played_by", raw_card.get("owner", -1)))
	return -1

static func _meld_card_ids(cards: Array) -> Array:
	var out: Array = []
	for raw_card in cards:
		out.append(_meld_card_id(raw_card))
	return out

static func validate(state: GameState, registry: CardRegistry, rules: RulesConfig) -> Dictionary:
	var errs: Array[String] = []

	if state.num_players <= 0:
		errs.append("num_players must be > 0")

	if state.turn_player < 0 or state.turn_player >= state.num_players:
		errs.append("turn_player out of range")

	if state.phase != "DRAW" and state.phase != "PLAY":
		errs.append("phase must be DRAW or PLAY")

	if state.must_play_discard_target.size() != state.num_players:
		errs.append("must_play_discard_target wrong size")
	if state.must_play_discard_pending.size() != state.num_players:
		errs.append("must_play_discard_pending wrong size")

	if state.hands.size() != state.num_players:
		errs.append("hands wrong size")

	if state.hand_scored:
		if state.hand_points_table.size() != state.num_players:
			errs.append("hand_points_table wrong size")
		if state.hand_points_deadwood.size() != state.num_players:
			errs.append("hand_points_deadwood wrong size")
		if state.hand_points_net.size() != state.num_players:
			errs.append("hand_points_net wrong size")

	if state.next_meld_id < 1:
		errs.append("next_meld_id must be >= 1")

	var seen: Dictionary = {}

	for i in range(state.stock.size()):
		_check_card(str(state.stock[i]), "stock[" + str(i) + "]", seen, errs, registry)

	for i in range(state.discard.size()):
		_check_card(str(state.discard[i]), "discard[" + str(i) + "]", seen, errs, registry)

	if state.hands.size() == state.num_players:
		for p in range(state.num_players):
			var h: Array = state.hands[p]
			for i in range(h.size()):
				_check_card(str(h[i]), "hands[" + str(p) + "][" + str(i) + "]", seen, errs, registry)

	var seen_meld_ids: Dictionary = {}

	for mi in range(state.melds.size()):
		var meld_any = state.melds[mi]
		if not (meld_any is Dictionary):
			errs.append("meld[" + str(mi) + "] is not a dictionary")
			continue

		var meld: Dictionary = meld_any

		if not meld.has("id"):
			errs.append("meld[" + str(mi) + "] missing id")
		else:
			var meld_id = int(meld["id"])
			if seen_meld_ids.has(meld_id):
				errs.append("duplicate meld id " + str(meld_id))
			else:
				seen_meld_ids[meld_id] = true

		if not meld.has("type"):
			errs.append("meld[" + str(mi) + "] missing type")
			continue
		if not meld.has("cards"):
			errs.append("meld[" + str(mi) + "] missing cards")
			continue
		if typeof(meld["cards"]) != TYPE_ARRAY:
			errs.append("meld[" + str(mi) + "] cards is not an array")
			continue

		var mtype = str(meld["type"])
		var cards: Array = meld["cards"]
		var card_ids: Array = []
		var contrib_ok = meld.has("contrib") and typeof(meld["contrib"]) == TYPE_DICTIONARY

		if cards.size() < 3:
			errs.append("meld[" + str(mi) + "] has fewer than 3 cards")

		for ci in range(cards.size()):
			var raw_card = cards[ci]
			var cid = _meld_card_id(raw_card)
			card_ids.append(cid)

			_check_card(cid, "melds[" + str(mi) + "].cards[" + str(ci) + "]", seen, errs, registry)

			if raw_card is Dictionary:
				if not raw_card.has("card_id") and not raw_card.has("id"):
					errs.append("meld[" + str(mi) + "] card[" + str(ci) + "] missing card_id")
				var played_by = _meld_card_played_by(raw_card)
				if played_by < 0 or played_by >= state.num_players:
					errs.append("meld[" + str(mi) + "] card[" + str(ci) + "] played_by out of range")
				if contrib_ok and cid != "" and meld["contrib"].has(cid):
					var contrib_player = int(meld["contrib"][cid])
					if contrib_player != played_by:
						errs.append("meld[" + str(mi) + "] contrib mismatch for " + cid)
				elif contrib_ok and cid != "" and not meld["contrib"].has(cid):
					errs.append("meld[" + str(mi) + "] contrib missing card " + cid)
			else:
				if contrib_ok:
					if cid != "" and not meld["contrib"].has(cid):
						errs.append("meld[" + str(mi) + "] contrib missing legacy card " + cid)
					elif cid != "":
						var legacy_player = int(meld["contrib"][cid])
						if legacy_player < 0 or legacy_player >= state.num_players:
							errs.append("meld[" + str(mi) + "] contrib out of range for " + cid)
				else:
					errs.append("meld[" + str(mi) + "] uses legacy string cards without contrib")

		if mtype == "SET":
			if not meld.has("rank"):
				errs.append("meld[" + str(mi) + "] SET missing rank")
			else:
				var set_rank = int(meld["rank"])
				var suits_seen: Dictionary = {}

				for cid_any in card_ids:
					var cid = str(cid_any)
					var c = registry.get_card(cid)
					if c.is_empty():
						continue

					if int(c["rank"]) != set_rank:
						errs.append("meld[" + str(mi) + "] SET rank mismatch")

					if not rules.allow_duplicate_suits_in_set:
						var s = str(c["suit"])
						if suits_seen.has(s):
							errs.append("meld[" + str(mi) + "] SET duplicate suit not allowed")
						suits_seen[s] = true

		elif mtype == "RUN":
			if not meld.has("suit"):
				errs.append("meld[" + str(mi) + "] RUN missing suit")
			else:
				var suit = str(meld["suit"])
				for cid_any in card_ids:
					var cid = str(cid_any)
					var c = registry.get_card(cid)
					if not c.is_empty() and str(c["suit"]) != suit:
						errs.append("meld[" + str(mi) + "] RUN suit mismatch")

			var chk = MeldRules.build_run_meld(card_ids, registry, rules.allow_wrap_runs)
			if not bool(chk.get("ok", false)):
				errs.append("meld[" + str(mi) + "] RUN invalid: " + str(chk.get("reason", "")))
			else:
				var expected: Array = Array(chk.get("ordered_card_ids", []))
				if expected.size() == card_ids.size():
					for i in range(card_ids.size()):
						if str(card_ids[i]) != str(expected[i]):
							errs.append("meld[" + str(mi) + "] RUN cards stored out of logical order")
							break

		else:
			errs.append("meld[" + str(mi) + "] unknown type " + mtype)

	for meld_id_any in seen_meld_ids.keys():
		var meld_id = int(meld_id_any)
		if meld_id >= state.next_meld_id:
			errs.append("next_meld_id must be greater than all existing meld ids")
			break

	for p in range(state.num_players):
		if bool(state.must_play_discard_pending[p]):
			var t = str(state.must_play_discard_target[p])
			if t == "":
				errs.append("must_play pending but target empty for player " + str(p))
			elif state.hands.size() == state.num_players and not state.hands[p].has(t):
				errs.append("must_play target not in player hand for player " + str(p))
		else:
			if str(state.must_play_discard_target[p]) != "":
				errs.append("must_play target set but pending false for player " + str(p))

	if state.hand_over:
		if state.hand_end_reason == "":
			errs.append("hand_over true but hand_end_reason empty")
		if not state.hand_scored:
			errs.append("hand_over true but hand_scored false")
		if state.went_out_player != -1:
			if state.went_out_player < 0 or state.went_out_player >= state.num_players:
				errs.append("went_out_player out of range")
			elif state.hands.size() == state.num_players and not state.hands[state.went_out_player].is_empty():
				errs.append("went_out_player set but that hand is not empty")
	else:
		if state.hand_end_reason != "":
			errs.append("hand_over false but hand_end_reason not empty")

	return {"ok": errs.is_empty(), "errors": errs}
