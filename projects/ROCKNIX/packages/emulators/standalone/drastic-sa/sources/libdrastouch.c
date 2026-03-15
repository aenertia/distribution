#define _GNU_SOURCE
#include <dlfcn.h>
#include <SDL2/SDL.h>
#include <GLES2/gl2.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

// Shader post-processing support
static GLuint shader_program = 0;
static GLuint shader_fbo = 0;
static GLuint shader_tex = 0;
static int shader_enabled = 0;
static int shader_initialized = 0;
static int shader_width = 0;
static int shader_height = 0;
static GLint shader_loc_texture = -1;
static GLint shader_loc_resolution = -1;

// Simple vertex shader — fullscreen quad via triangle strip
static const char* shader_vert_src =
    "attribute vec2 a_pos;\n"
    "attribute vec2 a_texcoord;\n"
    "varying vec2 v_texcoord;\n"
    "void main() {\n"
    "    gl_Position = vec4(a_pos, 0.0, 1.0);\n"
    "    v_texcoord = a_texcoord;\n"
    "}\n";

// Default fragment shader — sharp bilinear upscale
static const char* shader_frag_default =
    "precision mediump float;\n"
    "varying vec2 v_texcoord;\n"
    "uniform sampler2D u_texture;\n"
    "uniform vec2 u_resolution;\n"
    "void main() {\n"
    "    gl_FragColor = texture2D(u_texture, v_texcoord);\n"
    "}\n";

// Scanline shader
static const char* shader_frag_scanline =
    "precision mediump float;\n"
    "varying vec2 v_texcoord;\n"
    "uniform sampler2D u_texture;\n"
    "uniform vec2 u_resolution;\n"
    "void main() {\n"
    "    vec4 color = texture2D(u_texture, v_texcoord);\n"
    "    float scanline = sin(v_texcoord.y * u_resolution.y * 3.14159) * 0.15;\n"
    "    color.rgb -= scanline;\n"
    "    gl_FragColor = color;\n"
    "}\n";

// LCD grid shader
static const char* shader_frag_lcd =
    "precision mediump float;\n"
    "varying vec2 v_texcoord;\n"
    "uniform sampler2D u_texture;\n"
    "uniform vec2 u_resolution;\n"
    "void main() {\n"
    "    vec4 color = texture2D(u_texture, v_texcoord);\n"
    "    vec2 pixel = v_texcoord * u_resolution;\n"
    "    float grid = 1.0 - (step(0.9, fract(pixel.x)) + step(0.9, fract(pixel.y))) * 0.15;\n"
    "    color.rgb *= grid;\n"
    "    gl_FragColor = color;\n"
    "}\n";

static const char* get_shader_frag(void) {
    const char* shader_name = getenv("DSHOOK_SHADER");
    if (!shader_name || strlen(shader_name) == 0 || strcmp(shader_name, "none") == 0)
        return NULL; // No shader
    if (strcmp(shader_name, "scanline") == 0 || strcmp(shader_name, "scanlines") == 0)
        return shader_frag_scanline;
    if (strcmp(shader_name, "lcd") == 0 || strcmp(shader_name, "lcd-grid") == 0)
        return shader_frag_lcd;
    if (strcmp(shader_name, "default") == 0 || strcmp(shader_name, "sharp") == 0)
        return shader_frag_default;
    return shader_frag_default;
}

static GLuint compile_shader(GLenum type, const char* src) {
    GLuint s = glCreateShader(type);
    glShaderSource(s, 1, &src, NULL);
    glCompileShader(s);
    GLint ok = 0;
    glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[512];
        glGetShaderInfoLog(s, sizeof(log), NULL, log);
        fprintf(stderr, "libdrastouch: shader compile error: %s\n", log);
        glDeleteShader(s);
        return 0;
    }
    return s;
}

