extends Node

# --- CONFIGURATION ---
const USE_SMOOTH_MOVEMENT := true # Keep this True for smooth movement
var BASE_SPEED = MainClock.time_scale               # Updated by MainClock
var AUTO_MERGE = true             # Auto-merge adjacent troops

# --- DATA STRUCTURES (Optimized Indexes) ---
var troops: Array = []                     # Master list of all troops
var moving_troops: Array = []              # Subset for _process updates
var troops_by_province: Dictionary = {}    # { province_id: [TroopData, ...] }
var troops_by_country: Dictionary = {}     # { country_name: [TroopData, ...] }

var path_cache: Dictionary = {}            # { start_id: { target_id: path_array } }
var flag_cache: Dictionary = {}            # { country_name: texture }
var needs_redraw := false                  # Used to throttle redraw calls

# =============================================================
# LIFECYCLE & TIME MANAGEMENT
# =============================================================

func _ready() -> void:
	set_process(false)
	if MainClock:
		MainClock.time_scale_changed.connect(_update_time_stuff)

func _update_time_stuff(speed) -> void:
	BASE_SPEED = speed

func change_merge() -> void:
	AUTO_MERGE = !AUTO_MERGE
	if AUTO_MERGE:
		if CurrentPlayer and MapManager:
			var current_country = CurrentPlayer.get_country()
			var provinces = MapManager.country_to_provinces.get(current_country, [])
			for prov in provinces:
				_auto_merge_in_province(prov, current_country)

func _process(delta: float) -> void:
	if moving_troops.is_empty():
		set_process(false)
		return

	needs_redraw = false
	var snapshot := moving_troops.duplicate() # Shallow copy for safe iteration

	for troop in snapshot:
		if not troops.has(troop):
			continue # Troop was removed (e.g., by combat)

		if USE_SMOOTH_MOVEMENT:
			_update_smooth(troop, delta)
		# We explicitly skip the teleport update since USE_SMOOTH_MOVEMENT is hardcoded True
		# else: _update_teleport(troop, delta) 

	if needs_redraw:
		get_tree().call_group("TroopRenderer", "queue_redraw")
		needs_redraw = false

# =============================================================
# MOVEMENT LOGIC
# =============================================================

## Handles the continuous linear interpolation (LERP) movement.
func _update_smooth(troop: TroopData, delta: float) -> void:
	var start = troop.get_meta("start_pos", troop.position)
	var end = troop.target_position
	var total_dist = start.distance_to(end)
	
	if total_dist < 0.001:
		_arrive_at_leg_end(troop)
		return

	var speed_factor = BASE_SPEED * delta / total_dist
	var progress = troop.get_meta("progress", 0.0) + speed_factor
	
	if progress >= 1.0:
		troop.position = end
		troop.set_meta("progress", 0.0)
		_arrive_at_leg_end(troop)
	else:
		troop.position = start.lerp(end, progress)
		troop.set_meta("progress", progress)
		needs_redraw = true

## Handles the consequence of reaching the end of one path segment.
func _arrive_at_leg_end(troop: TroopData) -> void:
	if troop.path.is_empty():
		_stop_troop(troop)
		return

	var next_pid = troop.path.pop_front()
	
	# 1. Update internal map state (province_id, indexes)
	_move_troop_to_province_logically(troop, next_pid)

	# 2. Check for combat/conquest immediately upon entering the new province
	if WarManager:
		WarManager.resolve_province_conflict(next_pid)
		# Use deferred call to ensure all combat/death logic finishes before conquest check
		#WarManager.call_deferred("_handle_combat_end", next_pid) 

	# Check if the troop survived the WarManager call
	if not troops.has(troop): return

	if troop.path.is_empty():
		_stop_troop(troop)
		# Auto-merge if stopped and enabled
		if AUTO_MERGE and troops.has(troop):
			_auto_merge_in_province(troop.province_id, troop.country_name)
	else:
		_start_next_leg(troop)
		needs_redraw = true

