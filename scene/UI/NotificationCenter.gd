extends Control
class_name NotificationCenter

## Reusable right-edge notification stack.
## Notifications carry an importance level (1-4): lower levels auto-expire
## after a configurable real-time lifetime, level 4 stays until dismissed.
## Each card can be dismissed, can embed a custom content Control, and can
## carry an action payload that is emitted when the card is clicked — the
## host decides what to do with it (open a system, select an entity, ...).
## The component has no game dependencies and can be reused by any screen.

signal notification_activated(notification_id: String, action: Dictionary)
signal notification_dismissed(notification_id: String)

const IMPORTANCE_MIN := 1
const IMPORTANCE_MAX := 4
const MAX_NOTIFICATIONS := 30
const PANEL_WIDTH := 330.0
const COLOR_CARD := Color(0.03, 0.045, 0.058, 0.94)
const COLOR_CARD_BORDER := Color(0.4, 0.58, 0.68, 0.45)
const COLOR_TEXT := Color(0.96, 0.98, 1.0, 0.96)
const COLOR_MUTED := Color(0.76, 0.84, 0.9, 0.78)
const IMPORTANCE_COLORS := {
	1: Color(0.52, 0.66, 0.76, 0.9),
	2: Color(0.42, 0.78, 0.56, 0.95),
	3: Color(0.95, 0.74, 0.32, 0.95),
	4: Color(1.0, 0.4, 0.32, 0.98),
}

var _lifetimes_by_importance: Dictionary = {
	1: 8.0,
	2: 15.0,
	3: 30.0,
	4: 0.0,
}
var _next_notification_id: int = 1
var _cards_by_id: Dictionary = {}
var _stack: VBoxContainer = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_left = -PANEL_WIDTH - 14.0
	offset_right = -14.0
	offset_top = 96.0
	offset_bottom = -110.0

	var scroll := ScrollContainer.new()
	scroll.name = "NotificationScroll"
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(scroll)

	_stack = VBoxContainer.new()
	_stack.name = "NotificationStack"
	_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stack.add_theme_constant_override("separation", 8)
	scroll.add_child(_stack)


func _process(delta: float) -> void:
	if _cards_by_id.is_empty():
		return
	for notification_id in _cards_by_id.keys().duplicate():
		var card: Dictionary = _cards_by_id.get(notification_id, {})
		var remaining := float(card.get("remaining_seconds", 0.0))
		if remaining <= 0.0:
			continue
		remaining -= delta
		if remaining <= 0.0:
			_remove_card(str(notification_id), false)
		else:
			card["remaining_seconds"] = remaining
			_cards_by_id[notification_id] = card
			var root := card.get("root", null) as PanelContainer
			var lifetime := float(card.get("lifetime_seconds", 0.0))
			if root != null and lifetime > 0.0 and remaining < 2.0:
				root.modulate = Color(1.0, 1.0, 1.0, clampf(remaining / 2.0, 0.15, 1.0))


## Configure how long each importance level stays visible (seconds).
## A value of 0 (or below) means the level never auto-expires.
func set_importance_lifetimes(lifetimes: Dictionary) -> void:
	for importance_variant in lifetimes.keys():
		var importance := clampi(int(importance_variant), IMPORTANCE_MIN, IMPORTANCE_MAX)
		_lifetimes_by_importance[importance] = maxf(float(lifetimes.get(importance_variant, 0.0)), 0.0)


## Post a notification. Supported data keys:
##   title: String (required), message: String, importance: int 1-4,
##   action: Dictionary (emitted on click; empty = card is not clickable),
##   custom_content: Control (embedded below the message),
##   lifetime_seconds: float (overrides the importance default),
##   notification_id: String (optional explicit id).
## Returns the notification id, or "" if the data was invalid.
func post_notification(data: Dictionary) -> String:
	if _stack == null or data.is_empty():
		return ""
	var title := str(data.get("title", "")).strip_edges()
	if title.is_empty():
		return ""

	var notification_id := str(data.get("notification_id", "")).strip_edges()
	if notification_id.is_empty():
		notification_id = "notification_%04d" % _next_notification_id
		_next_notification_id += 1
	if _cards_by_id.has(notification_id):
		return ""

	var importance := clampi(int(data.get("importance", IMPORTANCE_MIN)), IMPORTANCE_MIN, IMPORTANCE_MAX)
	var lifetime := float(data.get("lifetime_seconds", _lifetimes_by_importance.get(importance, 0.0)))
	var action_variant: Variant = data.get("action", {})
	var action: Dictionary = action_variant.duplicate(true) if action_variant is Dictionary else {}

	var root := _build_card(notification_id, title, str(data.get("message", "")), importance, action, data.get("custom_content", null))
	_stack.add_child(root)
	_stack.move_child(root, 0)

	_cards_by_id[notification_id] = {
		"root": root,
		"importance": importance,
		"action": action,
		"lifetime_seconds": lifetime,
		"remaining_seconds": lifetime,
	}
	_enforce_capacity()
	return notification_id