static void shader_init(int w, int h) {
    const char* frag_src = get_shader_frag();
    if (!frag_src) {
        shader_enabled = 0;
        shader_initialized = 1;
        return;
    }

    GLuint vs = compile_shader(GL_VERTEX_SHADER, shader_vert_src);
    GLuint fs = compile_shader(GL_FRAGMENT_SHADER, frag_src);
    if (!vs || !fs) {
        shader_enabled = 0;
        shader_initialized = 1;
        return;
    }

    shader_program = glCreateProgram();
    glAttachShader(shader_program, vs);
    glAttachShader(shader_program, fs);
    glBindAttribLocation(shader_program, 0, "a_pos");
    glBindAttribLocation(shader_program, 1, "a_texcoord");
    glLinkProgram(shader_program);

    GLint linked = 0;
    glGetProgramiv(shader_program, GL_LINK_STATUS, &linked);
    if (!linked) {
        char log[512];
        glGetProgramInfoLog(shader_program, sizeof(log), NULL, log);
        fprintf(stderr, "libdrastouch: shader link error: %s\n", log);
        glDeleteProgram(shader_program);
        shader_program = 0;
        shader_enabled = 0;
        shader_initialized = 1;
        return;
    }

    glDeleteShader(vs);
    glDeleteShader(fs);

    shader_loc_texture = glGetUniformLocation(shader_program, "u_texture");
    shader_loc_resolution = glGetUniformLocation(shader_program, "u_resolution");

    // Create FBO + texture to capture framebuffer
    glGenTextures(1, &shader_tex);
    glBindTexture(GL_TEXTURE_2D, shader_tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    shader_width = w;
    shader_height = h;
    shader_enabled = 1;
    shader_initialized = 1;
    fprintf(stderr, "libdrastouch: shader initialized (%dx%d, shader=%s)\n",
            w, h, getenv("DSHOOK_SHADER"));
}

static void shader_apply(void) {
    if (!shader_enabled || !shader_program) return;

    // Save full GL state that SDL2's GLES2 renderer depends on
    GLint prev_program, prev_texture, prev_active_tex;
    GLint prev_viewport[4];
    GLint prev_vao;
    glGetIntegerv(GL_CURRENT_PROGRAM, &prev_program);
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &prev_texture);
    glGetIntegerv(GL_ACTIVE_TEXTURE, &prev_active_tex);
    glGetIntegerv(GL_VIEWPORT, prev_viewport);
    GLboolean prev_blend = glIsEnabled(GL_BLEND);
    GLboolean prev_depth = glIsEnabled(GL_DEPTH_TEST);
    GLboolean prev_scissor = glIsEnabled(GL_SCISSOR_TEST);

    // Copy current framebuffer content to our texture
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, shader_tex);
    glCopyTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 0, 0, shader_width, shader_height);

    // Clear and draw fullscreen shader quad
    glViewport(0, 0, shader_width, shader_height);
    glDisable(GL_BLEND);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_SCISSOR_TEST);
    glUseProgram(shader_program);

    glUniform1i(shader_loc_texture, 0);
    glUniform2f(shader_loc_resolution, (float)shader_width, (float)shader_height);

    // Fullscreen quad (triangle strip)
    static const float verts[] = {
        // pos        texcoord
        -1.0f, -1.0f,  0.0f, 0.0f,
         1.0f, -1.0f,  1.0f, 0.0f,
        -1.0f,  1.0f,  0.0f, 1.0f,
         1.0f,  1.0f,  1.0f, 1.0f,
    };

    glEnableVertexAttribArray(0);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), verts);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float), verts + 2);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    glDisableVertexAttribArray(0);
    glDisableVertexAttribArray(1);

    // Restore ALL GL state for SDL2
    glUseProgram(prev_program);
    glActiveTexture(prev_active_tex);
    glBindTexture(GL_TEXTURE_2D, prev_texture);
    glViewport(prev_viewport[0], prev_viewport[1], prev_viewport[2], prev_viewport[3]);
    if (prev_blend) glEnable(GL_BLEND); else glDisable(GL_BLEND);
    if (prev_depth) glEnable(GL_DEPTH_TEST); else glDisable(GL_DEPTH_TEST);
    if (prev_scissor) glEnable(GL_SCISSOR_TEST); else glDisable(GL_SCISSOR_TEST);
}

