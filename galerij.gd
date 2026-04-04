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

@export_group("Effecten")
## Kanteling in graden bij het draaien
@export var tilt_angle: float = 3.0
## Schaduw opacity
@export var shadow_opacity: float = 0.25
## Schaduw Y offset (pixels onder het midden van de kast)
@export var shadow_y_offset: float = -65.0
## Hoe lang de kast stilstaat op voorkant (seconden)
@export var front_duration: float = 2.0
## Hoe lang de kast stilstaat op achterkant (seconden)
@export var back_duration: float = 4.0
## Hoe snel de draai is (seconden)
@export var flip_duration: float = 0.4

@onready var _background: TextureRect = $Background

var _kast_nodes: Array[Node2D] = []
var _kast_data: Array[Dictionary] = []
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

	# ESC = afsluiten
	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().quit()

	_scan_timer += delta
	if _scan_timer >= scan_interval:
		_scan_timer = 0.0
		_scan_fotos()

	# Animatie voor elke kast
	for i in _kast_data.size():
		var data = _kast_data[i]
		var sprite: Sprite2D = data["sprite"]
		var border: Sprite2D = data["border"]
		var shadow: Sprite2D = data["shadow"]
		var container: Node2D = data["container"]
		var front_tex: Texture2D = data["front"]
		var back_tex: Texture2D = data["back"]
		var base_y: float = data["base_y"]
		var base_scale: float = data["base_scale"]

		var phase = _time + i * phase_offset

		# === 2.5D Rotatie met pauze + snelle flip ===
		var cycle = front_duration + back_duration + flip_duration * 2.0
		var local_t = fmod(phase, cycle)
		var squash: float = 1.0
		var is_front: bool = true

		if local_t < front_duration:
			squash = 1.0
			is_front = true
		elif local_t < front_duration + flip_duration:
			var flip_t = (local_t - front_duration) / flip_duration
			squash = cos(flip_t * PI)
			is_front = squash > 0
		elif local_t < front_duration + flip_duration + back_duration:
			squash = -1.0
			is_front = false
		else:
			var flip_t = (local_t - front_duration - flip_duration - back_duration) / flip_duration
			squash = cos(PI + flip_t * PI)
			is_front = squash > 0

		sprite.scale.x = absf(squash) * base_scale

		# Wissel texture
		if is_front:
			if sprite.texture != front_tex:
				sprite.texture = front_tex
		else:
			if sprite.texture != back_tex:
				sprite.texture = back_tex

		# === Lichte kanteling bij draaien ===
		var tilt_amount = 1.0 - absf(squash)  # Meer kanteling bij het draaien
		var tilt_dir = 1.0 if squash >= 0 else -1.0
		sprite.rotation = tilt_amount * deg_to_rad(tilt_angle) * tilt_dir

		# === Schaduw: breedte schaalt mee met rotatie ===
		if shadow:
			var orig_shadow_w = data["shadow_base_w"]
			shadow.scale.x = maxf(absf(squash), 0.3) * orig_shadow_w / 128.0


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

	# Check welke foto's nieuw zijn
	var new_files: Array[String] = []
	for path in latest:
		if not _current_files.has(path):
			new_files.append(path)

	_current_files = latest
	_update_grid(new_files)


