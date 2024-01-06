extends Node2D


# Declare member variables here. Examples:
# var a = 2
# var b = "text"

#var chord_progression = ["C7", "C7", "C7", "C7", "F7", "F7", "C7", "C7", "G7", "F7", "C7", "G7"]
#var current_measure = 12


func key_number_to_note(midi_code):
	return ["c", "c#/db", "d", "d#/eb", "e", "f", "f#/gb", "g", "g#/ab", "a", "a#/bb", "b"][midi_code % 12]


func janky_join(arr: Array) -> String:
	var s = ""
	for i in arr:
		s += String(i.pitch) + "@" + String(i.start_time) + ", "
	return s
	
func indices_to_note_names(arr: Array) -> Array:
	var retval = []
	for x in arr:
		retval.append(key_number_to_note(x))
	return retval
	
	
var song_library = {
	# TODO song library also needs ways to store:
	#  - if one of the tracks needs an octave offset
	#  - what the key should be
	# TODO could we deduce they key signature from the notes data intead of
	# having to hard-code it?
	"Vampire Killer": {
		"filenames": ["vampire_killer/Staff-3.txt", "vampire_killer/Staff-4.txt"],
		"drum_tracks": ["vampire_killer/Staff-7.txt"],
		"octave_offsets": [0, 1],
		"sixteenth_note_duration": 120,
		"key": "#"	
	},
	"Firework": {
		"filenames": ["firework/Fireworks_channel_11.txt", "firework/Fireworks_channel_12.txt"],
		"drum_tracks": ["firework/Fireworks_channel_7.txt", "firework/Fireworks_channel_9.txt"],
		"octave_offsets": [1, 0],
		"sixteenth_note_duration": 120,
		"starting_time": 16 * 120,
		"key": "bbb"
	},
	"Psycho Killer": {
		"filenames": ["psycho_killer/piano.txt", "psycho_killer/bass.txt"],
		"drum_tracks": ["psycho_killer/drums.txt", "psycho_killer/drums_2.txt"],
		"octave_offsets": [1, 1],
		"sixteenth_note_duration": 96,
		"starting_time": 16 * 96,
		"key": "#",
		"lyrics": "psycho_killer/lyrics.txt"
	},
	"Super Mario Bros 2": {
		"filenames": ["super_mario_2/Piano.txt"],
		"drum_tracks": [],
		"octave_offsets": [0],
		"sixteenth_note_duration": 260,
		"key": "#"
	},
	"Deep Space Nine": {
		"filenames": ["deep_space_9/_2.txt", "deep_space_9_4.txt"],
		"drum_tracks": [],
		"octave_offsets": [0,0],
		"sixteenth_note_duration": 24, # !!
		"starting_time": 0,
		"key": "b",
		"default_tempo": 90,
	},
	#"Song of Storms": [],
	#"Epona": [],
	#"Moonlight Densetsu": [],
	#"Gilgamesh": [],
	#"Stairway to Heaven": [],
	#"Birdhouse in your Soul": [],
	#"Hava Nagilah": [],	
	#"Manzanitas": [],
	#"Carry On My Wayward Son": [],
	#"Bohemian Rhapsody": [],
	#"Crazy Train": [],
	"Creep": {
		"filenames": ["creep/_7.txt"],
		"drum_tracks": ["creep/_2.txt", "creep/_3.txt"],
		"sixteenth_note_duration": 48,
		"default_tempo": 250
	},
	#"FF6 Terra": []
}
	


var song_data = []
var accordion_samples = {}

var drum_data = []
var drum_samples = {}

var global_default_tempo = 500 # TODO add a control for this
var tempo_setting = 500
var the_now_line = 150
var window_width = 1500
# Determines how close a note needs to be to show up on screen
var space_factor = 0.5 # position of time to space
var song_key = "bbb" # TODO determine this song by song

 # This too. This is in units of "midi event ticks"
var sixteenth_note_duration = 120 # for Vampire Killer and Firework
var metronome_interval = 4 * sixteenth_note_duration / float(tempo_setting) # Some function of tempo_setting and
# sixteenth note duration. Should be in units of Seconds.

# Game state:
var time_progress_in_song = (-16) * sixteenth_note_duration
# 4 metronome clicks before first note
var oncoming_note_sprites = []
var measure_lines = []
var oncoming_measure_sprites = []
var currently_held_sprites = {} # key = midi code, value = sprite
var midi_keys_that_are_down = []
var score_hits = 0
var score_misses = 0