static int ds_screen_width = 256;
static int ds_screen_height = 192;
static int last_x = -1;
static int last_y = -1;
static int xy_idx = 0;
static int phys_width = -1;
static int phys_height = -1;
static int logical_width = -1;
static int logical_height = -1;
static int actual_touch = 0;

// Microphone monitoring
static SDL_AudioDeviceID mic_device = 0;
static int mic_key_held = 0;
static float mic_threshold = 0.0f;
static int mic_enabled = 0;
static float mic_baseline = 0.0f;
static int mic_baseline_samples = 0;

static SDL_Texture* screens[4];
static SDL_Texture* stylus_tex[2];
static SDL_Rect touch_rect_storage = {0};
static SDL_Rect* touch_rect = NULL;
static SDL_Renderer* renderer = NULL;
static SDL_Window* (*real_SDL_CreateWindow)(const char*, int, int, int, int, Uint32) = NULL;
static void (*real_SDL_SetWindowSize)(SDL_Window* window, int w, int h) = NULL;
static SDL_Renderer* (*real_SDL_CreateRenderer)(SDL_Window*, int, Uint32) = NULL;
static int (*real_SDL_RenderSetLogicalSize)(SDL_Renderer*, int, int) = NULL;
static SDL_Texture* (*real_SDL_CreateTexture)(SDL_Renderer*, Uint32, int, int, int) = NULL;
static int (*real_SDL_RenderCopy)(SDL_Renderer*, SDL_Texture*, const SDL_Rect*, const SDL_Rect*) = NULL;
static int (*real_SDL_PollEvent)(SDL_Event*) = NULL;
static int (*real_SDL_PushEvent)(SDL_Event*) = NULL;
static Uint32 (*real_SDL_WasInit)(Uint32) = NULL;
static int (*real_SDL_InitSubSystem)(Uint32) = NULL;
static SDL_AudioDeviceID (*real_SDL_OpenAudioDevice)(const char*, int, const SDL_AudioSpec*, SDL_AudioSpec*, int) = NULL;
static void (*real_SDL_PauseAudioDevice)(SDL_AudioDeviceID, int) = NULL;
static void (*real_SDL_CloseAudioDevice)(SDL_AudioDeviceID) = NULL;
static int (*real_SDL_GetNumAudioDevices)(int) = NULL;
static const char* (*real_SDL_GetAudioDeviceName)(int, int) = NULL;
static void (*real_SDL_GL_SwapWindow)(SDL_Window*) = NULL;
static void (*real_SDL_RenderPresent)(SDL_Renderer*) = NULL;

SDL_Window* SDL_CreateWindow(const char* title, int x, int y, int w, int h, Uint32 flags) {
    int num_displays = SDL_GetNumVideoDisplays();
    int total_width = 0;
    int total_height = 0;
    int last_width = 0;
    int last_height = 0;

    // Change window to total screen size
    // Prevents empty spacing on dual displays
    for (int i = 0; i < num_displays; ++i) {
        SDL_Rect bounds;
        if (SDL_GetDisplayBounds(i, &bounds) == 0) {
            last_width = bounds.w;
            last_height = bounds.h;
            if (bounds.w + bounds.x > total_width)
                total_width += bounds.w;
            if (bounds.h + bounds.y > total_height)
                total_height += bounds.h;
        }
    }

    // Record screen size for rect tracking/conversion
    phys_width = total_width;
    phys_height = total_height;

    // DraStic starts in the center of the native virtual screen
    last_x = 128;
    last_y = 96;

    // Check which screen side is longer for dual screens
    if (num_displays > 1)
        xy_idx = (last_width > last_height) ? 1 : 2;

    // Set window size to single screen to fix offsets when resizing
    return real_SDL_CreateWindow(title, 0, 0, last_width, last_height, flags);
}

void SDL_SetWindowSize(SDL_Window* window, int w, int h) {
    static int init_resize = 2;

    if (init_resize > 0) {
        real_SDL_SetWindowSize(window, w, h);
        init_resize -= 1;
    }

    // Force window size to fill AFTER DraStic does its weird init thing
    // Also check if this is a resize after init, if so, toggle a scale down to allow DraStic menu visibility
    if (init_resize == 0) {
        real_SDL_SetWindowSize(window, phys_width, phys_height);
        init_resize = -1;
    } else if (init_resize == -1) {
        if (xy_idx == 1)
            w = phys_width / 2;
        if (xy_idx == 2)
            h = phys_height / 2;

        real_SDL_SetWindowSize(window, w, h);
        init_resize = 0;
    }

}