## Prepares the troop for the next segment of its journey.
func _start_next_leg(troop: TroopData) -> void:
	if troop.path.is_empty():
		return
	

	var next_pid = troop.path[0]
	# Set the target position to the center of the next province
	troop.target_position = MapManager.province_centers.get(int(next_pid), troop.position)
	troop.set_meta("start_pos", troop.position)

	# Reset progress for smooth movement
	if USE_SMOOTH_MOVEMENT:
		troop.set_meta("progress", 0.0)
	
	# Enable processing
	troop.is_moving = true
	if not moving_troops.has(troop):
		moving_troops.append(troop)
	if not is_processing():
		set_process(true)

## Stops the troop and disables processing if no others are moving.
func _stop_troop(troop: TroopData) -> void:
	moving_troops.erase(troop)
	troop.is_moving = false
	troop.path.clear()
	needs_redraw = true
	if moving_troops.is_empty():
		set_process(false)

# =============================================================
# COMMAND & PATHFINDING
# =============================================================

## Public entry point for a single troop move order.
func order_move_troop(troop: TroopData, target_pid: int) -> void:
	command_move_assigned([ { "troop": troop, "province_id": target_pid } ])

## Public entry point for executing complex move/split commands.
func command_move_assigned(payload: Array) -> void:
	if payload.is_empty(): return

	var country = payload[0].get('troop').country_name
	var allowedCountries: Array[String] = [country] as Array[String] + WarManager.get_enemies(country)

	
	# --- STEP 1: Process and Group ---
	var troop_to_targets: Dictionary = {}
	var unique_paths_needed: Dictionary = {} # Tracks unique (start_id, target_id) pairs

  


	for entry in payload:
		var troop = entry.get("troop")
		var target_pid = entry.get("province_id")
		if not troop or target_pid <= 0: continue
		
		# SFX (only for the current player's troops)
		if troop.country_name == CurrentPlayer.country_name:
			if MusicManager: MusicManager.play_sfx(MusicManager.SFX.TROOP_MOVE) 

		var start_id = troop.province_id
		var key = "%d_%d" % [start_id, target_pid]
		
		if not troop_to_targets.has(troop):
			troop_to_targets[troop] = { "targets": [], "paths": {} }
		var data = troop_to_targets[troop]
		
		if not data["targets"].has(target_pid):
			data["targets"].append(target_pid)
		data["paths"][target_pid] = null
		unique_paths_needed[key] = true

	
	# --- STEP 2: Batch Pathfinding (efficiently uses cache) ---
	var pre_calculated_paths: Dictionary = {} # { "start_target": path }
	for key in unique_paths_needed.keys():
		var parts = key.split("_")
		var start = int(parts[0])
		var target = int(parts[1])
		pre_calculated_paths[key] = _get_cached_path(start, target, allowedCountries)

	# --- STEP 3: Assign Paths and Execute Movement ---
	for troop in troop_to_targets.keys():
		var data = troop_to_targets[troop]
		var targets = data["targets"]

		# 3a. Assign pre-calculated paths to troop data structure
		for target_pid in targets:
			var key = "%d_%d" % [troop.province_id, target_pid]
			data["paths"][target_pid] = pre_calculated_paths.get(key)

		# 3b. Execute move or split
		if targets.size() == 1:
			var path = data["paths"][targets[0]]
			if path and path.size() > 1:
				troop.path = path.duplicate()
				troop.path.pop_front()
				_start_next_leg(troop)
		else:
			_split_and_send_troop(troop, targets, data["paths"])

	# Final cleanup and drawing
	if not moving_troops.is_empty(): set_process(true)
	needs_redraw = true
	get_tree().call_group("TroopRenderer", "queue_redraw")

func _get_cached_path(start_id: int, target_id: int,  allowed_countries: Array[String]) -> Array:
	if start_id == target_id:
		return [] # no movement needed

	if not path_cache.has(start_id):
		path_cache[start_id] = {}
		
	if path_cache[start_id].has(target_id):
		# return duplicate to avoid external mutation
		return path_cache[start_id][target_id].duplicate()
	
	var path = MapManager.find_path(start_id, target_id, allowed_countries)

	# sanitize path (remove leading start nodes)
	path = _sanitize_path_for_troop(path, start_id)

	if path.size() > 0:
		path_cache[start_id][target_id] = path.duplicate()
	return path


