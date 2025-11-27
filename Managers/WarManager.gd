extends Node

# --- CONFIGURATION ---
# Minimum divisions a troop must have to be considered for an attack.
const MIN_DIVISIONS_TO_ATTACK = 1
# Maximum number of targets a single troop can be ordered to split toward.
const MAX_SPLIT_TARGETS = 3 
# Distance threshold (squared) for a troop to consider a friendly neighbor for merging.
const MERGE_RANGE_SQ = 6000.0 * 6000.0 

# --- STATE VARIABLES ---
# Tracks active wars: [ [CountryA, CountryB], [CountryC, CountryD] ]
var war_pairs: Array = [] 

# Used by AI: { province_id: attacking_country_name }
var reserved_provinces: Dictionary = {} 

# --- INITIALIZATION ---

func _ready() -> void:
	if MainClock:
		MainClock.hour_passed.connect(_on_ai_tick)

# =============================================================
# DIPLOMACY (WAR STATUS)
# (No changes needed)
# =============================================================

## Starts a war by adding the country pair to the centralized list.
func declare_war(country_a: String, country_b: String) -> void:
	if country_a == country_b: return
	var sorted_pair = [country_a, country_b]
	sorted_pair.sort() 
	
	if not is_at_war(country_a, country_b):
		war_pairs.append(sorted_pair) 
		print("WAR DECLARED: %s vs %s" % [country_a, country_b])

## Checks if two specific countries are fighting.
func is_at_war(country_a: String, country_b: String) -> bool:
	var check_pair = [country_a, country_b]
	check_pair.sort() 
	return check_pair in war_pairs

## Gets a list of all current enemies for one country.
func get_enemies(country: String) -> Array:
	var enemies = []
	for pair in war_pairs:
		if pair[0] == country:
			enemies.append(pair[1])
		elif pair[1] == country:
			enemies.append(pair[0])
	return enemies.duplicate() 

# =============================================================
# COMBAT CORE
# (No changes needed)
# =============================================================

## The entry point: checks if troops in a province should fight.
func resolve_province_conflict(province_id: int) -> void:
	var local_troops = TroopManager.get_troops_in_province(province_id)
	if local_troops.size() < 2:
		_finish_province_actions(province_id)
		return

	var countries_present = _get_countries_in_province(local_troops)

	for i in range(countries_present.size()):
		var country_a = countries_present[i]
		for j in range(i + 1, countries_present.size()):
			var country_b = countries_present[j]
			
			if is_at_war(country_a, country_b):
				_execute_battle(province_id, country_a, country_b, local_troops)
				return 

## Identifies all distinct countries in a list of troops.
func _get_countries_in_province(troops: Array) -> Array:
	var countries = []
	for troop in troops:
		if not countries.has(troop.country_name):
			countries.append(troop.country_name)
	return countries

## Calculates power, applies simultaneous damage, and schedules conquest check.
func _execute_battle(pid: int, country_a: String, country_b: String, all_troops: Array) -> void:
	var troops_a = all_troops.filter(func(t): return t.country_name == country_a)
	var troops_b = all_troops.filter(func(t): return t.country_name == country_b)
	
	var power_a = _calculate_group_power(troops_a)
	var power_b = _calculate_group_power(troops_b)
	
	var damage_to_a = power_b 
	var damage_to_b = power_a 
	
	_apply_damage_to_group(troops_a, damage_to_a)
	_apply_damage_to_group(troops_b, damage_to_b)
	
	call_deferred("_finish_province_actions", pid)

## Sums up divisions in a troop array.
func _calculate_group_power(troop_list: Array) -> int:
	var power = 0
	for t in troop_list: power += t.divisions
	return power

## Applies damage by eliminating troops from the front of the list.
func _apply_damage_to_group(troop_list: Array, damage: int) -> void:
	for troop in troop_list:
		if damage <= 0: break
		
		if troop.divisions <= damage:
			damage -= troop.divisions
			troop.divisions = 0
			# Use the cleaner public interface from TroopManager
			TroopManager.remove_troop_by_war(troop) 
		else:
			troop.divisions -= damage
			damage = 0

# =============================================================
# CONQUEST & RESERVATION
# (No changes needed)
# =============================================================

## Checks for conquest and clears AI reservations after combat or movement finishes.
func _finish_province_actions(pid: int) -> void:
	var remaining_troops = TroopManager.get_troops_in_province(pid)
	
	if reserved_provinces.has(pid):
		reserved_provinces.erase(pid)
	
	if remaining_troops.is_empty(): return
	
	var dominant_country = remaining_troops[0].country_name
	for t in remaining_troops:
		if t.country_name != dominant_country: return 

	var current_owner = MapManager.province_to_country.get(pid)
	
	if dominant_country != current_owner and (is_at_war(dominant_country, current_owner) or current_owner == "Neutral"):
		_update_map_ownership(pid, dominant_country)
		
