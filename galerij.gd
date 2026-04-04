@tool
extends Node2D

## Galerij: toont de laatste foto's van bezoekers op het wandscherm.
## Scant een map voor PNG bestanden en toont de nieuwste in een grid.

@export_group("Fotos")
## Map waar foto's worden opgeslagen (absoluut pad)
@export var fotos_path: String = ""
## Aantal foto's dat getoond wordt
@export var max_fotos: int = 8
## Hoe vaak de map gescand wordt (seconden)
@export var scan_interval: float = 3.0

@export_group("Layout")
## Aantal kolommen in het grid
@export var columns: int = 2
## Ruimte tussen foto's
@export var spacing: float = 30.0
## Marge rond het grid
@export var margin: float = 50.0

@onready var _background: TextureRect = $Background

var _foto_nodes: Array[TextureRect] = []
var _current_files: Array[String] = []
var _scan_timer: float = 0.0
var _grid_container: Node2D = null


func _ready() -> void:
	_resize_background()
	if Engine.is_editor_hint():
		return
	get_tree().root.size_changed.connect(_resize_background)

	# Bepaal fotos pad automatisch als niet ingesteld
	if fotos_path.is_empty():
		fotos_path = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP) + "/fotos"

	# Maak de fotos map aan als die niet bestaat
	if not DirAccess.dir_exists_absolute(fotos_path):
		DirAccess.make_dir_recursive_absolute(fotos_path)

	_grid_container = Node2D.new()
	add_child(_grid_container)

	_scan_fotos()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_scan_timer += delta
	if _scan_timer >= scan_interval:
		_scan_timer = 0.0
		_scan_fotos()


func _scan_fotos() -> void:
	## Scan de fotos map voor PNG bestanden, toon de nieuwste
	var dir = DirAccess.open(fotos_path)
	if not dir:
		return

	# Verzamel alle PNG bestanden met hun modificatietijd
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

	# Sorteer op tijd (nieuwste eerst)
	files.sort_custom(func(a, b): return a["time"] > b["time"])

	# Neem de laatste max_fotos
	var latest: Array[String] = []
	for i in mini(files.size(), max_fotos):
		latest.append(files[i]["path"])

	# Check of er iets veranderd is
	if latest == _current_files:
		return

	_current_files = latest
	_update_grid()


func _update_grid() -> void:
	## Herbouw het grid met de huidige foto's
	# Verwijder oude nodes
	for node in _foto_nodes:
		node.queue_free()
	_foto_nodes.clear()

	if _current_files.is_empty():
		return

	# Bereken grid dimensies
	var viewport_size = get_viewport_rect().size if not Engine.is_editor_hint() else Vector2(1080, 1920)
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

		var tex = ImageTexture.create_from_image(image)

		var foto_rect = TextureRect.new()
		foto_rect.texture = tex
		foto_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		foto_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		foto_rect.size = Vector2(cell_w, cell_h)

		# Positie in grid
		var col = i % columns
		var row = i / columns
		foto_rect.position = Vector2(
			margin + col * (cell_w + spacing),
			margin + row * (cell_h + spacing)
		)

		# Fade-in animatie voor nieuwe foto's
		foto_rect.modulate.a = 0.0
		_grid_container.add_child(foto_rect)
		_foto_nodes.append(foto_rect)

		var tween = create_tween()
		tween.tween_property(foto_rect, "modulate:a", 1.0, 0.5).set_delay(i * 0.1)


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