SDL_Renderer* SDL_CreateRenderer(SDL_Window* window, int index, Uint32 flags) {
    renderer = real_SDL_CreateRenderer(window, index, flags);
    // Just in case it's already set
    SDL_RenderGetLogicalSize(renderer, &logical_width, &logical_height);
    return renderer;
}

int SDL_RenderSetLogicalSize(SDL_Renderer* renderer, int w, int h) {
    int result = real_SDL_RenderSetLogicalSize(renderer, w, h);
    // Otherwise store it here
    logical_width = w;
    logical_height = h;
    return result;
}

SDL_Texture* SDL_CreateTexture(SDL_Renderer *renderer, Uint32 format, int type, int w, int h) {
	SDL_Texture* texture = real_SDL_CreateTexture(renderer, format, type, w, h);
	// Identify DS screen and stylus textures
	if (type == SDL_TEXTUREACCESS_STREAMING) {
		if (w == 512 && h == 384) {
            ds_screen_width = 512;
            ds_screen_height = 384;
			if (!screens[0]) screens[0] = texture;
			else if (!screens[1]) screens[1] = texture;
        } else if (w == 256 && h == 192 && !screens[0]) {
		    if (!screens[2]) screens[2] = texture;
		    else if (!screens[3]) screens[3] = texture;
        }
    }
    if (w == 32 && h == 32) {
		if (!stylus_tex[0]) stylus_tex[0] = texture;
		else if (!stylus_tex[1]) stylus_tex[1] = texture;
    }
	return texture;
}

int SDL_RenderCopy(SDL_Renderer *renderer, SDL_Texture *texture, const SDL_Rect *srcrect, const SDL_Rect *dstrect) {
    if ((screens[0] && texture == screens[0] && ds_screen_width == 512) ||
        (screens[3] && texture == screens[3] && ds_screen_width == 256)) {
        // Convert renderer coordinates to physical screen coordinates
        if (logical_width > 0 && logical_height > 0) {
            int output_w, output_h;
            SDL_GetRendererOutputSize(renderer, &output_w, &output_h);
            float scale_x = (float)output_w / logical_width;
            float scale_y = (float)output_h / logical_height;

            touch_rect_storage.x = (int)(dstrect->x * scale_x);
            touch_rect_storage.y = (int)(dstrect->y * scale_y);
            touch_rect_storage.w = (int)(dstrect->w * scale_x);
            touch_rect_storage.h = (int)(dstrect->h * scale_y);
        } else {
            // Fallback and hope they're right
            touch_rect_storage.x = dstrect->x;
            touch_rect_storage.y = dstrect->y;
            touch_rect_storage.w = dstrect->w;
            touch_rect_storage.h = dstrect->h;
        }
        touch_rect = &touch_rect_storage;
    }

    // Make stylus fully transparent for actual touchscreens
    if (actual_touch && (texture == stylus_tex[0] || texture == stylus_tex[1]))
        SDL_SetTextureAlphaMod(texture, 0);
    
    return real_SDL_RenderCopy(renderer, texture, srcrect, dstrect);
}

void SDL_RenderPresent(SDL_Renderer* rend) {
    if (!shader_initialized && phys_width > 0 && phys_height > 0) {
        int w, h;
        SDL_GetRendererOutputSize(rend, &w, &h);
        if (w > 0 && h > 0)
            shader_init(w, h);
    }
    if (shader_enabled) {
        // Flush SDL2's render commands before we touch GL state
        SDL_RenderFlush(rend);
        shader_apply();
    }
    real_SDL_RenderPresent(rend);
}

