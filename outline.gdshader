shader_type canvas_item;

uniform float outline_width : hint_range(0.0, 20.0) = 4.0;
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	if (tex.a < 0.5) {
		// Check pixels rondom voor een rand
		vec2 pixel_size = vec2(outline_width) / vec2(textureSize(TEXTURE, 0));
		float max_alpha = 0.0;
		max_alpha = max(max_alpha, texture(TEXTURE, UV + vec2(pixel_size.x, 0.0)).a);
		max_alpha = max(max_alpha, texture(TEXTURE, UV + vec2(-pixel_size.x, 0.0)).a);
		max_alpha = max(max_alpha, texture(TEXTURE, UV + vec2(0.0, pixel_size.y)).a);
		max_alpha = max(max_alpha, texture(TEXTURE, UV + vec2(0.0, -pixel_size.y)).a);
		max_alpha = max(max_alpha, texture(TEXTURE, UV + vec2(pixel_size.x, pixel_size.y)).a);
		max_alpha = max(max_alpha, texture(TEXTURE, UV + vec2(-pixel_size.x, pixel_size.y)).a);
		max_alpha = max(max_alpha, texture(TEXTURE, UV + vec2(pixel_size.x, -pixel_size.y)).a);
		max_alpha = max(max_alpha, texture(TEXTURE, UV + vec2(-pixel_size.x, -pixel_size.y)).a);

		if (max_alpha > 0.5) {
			COLOR = outline_color;
		} else {
			COLOR = tex;
		}
	} else {
		COLOR = tex;
	}
}
