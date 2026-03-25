extends RefCounted
class_name TablePresenter

static func build_snapshot(public_input: Dictionary, local_player: int = -1) -> Dictionary:
	var normalized := _normalize_public_input(public_input)
	var version := int(normalized["version"])
	var public_state: Dictionary = normalized["public_state"]

	var num_players := int(public_state.get("num_players", 0))
	var turn_player := int(public_state.get("turn_player", -1))
	var phase := str(public_state.get("phase", ""))
	var hand_over := bool(public_state.get("hand_over", false))
	var hand_end_reason := str(public_state.get("hand_end_reason", ""))
	var went_out_player := int(public_state.get("went_out_player", -1))
	var hand_scored := bool(public_state.get("hand_scored", false))

	var stock_count := int(public_state.get("stock_count", 0))
	var discard_cards_raw: Array = Array(public_state.get("discard", []))
	var hand_sizes_by_player: Array = Array(public_state.get("hand_sizes_by_player", []))

	var snapshot := {
		"version": version,
		"table": {
			"num_players": num_players,
			"local_player": local_player,
			"turn_player": turn_player,
			"phase": phase,
			"hand_over": hand_over,
			"hand_end_reason": hand_end_reason,
			"went_out_player": went_out_player,
			"hand_scored": hand_scored,
			"stock_count": stock_count,
			"discard_count": discard_cards_raw.size(),
			"discard_top": str(discard_cards_raw[-1]) if discard_cards_raw.size() > 0 else "",
			"selected_meld_id": -1,
			"selected_card_id": "",
			"selected_player_index": -1
		},
		"players": [],
		"melds": [],
		"discard": [],
		"card_index": {}
	}

	_build_player_records(snapshot, public_state, local_player, num_players, turn_player, hand_sizes_by_player)
	_build_discard_records(snapshot, discard_cards_raw)
	_build_meld_records(snapshot, public_state)

	return snapshot


# --------------------------------------------------
# Input normalization
# --------------------------------------------------

static func _normalize_public_input(public_input: Dictionary) -> Dictionary:
	if public_input.has("state_public"):
		return {
			"version": int(public_input.get("state_version", 0)),
			"public_state": Dictionary(public_input.get("state_public", {}))
		}

	return {
		"version": int(public_input.get("state_version", public_input.get("version", 0))),
		"public_state": public_input
	}


# --------------------------------------------------
# Player records
# --------------------------------------------------

static func _build_player_records(
	snapshot: Dictionary,
	public_state: Dictionary,
	local_player: int,
	num_players: int,
	turn_player: int,
	hand_sizes_by_player: Array
) -> void:
	var players: Array = snapshot["players"]

	for p in range(num_players):
		var hand_count := 0
		if p < hand_sizes_by_player.size():
			hand_count = int(hand_sizes_by_player[p])

		players.append({
			"player_index": p,
			"is_local": p == local_player,
			"is_turn": p == turn_player,
			"hand_known": false,
			"hand_count": hand_count,
			"hand_cards": [],
			"meld_cards": [],
			"must_play": {
				"known": false,
				"pending": false,
				"target_card_id": ""
			},
			"score": {
				"table_points": _array_int_at(public_state.get("hand_points_table", []), p, 0),
				"deadwood_points": _array_int_at(public_state.get("hand_points_deadwood", []), p, 0),
				"net_points": _array_int_at(public_state.get("hand_points_net", []), p, 0)
			}
		})

	# Full reveal mode
	if public_state.has("hands"):
		var hands: Array = Array(public_state.get("hands", []))
		for p in range(min(num_players, hands.size())):
			var hand_cards_raw: Array = Array(hands[p])
			var player_record: Dictionary = players[p]
			player_record["hand_known"] = true

			var hand_cards: Array = player_record["hand_cards"]
			for i in range(hand_cards_raw.size()):
				var card_id := str(hand_cards_raw[i])
				var hand_card := {
					"card_id": card_id,
					"owner_player": p,
					"zone": "HAND",
					"hand_index": i,
					"clickable": p == local_player,
					"known": true
				}
				hand_cards.append(hand_card)
				_index_card(snapshot, card_id, {
					"card_id": card_id,
					"physical_zone": "HAND",
					"player_index": p,
					"hand_index": i,
					"known": true,
					"clickable": p == local_player
				})

		# Full reveal must-play arrays
		var must_targets: Array = Array(public_state.get("must_play_discard_target", []))
		var must_pending: Array = Array(public_state.get("must_play_discard_pending", []))
		for p in range(num_players):
			var player_record: Dictionary = players[p]
			player_record["must_play"] = {
				"known": true,
				"pending": bool(must_pending[p]) if p < must_pending.size() else false,
				"target_card_id": str(must_targets[p]) if p < must_targets.size() else ""
			}
		return

	# Multiplayer-safe mode: only local player hand is known
	if local_player >= 0 and local_player < num_players:
		var your_hand: Array = Array(public_state.get("your_hand", []))
		var local_record: Dictionary = players[local_player]
		local_record["hand_known"] = true

		var local_hand_cards: Array = local_record["hand_cards"]
		for i in range(your_hand.size()):
			var card_id := str(your_hand[i])
			var hand_card := {
				"card_id": card_id,
				"owner_player": local_player,
				"zone": "HAND",
				"hand_index": i,
				"clickable": true,
				"known": true
			}
			local_hand_cards.append(hand_card)
			_index_card(snapshot, card_id, {
				"card_id": card_id,
				"physical_zone": "HAND",
				"player_index": local_player,
				"hand_index": i,
				"known": true,
				"clickable": true
			})

		var must_play: Dictionary = Dictionary(public_state.get("must_play", {}))
		local_record["must_play"] = {
			"known": true,
			"pending": bool(must_play.get("pending", false)),
			"target_card_id": str(must_play.get("target_card_id", ""))
		}