## Handles all data and visual updates for a province changing hands.
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
# ADVANCED AI LOGIC
# =============================================================

## Runs the AI decision logic periodically.
func _on_ai_tick(_hour = 0) -> void:
	var all_countries = MapManager.country_to_provinces.keys()
	var human_player = CurrentPlayer.get_country() if CurrentPlayer else ""
	
	for country in all_countries:
		if country == human_player: continue
		
		var enemies = get_enemies(country)
		if enemies.is_empty(): continue
		
		# 1. Decide on coordinated moves (Attack/Reinforce)
		_process_country_moves(country, enemies)
		
		# 2. Check for friendly consolidation (Troop coordination)
		_process_country_reinforcements(country)


## Decides on a move for each available troop, prioritizing splitting for mass attacks.
func _process_country_moves(country: String, enemies: Array) -> void:
	var my_troops = TroopManager.get_troops_for_country(country)
	
	# --- STEP 1: Identify all potential attack targets (province IDs) ---
	var all_potential_targets = []
	for enemy in enemies:
		all_potential_targets.append_array(MapManager.country_to_provinces.get(enemy, []))
	
	# --- STEP 2: Process each troop's decision ---
	for troop in my_troops:
		if troop.is_moving or troop.divisions < MIN_DIVISIONS_TO_ATTACK: continue
		
		# Find the top N unreserved nearest targets for this troop
		var targets = _find_best_attack_targets(country, all_potential_targets, troop.position)
		
		if not targets.is_empty():
			var target_pids = []
			var payload = []
			
			# 3. Reserve and build the payload for the TroopManager
			for target_pid in targets:
				# Only reserve if it's not already reserved by this country
				if not reserved_provinces.has(target_pid) or reserved_provinces[target_pid] != country:
					reserved_provinces[target_pid] = country
					target_pids.append(target_pid)
					payload.append({ "troop": troop, "province_id": target_pid })

			if not payload.is_empty():
				# Use the split command in TroopManager. It handles single/multiple targets and splitting the troop.
				TroopManager.command_move_assigned(payload)

## Finds the unreserved, nearest enemy provinces (up to MAX_SPLIT_TARGETS).
func _find_best_attack_targets(country: String, all_target_pids: Array, start_pos: Vector2) -> Array:
	var distances = [] # Array of { distance: float, pid: int }
	
	for pid in all_target_pids:
		# Ignore if this province is already reserved by our country.
		if reserved_provinces.has(pid) and reserved_provinces[pid] == country:
			continue
			
		var pos = MapManager.province_centers.get(pid, Vector2.ZERO)
		var dist_sq = start_pos.distance_squared_to(pos)
		
		distances.append({ "distance": dist_sq, "pid": pid })
		
	# Sort by distance
	distances.sort_custom(func(a, b): return a.distance < b.distance)
	
	var final_targets = []
	for i in range(min(distances.size(), MAX_SPLIT_TARGETS)):
		final_targets.append(distances[i].pid)
		
	return final_targets

# =============================================================
# COORDINATION & REINFORCEMENTS
# =============================================================

## AI attempts to move smaller, nearby friendly troops towards larger, stationary troops.
func _process_country_reinforcements(country: String) -> void:
	var my_troops = TroopManager.get_troops_for_country(country)
	
	# Filter for stationary troops that are large enough to be a target/garrison
	var garrisons = my_troops.filter(func(t): return not t.is_moving and t.divisions > 5)
	var small_troops = my_troops.filter(func(t): return not t.is_moving and t.divisions <= 5)

	if garrisons.is_empty() or small_troops.is_empty(): return

	for small_troop in small_troops:
		var best_garrison = -1
		var min_dist = INF
		
		for garrison in garrisons:
			# Prevent moving a troop to a province that is currently reserved for attack
			if reserved_provinces.has(garrison.province_id): continue
			
			var dist_sq = small_troop.position.distance_squared_to(garrison.position)
			
			if dist_sq < min_dist and dist_sq < MERGE_RANGE_SQ:
				min_dist = dist_sq
				best_garrison = garrison.province_id
		
		if best_garrison != -1:
			# Reserve the target province for reinforcement to avoid attacks/conflicts
			reserved_provinces[best_garrison] = country 
			
			# Issue a move command for the small troop to the garrison's province
			var payload = [{ "troop": small_troop, "province_id": best_garrison }]
			TroopManager.command_move_assigned(payload)