var paused = false

#var default_font = ThemeDB.fallback_font
#var default_font_size = ThemeDB.fallback_font_size
#var default_font = Control.new().get_font("font")
# Called when the node enters the scene tree for the first time.
func _ready():
	OS.open_midi_inputs() # Required for cross-platform reliability.

	print(OS.get_connected_midi_inputs()) # List available MIDI input sources (e.g. keyboard, controller).

	preload_accordion_samples()
	preload_drum_samples()
	
	$TargetLine.position = Vector2( the_now_line, 0 )
	
	var popup = $SongSelectMenuButton.get_popup()
	for key in song_library.keys():
		popup.add_item(key)
	popup.connect("id_pressed", Callable(self, "_on_song_selection"))
	# populate menu with
	#self.start_song("Firework")
	self.reset_to_beginning()
	
	
	
	
	
func reset_to_beginning():
	
	# Remove any children
	
	self.song_data = []
	self.time_progress_in_song = (-16) * sixteenth_note_duration
	# 4 metronome clicks before first note
	for sprite in self.oncoming_note_sprites:
		self.remove_child(sprite)
		sprite.queue_free()
	self.oncoming_note_sprites = []
	self.measure_lines = []
	for sprite in self.oncoming_measure_sprites:
		self.remove_child(sprite)
		sprite.queue_free()
	self.oncoming_measure_sprites = []
	
	self.score_hits = 0
	self.score_misses = 0
	$Timer.stop()

	
func start_song( song_title ):
	reset_to_beginning()
	
	var song_metadata = song_library[song_title]
	
	# There's also "res://song_data/firework_violin.txt", 1) # +1 octave
	if "key" in song_metadata.keys():
		self.song_key = song_metadata["key"]
	
	
	for idx in range(len(song_metadata["filenames"])):
		var offset
		if "octave_offsets" in song_metadata.keys():
			offset = song_metadata["octave_offsets"][idx]
		else:
			offset = 0
		var track_name = song_metadata["filenames"][idx]
		var new_track_data = self.load_one_midi_track(track_name, offset)
		self.song_data.append_array(new_track_data)
	
	self.song_data.sort_custom(Callable(self, "note_sorter"))
	
	
	for track_name in song_metadata["drum_tracks"]:
		var new_track_data = self.load_one_midi_track(track_name)
		self.drum_data.append_array(new_track_data)
	
	self.drum_data.sort_custom(Callable(self, "note_sorter"))
	
	if "sixteenth_note_duration" in song_metadata.keys():
		self.sixteenth_note_duration = song_metadata["sixteenth_note_duration"]
	
	if "starting_time" in song_metadata.keys():
		self.time_progress_in_song = song_metadata["starting_time"]
		
	if "default_tempo" in song_metadata.keys():
		self.tempo_setting = song_metadata["default_tempo"]
	else:
		self.tempo_setting = self.global_default_tempo
	
	var lyrics_by_measure = {}
	if "lyrics" in song_metadata.keys():
		print("Opening file")
		var lyric_file_path = "res://song_data/{f}".format({"f": song_metadata["lyrics"]})
		print(lyric_file_path)
		var file = FileAccess.open(lyric_file_path, FileAccess.READ)
		var content = file.get_as_text()
		var rows = content.split("\n")
		print("Row text from lyrics file")
		for row_text in rows:
			print(row_text)
			var row = row_text.split(",")
			if len(row) != 2:
				continue
			lyrics_by_measure[ int(row[0]) ] = row[1]
		file.close()
	
	# Create some measure lines:
	var measure_line_cumulative_time = 0
	var measure_number = 1
	self.measure_lines = []
	print("Lyrics by measure:")
	print(lyrics_by_measure)
	while (measure_line_cumulative_time < self.song_data[-1]["start_time"]):
		var lyrics_this_measure
		if measure_number in lyrics_by_measure.keys():
			lyrics_this_measure = lyrics_by_measure[measure_number]
		else:
			lyrics_this_measure = ""
		print("appended measure", measure_number, " with lyrics: ", lyrics_this_measure)
		self.measure_lines.append({
			"start_time": measure_line_cumulative_time,
			"lyric_text": lyrics_this_measure})
		measure_line_cumulative_time += 16 * self.sixteenth_note_duration
		measure_number += 1
	# Start metronome:
	self.metronome_interval = 4 * self.sixteenth_note_duration / float(tempo_setting)
	$Timer/MetronomePlayer.play()
	$Timer.set_wait_time(metronome_interval)
	
