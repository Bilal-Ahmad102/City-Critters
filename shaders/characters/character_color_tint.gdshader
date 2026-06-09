// character_color_tint.gdshader
// Applies a body color tint to the character mesh while preserving shading.
// Set "tint_color" uniform from PlayerAppearance.gd when applying species color.

shader_type spatial;

uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D albedo_texture : source_color;

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	ALBEDO = tex.rgb * tint_color.rgb;
	ALPHA = tex.a;
}
