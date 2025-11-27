# MapData.gd
@tool
class_name MapData
extends Resource

@export var province_centers: Dictionary = {}
@export var adjacency_list: Dictionary = {}
@export var province_to_country: Dictionary = {}
@export var country_to_provinces: Dictionary = {}
@export var max_province_id: int = 0
@export var id_map_image: Image = null