func preload_drum_samples():
	# https://soundprogramming.net/file-formats/general-midi-drum-note-numbers/
	# https://soundpacks.com/free-sound-packs/couch-kit-vol-1/
	var midi_code_to_filename = {
		35: "res://sfx/Kick/CKV1_Kick Medium 2.wav",
		36: "res://sfx/Kick/CKV1_Kick Medium 1.wav", # bass drum 1
		38: "res://sfx/Snare/CKV1_Snare Medium.wav",
		39: "res://sfx/Cross Stick/CKV1_Cross Stick 1.wav", #Should be Clap
		46: "res://sfx/HiHat/CKV1_HH Open Medium.wav", # open hi-hat
		42: "res://sfx/HiHat/CKV1_HH Closed Medium.wav", # closed hi-hat
		49: "res://sfx/HiHat/CKV1_HH Slush Foot Loud 1.wav", # crash cymbal 1
		# Not quite right!!!
		73: "res://sfx/Rim Click/CKV1_Rim Click 1.wav" # Should really be Short Guiro
	}
	for midi_code in midi_code_to_filename:
		var new_audio_player = AudioStreamPlayer.new()
		new_audio_player.set_stream(load(midi_code_to_filename[midi_code]))
		#new_audio_player.stream.set_loop(false)
		new_audio_player.set_volume_db(1.0)
		add_child(new_audio_player) # Audio won't play without this!
		self.drum_samples[midi_code] = new_audio_player
	# TODO share code with preload_accordion_samples

	
func preload_accordion_samples():
	
	var midi_code_to_filename = {
		33: "res://accordion_samples/a2.mp3",
		32: 	"res://accordion_samples/a_flat_2.mp3",
		31: "res://accordion_samples/g2.mp3",
		30: "res://accordion_samples/f_sharp_2.mp3",
		29: "res://accordion_samples/f2.mp3",
		28: "res://accordion_samples/e2.mp3",
		27: "res://accordion_samples/e_flat_2.mp3",
		26: "res://accordion_samples/d2.mp3",
		25: "res://accordion_samples/d_flat_2.mp3",
		24: 	"res://accordion_samples/c2.mp3",
		23: "res://accordion_samples/b_flat_2.mp3",
		22: "res://accordion_samples/b2.mp3",	
		84: "res://accordion_samples/c7.mp3",
		83: 	"res://accordion_samples/b6.mp3",
		82: "res://accordion_samples/b_flat_6.mp3",
		81: "res://accordion_samples/a6.mp3",
		80: "res://accordion_samples/g_sharp_6.mp3",
		79: "res://accordion_samples/g6.mp3",
		78: "res://accordion_samples/f_sharp_6.mp3",
		77: "res://accordion_samples/f6.mp3",
		76: "res://accordion_samples/e6.mp3",
		75: "res://accordion_samples/e_flat_6.mp3",
		74: 	"res://accordion_samples/d6.mp3",
		73: "res://accordion_samples/c_sharp_6.mp3",
		72: "res://accordion_samples/c6.mp3",
		71: 	"res://accordion_samples/b5.mp3",
		70: "res://accordion_samples/b_flat_5.mp3",
		69: "res://accordion_samples/a5.mp3",
		68: "res://accordion_samples/g_sharp_5.mp3",
		67: "res://accordion_samples/g5.mp3",
		66: "res://accordion_samples/f_sharp_5.mp3",
		65: "res://accordion_samples/f5.mp3",
		64: "res://accordion_samples/e5.mp3",
		63: "res://accordion_samples/e_flat_5.mp3",
		62: "res://accordion_samples/d5.mp3",
		61: "res://accordion_samples/c_sharp_5.mp3",
		60: "res://accordion_samples/c5.mp3",
		59: "res://accordion_samples/b4.mp3",
		58: "res://accordion_samples/b_flat4.mp3",
		57: "res://accordion_samples/a4.mp3",
		56: "res://accordion_samples/g_sharp_4.mp3",
		55: "res://accordion_samples/g4.mp3",
		54: "res://accordion_samples/f_sharp_4.mp3",
		53: "res://accordion_samples/f4.mp3",
		52: "res://accordion_samples/e4.mp3",
		51: "res://accordion_samples/e_flat_4.mp3",
		50: "res://accordion_samples/d4.mp3",
		49: "res://accordion_samples/c_sharp_4.mp3",
		48: "res://accordion_samples/c4.wav",
		47: "res://accordion_samples/b_flat_3.mp3",
		46: "res://accordion_samples/b3.mp3",
		45: "res://accordion_samples/a3.mp3",
		44: "res://accordion_samples/g_sharp_3.mp3",
		43: "res://accordion_samples/g3.mp3"
	}
	
	for midi_code in midi_code_to_filename:
		var new_audio_player = AudioStreamPlayer.new()
		new_audio_player.set_stream(load(midi_code_to_filename[midi_code]))
		new_audio_player.set_volume_db(1.0)
		add_child(new_audio_player) # Audio won't play without this!
		self.accordion_samples[midi_code] = new_audio_player
	
	
	
