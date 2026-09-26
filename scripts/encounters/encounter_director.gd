class_name EncounterDirector
extends Node

signal wave_planned(wave_number: int, plan: EncounterPlanner.Plan)
signal wave_spawned(wave_number: int, difficulty_score: int)

class PendingWave:
	var number: int
	var plan: EncounterPlanner.Plan
	var next_ship: int = 0

@export var profile: EncounterProfile
@export var enabled: bool = true
## Zero randomizes each journey. Placement uses a separate RNG owned by Journey.
@export var random_seed: int = 0
@export_range(1, 32) var spawns_per_tick: int = 8

var threat_level: int = 0
var planned_waves: int = 0
var spawned_count: int = 0
var _pending: Array[PendingWave] = []
var _rng := RandomNumberGenerator.new()
var _retry_remaining: float = 0.0


func is_combat_active(journey: Journey) -> bool:
	if not journey.combat_enabled:
		return false
	if enabled and not _pending.is_empty():
		return true
	for ship in journey.ships:
		if ship.alive and not ship.is_queued_for_deletion() and Factions.are_hostile(Factions.PLAYER, ship.faction):
			return true
	return false


func _ready() -> void:
	assert(profile != null)
	profile.validate()
	if random_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = random_seed


func step(delta: float, journey: Journey) -> void:
	if not enabled or not journey.combat_enabled or delta <= 0.0 or journey.fleet.members.is_empty():
		return
	var reached := profile.threat_at(journey.progression.distance)
	if reached > threat_level:
		threat_level = reached
	# Catch up crossed milestones once each, with at most one plan per physics tick.
	if planned_waves < threat_level:
		planned_waves += 1
		var pending := PendingWave.new()
		pending.number = planned_waves
		pending.plan = EncounterPlanner.build(profile, planned_waves, _rng)
		if not pending.plan.ships.is_empty():
			_pending.append(pending)
		wave_planned.emit(planned_waves, pending.plan)
	_retry_remaining = maxf(0.0, _retry_remaining - delta)
	if _retry_remaining > 0.0:
		return
	for attempt in range(spawns_per_tick):
		if _pending.is_empty():
			return
		var pending := _pending[0]
		if not journey.try_spawn_enemy(pending.plan.ships[pending.next_ship]):
			# Retry the selected ship without rerolling composition or losing guarantees.
			_retry_remaining = 0.5
			return
		spawned_count += 1
		pending.next_ship += 1
		if pending.next_ship == 1:
			wave_spawned.emit(pending.number, pending.plan.spent + pending.plan.bonus_cost)
		if pending.next_ship == pending.plan.ships.size():
			_pending.pop_front()
