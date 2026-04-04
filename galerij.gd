@tool
extends Node2D

## Galerij: toont de laatste creaties van bezoekers als draaiende 2.5D kasten.
## Elke foto bevat links de voorkant en rechts de binnenkant.
## De kasten draaien continu met een Paper Mario-achtige platte 3D rotatie.

@export_group("Fotos")
## Map waar foto's worden opgeslagen (absoluut pad)
@export var fotos_path: String = ""
## Aantal foto's dat getoond wordt
@export var max_fotos: int = 8
## Hoe vaak de map gescand wordt (seconden)
@export var scan_interval: float = 3.0

@export_group("Layout")
## Aantal kolommen in het grid
@export var columns: int = 4
## Ruimte tussen foto's
@export var spacing: float = 30.0
## Marge rond het grid
@export var margin: float = 50.0

@export_group("Rotatie")
## Hoe snel de kasten draaien (seconden per volle rotatie)
@export var rotation_speed: float = 6.0
## Hoe veel de kasten uit fase lopen (seconden verschil per kast)
@export var phase_offset: float = 0.8

@onready var _background: TextureRect = $Background

var _kast_nodes: Array[Node2D] = []  ## Container nodes voor elke kast
var _kast_data: Array[Dictionary] = []  ## {front: Texture2D, back: Texture2D, sprite: Sprite2D}
var _current_files: Array[String] = []
var _scan_timer: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	_resize_background()
	if Engine.is_editor_hint():
		return
	get_tree().root.size_changed.connect(_resize_background)

	if fotos_path.is_empty():
		fotos_path = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP) + "/fotos"

	if not DirAccess.dir_exists_absolute(fotos_path):
		DirAccess.make_dir_recursive_absolute(fotos_path)

	_scan_fotos()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	_time += delta

	# Scan timer
	_scan_timer += delta
	if _scan_timer >= scan_interval:
		_scan_timer = 0.0
		_scan_fotos()

	# Rotatie animatie voor elke kast
	for i in _kast_data.size():
		var data = _kast_data[i]
		var sprite: Sprite2D = data["sprite"]
		var front_tex: Texture2D = data["front"]
		var back_tex: Texture2D = data["back"]

		# Bereken rotatie fase (0-1) met offset per kast
		var t = fmod((_time + i * phase_offset) / rotation_speed, 1.0)

		# Gebruik cosinus voor de squash: 1 → 0 → -1 → 0 → 1
		var squash = cos(t * TAU)

		# Scale.x simuleert de 3D rotatie
		sprite.scale.x = absf(squash) * absf(sprite.scale.y)

		# Wissel texture op het omslagpunt
		if squash > 0:
			if sprite.texture != front_tex:
				sprite.texture = front_tex
		else:
			if sprite.texture != back_tex:
				sprite.texture = back_tex


func _scan_fotos() -> void:
	var dir = DirAccess.open(fotos_path)
	if not dir:
		return

	var files: Array[Dictionary] = []
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.get_extension().to_lower() == "png":
			var full_path = fotos_path + "/" + file_name
			var modified = FileAccess.get_modified_time(full_path)
			files.append({"name": file_name, "path": full_path, "time": modified})
		file_name = dir.get_next()
	dir.list_dir_end()

	files.sort_custom(func(a, b): return a["time"] > b["time"])

	var latest: Array[String] = []
	for i in mini(files.size(), max_fotos):
		latest.append(files[i]["path"])

	if latest == _current_files:
		return

	_current_files = latest
	_update_grid()


func _update_grid() -> void:
	# Verwijder oude nodes
	for node in _kast_nodes:
		node.queue_free()
	_kast_nodes.clear()
	_kast_data.clear()

	if _current_files.is_empty():
		return

	var viewport_size = get_viewport_rect().size if not Engine.is_editor_hint() else Vector2(1920, 1080)
	var rows = ceili(float(max_fotos) / float(columns))
	var available_w = viewport_size.x - margin * 2.0 - spacing * (columns - 1)
	var available_h = viewport_size.y - margin * 2.0 - spacing * (rows - 1)
	var cell_w = available_w / float(columns)
	var cell_h = available_h / float(rows)

	for i in _current_files.size():
		var path = _current_files[i]

		# Laad de afbeelding
		var image = Image.new()
		var err = image.load(path)
		if err != OK:
			continue

		var img_w = image.get_width()
		var img_h = image.get_height()

		# Knip in twee helften: links = voorkant, rechts = binnenkant
		@warning_ignore("integer_division")
		var half_w = img_w / 2

		var front_img = Image.create(half_w, img_h, false, image.get_format())
		front_img.blit_rect(image, Rect2i(0, 0, half_w, img_h), Vector2i(0, 0))
		var front_tex = ImageTexture.create_from_image(front_img)

		var back_img = Image.create(half_w, img_h, false, image.get_format())
		back_img.blit_rect(image, Rect2i(half_w, 0, half_w, img_h), Vector2i(0, 0))
		var back_tex = ImageTexture.create_from_image(back_img)

		# Container node voor positie
		var container = Node2D.new()
		var col = i % columns
		@warning_ignore("integer_division")
		var row = i / columns
		container.position = Vector2(
			margin + col * (cell_w + spacing) + cell_w / 2.0,
			margin + row * (cell_h + spacing) + cell_h / 2.0
		)
		add_child(container)
		_kast_nodes.append(container)

		# Sprite gecentreerd in de cel
		var sprite = Sprite2D.new()
		sprite.texture = front_tex
		sprite.centered = true

		# Schaal zodat het in de cel past
		var tex_w = float(half_w)
		var tex_h = float(img_h)
		var scale_factor = minf(cell_w / tex_w, cell_h / tex_h) * 0.9
		sprite.scale = Vector2(scale_factor, scale_factor)

		container.add_child(sprite)

		_kast_data.append({
			"front": front_tex,
			"back": back_tex,
			"sprite": sprite,
		})

		# Fade-in animatie
		container.modulate.a = 0.0
		var tween = create_tween()
		tween.tween_property(container, "modulate:a", 1.0, 0.5).set_delay(i * 0.1)


func _resize_background() -> void:
	if not _background:
		return
	var size: Vector2
	if Engine.is_editor_hint():
		size = Vector2(
			ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height")
		)
	else:
		size = get_viewport_rect().size
	_background.size = size