func note_sorter(a, b):
	return a["start_time"] < b["start_time"]

func load_one_midi_track(filename, octave_adjust=0):
	var path = "res://song_data/{f}".format({"f": filename})
	var file = FileAccess.open(path, FileAccess.READ)
	var content = file.get_as_text()
	# Is there a CSV parser in Godot or do i need to split and iterate?
	var rows = content.split("\n")
	var new_track_data = []
	print("Midi track contains {x} rows".format({"x": len(rows)}))
	for row_index in range(len(rows)):
		if row_index == 0:
			# header row
			continue
		var row = rows[row_index].split(",")
		#print("Before splitting, row is {x}".format({"x": rows[row_index]}))
		if len(row) != 3:
			continue
		#print("Row[0] is {x} and row[1] is {y}".format({"x": row[0], "y": row[1]}))
		new_track_data.append({"pitch": int(row[0]) + octave_adjust*12, 
						  "start_time": int(row[1]),
						  "duration": int(row[2]),
						  "scored": false})
	file.close()
	return new_track_data


func _process(_delta):
	if self.paused:
		return
	time_progress_in_song += self.tempo_setting * _delta
	
	var onscreen_notes = []
	var onscreen_measure_lines = []

	for note in song_data:
		if time_progress_in_song < note.start_time + note.duration and time_progress_in_song > note.start_time  - window_width:
			onscreen_notes.append(note)
			
	#print( janky_join(onscreen_notes) )
	
	for line_pos in self.measure_lines:
		if time_progress_in_song < line_pos.start_time+500 and time_progress_in_song > line_pos.start_time - window_width:
			onscreen_measure_lines.append(line_pos)
			
	# play the drums:
	for note in self.drum_data:
		if time_progress_in_song >= note.start_time - 5 and note.scored == false:
			if note.pitch in self.drum_samples.keys():
				self.drum_samples[note.pitch].play()
			note.scored = true
			break
			
	
	#print("Time progress is {t}. Onscreen notes should be...".format({"t": time_progress_in_song}))
	#for note in onscreen_notes:
	#	print("    {x} (at {y})".format({"x": note.pitch, "y": note.start_time}))
	while len(oncoming_note_sprites) > len(onscreen_notes):
		# remove passed ones from beginning of array (oldest notes
		# were ones that were pushed in first)
		var finished_note = oncoming_note_sprites.pop_front() # No such thing as Shift.
		for incidental in finished_note.get_children(): # TODO: not needed anymore?
			finished_note.remove_child(incidental)
			incidental.queue_free()
		remove_child(finished_note)
		finished_note.queue_free()
	while len(oncoming_note_sprites) < len(onscreen_notes):
		var next_note = onscreen_notes[ len(oncoming_note_sprites)]
		var newSprite = load("res://MusicNote.tscn").instantiate()
		add_child(newSprite)
		newSprite.setup(next_note)
		oncoming_note_sprites.append( newSprite )
		# Since its vertical position doesnt' change, we could
		# just calculate this once, now when intantiating new note
		# (Pretending it just came in from right side of screen)
		
	while len(oncoming_measure_sprites) > len(onscreen_measure_lines):
		var finished_line = oncoming_measure_sprites.pop_front()
		remove_child(finished_line)
		finished_line.queue_free()
	while len(oncoming_measure_sprites) < len(onscreen_measure_lines):
		var next_line_pos = onscreen_measure_lines[ len(oncoming_measure_sprites)]
		var newLine = load("res://Measure.tscn").instantiate()
		newLine.position = Vector2(800, 150)
		print("Instantiating measure")
		print(next_line_pos)
		newLine.setup(next_line_pos)
		add_child(newLine)
		var notes_in_measure = self.collect_notes(next_line_pos.start_time)
		newLine.set_chord_name(name_chord(notes_in_measure))
		oncoming_measure_sprites.append(newLine)

	for spr in oncoming_note_sprites:
		spr.scroll_position(time_progress_in_song)
	#sprite.draw_string(default_font, Vector2(64, 64), "Hello world")


		
	for spr in oncoming_measure_sprites:
		spr.scroll_position(time_progress_in_song)

	
	# check if any note has passed, un-played, beyond a certain threshold.
	for note in song_data:
		if note["scored"] == false and time_progress_in_song > note.start_time + 100 : # TODO move this to named constant
			note["scored"] = true
			$FeedbackLabel.text = "Missed!"
			score_misses += 1
			$ScoreLabel.text = "Hits: {hits} Misses: {misses}".format(
				{"hits": score_hits,
				"misses": score_misses}
			)
		
		

