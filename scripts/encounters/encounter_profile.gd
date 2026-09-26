class_name EncounterProfile
extends Resource

@export_range(1.0, 10000.0, 1.0, "or_greater") var threat_distance: float = 500.0
@export_range(0, 10000) var base_budget: int = 0
@export_range(1.0, 1000.0, 0.5) var budget_per_threat: float = 15.0
## Budget = base + points * threat^growth. One gives linear growth.
@export_range(0.1, 3.0, 0.05) var budget_growth: float = 1.0
## Stop after spending a randomly chosen 75–100% of the budget, or exhausting choices.
@export_range(0.0, 1.0, 0.05) var minimum_spend_ratio: float = 0.75
@export var options: Array[EncounterOption] = []
@export var wave_overrides: Array[WaveOverride] = []


func threat_at(distance: float) -> int:
	return maxi(0, floori(distance / threat_distance))


func budget_at(threat: int) -> int:
	return maxi(0, roundi(base_budget + budget_per_threat * pow(maxi(0, threat), budget_growth)))


func override_at(wave_number: int) -> WaveOverride:
	for authored in wave_overrides:
		if authored.wave_number == wave_number:
			return authored
	return null


func validate() -> void:
	assert(is_finite(threat_distance) and threat_distance > 0.0)
	assert(base_budget >= 0 and is_finite(budget_per_threat) and budget_per_threat > 0.0)
	assert(is_finite(budget_growth) and budget_growth > 0.0)
	assert(minimum_spend_ratio >= 0.0 and minimum_spend_ratio <= 1.0)
	for option in options:
		assert(option != null)
		option.validate()
	var numbers: Array[int] = []
	for authored in wave_overrides:
		assert(authored != null)
		authored.validate()
		assert(authored.wave_number not in numbers, "Use one override per wave number.")
		numbers.append(authored.wave_number)
