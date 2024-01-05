extends Node2D
# Constants:
var sample_hz = 22050.0 # Keep the number of samples to mix low, GDScript is not super fast.
var middle_a_hz = 440.0
var phase = 0.0
var twelfth_root_of_two = 1.0594630943593

var playback: AudioStreamPlayback = null # Actual playback stream, assigned in _ready().
# TODO factor audio generation out to a separate module.

$AudioStreamPlayer.stream.mix_rate = sample_hz # Setting mix rate is only possible before play().
	playback = $AudioStreamPlayer.get_stream_playback()
	#for method in playback.get_method_list():
	#	print(method["name"])
	#	#print(method["hint_string"])
	
	
if len(midi_keys_that_are_down) > 0:
		_fill_buffer(midi_keys_that_are_down[0])
	else:
		playback.clear_buffer()
		
		
func _fill_buffer(midi_key_index):
	var half_steps_from_a = midi_key_index - 57
	var pulse_hz = middle_a_hz * pow(twelfth_root_of_two, half_steps_from_a)
	var increment = pulse_hz / sample_hz

	var to_fill = playback.get_frames_available()
	while to_fill > 0:
		playback.push_frame(Vector2.ONE * sin(phase * TAU)) # Audio frames are stereo.
		phase = fmod(phase + increment, 1.0)
		to_fill -= 1

_fill_buffer(event.pitch) # Prefill, do before play() to avoid delay.
$AudioStreamPlayer.play()
$AudioStreamPlayer.stop()
