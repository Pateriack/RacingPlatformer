extends CharacterBody3D

@export var current_path: Path3D
@export var speed: float = 5
@export var acceleration: float = 1
@export var damping: float = 1
@export var rotation_speed: float = 20
@export var rotation_center_threshold: float = 0.2
@export var bounce_height: float = 0.1
@export var bounce_stationary_multiplier: float = 0.2
@export var bounce_frequency: float = 1
@export var bounce_squish_vertical = 0.5
@export var bounce_squish_horizontal = 1.2
@export var bounce_squish_power = 2
@export var jump_impulse = 20
@export var fall_squish_amount = 0.7
@export var fall_squish_max_speed = 5
@export var grounded_threshold = 0.05
@export var gravity = 1.0
@export var terminal_velocity = 5.0
@export var path_detect_ray_length = 10
@export var path_detect_ray_start_offset = 0.05
@export var path_closest_step_size = 0.01
@export var down_squish_vertical = 0.25
@export var down_squish_horizontal = 1.5
@export var down_squish_time = 0.1
@export var landing_down_squish_amount = 0.5
@export var landing_down_squish_time = 0.05
@export var drop_through_ignore_path_time = 0.1
@export var fall_recovery_time = 5.0
@export var fall_recovery_safety_threshold = 0.5

var path_follow: PathFollow3D
var previous_grounded_path: Path3D
var previous_grounded_progress: float
var current_speed: float = 0
var current_bounce: float = 0
var input_direction: float = 0
var target_speed: float = 0
var bounce_time = 0
var y_velocity = 0
var was_grounded = true
var down_squish_amount = 0.0
var down_held = false
var ignore_path_timer = 0.0
var recovering = false

func _ready():
	path_follow = $PathFollow
	path_follow.loop = false
	if current_path != null:
		switch_current_path(current_path)
		path_follow.progress = 0.5
		position = path_follow.position

func _physics_process(delta):
	if recovering:
		return
	
	bounce_time += delta
	handle_input()
	handle_movement(delta)
	handle_rotation(delta)
	handle_bouncing(delta)
	
	if ignore_path_timer <= 0:
		ignore_path_timer = 0
		check_for_path_below()
	else:
		ignore_path_timer -= delta
	
	if is_grounded() && !was_grounded:
		var squish_amount = clamp(-y_velocity / terminal_velocity, 0, 1)
		var tween = get_tree().create_tween()
		tween.tween_property(self, "down_squish_amount", squish_amount * landing_down_squish_amount, landing_down_squish_time)
		tween.chain().tween_property(self, "down_squish_amount", 0, landing_down_squish_time * 2)
		bounce_time = 0
		y_velocity = 0
	was_grounded = is_grounded()
	
func handle_input():
	input_direction = 0
	if Input.is_action_pressed("Right"):
		input_direction += 1
	if Input.is_action_pressed("Left"):
		input_direction -= 1
		
	if Input.is_action_just_pressed("Down"):
		down_held = true
	elif Input.is_action_just_released("Down"):
		down_held = false
		bounce_time = 0
		if is_grounded():
			var down_tween = get_tree().create_tween()
			down_tween.tween_property(self, "down_squish_amount", 0, down_squish_time)
		
		
	if Input.is_action_pressed("Down") && is_grounded():
		var down_tween = get_tree().create_tween()
		down_tween.tween_property(self, "down_squish_amount", 1, down_squish_time)
		
	if Input.is_action_just_pressed("Jump") && is_grounded():
		if down_held:
			ignore_path_timer = drop_through_ignore_path_time
			switch_current_path(null)
			var down_tween = get_tree().create_tween()
			down_tween.tween_property(self, "down_squish_amount", 0, down_squish_time)
		else:
			y_velocity = jump_impulse
			
	if Input.is_action_just_pressed("Grapple"):
		print("start grapple")
	elif Input.is_action_just_released("Grapple"):
		print("end grapple")
	
func handle_movement(delta):
	target_speed = 0 if down_held && is_grounded() else input_direction * speed
	var accel = acceleration if target_speed != 0 else damping
	current_speed = current_speed + (target_speed - current_speed) * delta * accel
	
	if current_path != null:
		path_follow.progress += current_speed * delta
	
		if path_follow.progress_ratio != 0 && path_follow.progress_ratio != 1:
			handle_path_movement(delta)
			return
			
		switch_current_path(null)
			
	handle_off_path_movement(delta)
	
func handle_off_path_movement(delta):
	var new_position = position + basis.x * current_speed * delta
	
	if y_velocity > -terminal_velocity:
		y_velocity -= gravity * delta
	else:
		y_velocity += gravity * delta
		
	new_position.y += y_velocity * delta
	
	position = new_position
	
	
func handle_path_movement(delta):
	var new_position = path_follow.position
	
	var path_y = new_position.y
	
	if was_grounded:
		position = new_position
	
	if is_grounded():
		previous_grounded_path = current_path
		previous_grounded_progress = path_follow.progress
	else:
		if y_velocity > -terminal_velocity:
			y_velocity -= gravity * delta
		else:
			y_velocity += gravity * delta
		new_position.y = max(position.y + y_velocity * delta, path_y)
		
	
	position = new_position
	