func position_note_on_staff(midi_code):
	# reference point: y = 200 for 57 (middle A)
	var row_spacing = 13 # determined empirically
	var octave_spacing = 92
	var octave_number = floor( midi_code / 12 ) - 1
	
	var octave_floor_y = 634 - octave_spacing * octave_number # treble clef
	if octave_number <= 3: # bass clef
		octave_floor_y += 18 # slight adjustment, empirically
		
	
	# this keyboard is mostly making octaves 4 and 5
	# 266 for c4, 174 for c5  ... 92 pixels per octave
	var note_name = key_number_to_note(midi_code)[0] # take first char to ignore sharps/flats for now
	if len(key_number_to_note(midi_code)) > 1:
		if self.song_key[0] == "#":
			note_name = key_number_to_note(midi_code -1)
		else:
			note_name = key_number_to_note(midi_code + 1)

	var note_letter_offset = ["c", "d", "e", "f", "g", "a", "b"].find(note_name)
	var y = octave_floor_y - note_letter_offset * row_spacing
	return y


func get_sharpness_or_flatness(midi_code):
	# returns "#", "b", or ""
	if len (key_number_to_note(midi_code)) > 1:
		if self.song_key[0] == "#":
			return "#"
		else:
			return "b"
	return ""


func _unhandled_input(event : InputEvent):

	if (event is InputEventMIDI): # When we get a MIDI input event...

		# Example of converting pitch to a keyboard key (not a musical key) within an octave.
		#var key_index = event.pitch % 12
		if event.message == 9:
			if not event.pitch in midi_keys_that_are_down:
				midi_keys_that_are_down.append(event.pitch)
				if event.pitch in self.accordion_samples.keys():
					self.accordion_samples[event.pitch].play()
				
				if not event.pitch in currently_held_sprites.keys():
					var new_sprite = load("res://MusicNote.tscn").instantiate()
					add_child(new_sprite)
					new_sprite.add_to_group("my_held_notes")
					new_sprite.setup({"start_time": null,
									  "duration": 4 * sixteenth_note_duration,
									  "pitch": event.pitch})
					# TODO: we could try extending duration as you hold the key?
					new_sprite.position.x = the_now_line
					currently_held_sprites[event.pitch] = new_sprite
				
				self.score_my_keystroke(event.pitch)
				$MyChordLabel.text = name_chord(self.midi_keys_that_are_down)
	
			#$RichTextLabel.text = "{pitch} pressed".format({"pitch": event.pitch})
		elif event.message == 8:
			if event.pitch in midi_keys_that_are_down:
				midi_keys_that_are_down.remove( midi_keys_that_are_down.find(event.pitch) )
				if event.pitch in self.accordion_samples.keys():
					self.accordion_samples[event.pitch].stop()
				$MyChordLabel.text = name_chord(self.midi_keys_that_are_down)
			if event.pitch in currently_held_sprites.keys():
				remove_child( currently_held_sprites[event.pitch] )
				currently_held_sprites[event.pitch].queue_free()
				currently_held_sprites.erase(event.pitch)
			# Bug here: there can be currently_held_sprites even
			# after all keys have been released and midi_keys_that_are_down
			# is empty. Also thare are more sprites on screen than there are
			# entries in currently_held_sprites. Both of these bugs combined
			# cause lots of notes to stick around clogging up the staff, so you
			# can't see what you're playing. Put all currently_held_sprites
			# in some kind of grouping and then whenever len(midi_keys_that_are_down)
			# is empty, clear that grouping?
	
		# Bug workaround: if I'm not holding any keys, delete all my
		# held note sprites. This is kind of a nuclear solution but it works.
		# note that iterating through and deleting all sprites in currently_held_sprites
		# does NOT work to fix this problem, suggesting that the underlying bug is sprites
		# getting created and somehow not held in currently_held_sprites.
		# (To check later: does queue_free() actually do what I think it does?
		if len(midi_keys_that_are_down) == 0:
			for sprite in get_tree().get_nodes_in_group("my_held_notes"):
				sprite.queue_free()
				remove_child(sprite)
				
			currently_held_sprites = {}
		
			
			
			#$RichTextLabel.text = "{pitch} released".format({"pitch": event.pitch})
		#$RichTextLabel.text = janky_join(indices_to_note_names(midi_keys_that_are_down))

