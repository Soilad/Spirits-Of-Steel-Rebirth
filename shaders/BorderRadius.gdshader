shader_type canvas_item;

/* --- STRETCH SETTINGS --- */
uniform vec2 tex_size = vec2(512.0, 512.0); // original texture size in pixels
uniform vec2 rect_size = vec2(180.0, 90.0); // the rectangle size in pixels
uniform int stretch_mode : hint_range(0, 7, 1) = 0; // 0..7
uniform bool expand = true;  // only affects mode 0

/* --- BORDER RADIUS SETTINGS --- */
uniform float top = 0.0;
uniform float right = 0.0;
uniform float bottom = 0.0;
uniform float left = 0.0;


// Resize option
uniform bool use_resize = false; // Enable/disable resizing

/* --- ALIGNMENT AND EMPTY SPACE SETTINGS --- */
uniform vec2 new_size = vec2(180.0, 90.0);       // Desired size in pixels

// Position enum (0..8)
// 0: topLeft, 1: topCenter, 2: topRight
// 3: centerLeft, 4: center, 5: centerRight
// 6: bottomLeft, 7: bottomCenter, 8: bottomRight
uniform int align: hint_range(0, 8, 1) = 4;

// Empty space behavior
uniform bool use_fill = false;           
uniform vec4 bg_color = vec4(0.0, 0.0, 0.0, 1.0); // Default transparent
uniform vec4 fg_color = vec4(1.0, 1.0, 1.0, 0.0); // Default white

// for fg color
uniform float fg_alpha: hint_range(0.0, 1.0, 0.1) = 0.5;

/* --- HELPERS --- */
vec2 get_uv(vec2 uv) {
    vec2 result_uv = uv;

    if (stretch_mode == 0) { // STRETCH_SCALE_ON_EXPAND
        if (expand) {
            result_uv = uv;
        } else {
            result_uv = (uv * rect_size) / tex_size;
        }
    }
    else if (stretch_mode == 1) { result_uv = uv; }
    else if (stretch_mode == 2) { result_uv = fract(uv * rect_size / tex_size); }
    else if (stretch_mode == 3) { result_uv = (uv * rect_size) / tex_size; }
    else if (stretch_mode == 4) { 
        vec2 offset = (rect_size - tex_size) * 0.5 / rect_size;
        result_uv = (uv - offset) * rect_size / tex_size;
    }
    else if (stretch_mode == 5) {
        float tex_aspect = tex_size.x / tex_size.y;
        float rect_aspect = rect_size.x / rect_size.y;
        vec2 scale = vec2(1.0);
        if (tex_aspect > rect_aspect) scale.y = rect_aspect / tex_aspect;
        else scale.x = tex_aspect / rect_aspect;
        result_uv = uv / scale;
    }
    else if (stretch_mode == 6) {
        float tex_aspect = tex_size.x / tex_size.y;
        float rect_aspect = rect_size.x / rect_size.y;
        vec2 scale = vec2(1.0);
        vec2 offset = vec2(0.0);
        if (tex_aspect > rect_aspect) { scale.y = rect_aspect / tex_aspect; offset.y = (1.0 - scale.y) * 0.5; }
        else { scale.x = tex_aspect / rect_aspect; offset.x = (1.0 - scale.x) * 0.5; }
        result_uv = (uv - offset) / scale;
    }
    else if (stretch_mode == 7) {
        float tex_aspect = tex_size.x / tex_size.y;
        float rect_aspect = rect_size.x / rect_size.y;
        vec2 scale = vec2(1.0);
        if (tex_aspect > rect_aspect) scale.x = tex_aspect / rect_aspect;
        else scale.y = rect_aspect / tex_aspect;
        result_uv = uv / scale + (scale - vec2(1.0)) * 0.5 / scale;
    }

    return result_uv;
}

/* --- BORDER RADIUS HELPERS --- */
bool isOut(float x, float y, float radius) {
    return (x * x + y * y) > (radius * radius);
}

bool checkCorner(vec2 uv, float radius, vec2 corner_pos, bool flip_x, bool flip_y) {
    if (radius <= 0.0) return false;
    vec2 pos = uv * rect_size;
    if ((flip_x ? pos.x > corner_pos.x : pos.x < corner_pos.x) &&
        (flip_y ? pos.y > corner_pos.y : pos.y < corner_pos.y)) {
        vec2 dist = pos - corner_pos;
        return isOut(dist.x, dist.y, radius);
    }
    return false;
}

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
    // Get offset based on align
    vec2 offset = get_offset();
    
    // Transform UV into the new_size area (only if resize is enabled)
    vec2 local_uv;
    if (use_resize) {
        local_uv = (UV * rect_size - offset) / new_size;
    } else {
        local_uv = UV;
    }
    
    // Check if we're inside the aligned content area (only if resize is enabled)
    bool inside_content = true;
    if (use_resize) {
        inside_content = local_uv.x >= 0.0 && local_uv.x <= 1.0 &&
                         local_uv.y >= 0.0 && local_uv.y <= 1.0;
    }
    
    // Get the stretched UV for texture sampling
    vec2 stretched_uv = get_uv(local_uv);
    
    // Check if texture UV is outside valid range for certain stretch modes
    bool texture_out_of_bounds = false;
    if (stretch_mode == 3 || stretch_mode == 4 || stretch_mode == 5 || stretch_mode == 6) {
        texture_out_of_bounds = (stretched_uv.x < 0.0 || stretched_uv.y < 0.0 || stretched_uv.x > 1.0 || stretched_uv.y > 1.0);
    }
    
    // --- BORDER-RADIUS CLIPPING ---
    bool discard_pixel =
        checkCorner(UV, top, vec2(top, top), false, false) ||          
        checkCorner(UV, right, vec2(rect_size.x - right, right), true, false) || 
        checkCorner(UV, bottom, vec2(rect_size.x - bottom, rect_size.y - bottom), true, true) || 
        checkCorner(UV, left, vec2(left, rect_size.y - left), false, true);

    if (discard_pixel) {
        COLOR.a = 0.0;
    } else {
		
        if (!use_resize || inside_content) {
			
            if (texture_out_of_bounds) {
                COLOR = use_fill ? bg_color : vec4(0.0);
            } else {
				vec4 tex_color = texture(TEXTURE, stretched_uv);
				if (use_fill) {
					if(tex_color.a > fg_alpha){
						COLOR = fg_color.a > 0.0? fg_color: tex_color;
					}else{
						COLOR = bg_color;
					}
					
				} else {
					COLOR = tex_color;
				}
        	}
			
        } else {
            // Outside content area and resize is enabled - use fill color
            COLOR = use_fill ? bg_color : vec4(0.0);
        }
		
    }
	
}