func handle_rotation(delta):
	if current_path != null:
		var new_rotation = path_follow.global_rotation
		new_rotation.y += deg_to_rad(90)
		global_rotation = new_rotation
	
	var target_model_rotation = 0
	
	if (target_speed > 0 && is_grounded()) || (target_speed == 0  && current_speed > rotation_center_threshold) || (!is_grounded() && current_speed > rotation_center_threshold):
		target_model_rotation = 90
	elif (target_speed < 0 && is_grounded()) || (target_speed == 0 && current_speed < -rotation_center_threshold) || (!is_grounded() && current_speed < -rotation_center_threshold):
		target_model_rotation = -90
		
	var current_model_rotation = rad_to_deg($Smoothing/Model.rotation.y)
	var new_model_rotation = deg_to_rad(current_model_rotation + (target_model_rotation - current_model_rotation) * delta * rotation_speed)
	$Smoothing/Model.rotation.y = new_model_rotation
	
func handle_bouncing(delta):
	var relative_speed = abs(current_speed) / speed
	var bounce_amount = bounce_stationary_multiplier + (1 - bounce_stationary_multiplier) * relative_speed if is_grounded() && down_squish_amount <= 0.05 else 0
	
	current_bounce = abs(sin(bounce_time * bounce_frequency))
	$Smoothing/Model.position.y = current_bounce * bounce_height * bounce_amount

	var bounce_squish_amount =  pow(1 - (abs(sin(bounce_time * bounce_frequency))), bounce_squish_power) * bounce_amount
	var air_squish = fall_squish_amount * clamp(-y_velocity, -fall_squish_max_speed, fall_squish_max_speed) / fall_squish_max_speed
	var squish_amount = bounce_squish_amount if is_grounded() else air_squish
	var horizontal_scale = 1 + (bounce_squish_horizontal - 1) * squish_amount
	var vertical_scale = 1 + (bounce_squish_vertical - 1) * squish_amount
	if down_squish_amount > 0.05:
		horizontal_scale = 1 + (down_squish_horizontal - 1) * down_squish_amount
		vertical_scale = 1 + (down_squish_vertical - 1) * down_squish_amount
	$Smoothing/Model.scale = Vector3(horizontal_scale, vertical_scale, horizontal_scale)

func is_grounded():
	if current_path == null:
		return false
	var current_y = position.y
	var path_y = path_follow.position.y
	return abs(current_y - path_y) < grounded_threshold && y_velocity <= 0
	
func check_for_path_below():
	var space_state = get_world_3d().direct_space_state
	var from = position + Vector3.UP * path_detect_ray_start_offset
	var to = position + Vector3.DOWN * path_detect_ray_length
	var query = PhysicsRayQueryParameters3D.create(from, to, 2)
	var result = space_state.intersect_ray(query)
	if result:
		var path_detected = result.collider.get_parent()
		if current_path != path_detected:
			switch_current_path(path_detected)
	
func switch_current_path(path: Path3D):
	path_follow.get_parent().remove_child(path_follow)
	if path != null:
		path.add_child(path_follow)
		path_follow.rotation_mode = PathFollow3D.ROTATION_Y
		var closest_offset = get_closest_offset(path)
		path_follow.progress = closest_offset	
		
	else:
		add_child(path_follow)	
	current_path = path
	
func get_closest_offset(path: Path3D):
	if path == null:
		return 0
		
	var closest_offset = path.curve.get_closest_offset(position)
	var closest_dist = get_horizontal_dist_squared(position, path.curve.sample_baked(closest_offset))
	
	while true:
		var next_offset = closest_offset + path_closest_step_size
		if next_offset > path.curve.get_baked_length():
			break
		var horizontal_dist = get_horizontal_dist_squared(position, path.curve.sample_baked(next_offset))
		if (closest_dist < horizontal_dist):
			break
		closest_offset = next_offset
		closest_dist = horizontal_dist
		
	while true:
		var next_offset = closest_offset - path_closest_step_size
		if next_offset < 0:
			break
		var horizontal_dist = get_horizontal_dist_squared(position, path.curve.sample_baked(next_offset))
		if (closest_dist < horizontal_dist):
			break
		closest_offset = next_offset
		closest_dist = horizontal_dist
		
	return closest_offset
		
func get_horizontal_dist_squared(a: Vector3, b: Vector3):
	var a2 = Vector2(a.x, a.z)
	var b2 = Vector2(b.x, b.z)
	return a2.distance_squared_to(b2)

func _on_fall_zone_body_entered(body):
	current_speed = 0
	recovering = true
	switch_current_path(previous_grounded_path)
	path_follow.progress = previous_grounded_progress
	if path_follow.progress < fall_recovery_safety_threshold:
		path_follow.progress = fall_recovery_safety_threshold
	elif path_follow.progress > current_path.curve.get_baked_length() - fall_recovery_safety_threshold:
		path_follow.progress = current_path.curve.get_baked_length() - fall_recovery_safety_threshold
	
	var tween = get_tree().create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position", path_follow.position, fall_recovery_time)
	tween.tween_property(self, "basis", path_follow.rotation, fall_recovery_time)
	tween.chain().tween_callback(self.on_recovery_finished)
	
func on_recovery_finished():
	recovering = false
