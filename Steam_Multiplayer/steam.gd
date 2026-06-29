# global.gd (Add this to your autoload/singleton)
extends Node

func _init():
	# Initialize Steam BEFORE anything else
	# Use 480 for testing, or your actual App ID
	OS.set_environment("SteamAppId", str(480))
	OS.set_environment("SteamGameId", str(480))

func _ready():
	# GodotSteam provides the `Steam` singleton. Until the extension is
	# installed, skip init so the project still boots for offline testing.
	if not Engine.has_singleton("Steam"):
		push_warning("SteamManager: GodotSteam not installed - Steam features disabled.")
		return

	# Initialize Steam
	var init_response: Dictionary = Steam.steamInitEx()
	print("Steam Init Response: ", init_response)
	
	# steamInitEx() reports success as STEAM_API_INIT_RESULT_OK (0); any other
	# status (1 = generic failure, 2 = no client, 3 = version mismatch) is an error.
	if init_response['status'] != Steam.STEAM_API_INIT_RESULT_OK:
		print("ERROR: Failed to initialize Steam!")
		print("Status: %s" % init_response['status'])
		print("Verbal: %s" % init_response['verbal'])
		return
	
	print("Steam initialized successfully!")
	print("Steam ID: %s" % Steam.getSteamID())
	print("Username: %s" % Steam.getPersonaName())
