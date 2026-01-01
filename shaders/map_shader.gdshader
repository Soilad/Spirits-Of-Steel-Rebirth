shader_type canvas_item;

// --- TEXTURES ---
uniform sampler2D region_id_map : filter_nearest;
uniform sampler2D state_colors : filter_nearest;
uniform sampler2D original_texture : filter_nearest; // Sea
uniform vec2 tex_size;

// --- BORDER SETTINGS ---
uniform vec4 country_border_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float internal_border_darkness : hint_range(0.0, 1.0) = 0.2;
// How far (in pixels) to search for neighbors to determine border type.
// For a 2x upscale, 2.0 or 3.0 is usually safe.
uniform float border_scan_distance : hint_range(1.0, 5.0) = 2.0;

// --- SHORELINE SETTINGS ---
uniform vec4 shoreline_color : source_color = vec4(1.0, 1.0, 1.0, 0.5);
uniform float shoreline_size : hint_range(0.0, 10.0) = 2.0;

// Standard 8-way offsets
const vec2 DIRS[8] = vec2[8](
    vec2(0.0, -1.0), vec2(0.0, 1.0), vec2(-1.0, 0.0), vec2(1.0, 0.0),
    vec2(-1.0, -1.0), vec2(1.0, -1.0), vec2(-1.0, 1.0), vec2(1.0, 1.0)
);

// --- HELPER FUNCTIONS ---

int get_id(vec2 uv) {
    vec2 cuv = clamp(uv, vec2(0.0), vec2(1.0));
    vec4 c = texture(region_id_map, cuv);
    int r = int(round(c.r * 255.0));
    int g = int(round(c.g * 255.0));
    return r + g * 256;
}

vec4 get_country_color(int id) {
    // ID 0 = Sea, ID 1 = Grid. Countries start at 2.
    if (id <= 1) return vec4(0.0);
    float u = (float(id) + 0.5) / float(textureSize(state_colors, 0).x);
    return texture(state_colors, vec2(u, 0.0));
}

// Checks surroundings to decide if this grid pixel separates countries or is just internal.
// Returns: vec3(r, g, b) = the color to draw.
// Modifies: 'is_hard_border' (true if bordering sea or different country).
vec4 get_border_context(vec2 uv, vec2 pixel_size, out bool is_hard_border) {
    is_hard_border = false;
    vec4 detected_color = vec4(0.0);
    bool found_any_color = false;

    // Iterate through 8 directions
    for (int i = 0; i < 8; i++) {
        // We iterate outwards up to the scan distance
        for (float d = 1.0; d <= border_scan_distance; d += 1.0) {
            vec2 sample_pos = uv + (DIRS[i] * pixel_size * d);
            int nid = get_id(sample_pos);

            // Skip if we hit another grid/border pixel (ID 1).
            // We need to look past the border line to find the actual content.
            if (nid == 1) continue;

            // Case A: We found Sea (ID 0)
            if (nid == 0) {
                is_hard_border = true;
                // If we found sea, we know it's a hard border, but we keep looking
                // briefly to see if we can find a land color to mix (optional),
                // but usually, Sea connection implies Black Border immediately.
                return country_border_color;
            }

            // Case B: We found Land (ID > 1)
            vec4 c = get_country_color(nid);

            if (!found_any_color) {
                // First country found, store it as reference
                detected_color = c;
                found_any_color = true;
            } else {
                // We already have a reference. Check if this new one is different.
                // If colors differ significantly, it's a border between two countries.
                if (distance(c.rgb, detected_color.rgb) > 0.01) {
                    is_hard_border = true;
                    return country_border_color;
                }
            }

            // Once we find a valid neighbor in this direction, stop scanning further in this direction
            break;
        }
    }

    if (found_any_color) {
        return detected_color;
    }

    // Fallback if somehow surrounded entirely by other grid pixels (rare)
    return country_border_color;
}

void fragment() {
    int id = get_id(UV);
    vec2 pixel_size = 1.0 / tex_size;
    vec4 final_color = vec4(0.0);

    // --- SEA LOGIC ---
    if (id == 0) {
        final_color = texture(original_texture, UV);

        // Shoreline Glow
        // We scan 8 directions. If we hit land within 'shoreline_size', we add glow.
        // We use 'max' to find the closest land mass to keep the glow solid.
        float glow_intensity = 0.0;

        for (int i = 0; i < 8; i++) {
             // Check slightly further than the border itself
            vec2 check_uv = UV + (DIRS[i] * pixel_size * shoreline_size);
            int neighbor_id = get_id(check_uv);

            // If neighbor is Land (>1) or Border (1), we are near shore
            if (neighbor_id > 0) {
                glow_intensity = 1.0;
                break;
            }
        }

        if (glow_intensity > 0.0) {
            final_color = mix(final_color, shoreline_color, shoreline_color.a);
        }
    }

    // --- LAND LOGIC ---
    else if (id > 1) {
        final_color = get_country_color(id);
    }

    // --- BORDER/GRID LOGIC (ID == 1) ---
    else {
        bool is_hard_border = false;
        vec4 context_color = get_border_context(UV, pixel_size, is_hard_border);

        if (is_hard_border) {
            // Country Border or Coastline -> Solid Black
            final_color = country_border_color;
        } else {
            // Internal Province Border -> Darkened Color
            final_color = mix(context_color, vec4(0.0, 0.0, 0.0, 1.0), internal_border_darkness);
        }
    }

    COLOR = final_color;
}