# MusicManager.gd
extends Node

var music_player: AudioStreamPlayer
enum SFX {
	TROOP_MOVE,
	TROOP_SELECTED,
	BATTLE_START,
	OPEN_MENU,
	DECLARE_WAR,
	HOVERED,
}
enum MUSIC {
	MAIN_THEME,
	BATTLE_THEME
}

var sfx_map = {
	SFX.TROOP_MOVE: preload("res://assets/snd/moveDivSound.mp3"),
	SFX.TROOP_SELECTED: preload("res://assets/snd/selectDivSound.mp3"),
	SFX.OPEN_MENU: preload("res://assets/snd/openMenuSound.mp3"),
	SFX.DECLARE_WAR: preload("res://assets/snd/declareWarSound.mp3"),
	SFX.HOVERED: preload("res://assets/snd/hoveredSound.mp3")
}

var music_map = {
	MUSIC.MAIN_THEME: preload("res://assets/music/gameMusic.mp3"),
	MUSIC.BATTLE_THEME: preload("res://assets/music/warMusic.mp3")
	# MUSIC.BATTLE_THEME: preload("res://assets/music/battle_theme.ogg")
}

# *** MULTIPLE SFX SUPPORT ***
var sfx_players: Array[AudioStreamPlayer] = []

func _ready():
	# Music player
	music_player = AudioStreamPlayer.new()
	add_child(music_player)
	music_player.bus = "Music"
	
	# SFX Players Pool (8 players for overlapping sounds
	for i in 8:
		var player = AudioStreamPlayer.new()
		add_child(player)
		player.bus = "SFX"
		sfx_players.append(player)
	play_music(MUSIC.MAIN_THEME, true)

func play_sfx(sfx: int):
	if sfx not in sfx_map:
		return
	
	# Find first available (stopped) player
	var player = null
	for p in sfx_players:
		if not p.playing:
			player = p
			break
	
	# If none available, use the first one (overwrites oldest)
	if not player:
		player = sfx_players[0]
	
	player.stream = sfx_map[sfx]
	player.play()

func play_music(track: int, loop: bool = true):
	if track not in music_map:
		return
	
	music_player.stream = music_map[track]
	music_player.play()

# *** BONUS: Stop all SFX ***
func stop_all_sfx():
	for player in sfx_players:
		player.stop()

# *** BONUS: Fade out music ***
func fade_out_music(duration: float = 1.0):
	var tween = create_tween()
	tween.tween_method(set_music_volume, 1.0, 0.0, duration)
	await tween.finished
	music_player.stop()

func set_music_volume(volume: float):
	music_player.volume_db = linear_to_db(volume)