void mic_audio_callback(void* userdata, Uint8* stream, int len) {
    if (!mic_enabled) return;

    Sint16* samples = (Sint16*)stream;
    int sample_count = len / 2;

    // Calculate RMS amplitude
    float sum = 0.0f;
    for (int i = 0; i < sample_count; i++) {
        float sample = samples[i] / 32768.0f; // Normalize to [-1.0..1.0]
        sum += sample * sample;
    }
    float rms = sqrtf(sum / sample_count);

    // Build ambient baseline over first ~3 seconds
    if (mic_baseline_samples < 60) {
        mic_baseline = (mic_baseline * mic_baseline_samples + rms) / (mic_baseline_samples + 1);
        mic_baseline_samples++;
        return; // Don't trigger during calibration
    }

    mic_baseline = mic_baseline * 0.999f + rms * 0.001f;

    // Trigger only if significantly above baseline
    float trigger_level = mic_baseline + mic_threshold;
    int should_hold = (rms > trigger_level);
    if (should_hold && !mic_key_held) {
        // Noise detected, press Scroll Lock
        SDL_Event key_event = {0};
        key_event.type = SDL_KEYDOWN;
        key_event.key.state = SDL_PRESSED;
        key_event.key.keysym.scancode = SDL_SCANCODE_SCROLLLOCK;
        key_event.key.keysym.sym = SDLK_SCROLLLOCK;
        real_SDL_PushEvent(&key_event);
        mic_key_held = 1;
    } else if (!should_hold && mic_key_held) {
        // Noise dropped below threshold, release Scroll Lock
        SDL_Event key_event = {0};
        key_event.type = SDL_KEYUP;
        key_event.key.state = SDL_RELEASED;
        key_event.key.keysym.scancode = SDL_SCANCODE_SCROLLLOCK;
        key_event.key.keysym.sym = SDLK_SCROLLLOCK;
        real_SDL_PushEvent(&key_event);
        mic_key_held = 0;
    }
}

int SDL_PollEvent(SDL_Event* event) {
    // Loop required to filter events we don't want to pass along
    while (1) {
        int result = real_SDL_PollEvent(event);
        if (!result) return 0;

        switch (event->type) {
            case SDL_FINGERDOWN: {
                if (!actual_touch)
                    actual_touch = 1;

                int x = (int)(event->tfinger.x * phys_width);
                int y = (int)(event->tfinger.y * phys_height);
                if (xy_idx == 1)
                    x *= 2;
                if (xy_idx == 2)
                    y *= 2;

                if (x < touch_rect->x || x > touch_rect->x + touch_rect->w ||
                    y < touch_rect->y || y > touch_rect->y + touch_rect->h)
                    return 0; // Outside valid coords, don't convert

                // Scale to native virtual touchscreen
                x = ((x - touch_rect->x) * 256) / touch_rect->w;
                y = ((y - touch_rect->y) * 192) / touch_rect->h;

                // Queue click for after jump
                event->type = SDL_MOUSEBUTTONDOWN;
                event->button.button = SDL_BUTTON_LEFT;
                event->button.state = SDL_PRESSED;
                event->button.x = x;
                event->button.y = y;
                real_SDL_PushEvent(event);

                // Jump to new position
                event->type = SDL_MOUSEMOTION;
                event->motion.x = x;
                event->motion.y = y;
                event->motion.xrel = x - last_x;
                event->motion.yrel = y - last_y;

                // Update to keep position accurate
                last_x = x;
                last_y = y;
                break;
            }
            case SDL_FINGERMOTION: {
                int x = (int)(event->tfinger.x * phys_width);
                int y = (int)(event->tfinger.y * phys_height);
                if (xy_idx == 1)
                    x *= 2;
                if (xy_idx == 2)
                    y *= 2;

                if (x < touch_rect->x || x > touch_rect->x + touch_rect->w ||
                    y < touch_rect->y || y > touch_rect->y + touch_rect->h)
                    return 0;

                x = ((x - touch_rect->x) * 256) / touch_rect->w;
                y = ((y - touch_rect->y) * 192) / touch_rect->h;
                int xrel = x - last_x;
                int yrel = y - last_y;

                // Motion is also used when already clicked but not moving
                // Always update it
                event->type = SDL_MOUSEMOTION;
                event->motion.x = x;
                event->motion.y = y;
                event->motion.xrel = xrel;
                event->motion.yrel = yrel;

                last_x = x;
                last_y = y;
                break;
            }
            case SDL_FINGERUP: {
                event->type = SDL_MOUSEBUTTONUP;
                event->button.button = SDL_BUTTON_LEFT;
                event->button.state = SDL_RELEASED;
                event->button.x = last_x;
                event->button.y = last_y;
                break;
            }
        }
        return result;
    }
}

