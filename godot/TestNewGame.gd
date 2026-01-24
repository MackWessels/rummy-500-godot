extends Node

func _ready() -> void:
	seed(123456)

	print("TestNewGame _ready() fired")
	_run_all_tests()

	await get_tree().create_timer(0.2).timeout
	get_tree().quit()


func _assert_true(cond: bool, label: String) -> void:
	if not cond:
		push_error("ASSERT FAIL: " + label)
	else:
		print("OK:", label)

func _assert_eq(a, b, label: String) -> void:
	if a != b:
		push_error("ASSERT FAIL: %s (got=%s expected=%s)" % [label, str(a), str(b)])
	else:
		print("OK:", label)


func _run_all_tests() -> void:
	_test_new_game_2p()
	_test_new_game_3p()
	_test_new_game_4p()
	_test_refill_behavior()


func _test_new_game_2p() -> void:
	print("\n--- test_new_game_2p ---")
	var registry: CardRegistry = CardRegistry.new()
	var state: GameState = NewGame.create_game(2, registry)

	var total_cards: int = 52
	var dealt: int = 2 * 13
	var expected_stock: int = total_cards - dealt - 1

	_assert_eq(registry.cards_by_id.size(), total_cards, "registry has 52 cards (1 deck)")
	_assert_eq(state.hands.size(), 2, "hands array size = num_players")
	_assert_eq(state.hands[0].size(), 13, "player 0 has 13 cards")
	_assert_eq(state.hands[1].size(), 13, "player 1 has 13 cards")
	_assert_eq(state.discard.size(), 1, "discard starts with 1 card")
	_assert_eq(state.stock.size(), expected_stock, "stock size matches total - dealt - 1")
	_assert_true(state.phase == "DRAW", "phase starts as DRAW")
	_assert_true(state.turn_player == 0, "turn_player starts as 0")
	_assert_true(_all_state_cards_exist_and_unique(state, registry), "state cards exist in registry and are unique")


func _test_new_game_3p() -> void:
	print("\n--- test_new_game_3p ---")
	var registry: CardRegistry = CardRegistry.new()
	var state: GameState = NewGame.create_game(3, registry)

	var total_cards: int = 104
	var dealt: int = 3 * 7
	var expected_stock: int = total_cards - dealt - 1

	_assert_eq(registry.cards_by_id.size(), total_cards, "registry has 104 cards (2 decks)")
	_assert_eq(state.hands.size(), 3, "hands array size = num_players")
	for p in range(3):
		_assert_eq(state.hands[p].size(), 7, "player %s has 7 cards" % p)
	_assert_eq(state.discard.size(), 1, "discard starts with 1 card")
	_assert_eq(state.stock.size(), expected_stock, "stock size matches total - dealt - 1")
	_assert_true(_all_state_cards_exist_and_unique(state, registry), "state cards exist in registry and are unique")


func _test_new_game_4p() -> void:
	print("\n--- test_new_game_4p ---")
	var registry: CardRegistry = CardRegistry.new()
	var state: GameState = NewGame.create_game(4, registry)

	var total_cards: int = 104
	var dealt: int = 4 * 7
	var expected_stock: int = total_cards - dealt - 1

	_assert_eq(registry.cards_by_id.size(), total_cards, "registry has 104 cards (2 decks)")
	_assert_eq(state.hands.size(), 4, "hands array size = num_players")
	for p in range(4):
		_assert_eq(state.hands[p].size(), 7, "player %s has 7 cards" % p)
	_assert_eq(state.discard.size(), 1, "discard starts with 1 card")
	_assert_eq(state.stock.size(), expected_stock, "stock size matches total - dealt - 1")
	_assert_true(_all_state_cards_exist_and_unique(state, registry), "state cards exist in registry and are unique")


func _test_refill_behavior() -> void:
	print("\n--- test_refill_behavior ---")
	var registry: CardRegistry = CardRegistry.new()
	var state: GameState = NewGame.create_game(2, registry)

	# Case 1: discard < 2, stock empty => draw_from_stock returns ""
	state.stock.clear()
	state.discard = [state.discard[0]]
	var drew: String = NewGame.draw_from_stock(state)
	_assert_eq(drew, "", "draw_from_stock returns empty when stock empty and discard<2")
	_assert_eq(state.stock.size(), 0, "stock stays empty when discard<2")
	_assert_eq(state.discard.size(), 1, "discard unchanged when discard<2")

	# Case 2: discard >= 2, stock empty => keep top discard, shuffle rest to stock, then draw 1
	state = NewGame.create_game(2, registry)
	for i in range(3):
		state.discard.append(state.stock.pop_back())

	var top_before: String = state.discard[-1]
	var discard_count_before: int = state.discard.size()

	state.stock.clear()
	drew = NewGame.draw_from_stock(state)

	_assert_true(drew != "", "draw_from_stock draws after refill when discard>=2")
	_assert_eq(state.discard.size(), 1, "refill keeps only top discard")
	_assert_eq(state.discard[-1], top_before, "top discard preserved through refill")

	var expected_new_stock_after_draw: int = (discard_count_before - 1) - 1
	_assert_eq(state.stock.size(), expected_new_stock_after_draw, "stock becomes (discard-1) then draw reduces by 1")


func _all_state_cards_exist_and_unique(state: GameState, registry: CardRegistry) -> bool:
	var seen := {}

	for p in range(state.hands.size()):
		for cid in state.hands[p]:
			if not registry.has_card(cid):
				return false
			if seen.has(cid):
				return false
			seen[cid] = true

	for cid in state.stock:
		if not registry.has_card(cid):
			return false
		if seen.has(cid):
			return false
		seen[cid] = true

	for cid in state.discard:
		if not registry.has_card(cid):
			return false
		if seen.has(cid):
			return false
		seen[cid] = true

	return true
