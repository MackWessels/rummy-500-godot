extends RefCounted
class_name GameState

var num_players: int = 0
var hands: Array = []       # Array[Array[String]] CardIDs per player
var stock: Array = []       # Array[String] (hidden to opponents; expose stock_count)
var discard: Array = []     # Array[String], fully visible

# Internal meld format moving forward:
# {
# 	"id": int,
# 	"type": "RUN" | "SET",
# 	"cards": [
# 		{"card_id": String, "played_by": int}
# 	]
# }
#
# This GameState also tolerates older meld shapes in to_public():
# {
# 	"type": "RUN" | "SET",
# 	"cards": ["CARD_A", "CARD_B", ...]
# }
var melds: Array = []       # Array[Dictionary] shared table melds
var next_meld_id: int = 1

var turn_player: int = 0
var phase: String = "DRAW"  # "DRAW" -> "PLAY"

var must_play_discard_target: Array = []   # Array[String], "" if none
var must_play_discard_pending: Array = []  # Array[bool]

var hand_over: bool = false
var hand_end_reason: String = ""
var went_out_player: int = -1

var hand_scored: bool = false
var hand_points_table: Array = []     # Array[int]
var hand_points_deadwood: Array = []  # Array[int]
var hand_points_net: Array = []       # Array[int]

func init_for_players(p: int) -> void:
	num_players = p

	hands = []
	for i in range(p):
		hands.append([])

	stock = []
	discard = []
	melds = []
	next_meld_id = 1

	turn_player = 0
	phase = "DRAW"

	must_play_discard_target = []
	must_play_discard_pending = []
	for i in range(p):
		must_play_discard_target.append("")
		must_play_discard_pending.append(false)

	hand_over = false
	hand_end_reason = ""
	went_out_player = -1

	hand_scored = false
	hand_points_table = []
	hand_points_deadwood = []
	hand_points_net = []
	for i in range(p):
		hand_points_table.append(0)
		hand_points_deadwood.append(0)
		hand_points_net.append(0)

func clear_must_play(player: int) -> void:
	if player < 0 or player >= num_players:
		return
	must_play_discard_target[player] = ""
	must_play_discard_pending[player] = false

func alloc_meld_id() -> int:
	var id := next_meld_id
	next_meld_id += 1
	return id

func make_meld_card(card_id: String, played_by: int) -> Dictionary:
	return {
		"card_id": card_id,
		"played_by": played_by
	}

func make_meld(meld_type: String, card_entries: Array) -> Dictionary:
	return {
		"id": alloc_meld_id(),
		"type": meld_type,
		"cards": card_entries.duplicate(true)
	}

func get_hand_sizes_by_player() -> Array:
	var sizes: Array = []
	for i in range(num_players):
		sizes.append(hands[i].size())
	return sizes

func _normalize_meld_card(raw_card, fallback_played_by: int = -1) -> Dictionary:
	if raw_card is Dictionary:
		return {
			"card_id": String(raw_card.get("card_id", raw_card.get("id", ""))),
			"played_by": int(raw_card.get("played_by", raw_card.get("owner", fallback_played_by)))
		}

	return {
		"card_id": String(raw_card),
		"played_by": fallback_played_by
	}

func _normalize_meld(raw_meld: Dictionary, fallback_id: int) -> Dictionary:
	var meld_id := int(raw_meld.get("id", fallback_id))
	var meld_type := String(raw_meld.get("type", raw_meld.get("meld_type", "")))

	var raw_cards: Array = []
	if raw_meld.has("cards"):
		raw_cards = raw_meld["cards"]
	elif raw_meld.has("card_ids"):
		raw_cards = raw_meld["card_ids"]

	var normalized_cards: Array = []
	for raw_card in raw_cards:
		normalized_cards.append(_normalize_meld_card(raw_card))

	return {
		"id": meld_id,
		"type": meld_type,
		"cards": normalized_cards
	}

func _build_public_links(meld_type: String, public_cards: Array) -> Array:
	var links: Array = []

	if public_cards.size() < 2:
		return links

	if meld_type == "RUN":
		for i in range(public_cards.size() - 1):
			links.append([
				String(public_cards[i]["card_id"]),
				String(public_cards[i + 1]["card_id"])
			])
	else:
		# For SET selection/inspection, connect all cards to the first card.
		var root_id := String(public_cards[0]["card_id"])
		for i in range(1, public_cards.size()):
			links.append([
				root_id,
				String(public_cards[i]["card_id"])
			])

	return links

func _public_melds() -> Array:
	var result: Array = []

	for i in range(melds.size()):
		var raw_meld = melds[i]
		if not (raw_meld is Dictionary):
			continue

		var normalized := _normalize_meld(raw_meld, i + 1)

		var public_cards: Array = []
		var normalized_cards: Array = normalized["cards"]
		for j in range(normalized_cards.size()):
			var c: Dictionary = normalized_cards[j]
			public_cards.append({
				"card_id": String(c.get("card_id", "")),
				"played_by": int(c.get("played_by", -1)),
				"logical_index": j
			})

		result.append({
			"id": int(normalized["id"]),
			"type": String(normalized["type"]),
			"cards": public_cards,
			"links": _build_public_links(String(normalized["type"]), public_cards)
		})

	return result

# Public snapshot for UI / future network clients.
# reveal_all=true  -> include full hands + must-play arrays (hotseat/dev).
# reveal_all=false -> include only requesting player's hand + opponent hand sizes (multiplayer-ready).
func to_public(for_player: int, reveal_all: bool = false) -> Dictionary:
	var d: Dictionary = {
		"num_players": num_players,
		"turn_player": turn_player,
		"phase": phase,

		"stock_count": stock.size(),
		"discard": discard.duplicate(),
		"melds": _public_melds(),
		"hand_sizes_by_player": get_hand_sizes_by_player(),

		"hand_over": hand_over,
		"hand_end_reason": hand_end_reason,
		"went_out_player": went_out_player,

		"hand_scored": hand_scored,
		"hand_points_table": hand_points_table.duplicate(),
		"hand_points_deadwood": hand_points_deadwood.duplicate(),
		"hand_points_net": hand_points_net.duplicate()
	}

	if reveal_all:
		d["hands"] = hands.duplicate(true)
		d["must_play_discard_target"] = must_play_discard_target.duplicate()
		d["must_play_discard_pending"] = must_play_discard_pending.duplicate()
		return d

	# Multiplayer-safe view
	d["player"] = for_player

	var valid_player := (for_player >= 0 and for_player < num_players)

	if valid_player:
		d["your_hand"] = Array(hands[for_player]).duplicate()
		d["must_play"] = {
			"pending": bool(must_play_discard_pending[for_player]),
			"target_card_id": String(must_play_discard_target[for_player])
		}
	else:
		d["your_hand"] = []
		d["must_play"] = {"pending": false, "target_card_id": ""}

	# Kept for compatibility with older UI/tests that may still expect this.
	var other_sizes: Array = []
	for i in range(num_players):
		if i == for_player:
			continue
		other_sizes.append(hands[i].size())
	d["other_hand_sizes"] = other_sizes

	return d

func debug_summary() -> String:
	var hand_sizes := []
	for h in hands:
		hand_sizes.append(h.size())
	return "players=%s hand_sizes=%s stock=%s discard=%s melds=%s turn=%s phase=%s" % [
		num_players, hand_sizes, stock.size(), discard.size(), melds.size(), turn_player, phase
	]