__attribute__((constructor))
static void init(void) {
    real_SDL_CreateWindow = dlsym(RTLD_NEXT, "SDL_CreateWindow");
    real_SDL_SetWindowSize = dlsym(RTLD_NEXT, "SDL_SetWindowSize");
    real_SDL_CreateRenderer = dlsym(RTLD_NEXT, "SDL_CreateRenderer");
    real_SDL_RenderSetLogicalSize = dlsym(RTLD_NEXT, "SDL_RenderSetLogicalSize");
    real_SDL_CreateTexture = dlsym(RTLD_NEXT, "SDL_CreateTexture");
    real_SDL_RenderCopy = dlsym(RTLD_NEXT, "SDL_RenderCopy");
    real_SDL_PollEvent = dlsym(RTLD_NEXT, "SDL_PollEvent");
    real_SDL_PushEvent = dlsym(RTLD_NEXT, "SDL_PushEvent");
    real_SDL_WasInit = dlsym(RTLD_NEXT, "SDL_WasInit");
    real_SDL_InitSubSystem = dlsym(RTLD_NEXT, "SDL_InitSubSystem");
    real_SDL_OpenAudioDevice = dlsym(RTLD_NEXT, "SDL_OpenAudioDevice");
    real_SDL_PauseAudioDevice = dlsym(RTLD_NEXT, "SDL_PauseAudioDevice");
    real_SDL_CloseAudioDevice = dlsym(RTLD_NEXT, "SDL_CloseAudioDevice");
    real_SDL_GetNumAudioDevices = dlsym(RTLD_NEXT, "SDL_GetNumAudioDevices");
    real_SDL_GetAudioDeviceName = dlsym(RTLD_NEXT, "SDL_GetAudioDeviceName");
    real_SDL_GL_SwapWindow = dlsym(RTLD_NEXT, "SDL_GL_SwapWindow");
    real_SDL_RenderPresent = dlsym(RTLD_NEXT, "SDL_RenderPresent");

    const char* threshold_str = getenv("DSHOOK_MIC_THRESH");
    if (threshold_str) {
        mic_threshold = atof(threshold_str);
        if (mic_threshold > 0.0f) {
            mic_enabled = 1;

            // Make sure SDL audio is ready, just in case
            if (real_SDL_WasInit(SDL_INIT_AUDIO) == 0)
                real_SDL_InitSubSystem(SDL_INIT_AUDIO);

            int num_devices = real_SDL_GetNumAudioDevices(1);
            const char* device_name = NULL;
            for (int i = 0; i < num_devices; i++) {
                const char* name = real_SDL_GetAudioDeviceName(i, 1);
                // Use first available device (or look for Built-in)
                if (name && (i == 0 || strstr(name, "Built-in"))) {
                    device_name = name;
                    break;
                }
            }

            // Configure audio capture
            SDL_AudioSpec desired_spec = {0};
            desired_spec.freq = 44100;
            desired_spec.format = AUDIO_S16SYS;
            desired_spec.channels = 1;
            desired_spec.samples = 2048;
            desired_spec.callback = mic_audio_callback;

            SDL_AudioSpec obtained_spec;
            mic_device = real_SDL_OpenAudioDevice(device_name, 1, &desired_spec, &obtained_spec, 0);

            if (mic_device > 0) // Opened, start capture
                real_SDL_PauseAudioDevice(mic_device, 0);
            else // Couldn't open, fallback to disable
                mic_enabled = 0;
        }
    }
}

__attribute__((destructor))
static void cleanup(void) {
    if (mic_device > 0 && real_SDL_CloseAudioDevice) {
        real_SDL_CloseAudioDevice(mic_device);
    }
}

// Major thanks/credit to Shaun Inman for providing the basis of this hook library!