func _update_grid(new_files: Array[String] = []) -> void:
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
		var is_new = new_files.has(path)

		var image = Image.new()
		var err = image.load(path)
		if err != OK:
			continue

		var img_w = image.get_width()
		var img_h = image.get_height()

		# Knip in twee helften
		@warning_ignore("integer_division")
		var half_w = img_w / 2

		var front_img = Image.create(half_w, img_h, false, image.get_format())
		front_img.blit_rect(image, Rect2i(0, 0, half_w, img_h), Vector2i(0, 0))
		var front_tex = ImageTexture.create_from_image(front_img)

		var back_img = Image.create(half_w, img_h, false, image.get_format())
		back_img.blit_rect(image, Rect2i(half_w, 0, half_w, img_h), Vector2i(0, 0))
		var back_tex = ImageTexture.create_from_image(back_img)

		# Container node
		var container = Node2D.new()
		var col = i % columns
		@warning_ignore("integer_division")
		var row = i / columns
		var grid_total_w = columns * cell_w + (columns - 1) * spacing
		var grid_total_h = rows * cell_h + (rows - 1) * spacing
		var grid_offset_x = (viewport_size.x - grid_total_w) / 2.0
		var grid_offset_y = (viewport_size.y - grid_total_h) / 2.0 + 30.0
		var pos_x = grid_offset_x + col * (cell_w + spacing) + cell_w / 2.0
		var pos_y = grid_offset_y + row * (cell_h + spacing) + cell_h / 2.0
		container.position = Vector2(pos_x, pos_y)
		add_child(container)
		_kast_nodes.append(container)

		# Schaal berekenen — groter
		var tex_w = float(half_w)
		var tex_h = float(img_h)
		var scale_factor = minf(cell_w / tex_w, cell_h / tex_h) * 1.2

		# Random positie offset
		var rand_offset = Vector2(randf_range(-10, 10), randf_range(-10, 10))
		container.position += rand_offset

		# Random rotatie
		var rand_rot = randf_range(-0.03, 0.03)

		# Schaduw: donkere ovaal, gepositioneerd relatief aan kast grootte
		var shadow_img = Image.create(128, 128, false, Image.FORMAT_RGBA8)
		for sx in 128:
			for sy in 128:
				var dx = (sx - 64.0) / 64.0
				var dy = (sy - 64.0) / 64.0
				var dist = dx * dx + dy * dy
				if dist <= 1.0:
					var alpha = (1.0 - sqrt(dist)) * shadow_opacity
					shadow_img.set_pixel(sx, sy, Color(0, 0, 0, alpha))
		var shadow_tex = ImageTexture.create_from_image(shadow_img)
		var shadow = Sprite2D.new()
		shadow.texture = shadow_tex
		shadow.centered = true
		var kast_pixel_w = tex_w * scale_factor
		var kast_pixel_h = tex_h * scale_factor
		shadow.scale = Vector2(kast_pixel_w * 1.2 / 128.0, 40.0 / 128.0)
		shadow.position = Vector2(0, kast_pixel_h * 0.5 + shadow_y_offset)
		container.add_child(shadow)
		# Schaduw moet VOOR de kast sprite getekend worden (als eerste child)

		# Kast sprite met witte outline shader
		var sprite = Sprite2D.new()
		sprite.texture = front_tex
		sprite.centered = true
		sprite.scale = Vector2(scale_factor, scale_factor)
		sprite.rotation = rand_rot
		var outline_shader = preload("res://outline.gdshader")
		var mat = ShaderMaterial.new()
		mat.shader = outline_shader
		mat.set_shader_parameter("outline_width", 20.0)
		mat.set_shader_parameter("outline_color", Color.WHITE)
		sprite.material = mat
		container.add_child(sprite)
		var border: Sprite2D = null  # Niet meer nodig, shader doet de outline

		_kast_data.append({
			"front": front_tex,
			"back": back_tex,
			"sprite": sprite,
			"border": border,
			"shadow": shadow,
			"shadow_base_w": tex_w * scale_factor * 0.8,
			"container": container,
			"base_y": pos_y,
			"base_scale": scale_factor,
		})

		# Animatie: fade-in of fly-in voor nieuwe foto's
		if is_new:
			# Nieuwe foto vliegt van rechts het grid in
			container.position.x += viewport_size.x
			container.modulate.a = 0.0
			var tween = create_tween().set_parallel()
			tween.tween_property(container, "position:x", pos_x, 0.6) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			tween.tween_property(container, "modulate:a", 1.0, 0.3)
		else:
			# Bestaande foto faded in
			container.modulate.a = 0.0
			var tween = create_tween()
			tween.tween_property(container, "modulate:a", 1.0, 0.4).set_delay(i * 0.05)


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
