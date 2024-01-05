extends Sprite


# Declare member variables here. Examples:
# var a = 2
# var b = "text"
var duration = null
var pitch = null
var start_time = null

func setup(next_note):
	self.start_time = next_note.start_time
	self.pitch = next_note.pitch
	self.duration = next_note.duration
	self.scale = Vector2(0.2, 0.2)
	self.set_texture_by_duration(self.duration)
	# Decide which image to use for sprite by dividing duration by
	# the smallest unit (the 16th note duration
	self.position_note_and_incidental(self.pitch, 0)
		

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.
	

func position_note_and_incidental(pitch, x_pos):
	var rootNode = get_tree().current_scene
	var y = rootNode.position_note_on_staff(pitch)
	self.position = Vector2(x_pos, y)
	#for child in sprite.get_children():
	#	sprite.remove_child(child)
	var incidental = rootNode.get_sharpness_or_flatness(pitch)
	if incidental == "#" or incidental == "b":
		#print("{x} is {y}".format({"x": key_number_to_note(pitch), "y": incidental}))
		var decorator = $Incidental
		if incidental == "#":
			decorator.texture = load("res://note_images/sharp.png")
			decorator.scale = Vector2(0.3, 0.3)
		else:
			decorator.texture = load("res://note_images/flat.png")
			decorator.scale = Vector2(0.2, 0.2)
					
		decorator.position = Vector2(-110, 90)
		


func set_texture_by_duration(duration):
	var rootNode = get_tree().current_scene
	var relative_duration = float(duration) / float(rootNode.sixteenth_note_duration)
	#print("Note relative duration is {d}".format({"d": relative_duration}))
	var dotted = false
	if relative_duration < 1.1:
		self.texture = load("res://note_images/sixteenth.png")
	elif relative_duration < 1.6:
		dotted = true
		self.texture = load("res://note_images/sixteenth.png")
	elif relative_duration < 2.1:
		self.texture = load("res://note_images/eigth.png")
	elif relative_duration < 3.1:
		dotted = true
		self.texture = load("res://note_images/eigth.png")
	elif relative_duration < 4.1:
		self.texture = load("res://note_images/quarter.png")
		# What do we do with like a 5.0? quarter-plus-sixteenth?
	elif relative_duration < 6.1:
		dotted = true
		self.texture = load("res://note_images/quarter.png")
	elif relative_duration < 8.1:
		self.texture = load("res://note_images/half.png")
	else:
		dotted = true
		self.texture = load("res://note_images/half.png")
	if dotted:

		var dot = $Dot
		dot.texture = load("res://note_images/dot.png")
		dot.position = Vector2(100, 150)
		dot.scale = Vector2(6.0, 6.0) # undo parent scaling of 0.2
		
	var duration_line = $DurationLine	
	duration_line.scale = Vector2(5, 5) # TO undo the scaling of 0.2, 0.2 on the parent note
	duration_line.add_point(Vector2.ZERO)
	duration_line.add_point(Vector2(duration * rootNode.space_factor, 0))
	# TODO should the tempo should affect this length?
	duration_line.set_default_color(Color.crimson)
	duration_line.width = 4
	duration_line.visible = false
# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass

func scroll_position(time_progress_in_song):
	var rootNode = get_tree().current_scene
	self.position.x = rootNode.the_now_line  + rootNode.space_factor * (self.start_time - time_progress_in_song)
	
