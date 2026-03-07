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
		errs.append("duplicate card_id " + cid + " in " + loc + " and " + String(seen[cid]))
	else:
		seen[cid] = loc

static func validate(state: GameState, registry: CardRegistry, rules: RulesConfig) -> Dictionary:
	var errs: Array[String] = []
	
	# --- basic fields ---
	if state.num_players <= 0:
		errs.append("num_players must be > 0")
	
	if state.turn_player < 0 or state.turn_player >= state.num_players:
		errs.append("turn_player out of range")
	
	if state.phase != "DRAW" and state.phase != "PLAY":
		errs.append("phase must be DRAW or PLAY")
	
	# must-play arrays sized correctly
	if state.must_play_discard_target.size() != state.num_players:
		errs.append("must_play_discard_target wrong size")
	if state.must_play_discard_pending.size() != state.num_players:
		errs.append("must_play_discard_pending wrong size")
	
	# --- card uniqueness + existence ---
	var seen: Dictionary = {} # card_id -> location string
	
	# stock
	for i in range(state.stock.size()):
		_check_card(String(state.stock[i]), "stock[" + str(i) + "]", seen, errs, registry)
	
	# discard
	for i in range(state.discard.size()):
		_check_card(String(state.discard[i]), "discard[" + str(i) + "]", seen, errs, registry)
	
	# hands
	if state.hands.size() != state.num_players:
		errs.append("hands wrong size")
	else:
		for p in range(state.num_players):
			var h: Array = state.hands[p]
			for i in range(h.size()):
				_check_card(String(h[i]), "hands[" + str(p) + "][" + str(i) + "]", seen, errs, registry)
	
	# melds + contrib
	for mi in range(state.melds.size()):
		var meld: Dictionary = state.melds[mi]
		if not meld.has("type"):
			errs.append("meld[" + str(mi) + "] missing type")
			continue
		if not meld.has("cards"):
			errs.append("meld[" + str(mi) + "] missing cards")
			continue
		
		var mtype = String(meld["type"])
		var cards: Array = meld["cards"]
		
		var contrib_ok = meld.has("contrib") and typeof(meld["contrib"]) == TYPE_DICTIONARY
		if not contrib_ok:
			errs.append("meld[" + str(mi) + "] missing contrib dict")
		
		for ci in range(cards.size()):
			var cid = String(cards[ci])
			_check_card(cid, "melds[" + str(mi) + "].cards[" + str(ci) + "]", seen, errs, registry)
			if contrib_ok and not meld["contrib"].has(cid):
				errs.append("meld[" + str(mi) + "] contrib missing card " + cid)
		
		if mtype == "SET":
			if not meld.has("rank"):
				errs.append("meld[" + str(mi) + "] SET missing rank")
			else:
				var set_rank = int(meld["rank"])
				var suits_seen: Dictionary = {}
				for cid_any in cards:
					var c = registry.get_card(String(cid_any))
					if not c.is_empty() and int(c["rank"]) != set_rank:
						errs.append("meld[" + str(mi) + "] SET rank mismatch")
					if not rules.allow_duplicate_suits_in_set and not c.is_empty():
						var s = String(c["suit"])
						if suits_seen.has(s):
							errs.append("meld[" + str(mi) + "] SET duplicate suit not allowed")
						suits_seen[s] = true
		
		elif mtype == "RUN":
			if not meld.has("suit"):
				errs.append("meld[" + str(mi) + "] RUN missing suit")
			else:
				var suit = String(meld["suit"])
				for cid_any in cards:
					var c = registry.get_card(String(cid_any))
					if not c.is_empty() and String(c["suit"]) != suit:
						errs.append("meld[" + str(mi) + "] RUN suit mismatch")
			
			var chk = MeldRules.build_run_meld(cards, registry, rules.allow_wrap_runs)
			if not bool(chk.get("ok", false)):
				errs.append("meld[" + str(mi) + "] RUN invalid: " + String(chk.get("reason", "")))
		
		else:
			errs.append("meld[" + str(mi) + "] unknown type " + mtype)
	
	# --- must-play consistency ---
	for p in range(state.num_players):
		if bool(state.must_play_discard_pending[p]):
			var t = String(state.must_play_discard_target[p])
			if t == "":
				errs.append("must_play pending but target empty for player " + str(p))
			elif state.hands.size() == state.num_players and not state.hands[p].has(t):
				errs.append("must_play target not in player hand for player " + str(p))
	
	# --- end-of-hand consistency ---
	if state.hand_over:
		if state.hand_end_reason == "":
			errs.append("hand_over true but hand_end_reason empty")
		if not state.hand_scored:
			errs.append("hand_over true but hand_scored false")

	return {"ok": errs.is_empty(), "errors": errs}