func score_my_keystroke(pitch):
	# find next candidate note to match this to:
	var matched = false
	for note in song_data:
		if note["scored"] == false and time_progress_in_song > note.start_time - 100 and time_progress_in_song < note.start_time + 100 : # TODO move this to named constant
			if note["pitch"] == pitch:
				matched = true
				note["scored"] = true
				score_hits	+= 1
				# TODO scoring threshold should be relative to tempo
				if abs(time_progress_in_song - note.start_time) < 50:
					$FeedbackLabel.text = "Wow!"
				elif time_progress_in_song > note.start_time:
					$FeedbackLabel.text = "Dragging"
				elif time_progress_in_song < note.start_time:
					$FeedbackLabel.text = "Rushing"
				break

	# deduct points fof a keypress with no possible match				
	if not matched:
		score_misses += 1
		$FeedbackLabel.text = "Wrong!"

	$ScoreLabel.text = "Hits: {hits} Misses: {misses}".format(
				{"hits": score_hits,
				"misses": score_misses}
				)

func collect_notes(end_of_measure_pos):
	var start_of_measure_pos = end_of_measure_pos - 16 * self.sixteenth_note_duration
	var notes_in_measure = []
	for note in self.song_data:
		if note.start_time >= start_of_measure_pos and note.start_time <= end_of_measure_pos:
			notes_in_measure.append(note.pitch)			
	return notes_in_measure

func name_chord(set_of_pitches):
	if len(set_of_pitches) < 3:
		return ""
	set_of_pitches.sort() # lowest to highest
	var note_names = []
	for midi_code in set_of_pitches:
		note_names.append(key_number_to_note(midi_code))
	
	var chord_spellings = {
		"Db Maj": ["c#/db", "f", "g#/ab"],
		"Db Min": ["c#/db", "e", "g#/ab"],
		"Ab Maj": ["g#/ab", "c", "d#/eb"],
		"Ab Min": ["g#/ab", "b", "d#/eb"],
		"Eb Maj": ["d#/eb", "g", "a#/bb"],
		"Eb Min": ["d#/eb", "f#/gb", "a#/bb"],
		"Bb Maj": ["a#/bb", "d", "f"],
		"Bb Min": ["a#/bb", "c#/db", "f"],
		"F Maj": ["f", "a", "c"],
		"F Min": ["f", "g#/ab", "c"],
		"C Maj": ["c", "e", "g"],
		"C Min": ["c", "d#/eb", "g"],
		"G Maj": ["g", "b", "d"],
		"G Min": ["g", "a#/bb", "d"],
		"D Maj": ["d", "f#/gb", "a"],
		"D Min": ["d", "f", "a"],
		"A Maj": ["a", "c#/db", "e"],
		"A Min": ["a", "c", "e"],
		"E Maj": ["e", "g#/ab", "b"],
		"E Min": ["e", "g", "b"],
		"B Maj": ["b", "d#/eb", "f#/gb"],
		"B Min": ["b", "d", "f#/gb"],
		"F# Maj": ["f#/gb", "a#/bb", "c#/db"],
		"F# Min": ["f#/gb", "a", "c#/db"],
		# TODO add suspended, augmented, diminished,
		# maj7, min7, dom7, min7flat5, and dim7
	}
	# Very common for more than one chord to match. Idea: Start from the
	# lowest notes and work our way up:
	var slice_len = 3 # start with lowest 3 notes and go up
	# This still doesn't work perfectly - it's detecting the Bb measures
	# of Firework as F#Maj
	
	while slice_len <= len(note_names):
		var names = note_names.slice(0, slice_len)
		for chord in chord_spellings.keys():
			var chord_tones = chord_spellings[chord]
			if chord_tones[0] in names and chord_tones[1] in names and chord_tones[2] in names:
				return chord
		slice_len += 1
		

	return null

		
