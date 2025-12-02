extends Node

# --- CONFIGURATION ---
const MIN_DIVISIONS_TO_ATTACK := 1
const MAX_SPLIT_TARGETS := 3
const MERGE_RANGE_SQ := 6000.0 * 6000.0

# --- STATE ---
var war_pairs: Array = []                       # [ [CountryA, CountryB], ... ]
var reserved_provinces: Dictionary = {}        # { province_id: country_name }

# --- LIFECYCLE ---
func _ready() -> void:
	if MainClock:
		MainClock.hour_passed.connect(_on_ai_tick)

# =============================================================
# DIPLOMACY / WAR STATUS
# =============================================================
func declare_war(country_a: String, country_b: String) -> void:
	if country_a == country_b: return
	var sorted_pair = [country_a, country_b]
	sorted_pair.sort()
	if not is_at_war(country_a, country_b):
		war_pairs.append(sorted_pair)
		PopupManager.show_alert("war", country_a, country_b)
		MusicManager.play_sfx (MusicManager.SFX.DECLARE_WAR)
		MusicManager.play_music(MusicManager.MUSIC.BATTLE_THEME)
		print("WAR DECLARED: %s vs %s" % [country_a, country_b])

func is_at_war(country_a: String, country_b: String) -> bool:
	var pair = [country_a, country_b]
	pair.sort()
	return pair in war_pairs

func get_enemies(country: String) -> Array[String]:
	var enemies: Array[String] = []
	for pair in war_pairs:
		if pair[0] == country:
			enemies.append(pair[1])
		elif pair[1] == country:
			enemies.append(pair[0])
	return enemies


# =============================================================
# COMBAT CORE
# =============================================================
func resolve_province_conflict(province_id: int) -> void:
	var local_troops = TroopManager.get_troops_in_province(province_id)
	if local_troops.size() < 2:
		_finish_province_actions(province_id)
		return

	var countries_present = _get_countries_in_province(local_troops)
	for i in range(countries_present.size()):
		for j in range(i + 1, countries_present.size()):
			var a = countries_present[i]
			var b = countries_present[j]
			if is_at_war(a, b):
				_execute_battle(province_id, a, b, local_troops)
				return

func _get_countries_in_province(troops: Array) -> Array:
	var countries: Array = []
	for t in troops:
		if not countries.has(t.country_name):
			countries.append(t.country_name)
	return countries

func _execute_battle(pid: int, country_a: String, country_b: String, troops: Array) -> void:
	var group_a = troops.filter(func(t): return t.country_name == country_a)
	var group_b = troops.filter(func(t): return t.country_name == country_b)

	var power_a = _calculate_group_power(group_a)
	var power_b = _calculate_group_power(group_b)

	_apply_damage_to_group(group_a, power_b)
	_apply_damage_to_group(group_b, power_a)

	call_deferred("_finish_province_actions", pid)

func _calculate_group_power(troops: Array) -> int:
	var power := 0
	for t in troops: power += t.divisions
	return power

func _apply_damage_to_group(troops: Array, damage: int) -> void:
	for t in troops:
		if damage <= 0: break
		if t.divisions <= damage:
			damage -= t.divisions
			t.divisions = 0
			TroopManager.remove_troop_by_war(t)
		else:
			t.divisions -= damage
			damage = 0

# =============================================================
# CONQUEST / PROVINCE CONTROL
# =============================================================
func _finish_province_actions(pid: int) -> void:
	var troops = TroopManager.get_troops_in_province(pid)
	if reserved_provinces.has(pid): reserved_provinces.erase(pid)
	if troops.is_empty(): return

	var dominant = troops[0].country_name
	for t in troops:
		if t.country_name != dominant: return

	var owner = MapManager.province_to_country.get(pid)
	if dominant != owner and (is_at_war(dominant, owner) or owner == "Neutral"):
		_update_map_ownership(pid, dominant)

func _update_map_ownership(pid: int, new_owner: String) -> void:
	var old_owner = MapManager.province_to_country.get(pid)
	if MapManager.country_to_provinces.has(old_owner):
		MapManager.country_to_provinces[old_owner].erase(pid)

	MapManager.province_to_country[pid] = new_owner
	if not MapManager.country_to_provinces.has(new_owner):
		MapManager.country_to_provinces[new_owner] = []
	MapManager.country_to_provinces[new_owner].append(pid)

	if MapManager.has_method("update_province_color"):
		MapManager.update_province_color(pid, new_owner)

# =============================================================
# AI / PLANNING
# =============================================================
func _on_ai_tick(_hour: int = 0) -> void:
	var all_countries = MapManager.country_to_provinces.keys()
	var human_country = CurrentPlayer.get_country() if CurrentPlayer else ""
	for country in all_countries:
		if country == human_country: continue

		var enemies = get_enemies(country)
		if enemies.is_empty(): continue

		_process_country_moves(country, enemies)
		_process_country_reinforcements(country)

func _process_country_moves(country: String, enemies: Array) -> void:
	var my_troops = TroopManager.get_troops_for_country(country)
	var targets: Array = []
	for enemy in enemies:
		targets.append_array(MapManager.country_to_provinces.get(enemy, []))

	for troop in my_troops:
		if troop.is_moving or troop.divisions < MIN_DIVISIONS_TO_ATTACK:
			continue

		var best_targets = _find_best_attack_targets(country, targets, troop.position)
		if best_targets.is_empty(): continue

		var payload: Array = []
		for pid in best_targets:
			if not reserved_provinces.has(pid) or reserved_provinces[pid] != country:
				reserved_provinces[pid] = country
				payload.append({ "troop": troop, "province_id": pid })

		if not payload.is_empty():
			TroopManager.command_move_assigned(payload)

func _find_best_attack_targets(country: String, target_pids: Array, start_pos: Vector2) -> Array:
	var distances: Array = []
	for pid in target_pids:
		if reserved_provinces.has(pid) and reserved_provinces[pid] == country:
			continue
		var pos = MapManager.province_centers.get(pid, Vector2.ZERO)
		distances.append({ "pid": pid, "distance": start_pos.distance_squared_to(pos) })

	distances.sort_custom(func(a, b): return a.distance < b.distance)
	var final_targets: Array = []
	for i in range(min(distances.size(), MAX_SPLIT_TARGETS)):
		final_targets.append(distances[i].pid)
	return final_targets

func _process_country_reinforcements(country: String) -> void:
	var troops = TroopManager.get_troops_for_country(country)
	var garrisons = troops.filter(func(t): return not t.is_moving and t.divisions > 5)
	var smalls = troops.filter(func(t): return not t.is_moving and t.divisions <= 5)

	if garrisons.is_empty() or smalls.is_empty(): return

	for s in smalls:
		var best: int = -1
		var min_dist := INF
		for g in garrisons:
			if reserved_provinces.has(g.province_id): continue
			var dist = s.position.distance_squared_to(g.position)
			if dist < min_dist and dist < MERGE_RANGE_SQ:
				min_dist = dist
				best = g.province_id

		if best != -1:
			reserved_provinces[best] = country
			TroopManager.command_move_assigned([{ "troop": s, "province_id": best }])
