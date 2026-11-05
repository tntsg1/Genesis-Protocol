// Night mode for whatever draws without a shader of its own (labels, panels'
// content, icons, the dish's marks): its colours turned to the night palette
// (night.gdshaderinc, night_ui). NightMode puts it on every such item; at
// night = 0 it changes nothing.
shader_type canvas_item;

#include "res://shaders/night.gdshaderinc"

void fragment() {
	if (night > 0.0) {
		// (Under hdr_2d a canvas item's COLOR is linear.)
		COLOR.rgb = mix(COLOR.rgb, night_ui_lin(COLOR.rgb), night);
	}
}
