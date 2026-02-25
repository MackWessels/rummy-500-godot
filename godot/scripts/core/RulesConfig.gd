extends RefCounted
class_name RulesConfig

# custom rules
var allow_wrap_runs: bool = true
var allow_duplicate_suits_in_set: bool = true

# Scoring
var ace_run_high_requires_qk: bool = true
var ace_low_points: int = 1
var ace_high_points: int = 15
