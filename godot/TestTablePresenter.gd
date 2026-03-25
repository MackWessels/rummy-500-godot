extends Node

func _ready() -> void:
	print("TestTablePresenter _ready() fired")
	test_split_meld_snapshot()
	print("Done.")


func test_split_meld_snapshot() -> void:
	print("")
	print("--- test_split_meld_snapshot ---")

	var wrapped_public := {
		"state_version": 42,
		"state_public": {
			"num_players": 2,
			"turn_player": 0,
			"phase": "PLAY",

			"stock_count": 17,
			"discard": ["D0-C8-0047"],

			"melds": [
				{
					"id": 1,
					"type": "SET",
					"cards": [
						{"card_id": "D0-C7-0046", "played_by": 0, "logical_index": 0},
						{"card_id": "D0-H7-0020", "played_by": 0, "logical_index": 1},
						{"card_id": "D0-S7-0007", "played_by": 0, "logical_index": 2}
					],
					"links": [
						["D0-C7-0046", "D0-H7-0020"],
						["D0-C7-0046", "D0-S7-0007"]
					]
				},
				{
					"id": 2,
					"type": "RUN",
					"cards": [
						{"card_id": "D0-S5-0005", "played_by": 1, "logical_index": 0},
						{"card_id": "D0-S6-0006", "played_by": 1, "logical_index": 1},
						{"card_id": "D0-S7-0007", "played_by": 1, "logical_index": 2},
						{"card_id": "D0-S8-0008", "played_by": 0, "logical_index": 3},
						{"card_id": "D0-S9-0009", "played_by": 1, "logical_index": 4}
					],
					"links": [
						["D0-S5-0005", "D0-S6-0006"],
						["D0-S6-0006", "D0-S7-0007"],
						["D0-S7-0007", "D0-S8-0008"],
						["D0-S8-0008", "D0-S9-0009"]
					]
				}
			],

			"hand_sizes_by_player": [1, 3],

			"hand_over": false,
			"hand_end_reason": "",
			"went_out_player": -1,

			"hand_scored": false,
			"hand_points_table": [60, 6],
			"hand_points_deadwood": [0, 11],
			"hand_points_net": [60, -5],

			"hands": [
				["D0-AH-0012"],
				["D0-D6-0018", "D0-9D-0031", "D0-JC-0041"]
			],

			"must_play_discard_target": ["", ""],
			"must_play_discard_pending": [false, false]
		}
	}

	var snapshot = TablePresenter.build_snapshot(wrapped_public, 0)

	_print_table_summary(snapshot)
	_print_players(snapshot)
	_print_melds(snapshot)
	_print_card_index_checks(snapshot)

	_expect_eq(snapshot["version"], 42, "snapshot version")
	_expect_eq(snapshot["table"]["turn_player"], 0, "turn player")
	_expect_eq(snapshot["table"]["phase"], "PLAY", "phase")
	_expect_eq(snapshot["table"]["stock_count"], 17, "stock count")
	_expect_eq(snapshot["table"]["discard_top"], "D0-C8-0047", "discard top")

	var players: Array = snapshot["players"]
	_expect_eq(players.size(), 2, "player record count")

	var p0: Dictionary = players[0]
	var p1: Dictionary = players[1]

	_expect_eq(p0["hand_known"], true, "p0 hand known")
	_expect_eq(Array(p0["hand_cards"]).size(), 1, "p0 hand count")
	_expect_eq(Array(p0["meld_cards"]).size(), 4, "p0 meld-card count")
	_expect_eq(p1["hand_known"], true, "p1 hand known")
	_expect_eq(Array(p1["hand_cards"]).size(), 3, "p1 hand count")
	_expect_eq(Array(p1["meld_cards"]).size(), 4, "p1 meld-card count")

	var melds: Array = snapshot["melds"]
	_expect_eq(melds.size(), 2, "logical meld count")

	var run_meld: Dictionary = melds[1]
	_expect_eq(run_meld["meld_id"], 2, "run meld id")
	_expect_eq(run_meld["type"], "RUN", "run meld type")
	_expect_eq(Array(run_meld["card_ids"]).size(), 5, "run logical card count")
	_expect_eq(Array(run_meld["links"]).size(), 4, "run link count")

	var card_index: Dictionary = snapshot["card_index"]
	_expect_eq(card_index.has("D0-S8-0008"), true, "card index has split run card 8S")
	_expect_eq(card_index["D0-S8-0008"]["player_index"], 0, "8S visually belongs to player 0")
	_expect_eq(card_index["D0-S8-0008"]["meld_id"], 2, "8S belongs to run meld 2")

	print("OK:test_split_meld_snapshot finished")


func _print_table_summary(snapshot: Dictionary) -> void:
	var table: Dictionary = snapshot["table"]
	print("TABLE")
	print("  version=", snapshot["version"])
	print("  num_players=", table["num_players"])
	print("  local_player=", table["local_player"])
	print("  turn_player=", table["turn_player"])
	print("  phase=", table["phase"])
	print("  stock_count=", table["stock_count"])
	print("  discard_count=", table["discard_count"])
	print("  discard_top=", table["discard_top"])


func _print_players(snapshot: Dictionary) -> void:
	var players: Array = snapshot["players"]
	print("PLAYERS")

	for p_any in players:
		var p: Dictionary = p_any
		print("  Player ", p["player_index"], " is_turn=", p["is_turn"], " hand_known=", p["hand_known"], " hand_count=", p["hand_count"])

		var hand_cards: Array = p["hand_cards"]
		for hc_any in hand_cards:
			var hc: Dictionary = hc_any
			print("    HAND ", hc["card_id"], " hand_index=", hc["hand_index"])

		var meld_cards: Array = p["meld_cards"]
		for mc_any in meld_cards:
			var mc: Dictionary = mc_any
			print("    MELD_CARD ", mc["card_id"], " meld_id=", mc["meld_id"], " logical_index=", mc["logical_index"], " links_to=", mc["links_to"])


func _print_melds(snapshot: Dictionary) -> void:
	var melds: Array = snapshot["melds"]
	print("LOGICAL MELDS")

	for m_any in melds:
		var m: Dictionary = m_any
		print("  Meld ", m["meld_id"], " type=", m["type"])
		print("    card_ids=", m["card_ids"])
		print("    links=", m["links"])

		var cards: Array = m["cards"]
		for c_any in cards:
			var c: Dictionary = c_any
			print("    CARD ", c["card_id"], " played_by=", c["played_by"], " logical_index=", c["logical_index"], " links_to=", c["links_to"])


func _print_card_index_checks(snapshot: Dictionary) -> void:
	var card_index: Dictionary = snapshot["card_index"]
	print("CARD INDEX CHECKS")

	var interesting_cards := [
		"D0-S5-0005",
		"D0-S8-0008",
		"D0-S9-0009",
		"D0-AH-0012",
		"D0-C8-0047"
	]

	for card_id in interesting_cards:
		if card_index.has(card_id):
			print("  ", card_id, " -> ", card_index[card_id])
		else:
			print("  ", card_id, " -> MISSING")


func _expect_eq(got, expected, label: String) -> void:
	if got == expected:
		print("OK:", label, " (got=", got, " expected=", expected, ")")
	else:
		push_error("FAIL:%s (got=%s expected=%s)" % [label, str(got), str(expected)])