# --------------------------------------------------
# Discard records
# --------------------------------------------------

static func _build_discard_records(snapshot: Dictionary, discard_cards_raw: Array) -> void:
	var discard_records: Array = snapshot["discard"]

	for i in range(discard_cards_raw.size()):
		var card_id := str(discard_cards_raw[i])
		var is_top := i == discard_cards_raw.size() - 1

		var rec := {
			"card_id": card_id,
			"zone": "DISCARD",
			"discard_index": i,
			"is_top": is_top,
			"clickable": true
		}
		discard_records.append(rec)

		_index_card(snapshot, card_id, {
			"card_id": card_id,
			"physical_zone": "DISCARD",
			"discard_index": i,
			"is_top": is_top,
			"clickable": true,
			"known": true
		})


# --------------------------------------------------
# Meld records
# --------------------------------------------------

static func _build_meld_records(snapshot: Dictionary, public_state: Dictionary) -> void:
	var melds_raw: Array = Array(public_state.get("melds", []))
	var melds_out: Array = snapshot["melds"]
	var players: Array = snapshot["players"]

	for meld_raw_any in melds_raw:
		if not (meld_raw_any is Dictionary):
			continue

		var meld_raw: Dictionary = meld_raw_any
		var meld_id := int(meld_raw.get("id", -1))
		var meld_type := str(meld_raw.get("type", ""))
		var meld_cards_raw: Array = Array(meld_raw.get("cards", []))
		var raw_links: Array = Array(meld_raw.get("links", []))

		var normalized_links := _normalize_link_records(raw_links)
		var meld_record := {
			"meld_id": meld_id,
			"type": meld_type,
			"card_ids": [],
			"cards": [],
			"links": normalized_links,
			"clickable": true
		}

		for i in range(meld_cards_raw.size()):
			var card_raw_any = meld_cards_raw[i]
			if not (card_raw_any is Dictionary):
				continue

			var card_raw: Dictionary = card_raw_any
			var card_id := str(card_raw.get("card_id", ""))
			var played_by := int(card_raw.get("played_by", -1))
			var logical_index := int(card_raw.get("logical_index", i))
			var links_to := _links_for_card(raw_links, card_id)

			var meld_card_record := {
				"card_id": card_id,
				"meld_id": meld_id,
				"type": meld_type,
				"played_by": played_by,
				"logical_index": logical_index,
				"links_to": links_to,
				"clickable": true
			}

			Array(meld_record["card_ids"]).append(card_id)
			Array(meld_record["cards"]).append(meld_card_record)

			if played_by >= 0 and played_by < players.size():
				var player_record: Dictionary = players[played_by]
				var player_meld_cards: Array = player_record["meld_cards"]
				player_meld_cards.append({
					"card_id": card_id,
					"meld_id": meld_id,
					"type": meld_type,
					"played_by": played_by,
					"logical_index": logical_index,
					"links_to": links_to,
					"clickable": true
				})

			_index_card(snapshot, card_id, {
				"card_id": card_id,
				"physical_zone": "PLAYER_MELD",
				"player_index": played_by,
				"meld_id": meld_id,
				"meld_type": meld_type,
				"logical_index": logical_index,
				"links_to": links_to,
				"clickable": true,
				"known": true
			})

		melds_out.append(meld_record)


# --------------------------------------------------
# Links
# --------------------------------------------------

static func _normalize_link_records(raw_links: Array) -> Array:
	var out: Array = []

	for link_any in raw_links:
		if link_any is Array:
			var pair: Array = link_any
			if pair.size() >= 2:
				out.append({
					"from": str(pair[0]),
					"to": str(pair[1])
				})
		elif link_any is Dictionary:
			var d: Dictionary = link_any
			out.append({
				"from": str(d.get("from", "")),
				"to": str(d.get("to", ""))
			})

	return out

static func _links_for_card(raw_links: Array, card_id: String) -> Array:
	var out: Array = []

	for link_any in raw_links:
		if link_any is Array:
			var pair: Array = link_any
			if pair.size() < 2:
				continue

			var a := str(pair[0])
			var b := str(pair[1])

			if a == card_id:
				out.append(b)
			elif b == card_id:
				out.append(a)

		elif link_any is Dictionary:
			var d: Dictionary = link_any
			var a := str(d.get("from", ""))
			var b := str(d.get("to", ""))

			if a == card_id:
				out.append(b)
			elif b == card_id:
				out.append(a)

	return out


# --------------------------------------------------
# Card index
# --------------------------------------------------

static func _index_card(snapshot: Dictionary, card_id: String, data: Dictionary) -> void:
	var card_index: Dictionary = snapshot["card_index"]
	card_index[card_id] = data


# --------------------------------------------------
# Small helpers
# --------------------------------------------------

static func _array_int_at(arr_any, idx: int, default_value: int) -> int:
	if not (arr_any is Array):
		return default_value
	var arr: Array = arr_any
	if idx < 0 or idx >= arr.size():
		return default_value
	return int(arr[idx])