# =============================================================
# SPLIT & MANEUVER
# =============================================================

## Splits a troop into multiple new troops and sends them to different targets.
func _split_and_send_troop(original_troop: TroopData, target_pids: Array, paths: Dictionary) -> void:
	var total_divs = original_troop.divisions
	var num_targets = target_pids.size()
	if num_targets <= 1 or total_divs < num_targets:
		return # Cannot split or only one target

	
	var base_divs = total_divs / num_targets
	var remainder = total_divs % num_targets

	for i in range(num_targets):
		var target_pid = target_pids[i]
		if target_pid == original_troop.province_id:
			continue  # Skip splitting to same province

		var path = paths.get(target_pid)
		if not path or path.size() <= 1:
			continue

		var divs = base_divs
		if i < remainder: divs += 1 # Distribute remainder divisions

		var troop_to_move: TroopData

		if i == 0:
			# Reuse the original troop for the first split
			troop_to_move = original_troop
			troop_to_move.divisions = divs
		else:
			# Create a brand new troop for subsequent splits
			troop_to_move = _create_new_split_troop(original_troop, divs)

		troop_to_move.path = path.duplicate()
		troop_to_move.path.pop_front()
		_start_next_leg(troop_to_move)
		#if troop_to_move.path.is_empty():
			#troop_to_move.target_position = troop_to_move.position # Ensure target is synced
			#_stop_troop(troop_to_move)
		#else:
			#_start_next_leg(troop_to_move)
	print("Split %s (%d divs) into %d armies" % [original_troop.country_name, total_divs, num_targets])

## Creates and registers a new troop object resulting from a split.
func _create_new_split_troop(original: TroopData, divisions: int) -> TroopData:
	var pos = original.position
	# Use the existing create_troop function's core logic
	var new_troop = load("res://Scripts/TroopData.gd").new(
		original.country_name,
		original.province_id,
		divisions,
		pos,
		original.flag_texture
	)

	# Copy runtime metadata for new troop
	new_troop.is_moving = false
	new_troop.path = []
	new_troop.set_meta("start_pos", pos)
	new_troop.set_meta("time_left", 0.0)
	new_troop.set_meta("progress", 0.0)

	# Register the new troop in all indexes
	troops.append(new_troop)
	_add_troop_to_indexes(new_troop)

	return new_troop

# =============================================================
# TROOP MANAGEMENT & CREATION
# =============================================================

## Creates a new troop and registers it in all indexes.
func create_troop(country: String, divs: int, prov_id: int) -> TroopData:
	if divs <= 0: return null

	# 1. Flag caching
	if not flag_cache.has(country):
		var path = "res://assets/flags/%s_flag.png" % country.to_lower()
		flag_cache[country] = load(path) if ResourceLoader.exists(path) else null

	var pos = MapManager.province_centers.get(prov_id, Vector2.ZERO)
	var troop = load("res://Scripts/TroopData.gd").new(
		country,
		prov_id,
		divs,
		pos,
		flag_cache.get(country)
	)

	# 2. Critical: initialize runtime metadata
	troop.set_meta("start_pos", pos)
	troop.set_meta("time_left", 0.0)
	troop.set_meta("progress", 0.0)
	troop.is_moving = false
	troop.path = []
	troop.province_id = prov_id

	# 3. Add to master list and indexes
	troops.append(troop)
	_add_troop_to_indexes(troop)

	# 4. Auto-merge if enabled
	if AUTO_MERGE:
		_auto_merge_in_province(prov_id, country)

	needs_redraw = true
	get_tree().call_group("TroopRenderer", "queue_redraw")

	return troop

