extends Node
# CurrencySystem — handles earning, spending, and UI updates for currency.
# Add to Project > Autoloads as "CurrencySystem"

signal currency_changed(new_amount: int)

func earn(amount: int) -> void:
	PlayerData.add_currency(amount)
	currency_changed.emit(PlayerData.currency)

func spend(amount: int) -> bool:
	if PlayerData.currency >= amount:
		PlayerData.currency -= amount
		currency_changed.emit(PlayerData.currency)
		return true
	return false
