class_name EncounterPlanner
extends RefCounted

class Plan:
	var ships: Array[ShipDefinition] = []
	var selections: Array[EncounterOption] = []
	var budget: int = 0
	var spent: int = 0
	var bonus_cost: int = 0


static func build(profile: EncounterProfile, wave_number: int, rng: RandomNumberGenerator) -> Plan:
	var plan := Plan.new()
	plan.budget = profile.budget_at(wave_number)
	var authored := profile.override_at(wave_number)
	if authored != null:
		for entry in authored.guaranteed:
			for index in range(entry.count):
				entry.entry.append_ships(plan.ships)
			if entry.charge_budget:
				plan.spent += entry.entry.cost() * entry.count
			else:
				plan.bonus_cost += entry.entry.cost() * entry.count
		if not authored.fill_random_budget:
			return plan
	# An over-budget guarantee is honored, with no random extras or future debt.
	var target := ceili(plan.budget * rng.randf_range(profile.minimum_spend_ratio, 1.0))
	var used := PackedInt32Array()
	used.resize(profile.options.size())
	while plan.spent < target:
		var eligible: Array[int] = []
		var total_weight: float = 0.0
		for index in range(profile.options.size()):
			var option := profile.options[index]
			if option.weight <= 0.0 or used[index] >= option.maximum_selections or option.entry.cost() > plan.budget - plan.spent:
				continue
			eligible.append(index)
			total_weight += option.weight
		if eligible.is_empty():
			break
		var roll := rng.randf() * total_weight
		var selected: int = eligible.back()
		for index in eligible:
			roll -= profile.options[index].weight
			if roll < 0.0:
				selected = index
				break
		var option := profile.options[selected]
		used[selected] += 1
		option.entry.append_ships(plan.ships)
		plan.selections.append(option)
		plan.spent += option.entry.cost()
	return plan