func dismiss_notification(notification_id: String) -> bool:
	if not _cards_by_id.has(notification_id):
		return false
	_remove_card(notification_id, true)
	return true


func clear_notifications() -> void:
	for notification_id in _cards_by_id.keys().duplicate():
		_remove_card(str(notification_id), false)


func get_notification_count() -> int:
	return _cards_by_id.size()


func has_notification(notification_id: String) -> bool:
	return _cards_by_id.has(notification_id)


func get_notification_importance(notification_id: String) -> int:
	var card: Dictionary = _cards_by_id.get(notification_id, {})
	return int(card.get("importance", 0))


func _build_card(
	notification_id: String,
	title: String,
	message: String,
	importance: int,
	action: Dictionary,
	custom_content_variant: Variant
) -> PanelContainer:
	var root := PanelContainer.new()
	root.name = "Notification_%s" % notification_id
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_CARD
	style.border_color = COLOR_CARD_BORDER
	style.set_border_width_all(1)
	style.border_width_left = 4
	style.border_color = IMPORTANCE_COLORS.get(importance, COLOR_CARD_BORDER)
	style.set_corner_radius_all(5)
	root.add_theme_stylebox_override("panel", style)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.tooltip_text = "Klicken zum Oeffnen" if not action.is_empty() else ""
	root.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_card_activated(notification_id)
	)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	root.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	column.add_child(header)

	var title_label := Label.new()
	title_label.name = "NotificationTitle"
	title_label.text = title
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", COLOR_TEXT)
	header.add_child(title_label)

	var close_button := Button.new()
	close_button.name = "NotificationCloseButton"
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(24.0, 22.0)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(func() -> void:
		_remove_card(notification_id, true)
	)
	header.add_child(close_button)

	if not message.is_empty():
		var message_label := Label.new()
		message_label.name = "NotificationMessage"
		message_label.text = message
		message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		message_label.add_theme_font_size_override("font_size", 12)
		message_label.add_theme_color_override("font_color", COLOR_MUTED)
		column.add_child(message_label)

	if custom_content_variant is Control:
		var custom_content := custom_content_variant as Control
		custom_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_child(custom_content)

	return root


func _on_card_activated(notification_id: String) -> void:
	var card: Dictionary = _cards_by_id.get(notification_id, {})
	if card.is_empty():
		return
	var action: Dictionary = card.get("action", {})
	if action.is_empty():
		return
	notification_activated.emit(notification_id, action.duplicate(true))
	_remove_card(notification_id, false)


func _remove_card(notification_id: String, emit_dismissed: bool) -> void:
	var card: Dictionary = _cards_by_id.get(notification_id, {})
	if card.is_empty():
		return
	_cards_by_id.erase(notification_id)
	var root := card.get("root", null) as PanelContainer
	if root != null:
		root.queue_free()
	if emit_dismissed:
		notification_dismissed.emit(notification_id)


func _enforce_capacity() -> void:
	if _cards_by_id.size() <= MAX_NOTIFICATIONS:
		return
	# Drop the oldest non-persistent card first; fall back to the oldest card.
	var oldest_id := ""
	var oldest_persistent_id := ""
	for child_index in range(_stack.get_child_count() - 1, -1, -1):
		var child := _stack.get_child(child_index)
		var child_id := str(child.name).trim_prefix("Notification_")
		if not _cards_by_id.has(child_id):
			continue
		var card: Dictionary = _cards_by_id[child_id]
		if float(card.get("lifetime_seconds", 0.0)) > 0.0:
			oldest_id = child_id
			break
		if oldest_persistent_id.is_empty():
			oldest_persistent_id = child_id
	if oldest_id.is_empty():
		oldest_id = oldest_persistent_id
	if not oldest_id.is_empty():
		_remove_card(oldest_id, false)
