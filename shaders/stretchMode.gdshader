shader_type canvas_item;

/*
	stretch_mode 3 and 4 won't display pixels outsize of "rect_size"
*/

uniform vec2 tex_size = vec2(512.0, 512.0); // original texture size in pixels
uniform vec2 rect_size = vec2(180.0, 90.0); // the rectangle size in pixels
uniform int stretch_mode : hint_range(0, 7, 1) = 0; // 0..7
uniform bool expand = true;  // for mode 0

// Helper: map UV (0..1 in rect space) into texture UV (0..1 in texture space)
vec2 get_uv(vec2 uv) {
    vec2 result_uv = uv;
	
	if (stretch_mode == 0) { // STRETCH_SCALE_ON_EXPAND
	    if (expand) {
	        // behaves like SCALE (mode 1)
	        result_uv = uv;
	    } else {
	        // behaves like KEEP (mode 3)
	        result_uv = (uv * rect_size) / tex_size;
	    }
	}
    else if (stretch_mode == 1) { // STRETCH_SCALE
        result_uv = uv; // rect UV directly maps to texture
    }
    else if (stretch_mode == 2) { // STRETCH_TILE
        result_uv = uv * (rect_size / tex_size);
        result_uv = fract(result_uv);
    }
    else if (stretch_mode == 3) { // STRETCH_KEEP
        // Show texture at top-left corner in original size
        result_uv = (uv * rect_size) / tex_size;
    }
    else if (stretch_mode == 4) { // STRETCH_KEEP_CENTERED
        vec2 offset = (rect_size - tex_size) * 0.5 / rect_size;
        result_uv = (uv - offset) * rect_size / tex_size;
    }
    else if (stretch_mode == 5) { // STRETCH_KEEP_ASPECT
        float tex_aspect = tex_size.x / tex_size.y;
        float rect_aspect = rect_size.x / rect_size.y;

        vec2 scale = vec2(1.0);
        if (tex_aspect > rect_aspect) {
            scale.y = rect_aspect / tex_aspect;
        } else {
            scale.x = tex_aspect / rect_aspect;
        }

        result_uv = uv / scale;
    }
    else if (stretch_mode == 6) { // STRETCH_KEEP_ASPECT_CENTERED
        float tex_aspect = tex_size.x / tex_size.y;
        float rect_aspect = rect_size.x / rect_size.y;

        vec2 scale = vec2(1.0);
        vec2 offset = vec2(0.0);

        if (tex_aspect > rect_aspect) {
            scale.y = rect_aspect / tex_aspect;
            offset.y = (1.0 - scale.y) * 0.5;
        } else {
            scale.x = tex_aspect / rect_aspect;
            offset.x = (1.0 - scale.x) * 0.5;
        }

        result_uv = (uv - offset) / scale;
    }
    else if (stretch_mode == 7) { // STRETCH_KEEP_ASPECT_COVERED
        float tex_aspect = tex_size.x / tex_size.y;
        float rect_aspect = rect_size.x / rect_size.y;

        vec2 scale = vec2(1.0);
        if (tex_aspect > rect_aspect) {
            scale.x = tex_aspect / rect_aspect;
        } else {
            scale.y = rect_aspect / tex_aspect;
        }

        result_uv = uv / scale + (scale - vec2(1.0)) * 0.5 / scale;
    }

    return result_uv;
}

void fragment() {
	
    vec2 uv = get_uv(UV);

	bool skip = false;
    // clip for KEEP modes (don’t sample outside the original tex)
    if (stretch_mode == 3 || stretch_mode == 4 || stretch_mode == 5 || stretch_mode == 6) {
        if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
            COLOR = vec4(0.0);
            skip = true;
        }
    }

    if(!skip) COLOR = texture(TEXTURE, uv);
}