func _auto_merge_in_province(province_id: int, country: String) -> void:
	if not AUTO_MERGE:
		return

	var local_troops = troops_by_province.get(province_id, [])
	var same_country: Array = []

	# Collect unmoving troops
	for t in local_troops:
		if t.country_name == country and not t.is_moving:
			same_country.append(t)

	if same_country.size() <= 1:
		return

	var primary = same_country[0]
	var to_remove = []

	# Merge the rest
	for i in range(1, same_country.size()):
		var secondary = same_country[i]
		primary.divisions += secondary.divisions
		to_remove.append(secondary)

	# Remove AFTER merging to avoid breaking the list while iterating
	for troop in to_remove:
		_remove_troop(troop)

	needs_redraw = true


# =============================================================
# WAR MANAGER INTERFACE (Hooks for Combat & Strategy)
# =============================================================

## Public hook for the WarManager to remove a troop that has lost a battle.
func remove_troop_by_war(troop: TroopData) -> void:
	_remove_troop(troop)

## Public hook for the WarManager to force a troop to its home province center.
func move_to_garrison(troop: TroopData) -> void:
	var center = MapManager.province_centers.get(troop.province_id, troop.position)
	troop.position = center
	troop.target_position = center
	_stop_troop(troop) # Stops any ongoing movement
	needs_redraw = true

# =============================================================
# INDEXING HELPERS (Internal Maintenance)
# =============================================================

## Adds a troop reference to the spatial and country dictionaries.
func _add_troop_to_indexes(troop: TroopData) -> void:
	var pid = troop.province_id
	var country = troop.country_name
	
	# Province Index
	if not troops_by_province.has(pid):
		troops_by_province[pid] = []
	troops_by_province[pid].append(troop)

	# Country Index
	if not troops_by_country.has(country):
		troops_by_country[country] = []
	troops_by_country[country].append(troop)

## Removes a troop reference from all data structures (master, moving, indexes).
func _remove_troop(troop: TroopData) -> void:
	# 1. Master lists
	troops.erase(troop)
	moving_troops.erase(troop)
	
	var pid = troop.province_id
	var country = troop.country_name
	
	# 2. Province Index
	if troops_by_province.has(pid):
		troops_by_province[pid].erase(troop)
		if troops_by_province[pid].is_empty():
			troops_by_province.erase(pid)
			
	# 3. Country Index
	if troops_by_country.has(country):
		troops_by_country[country].erase(troop)

## Updates the troop's location in the spatial index (troops_by_province).
func _move_troop_to_province_logically(troop: TroopData, new_pid: int) -> void:
	var old_pid = troop.province_id
	if old_pid == new_pid: return
	
	# Remove from old province list
	if troops_by_province.has(old_pid):
		troops_by_province[old_pid].erase(troop)
		if troops_by_province[old_pid].is_empty():
			troops_by_province.erase(old_pid)
			
	# Add to new province list and update troop object
	troop.province_id = new_pid
	if not troops_by_province.has(new_pid):
		troops_by_province[new_pid] = []
	troops_by_province[new_pid].append(troop)


func get_province_division_count(pid: int) -> int:
	var total = 0
	var list = troops_by_province.get(pid, [])
	for troop in list:
		total += troop.divisions
	return total
	

func clear_path_cache() -> void:
	path_cache.clear()
	print("Pathfinding cache cleared.")

# Remove leading waypoints that are equal to the troop's current province.
func _sanitize_path_for_troop(path: Array, start_pid: int) -> Array:
	if not path:
		return []
	# Duplicate to avoid mutating caller arrays
	var p = path.duplicate()
	# Pop front while first entry equals start_pid
	while p.size() > 0 and int(p[0]) == int(start_pid):
		p.pop_front()
	return p


# extra helper functions. Not made by AI
func get_troops_for_country(country):
	return troops_by_country.get(country, [])
	
func get_troops_in_province(province_id):
	return troops_by_province.get(province_id, [])


# Used by popup for now
func get_flag(country: String) -> Texture2D:
	# Normalize the key
	country = country.to_lower()

	# If already cached → return it
	if flag_cache.has(country):
		return flag_cache[country]

	# Build the file path
	var path = "res://assets/flags/%s_flag.png" % country

	# Load if exists
	if ResourceLoader.exists(path):
		var tex := load(path)
		flag_cache[country] = tex
		return tex

	# Fallback texture (optional)
	print("Flag not found for country:", country)
	return null
