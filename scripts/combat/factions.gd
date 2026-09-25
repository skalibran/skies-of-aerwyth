class_name Factions
extends RefCounted

const PLAYER: StringName = &"player"
const ENEMY: StringName = &"enemy"
const NEUTRAL: StringName = &"neutral"


static func are_hostile(first: StringName, second: StringName) -> bool:
	return (first == PLAYER and second == ENEMY) or (first == ENEMY and second == PLAYER)