#func change_measure():
#	current_measure += 1
#	if current_measure >= len(chord_progression):
#		current_measure = 0
#	var current_chord = chord_progression[current_measure]
#	var chord_tones = chord_spellings[current_chord]
#	$CurrentChordLabel.text = str(chord_tones[0]) + ", " + str(chord_tones[1]) + ", " + str(chord_tones[2]) + "," + str(chord_tones[3])
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
func _input(event):
	
	for action_name in ["a_note", "b_note", "c_note", "d_note", "e_note", "f_note", "g_note"] :
		if event.is_action_pressed(action_name):
			#pressed_notes[action_name] = true
			print("computer keyboard {note} down".format({"note": action_name}))
		elif event.is_action_released(action_name):
			print("computer keyboard {note} up".format({"note": action_name}))
		#	#pressed_notes[action_name] = false
	if event.is_action_released("ui_select"):
		self.paused = ! self.paused
		$Timer.paused = self.paused

# How to score:
# (Done)if you key down and there's no such note nearby, lose pts
# (Done) if you key down and there's a note sufficiently closeby, score
# (and mark that note as "done" so you can't score it again?)
# (Done) if a note passes and you don't key down, lose pts

# Next steps:
# (Done) Show sharps/flats!  (this depends on having some idea what key we're in)
#   (vampire killer is 3-sharps)
# (Done) read treble part out of the MIDI file not just base!
# 
# (Done) some kind of count-in at the start?
# (Done) Read note_off events from midi file to figure out correct note duration
# (Done) show note duration (i.e. not all 1/4 notes) - based on reading end
#    (Done) Show dotted note durations (Why is this not working???)
#    Score how close my release is to the release time of the note
# (Done) Can I show less space between notes so taht i can see more notes ahead/ have them move slower?
# Turn the note into some kinda sparkle when you play it correctly
# (Done) show a "too fast" or "too slow" when you don't quite hit it
# (Done) show/play ALL the notes i'm pressing not just one
# figure out how to use other data from the MIDI file.
# (Done) Metronome
#   will need to, like, deduce what the beat is?
#   Can possibly get this from an event in Track 0 that looks like:
#  {'type': 'time_signature', 'numerator': 4, 'denominator': 4, 'clocks_per_click': 24, 'notated_32nd_notes_per_beat': 8, 'time': 0}
#  (Done)  Draw measure lines basd on the sixteenth_note_duration?

# (Fixed) Durations of notes as currently given are sketchy - they don't match what i see
# in musescore (or hear). almost all too short.
# (Fixed) and then the lines from them are drawn even shorter

# (Done) actually make the SOUND of all the notes i'm pressing, not just one
#  (DOne)   perhaps using actual accordion samples instead of sine waves
# (Done) Hit spacebar to pause
# (Fixed) At some point we lost the note sprites of notes i'm playing???
# (Done) Restart button
# (Done) Song-selector button
# (Done) TOdo: Populate SongSelectMenauButton
# (Done) Show the nae of the chord i'm playing
# (Done) Have it show lyrics.
# (Done) Bass notes are not displayed in correct location on staff
# (Done) Show the name of the chord in the song
# show streak of correct notes
# Tempo slider
# Scoreboard
# (Done) Play the drums
# Option to play other tracks such as electric bass or tuba in addition to
# drums
# Bug where notes i was previously playing don't all disappear
# (Done) Bigger font for lyrics
# Feature to choose a certain section of song to loop
#    (maybe show option when paused: "Start Loop"

func _on_Timer_timeout():
	$Timer/MetronomePlayer.play()
	#sfx/drumstick_hit.mp3")
	#change_measure()

func _on_song_selection(id):
	var title = $SongSelectMenuButton.get_popup().get_item_text(id)
	$SongSelectMenuButton.text = title

func _on_Button_pressed():
	self.start_song( $SongSelectMenuButton.text )
