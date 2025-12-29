shader_type canvas_item;

uniform vec2 tex_size = vec2(512.0, 512.0);   // Original texture size in pixels
uniform vec2 rect_size = vec2(15.0, 15.0);    // The rectangle size in pixels
uniform vec2 new_size = vec2(5.0, 5.0);       // Desired size in pixels

// Position enum (0..8)
// 0: topLeft, 1: topCenter, 2: topRight
// 3: centerLeft, 4: center, 5: centerRight
// 6: bottomLeft, 7: bottomCenter, 8: bottomRight
uniform int align: hint_range(0, 8, 1) = 4;

// Empty space behavior
uniform bool use_fill = false;           
uniform vec4 bg_color : hint_color = vec4(0.0, 0.0, 0.0, 0.0); // Default transparent


vec2 get_offset() {
	
    vec2 offset = vec2(0.0);

    // Horizontal
    if (align == 0 || align == 3 || align == 6) {
        offset.x = 0.0; // left
    } else if (align == 1 || align == 4 || align == 7) {
        offset.x = (rect_size.x - new_size.x) * 0.5; // center
    } else {
        offset.x = rect_size.x - new_size.x; // right
    }

    // Vertical
    if (align == 0 || align == 1 || align == 2) {
        offset.y = 0.0; // top
    } else if (align == 3 || align == 4 || align == 5) {
        offset.y = (rect_size.y - new_size.y) * 0.5; // middle
    } else {
        offset.y = rect_size.y - new_size.y; // bottom
    }

    return offset;
}

void fragment() {
    // Normalized rect UV in pixels
    vec2 uv = UV * rect_size;

    // Get offset based on align
    vec2 offset = get_offset();

    // Transform uv into the new_size area
    vec2 local_uv = (uv - offset) / new_size;

    // Default = empty color or transparent
    COLOR = use_fill ? bg_color : vec4(0.0);

    // If inside the new_size box, overwrite with texture
    if (local_uv.x >= 0.0 && local_uv.x <= 1.0 &&
        local_uv.y >= 0.0 && local_uv.y <= 1.0) {
		vec4 inner_uv = texture(TEXTURE, local_uv);
        COLOR = use_fill && inner_uv == vec4(0.0)  ? bg_color : inner_uv;
    }
}
