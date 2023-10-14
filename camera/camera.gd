extends Node3D

@export var follow_node: Node3D
@export var distance: float = 20
@export var angle: float = 20
@export var rotation_tween_duration: float = 1
@export var position_tween_duration: float = .3

func _process(_delta):
	$CameraRig/Camera.position.z = distance
	$CameraRig.rotation.x = deg_to_rad(-angle)
	
	var rotation_tween = get_tree().create_tween()
	rotation_tween.tween_property(self, "basis", follow_node.basis, rotation_tween_duration)
	
	var movement_tween = get_tree().create_tween()
	movement_tween.tween_property(self, "position", follow_node.position, position_tween_duration)
	
