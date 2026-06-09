extends CanvasLayer
# HUDController — manages the in-game HUD (currency, notifications).
# Attach to scenes/ui/hud/hud.tscn

@onready var currency_label: Label = $CurrencyLabel
@onready var notification_label: Label = $NotificationLabel

func _ready() -> void:
	CurrencySystem.currency_changed.connect(_on_currency_changed)
	_on_currency_changed(PlayerData.currency)

func _on_currency_changed(amount: int) -> void:
	currency_label.text = "$%d" % amount

func show_notification(text: String, duration: float = 2.5) -> void:
	notification_label.text = text
	notification_label.show()
	await get_tree().create_timer(duration).timeout
	notification_label.hide()
