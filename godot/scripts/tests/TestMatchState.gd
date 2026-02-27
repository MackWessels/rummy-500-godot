# TestMatchState.gd
extends Node

var fails = 0

func _ready() -> void:
	print("TestMatchState _ready() fired")

	test_accumulates_and_detects_winner()
	test_rotates_dealer_and_starting_player()

	print("Done. fails=%s" % fails)

func _expect(cond: bool, msg_ok: String, msg_fail: String) -> void:
	if cond:
		print("OK:%s" % msg_ok)
	else:
		fails += 1
		push_warning("FAIL:%s" % msg_fail)

func test_accumulates_and_detects_winner() -> void:
	var match_state = MatchState.new(2, 500, 0)

	# Fake a finished/scored hand state (no need to simulate full play here)
	var s = GameState.new()
	s.init_for_players(2)
	s.hand_over = true
	s.hand_scored = true
	s.hand_points_net = [300, -20]

	var res = match_state.finalize_hand(s)
	_expect(res.ok, "finalize ok", "finalize not ok")
	_expect(match_state.total_scores[0] == 300, "p0 total=300", "p0 total wrong")
	_expect(match_state.total_scores[1] == -20, "p1 total=-20", "p1 total wrong")
	_expect(match_state.winner == -1, "no winner yet", "winner should be none")

	# Second hand pushes p0 over 500
	var s2 = GameState.new()
	s2.init_for_players(2)
	s2.hand_over = true
	s2.hand_scored = true
	s2.hand_points_net = [220, 10]

	var res2 = match_state.finalize_hand(s2)
	_expect(res2.ok, "finalize2 ok", "finalize2 not ok")
	_expect(match_state.total_scores[0] == 520, "p0 total=520", "p0 total wrong after hand2")
	_expect(match_state.winner == 0, "winner is p0", "winner wrong")

func test_rotates_dealer_and_starting_player() -> void:
	var match_state = MatchState.new(3, 500, 0)
	_expect(match_state.dealer == 0, "dealer starts 0", "dealer start wrong")
	_expect(match_state.starting_player == 1, "start is left of dealer", "starting player wrong")

	var s = GameState.new()
	s.init_for_players(3)
	s.hand_over = true
	s.hand_scored = true
	s.hand_points_net = [0, 0, 0]

	match_state.finalize_hand(s)
	_expect(match_state.dealer == 1, "dealer rotated to 1", "dealer rotate wrong")
	_expect(match_state.starting_player == 2, "start rotated to 2", "start rotate wrong")
