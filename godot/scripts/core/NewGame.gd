
extends RefCounted
class_name NewGame

static func deal_count(num_players: int) -> int:
	if num_players == 2:
		return 13
	return 7

static func deck_count(num_players: int) -> int:
	if num_players > 2:
		return 2
	return 1

static func create_game(num_players: int, registry: CardRegistry) -> GameState:
	var state = GameState.new()
	state.num_players = num_players
	
	var decks = deck_count(num_players)
	var shoe = DeckBuilder.build_shoe(decks, registry)
	DeckBuilder.shuffle_in_place(shoe)
	
	#init hands
	state.hands = []
	for i in range(num_players):
		state.hands.append([])
	
	#deal
	var per = deal_count(num_players)
	for c in range(per):
		for p in range(num_players):
			state.hands[p].append(state.shoe.pop_back())
	
	#stock + discard
	state.stock = shoe
	state.discard = []
	if state.stock.size() > 0:
		state.discard.append(state.stock.pop_back())
	
	state.turn_player = 0
	state.phase = "DRAW"
	return state
