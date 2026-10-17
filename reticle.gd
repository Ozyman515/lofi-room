extends Control
## A small glowing dot in the middle of the view (desktop only), so you can see where you are aiming.
## It grows a thin ring when you are pointing at something you can click.

var dot_color := Color(1.0, 0.35, 0.65)
var hot := false
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	if visible:
		queue_redraw()


func _draw() -> void:
	var c := get_viewport_rect().size / 2.0
	var base := dot_color
	draw_circle(c, 9.0, Color(base.r, base.g, base.b, 0.10))                 # soft neon glow
	draw_circle(c, 5.5, Color(base.r, base.g, base.b, 0.18))
	draw_circle(c, 3.6, Color(0.05, 0.0, 0.1, 0.35))                         # thin dark rim so it shows on bright walls
	draw_circle(c, 2.4, Color(base.r, base.g, base.b, 0.9))
	if hot:
		var r := 9.5 + sin(_t * 6.0) * 0.8
		draw_arc(c, r, 0.0, TAU, 32, Color(base.r, base.g, base.b, 0.75), 1.6, true)
