extends Resource
# JobData — data resource for each job type.
class_name JobData

@export var job_id: String = ""
@export var display_name: String = ""
@export var scene: PackedScene = null
@export var base_pay: int = 50
@export var icon: Texture2D = null
