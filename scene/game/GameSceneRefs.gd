extends RefCounted
class_name GameSceneRefs

var view_root: Node = null
var info_label: Label = null
var loading_overlay: Control = null
var loading_status: Label = null
var loading_progress: ProgressBar = null
var bottom_category_bar: BottomCategoryBar = null
var system_panel: PanelContainer = null
var empire_status_label: Label = null
var change_empire_button: Button = null
var system_preview_image: TextureRect = null
var system_snapshot_viewport: SubViewport = null
var system_snapshot_preview: Node = null
var selected_system_title: Label = null
var selected_system_meta: Label = null
var claim_system_button: Button = null
var clear_owner_button: Button = null
var survey_system_button: Button = null
var empire_picker_overlay: Control = null
var empire_picker_list: ItemList = null
var select_empire_button: Button = null
var cancel_empire_picker_button: Button = null
var debug_spawn_toggle_button: Button = null
var debug_reveal_toggle_button: Button = null
var debug_spawn_panel: PanelContainer = null
var galaxy_hud: Control = null


static func from_root(root: Node) -> GameSceneRefs:
	var refs := GameSceneRefs.new()
	refs.view_root = root.get_node("ViewRoot")
	refs.info_label = root.get_node("CanvasLayer/InfoLabel") as Label
	refs.loading_overlay = root.get_node("CanvasLayer/LoadingOverlay") as Control
	refs.loading_status = root.get_node("CanvasLayer/LoadingOverlay/Panel/MarginContainer/VBoxContainer/LoadingStatus") as Label
	refs.loading_progress = root.get_node("CanvasLayer/LoadingOverlay/Panel/MarginContainer/VBoxContainer/LoadingProgress") as ProgressBar
	refs.bottom_category_bar = root.get_node("CanvasLayer/BottomCategoryBar") as BottomCategoryBar
	refs.system_panel = root.get_node("CanvasLayer/SystemPanel") as PanelContainer
	refs.empire_status_label = root.get_node("CanvasLayer/SystemPanel/MarginContainer/VBoxContainer/EmpireStatusLabel") as Label
	refs.change_empire_button = root.get_node("CanvasLayer/SystemPanel/MarginContainer/VBoxContainer/ChangeEmpireButton") as Button
	refs.system_preview_image = root.get_node("CanvasLayer/SystemPanel/MarginContainer/VBoxContainer/SystemPreviewImage") as TextureRect
	refs.system_snapshot_viewport = root.get_node("CanvasLayer/SystemPreviewSnapshotViewport") as SubViewport
	refs.system_snapshot_preview = root.get_node("CanvasLayer/SystemPreviewSnapshotViewport/StarSystemPreview")
	refs.selected_system_title = root.get_node("CanvasLayer/SystemPanel/MarginContainer/VBoxContainer/SelectedSystemTitle") as Label
	refs.selected_system_meta = root.get_node("CanvasLayer/SystemPanel/MarginContainer/VBoxContainer/SelectedSystemMeta") as Label
	refs.claim_system_button = root.get_node("CanvasLayer/SystemPanel/MarginContainer/VBoxContainer/ClaimSystemButton") as Button
	refs.clear_owner_button = root.get_node("CanvasLayer/SystemPanel/MarginContainer/VBoxContainer/ClearOwnerButton") as Button
	refs.survey_system_button = root.get_node("CanvasLayer/SystemPanel/MarginContainer/VBoxContainer/SurveySystemButton") as Button
	refs.empire_picker_overlay = root.get_node("CanvasLayer/EmpirePickerOverlay") as Control
	refs.empire_picker_list = root.get_node("CanvasLayer/EmpirePickerOverlay/Panel/MarginContainer/VBoxContainer/EmpirePickerList") as ItemList
	refs.select_empire_button = root.get_node("CanvasLayer/EmpirePickerOverlay/Panel/MarginContainer/VBoxContainer/ButtonRow/SelectEmpireButton") as Button
	refs.cancel_empire_picker_button = root.get_node("CanvasLayer/EmpirePickerOverlay/Panel/MarginContainer/VBoxContainer/ButtonRow/CancelEmpirePickerButton") as Button
	refs.debug_spawn_toggle_button = root.get_node("CanvasLayer/DebugSpawnToggleButton") as Button
	refs.debug_reveal_toggle_button = root.get_node("CanvasLayer/DebugRevealToggleButton") as Button
	refs.debug_spawn_panel = root.get_node("CanvasLayer/DebugSpawnPanel") as PanelContainer
	refs.galaxy_hud = root.get_node("CanvasLayer/GalaxyHud") as Control
	return refs
