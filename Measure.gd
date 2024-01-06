extends Node2D


var lyrics = ""
var chord_symbol = ""
var start_time = 0

func set_chord_name(chord_name):
	if chord_name == null:
		self.chord_symbol = ""
	else:
		self.chord_symbol = chord_name
	$ChordLabel.text = self.chord_symbol
	$ChordLabel.scale = Vector2(2.0, 2.0)

func setup(data_record):
	self.start_time = data_record.start_time
	self.lyrics = data_record.lyric_text
	$LyricLabel.text = self.lyrics
	$LyricLabel.scale = Vector2(2.0, 2.0)
	
func scroll_position(time_progress_in_song):
	var rootNode = get_tree().current_scene
	self.position.x = rootNode.the_now_line  + rootNode.space_factor * (self.start_time - time_progress_in_song)


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.
