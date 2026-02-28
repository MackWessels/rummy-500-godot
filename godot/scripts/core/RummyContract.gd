extends RefCounted
class_name RummyContract

# Action types
const A_DRAW_STOCK := "DRAW_STOCK"
const A_DRAW_DISCARD_STACK := "DRAW_DISCARD_STACK"
const A_CREATE_MELD := "CREATE_MELD"
const A_LAYOFF := "LAYOFF"
const A_DISCARD := "DISCARD"

# Phases
const PHASE_DRAW := "DRAW"
const PHASE_PLAY := "PLAY"

# Ends
const END_LEFT := "LEFT"
const END_RIGHT := "RIGHT"
