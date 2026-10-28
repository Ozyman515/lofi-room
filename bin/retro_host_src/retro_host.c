/* retro_host: runs one libretro core + one game and talks to the game over a loopback TCP socket.
 *
 *   retro_host <port> <core> <rom> <save_dir> <system_dir> [log_file]
 *
 * Godot -> host (little endian):
 *   'P' v            pause (1) or run (0); the host runs by itself at the game's own speed
 *   'M' v            speed in percent (80..120), used to keep the sound in step
 *   'D'              the last picture was shown, send the next one
 *   'B' p0 p1        joypad state of port 0 and 1, uint16 bit masks (bit = RETRO_DEVICE_ID_JOYPAD_*)
 *   'L' port on      plug a light gun into the port (on = 1: the core's own gun for that port, found by name:
 *                    Zapper, Super Scope, Menacer, GunCon...) or a pad back in (on = 0); answers 'I' len text
 *   'G' port x y b   the gun: where it points (int16 each, -32767..32767 across the picture, like libretro's
 *                    SCREEN_X/Y) and its buttons (bit 0 trigger, 1 off the screen, 2 reload, 3 aux A, 4 aux B,
 *                    5 start, 6 select)
 *   'X' port lx ly rx ry lt rt   analog sticks (int16 each, -32767..32767, y down) and analog triggers
 *                    (uint16 0..32767) of port 0 or 1 (GameCube: control stick, C stick, L / R)
 *   'S'              write the battery save now
 *   'T'              write the resume state now
 *   'R'              reset the game
 *   'Q'              save and quit
 * host -> Godot:
 *   'H' fps(f64) rate(f64) w(u32) h(u32)   the game is running
 *   'E' len(u8) text                         something failed (then the host exits)
 *   'V' w(u32) h(u32) RGBA8 pixels
 *   'A' n(u32) n * (float left, float right)
 *   'K' counter(u32)                         one frame finished
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdarg.h>
#include <ctype.h>
#include "libretro.h"

#ifdef _WIN32
#include <winsock2.h>
#include <windows.h>
#include <GL/gl.h>
typedef SOCKET sock_t;
#define CLOSESOCK closesocket
typedef CRITICAL_SECTION lock_t;
#define LOCK_INIT(l) InitializeCriticalSection(&(l))
#define LOCK(l) EnterCriticalSection(&(l))
#define UNLOCK(l) LeaveCriticalSection(&(l))
#else
#include <dlfcn.h>
#include <pthread.h>
typedef pthread_mutex_t lock_t;
#define LOCK_INIT(l) pthread_mutex_init(&(l), NULL)
#define LOCK(l) pthread_mutex_lock(&(l))
#define UNLOCK(l) pthread_mutex_unlock(&(l))
#include <unistd.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <netinet/in.h>
#include <arpa/inet.h>
typedef int sock_t;
#define CLOSESOCK close
#define INVALID_SOCKET (-1)
#endif

static sock_t g_sock = INVALID_SOCKET;
static FILE *g_log = NULL;
static char *g_system_dir = NULL;
static char *g_save_dir = NULL;
static unsigned g_pixel_format = RETRO_PIXEL_FORMAT_0RGB1555;
static unsigned g_frame_w = 0, g_frame_h = 0;
static uint8_t *g_rgba = NULL;
static size_t g_rgba_cap = 0;
static int g_have_video = 0;
static float *g_audio = NULL;
static size_t g_audio_n = 0, g_audio_cap = 0;     /* in int16 values */
/* Dolphin hands over its sound from its own CPU thread, so the sound buffer is shared under a lock */
static lock_t g_audio_lock;
static float *g_audio_out = NULL;
static size_t g_audio_out_cap = 0;
static uint16_t g_buttons[2] = {0, 0};
static int16_t g_stick[2][4];                      /* lx ly rx ry */
static uint16_t g_trig[2][2];                      /* L R, 0..32767 */
static int g_want_frame = 1;                       /* Godot showed the last picture: read the next one back */
static int g_heavy = 0;                            /* a big core (Dolphin): huge save states, no periodic ones */
static double g_fps_now = 0.0;                     /* changed by SET_SYSTEM_AV_INFO (a PAL game switching to 60 Hz) */
static int16_t g_gun_x[2] = {0, 0}, g_gun_y[2] = {0, 0};
static uint8_t g_gun_b[2] = {0, 0};
static int g_gun_px[2][2];                         /* where the core thinks a relative gun points (pixels) */
static unsigned g_geo_w = 256, g_geo_h = 224;
/* the controller types the core offered for ports 0 and 1 (from SET_CONTROLLER_INFO) */
#define MAX_TYPES 16
static char g_type_desc[2][MAX_TYPES][48];
static unsigned g_type_id[2][MAX_TYPES];
static unsigned g_type_n[2] = {0, 0};

static void logf_(const char *fmt, ...) {
	if (!g_log) return;
	va_list ap;
	va_start(ap, fmt);
	vfprintf(g_log, fmt, ap);
	va_end(ap);
	fputc('\n', g_log);
	fflush(g_log);
}

/* ---------------------------------------------------------------- tiny platform layer */

#ifdef _WIN32
static wchar_t *to_wide(const char *s) {
	int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
	wchar_t *w = (wchar_t *)malloc(sizeof(wchar_t) * (n + 1));
	MultiByteToWideChar(CP_UTF8, 0, s, -1, w, n + 1);
	return w;
}
static char **win_args(int *pc) {
	const wchar_t *p = GetCommandLineW();
	char **out = (char **)calloc(64, sizeof(char *));
	int n = 0;
	wchar_t *buf = (wchar_t *)malloc(sizeof(wchar_t) * (wcslen(p) + 2));
	while (*p && n < 63) {
		int inq = 0, len = 0;
		while (*p == L' ' || *p == L'\t') p++;
		if (!*p) break;
		while (*p && (inq || (*p != L' ' && *p != L'\t'))) {
			int bs = 0;
			while (*p == L'\\') { bs++; p++; }
			if (*p == L'"') {
				int k;
				for (k = 0; k < bs / 2; k++) buf[len++] = L'\\';
				if (bs & 1) buf[len++] = L'"'; else inq = !inq;
				p++;
			} else {
				int k;
				for (k = 0; k < bs; k++) buf[len++] = L'\\';
				if (*p) buf[len++] = *p++;
			}
		}
		buf[len] = 0;
		{
			int need = WideCharToMultiByte(CP_UTF8, 0, buf, -1, NULL, 0, NULL, NULL);
			out[n] = (char *)malloc(need + 1);
			WideCharToMultiByte(CP_UTF8, 0, buf, -1, out[n], need + 1, NULL, NULL);
			n++;
		}
	}
	free(buf);
	*pc = n;
	return out;
}
static void *open_lib(const char *path) { wchar_t *w = to_wide(path); void *h = (void *)LoadLibraryW(w); free(w); return h; }
static void *get_sym(void *h, const char *n) { return (void *)GetProcAddress((HMODULE)h, n); }
static FILE *open_file(const char *path, const char *mode) {
	wchar_t *w = to_wide(path), *m = to_wide(mode);
	FILE *f = _wfopen(w, m);
	free(w); free(m);
	return f;
}
#else
static void *open_lib(const char *path) { return dlopen(path, RTLD_NOW | RTLD_LOCAL); }
static void *get_sym(void *h, const char *n) { return dlsym(h, n); }
static FILE *open_file(const char *path, const char *mode) { return fopen(path, mode); }
#endif

static int send_all(const void *buf, size_t n) {
	const char *p = (const char *)buf;
	while (n > 0) {
		int r = (int)send(g_sock, p, (int)(n > 65536 ? 65536 : n), 0);
		if (r <= 0) return 0;
		p += r;
		n -= (size_t)r;
	}
	return 1;
}
static int recv_all(void *buf, size_t n) {
	char *p = (char *)buf;
	while (n > 0) {
		int r = (int)recv(g_sock, p, (int)n, 0);
		if (r <= 0) return 0;
		p += r;
		n -= (size_t)r;
	}
	return 1;
}
static void send_error(const char *text) {
	uint8_t hdr[2] = {'E', 0};
	size_t n = strlen(text);
	if (n > 200) n = 200;
	hdr[1] = (uint8_t)n;
	send_all(hdr, 2);
	send_all(text, n);
	logf_("ERROR: %s", text);
}

/* ---------------------------------------------------------------- hardware rendering (OpenGL, Windows)
 *
 * Cores like Dolphin draw with the GPU instead of handing over a picture. We give them an OpenGL context on a
 * hidden window and a framebuffer to draw into, then read each finished frame back and send it like any other. */

static struct retro_hw_render_callback g_hw;
static int g_use_hw = 0;
static unsigned g_fb_w = 0, g_fb_h = 0, g_fb_want_w = 0, g_fb_want_h = 0;
static uint8_t *g_readback = NULL;
static size_t g_readback_cap = 0;

#ifdef _WIN32
#define GL_FRAMEBUFFER 0x8D40
#define GL_RENDERBUFFER 0x8D41
#define GL_COLOR_ATTACHMENT0 0x8CE0
#define GL_DEPTH_STENCIL_ATTACHMENT 0x821A
#define GL_DEPTH24_STENCIL8 0x88F0
#define GL_FRAMEBUFFER_COMPLETE 0x8CD5
#define GL_FRAMEBUFFER_BINDING 0x8CA6
#define GL_READ_FRAMEBUFFER 0x8CA8
#define GL_READ_FRAMEBUFFER_BINDING 0x8CAA
#define GL_PIXEL_PACK_BUFFER 0x88EB
#define GL_PIXEL_PACK_BUFFER_BINDING 0x88ED
#define GL_PACK_ROW_LENGTH 0x0D02
#define GL_RGBA8 0x8058
#define WGL_CONTEXT_MAJOR_VERSION_ARB 0x2091
#define WGL_CONTEXT_MINOR_VERSION_ARB 0x2092
#define WGL_CONTEXT_PROFILE_MASK_ARB 0x9126
#define WGL_CONTEXT_CORE_PROFILE_BIT_ARB 0x0001
#define WGL_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB 0x0002

typedef void (APIENTRY *p_glGenFramebuffers)(GLsizei, GLuint *);
typedef void (APIENTRY *p_glDeleteFramebuffers)(GLsizei, const GLuint *);
typedef void (APIENTRY *p_glBindFramebuffer)(GLenum, GLuint);
typedef void (APIENTRY *p_glFramebufferTexture2D)(GLenum, GLenum, GLenum, GLuint, GLint);
typedef void (APIENTRY *p_glGenRenderbuffers)(GLsizei, GLuint *);
typedef void (APIENTRY *p_glDeleteRenderbuffers)(GLsizei, const GLuint *);
typedef void (APIENTRY *p_glBindRenderbuffer)(GLenum, GLuint);
typedef void (APIENTRY *p_glRenderbufferStorage)(GLenum, GLenum, GLsizei, GLsizei);
typedef void (APIENTRY *p_glFramebufferRenderbuffer)(GLenum, GLenum, GLenum, GLuint);
typedef GLenum (APIENTRY *p_glCheckFramebufferStatus)(GLenum);
typedef void (APIENTRY *p_glBindBuffer)(GLenum, GLuint);
typedef HGLRC (WINAPI *p_wglCreateContextAttribsARB)(HDC, HGLRC, const int *);
static p_glGenFramebuffers q_glGenFramebuffers;
static p_glDeleteFramebuffers q_glDeleteFramebuffers;
static p_glBindFramebuffer q_glBindFramebuffer;
static p_glFramebufferTexture2D q_glFramebufferTexture2D;
static p_glGenRenderbuffers q_glGenRenderbuffers;
static p_glDeleteRenderbuffers q_glDeleteRenderbuffers;
static p_glBindRenderbuffer q_glBindRenderbuffer;
static p_glRenderbufferStorage q_glRenderbufferStorage;
static p_glFramebufferRenderbuffer q_glFramebufferRenderbuffer;
static p_glCheckFramebufferStatus q_glCheckFramebufferStatus;
static p_glBindBuffer q_glBindBuffer;

static HWND g_gl_wnd = NULL;
static HDC g_gl_dc = NULL;
static HGLRC g_gl_rc = NULL;
static HMODULE g_gl_lib = NULL;
static GLuint g_fbo = 0, g_fb_tex = 0, g_fb_depth = 0;

static retro_proc_address_t RETRO_CALLCONV gl_proc(const char *name) {
	PROC p = wglGetProcAddress(name);
	if (p == NULL || p == (PROC)1 || p == (PROC)2 || p == (PROC)3 || p == (PROC)-1)
		p = GetProcAddress(g_gl_lib, name);         /* the OpenGL 1.1 functions live in opengl32.dll itself */
	return (retro_proc_address_t)p;
}
static uintptr_t RETRO_CALLCONV gl_current_fb(void) { return (uintptr_t)g_fbo; }

static int gl_create(int core_profile, unsigned want_major, unsigned want_minor) {
	WNDCLASSW wc;
	PIXELFORMATDESCRIPTOR pfd;
	HGLRC tmp;
	p_wglCreateContextAttribsARB create_attribs;
	int pf;
	memset(&wc, 0, sizeof(wc));
	wc.lpfnWndProc = DefWindowProcW;
	wc.hInstance = GetModuleHandleW(NULL);
	wc.lpszClassName = L"retro_host_gl";
	RegisterClassW(&wc);
	g_gl_wnd = CreateWindowExW(0, L"retro_host_gl", L"retro_host", WS_POPUP, 0, 0, 16, 16, NULL, NULL, wc.hInstance, NULL);
	if (!g_gl_wnd) { logf_("GL: no window"); return 0; }
	g_gl_dc = GetDC(g_gl_wnd);
	memset(&pfd, 0, sizeof(pfd));
	pfd.nSize = sizeof(pfd);
	pfd.nVersion = 1;
	pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
	pfd.iPixelType = PFD_TYPE_RGBA;
	pfd.cColorBits = 32;
	pfd.cDepthBits = 24;
	pfd.cStencilBits = 8;
	pf = ChoosePixelFormat(g_gl_dc, &pfd);
	if (!pf || !SetPixelFormat(g_gl_dc, pf, &pfd)) { logf_("GL: no pixel format"); return 0; }
	tmp = wglCreateContext(g_gl_dc);
	if (!tmp || !wglMakeCurrent(g_gl_dc, tmp)) { logf_("GL: no context"); return 0; }
	g_gl_lib = GetModuleHandleW(L"opengl32.dll");
	create_attribs = (p_wglCreateContextAttribsARB)wglGetProcAddress("wglCreateContextAttribsARB");
	if (create_attribs) {
		/* the newest version the driver gives us, but at least what the core asked for */
		static const int versions[][2] = {{4, 6}, {4, 5}, {4, 3}, {4, 0}, {3, 3}, {3, 2}, {3, 1}, {3, 0}};
		unsigned i;
		for (i = 0; i < sizeof(versions) / sizeof(versions[0]); i++) {
			int attr[16], n = 0;
			HGLRC rc;
			if ((unsigned)versions[i][0] < want_major || ((unsigned)versions[i][0] == want_major && (unsigned)versions[i][1] < want_minor)) break;
			attr[n++] = WGL_CONTEXT_MAJOR_VERSION_ARB; attr[n++] = versions[i][0];
			attr[n++] = WGL_CONTEXT_MINOR_VERSION_ARB; attr[n++] = versions[i][1];
			if (versions[i][0] * 10 + versions[i][1] >= 32) {
				attr[n++] = WGL_CONTEXT_PROFILE_MASK_ARB;
				attr[n++] = core_profile ? WGL_CONTEXT_CORE_PROFILE_BIT_ARB : WGL_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB;
			}
			attr[n] = 0;
			rc = create_attribs(g_gl_dc, NULL, attr);
			if (rc) {
				wglMakeCurrent(g_gl_dc, rc);
				wglDeleteContext(tmp);
				g_gl_rc = rc;
				logf_("GL: OpenGL %d.%d %s context (%s)", versions[i][0], versions[i][1], core_profile ? "core" : "compatibility",
					(const char *)glGetString(GL_RENDERER));
				break;
			}
		}
	}
	if (!g_gl_rc) {
		if (core_profile) { logf_("GL: the driver has no core OpenGL %u.%u", want_major, want_minor); wglMakeCurrent(NULL, NULL); wglDeleteContext(tmp); return 0; }
		g_gl_rc = tmp;
	}
#define GLP(n) do { *(void **)&q_##n = (void *)gl_proc(#n); if (!q_##n) { logf_("GL: missing " #n); return 0; } } while (0)
	GLP(glGenFramebuffers); GLP(glDeleteFramebuffers); GLP(glBindFramebuffer); GLP(glFramebufferTexture2D);
	GLP(glGenRenderbuffers); GLP(glDeleteRenderbuffers); GLP(glBindRenderbuffer); GLP(glRenderbufferStorage);
	GLP(glFramebufferRenderbuffer); GLP(glCheckFramebufferStatus); GLP(glBindBuffer);
#undef GLP
	return 1;
}

/* (re)make the framebuffer the core draws into, at least w x h */
static int gl_make_fb(unsigned w, unsigned h) {
	GLenum st;
	if (w == 0) w = 640;
	if (h == 0) h = 528;
	if (g_fbo && w <= g_fb_w && h <= g_fb_h) return 1;
	if (g_fbo) { q_glDeleteFramebuffers(1, &g_fbo); glDeleteTextures(1, &g_fb_tex); q_glDeleteRenderbuffers(1, &g_fb_depth); }
	glGenTextures(1, &g_fb_tex);
	glBindTexture(GL_TEXTURE_2D, g_fb_tex);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, (GLsizei)w, (GLsizei)h, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
	glBindTexture(GL_TEXTURE_2D, 0);
	q_glGenRenderbuffers(1, &g_fb_depth);
	q_glBindRenderbuffer(GL_RENDERBUFFER, g_fb_depth);
	q_glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, (GLsizei)w, (GLsizei)h);
	q_glBindRenderbuffer(GL_RENDERBUFFER, 0);
	q_glGenFramebuffers(1, &g_fbo);
	q_glBindFramebuffer(GL_FRAMEBUFFER, g_fbo);
	q_glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, g_fb_tex, 0);
	q_glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, g_fb_depth);
	st = q_glCheckFramebufferStatus(GL_FRAMEBUFFER);
	q_glBindFramebuffer(GL_FRAMEBUFFER, 0);
	if (st != GL_FRAMEBUFFER_COMPLETE) { logf_("GL: framebuffer not complete (0x%x)", (unsigned)st); return 0; }
	g_fb_w = w;
	g_fb_h = h;
	logf_("GL: framebuffer %ux%u", w, h);
	return 1;
}

/* copy the finished frame out of the GPU into g_rgba (top row first), without disturbing the core's GL state */
static void gl_read_frame(unsigned w, unsigned h) {
	GLint old_read = 0, old_pack = 0, old_align = 4, old_row = 0;
	size_t row = (size_t)w * 4;
	unsigned y;
	if (w > g_fb_w) w = g_fb_w;
	if (h > g_fb_h) h = g_fb_h;
	if (w == 0 || h == 0) return;
	row = (size_t)w * 4;
	if (row * h > g_readback_cap) { g_readback_cap = row * h; g_readback = (uint8_t *)realloc(g_readback, g_readback_cap); }
	if (row * h > g_rgba_cap) { g_rgba_cap = row * h; g_rgba = (uint8_t *)realloc(g_rgba, g_rgba_cap); }
	glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &old_read);
	glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &old_pack);
	glGetIntegerv(GL_PACK_ALIGNMENT, &old_align);
	glGetIntegerv(GL_PACK_ROW_LENGTH, &old_row);
	q_glBindFramebuffer(GL_READ_FRAMEBUFFER, g_fbo);
	q_glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
	glPixelStorei(GL_PACK_ALIGNMENT, 1);
	glPixelStorei(GL_PACK_ROW_LENGTH, 0);
	glReadPixels(0, 0, (GLsizei)w, (GLsizei)h, GL_RGBA, GL_UNSIGNED_BYTE, g_readback);
	glPixelStorei(GL_PACK_ALIGNMENT, old_align);
	glPixelStorei(GL_PACK_ROW_LENGTH, old_row);
	q_glBindBuffer(GL_PIXEL_PACK_BUFFER, (GLuint)old_pack);
	q_glBindFramebuffer(GL_READ_FRAMEBUFFER, (GLuint)old_read);
	for (y = 0; y < h; y++) {
		const uint8_t *src = g_readback + (size_t)(g_hw.bottom_left_origin ? h - 1 - y : y) * row;
		uint8_t *dst = g_rgba + (size_t)y * row;
		size_t i;
		memcpy(dst, src, row);
		for (i = 3; i < row; i += 4) dst[i] = 255;
	}
	g_frame_w = w;
	g_frame_h = h;
	g_have_video = 1;
}
#endif

/* the core asks for a GPU context (inside retro_load_game) */
static bool hw_request(struct retro_hw_render_callback *cb) {
#ifdef _WIN32
	int core_profile;
	if (cb->context_type != RETRO_HW_CONTEXT_OPENGL_CORE && cb->context_type != RETRO_HW_CONTEXT_OPENGL) {
		logf_("GL: the core asked for render type %d (only OpenGL here)", (int)cb->context_type);
		return false;
	}
	if (g_use_hw) {                  /* asked again: same context */
		cb->get_current_framebuffer = gl_current_fb;
		cb->get_proc_address = gl_proc;
		g_hw = *cb;
		return true;
	}
	core_profile = cb->context_type == RETRO_HW_CONTEXT_OPENGL_CORE;
	if (!gl_create(core_profile, core_profile ? cb->version_major : 0, core_profile ? cb->version_minor : 0)) return false;
	cb->get_current_framebuffer = gl_current_fb;
	cb->get_proc_address = gl_proc;
	g_hw = *cb;
	g_use_hw = 1;
	return true;
#else
	(void)cb;
	return false;
#endif
}

/* ---------------------------------------------------------------- libretro side */

static void (*c_set_environment)(retro_environment_t);
static void (*c_set_video_refresh)(retro_video_refresh_t);
static void (*c_set_audio_sample)(retro_audio_sample_t);
static void (*c_set_audio_sample_batch)(retro_audio_sample_batch_t);
static void (*c_set_input_poll)(retro_input_poll_t);
static void (*c_set_input_state)(retro_input_state_t);
static void (*c_init)(void);
static void (*c_deinit)(void);
static unsigned (*c_api_version)(void);
static void (*c_get_system_info)(struct retro_system_info *);
static void (*c_get_system_av_info)(struct retro_system_av_info *);
static bool (*c_load_game)(const struct retro_game_info *);
static void (*c_unload_game)(void);
static void (*c_run)(void);
static void (*c_reset)(void);
static void (*c_set_controller_port_device)(unsigned, unsigned);
static void *(*c_get_memory_data)(unsigned);
static size_t (*c_get_memory_size)(unsigned);
static size_t (*c_serialize_size)(void);
static bool (*c_serialize)(void *, size_t);
static bool (*c_unserialize)(const void *, size_t);

static void RETRO_CALLCONV log_cb(enum retro_log_level level, const char *fmt, ...) {
	if (!g_log || level < RETRO_LOG_WARN) return;
	va_list ap;
	va_start(ap, fmt);
	fputs("[core] ", g_log);
	vfprintf(g_log, fmt, ap);
	va_end(ap);
	fflush(g_log);
}

static bool RETRO_CALLCONV env_cb(unsigned cmd, void *data) {
	switch (cmd) {
		case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
			g_pixel_format = *(const unsigned *)data;
			return true;
		case RETRO_ENVIRONMENT_GET_CAN_DUPE:
			*(bool *)data = true;
			return true;
		case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
			*(const char **)data = g_system_dir;
			return true;
		case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
			*(const char **)data = g_save_dir;
			return true;
		case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
			((struct retro_log_callback *)data)->log = log_cb;
			return true;
		case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO: {
			const struct retro_controller_info *ci = (const struct retro_controller_info *)data;
			unsigned port, k;
			for (port = 0; port < 2 && ci && ci[port].types; port++) {
				g_type_n[port] = 0;
				for (k = 0; k < ci[port].num_types && k < MAX_TYPES; k++) {
					const char *d = ci[port].types[k].desc ? ci[port].types[k].desc : "";
					snprintf(g_type_desc[port][k], sizeof(g_type_desc[port][k]), "%s", d);
					g_type_id[port][k] = ci[port].types[k].id;
					g_type_n[port]++;
				}
			}
			return true;
		}
		case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
		case RETRO_ENVIRONMENT_SET_VARIABLES:
		case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME:
		case RETRO_ENVIRONMENT_SET_MEMORY_MAPS:
		case RETRO_ENVIRONMENT_SET_SERIALIZATION_QUIRKS:
		case RETRO_ENVIRONMENT_SET_GEOMETRY:
			return true;
		case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO: {
			/* new timing or a bigger picture (the core changed its resolution): the framebuffer grows before the next frame */
			const struct retro_system_av_info *ai = (const struct retro_system_av_info *)data;
			if (ai) {
				if (ai->timing.fps > 1.0) g_fps_now = ai->timing.fps;
				if (ai->geometry.max_width > g_fb_want_w) g_fb_want_w = ai->geometry.max_width;
				if (ai->geometry.max_height > g_fb_want_h) g_fb_want_h = ai->geometry.max_height;
			}
			return true;
		}
		/* ---- what GPU cores (Dolphin) ask for */
		case RETRO_ENVIRONMENT_GET_PREFERRED_HW_RENDER:
#ifdef _WIN32
			*(unsigned *)data = RETRO_HW_CONTEXT_OPENGL_CORE;
			return true;
#else
			return false;
#endif
		case RETRO_ENVIRONMENT_SET_HW_RENDER:
			return hw_request((struct retro_hw_render_callback *)data);
		case RETRO_ENVIRONMENT_SET_HW_SHARED_CONTEXT:
			return true;
		case RETRO_ENVIRONMENT_GET_JIT_CAPABLE:
			*(bool *)data = true;
			return true;
		case RETRO_ENVIRONMENT_GET_FASTFORWARDING:
			*(bool *)data = false;
			return true;
		case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:
			return true;
		case RETRO_ENVIRONMENT_SET_MESSAGE: {
			const struct retro_message *m = (const struct retro_message *)data;
			if (m && m->msg) logf_("[core message] %s", m->msg);
			return true;
		}
		case RETRO_ENVIRONMENT_GET_VARIABLE: {
			/* a few core options of our own; the rest stay at the core's defaults */
			static const char *opts[][2] = {
				/* PCSX ReARMed's recompiler crashes after a saved position is loaded, and the
				   interpreter is quick enough on a PC */
				{ "pcsx_rearmed_drc", "disabled" },
				/* Dolphin: draw with the GPU, at the console's own resolution (640 x 528; it is a TV in a room,
				   and every frame is copied back from the GPU), compile shaders in the background with
				   ubershaders meanwhile (no hitches when a new effect shows up, which feels bad in VR), and no
				   text drawn over the game */
				{ "dolphin_renderer", "Hardware" },
				{ "dolphin_efb_scale", "1" },
				{ "dolphin_shader_compilation_mode", "2" },
				{ "dolphin_osd_enabled", "disabled" },
			};
			struct retro_variable *v = (struct retro_variable *)data;
			unsigned i;
			if (!v || !v->key) return false;
			for (i = 0; i < sizeof(opts) / sizeof(opts[0]); i++)
				if (strcmp(v->key, opts[i][0]) == 0) { v->value = opts[i][1]; return true; }
			return false;
		}
		case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
			*(bool *)data = false;
			return true;
		case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION:
			*(unsigned *)data = 0;
			return true;
		default:
			return false;
	}
}

static void RETRO_CALLCONV video_cb(const void *data, unsigned w, unsigned h, size_t pitch) {
	unsigned x, y;
	uint8_t *o;
	if (!data || w == 0 || h == 0) return;     /* a repeated frame */
#ifdef _WIN32
	if (data == RETRO_HW_FRAME_BUFFER_VALID) {  /* drawn on the GPU: read it back only when Godot wants a picture */
		if (g_use_hw && g_fbo && g_want_frame) gl_read_frame(w, h);
		return;
	}
#else
	if (data == RETRO_HW_FRAME_BUFFER_VALID) return;
#endif
	if ((size_t)w * h * 4 > g_rgba_cap) {
		g_rgba_cap = (size_t)w * h * 4;
		g_rgba = (uint8_t *)realloc(g_rgba, g_rgba_cap);
	}
	g_frame_w = w;
	g_frame_h = h;
	o = g_rgba;
	for (y = 0; y < h; y++) {
		const uint8_t *row = (const uint8_t *)data + y * pitch;
		for (x = 0; x < w; x++) {
			uint8_t r, g, b;
			if (g_pixel_format == RETRO_PIXEL_FORMAT_XRGB8888) {
				uint32_t v = ((const uint32_t *)row)[x];
				r = (v >> 16) & 255; g = (v >> 8) & 255; b = v & 255;
			} else if (g_pixel_format == RETRO_PIXEL_FORMAT_RGB565) {
				uint16_t v = ((const uint16_t *)row)[x];
				r = (uint8_t)(((v >> 11) & 31) * 255 / 31);
				g = (uint8_t)(((v >> 5) & 63) * 255 / 63);
				b = (uint8_t)((v & 31) * 255 / 31);
			} else {
				uint16_t v = ((const uint16_t *)row)[x];
				r = (uint8_t)(((v >> 10) & 31) * 255 / 31);
				g = (uint8_t)(((v >> 5) & 31) * 255 / 31);
				b = (uint8_t)((v & 31) * 255 / 31);
			}
			*o++ = r; *o++ = g; *o++ = b; *o++ = 255;
		}
	}
	g_have_video = 1;
}

static void audio_push(const int16_t *d, size_t frames) {
	size_t need, i;
	LOCK(g_audio_lock);
	need = g_audio_n + frames * 2;
	if (need > 400000) {                 /* nobody is taking it (paused): drop the oldest rather than grow forever */
		g_audio_n = 0;
		need = frames * 2;
	}
	if (need > g_audio_cap) {
		g_audio_cap = need * 2;
		g_audio = (float *)realloc(g_audio, g_audio_cap * sizeof(float));
	}
	for (i = 0; i < frames * 2; i++) g_audio[g_audio_n + i] = (float)d[i] * (1.0f / 32768.0f);
	g_audio_n += frames * 2;
	UNLOCK(g_audio_lock);
}

/* take everything gathered so far (from whichever thread made it); returns the number of float values */
static size_t audio_take(void) {
	size_t n;
	LOCK(g_audio_lock);
	n = g_audio_n;
	if (n > g_audio_out_cap) {
		g_audio_out_cap = n * 2;
		g_audio_out = (float *)realloc(g_audio_out, g_audio_out_cap * sizeof(float));
	}
	if (n) memcpy(g_audio_out, g_audio, n * sizeof(float));
	g_audio_n = 0;
	UNLOCK(g_audio_lock);
	return n;
}
static void RETRO_CALLCONV audio_cb(int16_t l, int16_t r) { int16_t s[2]; s[0] = l; s[1] = r; audio_push(s, 1); }
static size_t RETRO_CALLCONV audio_batch_cb(const int16_t *d, size_t frames) { audio_push(d, frames); return frames; }
static void RETRO_CALLCONV input_poll_cb(void) {}
static int16_t RETRO_CALLCONV input_state_cb(unsigned port, unsigned device, unsigned index, unsigned id) {
	unsigned base = device & RETRO_DEVICE_MASK;
	(void)index;
	if (port > 1) return 0;
	if (base == RETRO_DEVICE_JOYPAD) {
		if (id == RETRO_DEVICE_ID_JOYPAD_MASK) return (int16_t)g_buttons[port];
		return id > 15 ? 0 : (g_buttons[port] >> id) & 1;
	}
	if (base == RETRO_DEVICE_ANALOG) {
		if (index == RETRO_DEVICE_INDEX_ANALOG_LEFT || index == RETRO_DEVICE_INDEX_ANALOG_RIGHT) {
			int k = (index == RETRO_DEVICE_INDEX_ANALOG_RIGHT ? 2 : 0) + (id == RETRO_DEVICE_ID_ANALOG_Y ? 1 : 0);
			return g_stick[port][k];
		}
		if (index == RETRO_DEVICE_INDEX_ANALOG_BUTTON) {
			/* analog L / R; a pad with only digital ones (or any other button) reads full when pressed */
			int dig = id <= 15 ? (g_buttons[port] >> id) & 1 : 0;
			if (id == RETRO_DEVICE_ID_JOYPAD_L2 && g_trig[port][0]) return (int16_t)g_trig[port][0];
			if (id == RETRO_DEVICE_ID_JOYPAD_R2 && g_trig[port][1]) return (int16_t)g_trig[port][1];
			return dig ? 0x7FFF : 0;
		}
		return 0;
	}
	if (base == RETRO_DEVICE_LIGHTGUN || base == RETRO_DEVICE_MOUSE) {
		uint8_t b = g_gun_b[port];
		switch (id) {
			case RETRO_DEVICE_ID_LIGHTGUN_SCREEN_X: return g_gun_x[port];
			case RETRO_DEVICE_ID_LIGHTGUN_SCREEN_Y: return g_gun_y[port];
			case RETRO_DEVICE_ID_LIGHTGUN_IS_OFFSCREEN: return (b >> 1) & 1;
			case RETRO_DEVICE_ID_LIGHTGUN_TRIGGER: return b & 1;
			case RETRO_DEVICE_ID_LIGHTGUN_RELOAD: return (b >> 2) & 1;
			case RETRO_DEVICE_ID_LIGHTGUN_AUX_A: return (b >> 3) & 1;
			case RETRO_DEVICE_ID_LIGHTGUN_AUX_B: return (b >> 4) & 1;
			case RETRO_DEVICE_ID_LIGHTGUN_START: return (b >> 5) & 1;
			case RETRO_DEVICE_ID_LIGHTGUN_SELECT: return (b >> 6) & 1;
			case RETRO_DEVICE_ID_LIGHTGUN_X:          /* the old, relative kind (SNES): the step to where it points now */
			case RETRO_DEVICE_ID_LIGHTGUN_Y: {
				int axis = id == RETRO_DEVICE_ID_LIGHTGUN_X ? 0 : 1;
				int size = axis == 0 ? (int)g_geo_w : (int)g_geo_h;
				int v = axis == 0 ? g_gun_x[port] : g_gun_y[port];
				int want = (int)(((long)v + 32767) * size / 65534);
				int step = want - g_gun_px[port][axis];
				g_gun_px[port][axis] = want;
				return (int16_t)step;
			}
			default: return 0;
		}
	}
	if (base == RETRO_DEVICE_POINTER) {
		switch (id) {
			case RETRO_DEVICE_ID_POINTER_X: return g_gun_x[port];
			case RETRO_DEVICE_ID_POINTER_Y: return g_gun_y[port];
			case RETRO_DEVICE_ID_POINTER_PRESSED: return g_gun_b[port] & 1;
			default: return 0;
		}
	}
	return 0;
}


/* plug the core's own light gun into a port (or a pad back in); returns the type's name */
static const char *plug_gun(unsigned port, int on) {
	static const char *names[] = {"zapper", "super scope", "superscope", "menacer", "guncon", "justifier", "phaser", "light gun", "lightgun", NULL};
	unsigned k;
	int n;
	if (port > 1) return "";
	if (!on) {
		c_set_controller_port_device(port, RETRO_DEVICE_JOYPAD);
		return "pad";
	}
	for (n = 0; names[n]; n++) {
		for (k = 0; k < g_type_n[port]; k++) {
			char low[48];
			unsigned i;
			for (i = 0; i < sizeof(low) - 1 && g_type_desc[port][k][i]; i++) low[i] = (char)tolower((unsigned char)g_type_desc[port][k][i]);
			low[i] = 0;
			if (strstr(low, names[n])) {
				c_set_controller_port_device(port, g_type_id[port][k]);
				g_gun_px[port][0] = g_gun_px[port][1] = 0;
				return g_type_desc[port][k];
			}
		}
	}
	return "";
}


/* ---------------------------------------------------------------- clock and waiting */

#ifdef _WIN32
__declspec(dllimport) unsigned int timeBeginPeriod(unsigned int);
static double now_s(void) {
	static LARGE_INTEGER f;
	LARGE_INTEGER c;
	if (!f.QuadPart) QueryPerformanceFrequency(&f);
	QueryPerformanceCounter(&c);
	return (double)c.QuadPart / (double)f.QuadPart;
}
#else
#include <time.h>
static double now_s(void) {
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec * 1e-9;
}
#endif

/* 1 = a command is waiting, 0 = timed out, -1 = error */
static int wait_readable(double seconds) {
	fd_set fds;
	struct timeval tv;
	int r;
	if (seconds < 0) seconds = 0;
	FD_ZERO(&fds);
	FD_SET(g_sock, &fds);
	tv.tv_sec = (long)seconds;
	tv.tv_usec = (long)((seconds - (double)tv.tv_sec) * 1e6);
	r = select((int)g_sock + 1, &fds, NULL, NULL, &tv);
	return r < 0 ? -1 : (r > 0 ? 1 : 0);
}

/* ---------------------------------------------------------------- save files */

static char g_srm_path[2048];

static void load_srm(void) {
	size_t n = c_get_memory_size(RETRO_MEMORY_SAVE_RAM);
	void *d = c_get_memory_data(RETRO_MEMORY_SAVE_RAM);
	FILE *f;
	if (!d || n == 0) return;
	f = open_file(g_srm_path, "rb");
	if (!f) return;
	if (fread(d, 1, n, f) == 0) logf_("empty save file");
	fclose(f);
	logf_("battery save loaded (%u bytes)", (unsigned)n);
}
static void save_srm(void) {
	size_t n = c_get_memory_size(RETRO_MEMORY_SAVE_RAM);
	void *d = c_get_memory_data(RETRO_MEMORY_SAVE_RAM);
	FILE *f;
	if (!d || n == 0) return;
	f = open_file(g_srm_path, "wb");
	if (!f) { logf_("cannot write %s", g_srm_path); return; }
	fwrite(d, 1, n, f);
	fclose(f);
}

/* A "resume" state: where the game was left, written when the game ends, the power goes off or every so often. */
static char g_state_path[2048];
static char g_core_id[160] = "";      /* core name + version, kept next to each saved position */
static int g_resume_pending = 0;      /* the saved position is not loaded yet: don't write over it */

static int replace_file(const char *from, const char *to) {
#ifdef _WIN32
	wchar_t *a = to_wide(from), *b = to_wide(to);
	int ok = MoveFileExW(a, b, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != 0;
	free(a); free(b);
	return ok;
#else
	return rename(from, to) == 0;
#endif
}

static void save_state(void) {
	size_t n;
	void *buf;
	FILE *f;
	char tmp[2100];
	if (g_state_path[0] == 0 || g_resume_pending) return;
	n = c_serialize_size();
	if (n == 0) return;
	buf = malloc(n);
	if (!buf) return;
	if (c_serialize(buf, n)) {
		/* written next to it first, then swapped in: a game closed half way through never leaves a broken file */
		snprintf(tmp, sizeof(tmp), "%s.tmp", g_state_path);
		f = open_file(tmp, "wb");
		if (f) {
			int ok = fwrite(buf, 1, n, f) == n;
			ok = (fclose(f) == 0) && ok;
			if (!ok || !replace_file(tmp, g_state_path)) logf_("cannot write %s", g_state_path);
			else {
				/* which core wrote it: a newer core (an update) may not read an older one's positions safely */
				FILE *c;
				snprintf(tmp, sizeof(tmp), "%s.core", g_state_path);
				c = open_file(tmp, "wb");
				if (c) { fputs(g_core_id, c); fclose(c); }
			}
		}
		else logf_("cannot write %s", g_state_path);
	}
	free(buf);
}

static void load_state(void) {
	size_t n, got;
	long fsize;
	void *buf;
	FILE *f;
	g_resume_pending = 0;
	{
		/* written by a different version of the core (an update came in between)? Dolphin, for one, can crash on
		   those, so the game starts fresh instead. (Positions from before this check have no note: they are tried.) */
		char note[2100], was[160];
		FILE *c;
		snprintf(note, sizeof(note), "%s.core", g_state_path);
		c = open_file(note, "rb");
		if (c) {
			size_t k = fread(was, 1, sizeof(was) - 1, c);
			fclose(c);
			was[k] = 0;
			if (strcmp(was, g_core_id) != 0) {
				logf_("the saved position is from another core version (%s), starting fresh", was);
				return;
			}
		}
	}
	f = open_file(g_state_path, "rb");
	if (!f) return;
	n = c_serialize_size();
	if (g_heavy) {                    /* (Dolphin's size can differ a little between runs: read the whole file) */
		fseek(f, 0, SEEK_END);
		fsize = ftell(f);
		fseek(f, 0, SEEK_SET);
		if (fsize > 0) n = (size_t)fsize;
	}
	buf = n ? malloc(n) : NULL;
	if (!buf) { fclose(f); return; }
	got = fread(buf, 1, n, f);
	fclose(f);
	if (got == n && c_unserialize(buf, n)) logf_("resumed from the saved position");
	else logf_("the saved position does not fit this game (ignored)");
	free(buf);
}

static const char *base_name(const char *p) {
	const char *a = strrchr(p, '/'), *b = strrchr(p, '\\');
	if (b > a) a = b;
	return a ? a + 1 : p;
}

/* ---------------------------------------------------------------- main */

#define SYM(var, name) do { *(void **)&(var) = get_sym(lib, name); if (!(var)) { send_error("core is missing " name); return 2; } } while (0)

int main(int argc, char **argv) {
	void *lib;
	struct retro_system_info si;
	struct retro_game_info gi;
	struct retro_system_av_info av;
	FILE *rf;
	uint8_t *rom;
	long rom_size;
	unsigned frame_counter = 0, saved_at = 0;
	int running = 1;
	int port;
	struct sockaddr_in addr;
#ifdef _WIN32
	WSADATA wsa;
	int argc_w = 0;
	char **argv_w = NULL;
	(void)argc_w; (void)argv_w;
#endif
#ifdef _WIN32
	argv = win_args(&argc);
#endif
	if (argc < 6) return 1;
	port = atoi(argv[1]);
	if (argc > 6) g_log = open_file(argv[6], "w");
	g_system_dir = argv[5];
	g_save_dir = argv[4];
	LOCK_INIT(g_audio_lock);
	logf_("retro_host starting: core=%s rom=%s", argv[2], argv[3]);
#ifdef _WIN32
	WSAStartup(MAKEWORD(2, 2), &wsa);
	timeBeginPeriod(1);
#endif
	g_sock = socket(AF_INET, SOCK_STREAM, 0);
	if (g_sock == INVALID_SOCKET) return 3;
	memset(&addr, 0, sizeof(addr));
	addr.sin_family = AF_INET;
	addr.sin_port = htons((unsigned short)port);
	addr.sin_addr.s_addr = htonl(0x7F000001);
	{   /* Godot listens, we connect: no firewall pop-ups, no port clashes */
		int tries;
		for (tries = 0; tries < 100; tries++) {
			if (connect(g_sock, (struct sockaddr *)&addr, sizeof(addr)) == 0) break;
#ifdef _WIN32
			Sleep(50);
#else
			usleep(50000);
#endif
		}
		if (tries >= 100) { logf_("cannot connect to the game"); return 4; }
	}
	{
		int one = 1;
		setsockopt(g_sock, IPPROTO_TCP, 1 /* TCP_NODELAY */, (const char *)&one, sizeof(one));
	}
	lib = open_lib(argv[2]);
	if (!lib) { send_error("cannot load the core"); return 5; }
	SYM(c_set_environment, "retro_set_environment");
	SYM(c_set_video_refresh, "retro_set_video_refresh");
	SYM(c_set_audio_sample, "retro_set_audio_sample");
	SYM(c_set_audio_sample_batch, "retro_set_audio_sample_batch");
	SYM(c_set_input_poll, "retro_set_input_poll");
	SYM(c_set_input_state, "retro_set_input_state");
	SYM(c_init, "retro_init");
	SYM(c_deinit, "retro_deinit");
	SYM(c_api_version, "retro_api_version");
	SYM(c_get_system_info, "retro_get_system_info");
	SYM(c_get_system_av_info, "retro_get_system_av_info");
	SYM(c_load_game, "retro_load_game");
	SYM(c_unload_game, "retro_unload_game");
	SYM(c_run, "retro_run");
	SYM(c_reset, "retro_reset");
	SYM(c_set_controller_port_device, "retro_set_controller_port_device");
	SYM(c_get_memory_data, "retro_get_memory_data");
	SYM(c_get_memory_size, "retro_get_memory_size");
	SYM(c_serialize_size, "retro_serialize_size");
	SYM(c_serialize, "retro_serialize");
	SYM(c_unserialize, "retro_unserialize");
	if (c_api_version() != RETRO_API_VERSION) { send_error("wrong libretro version"); return 6; }
	memset(&si, 0, sizeof(si));
	c_get_system_info(&si);
	if (si.library_name) {
		char low[64];
		unsigned i;
		for (i = 0; i < sizeof(low) - 1 && si.library_name[i]; i++) low[i] = (char)tolower((unsigned char)si.library_name[i]);
		low[i] = 0;
		g_heavy = strstr(low, "dolphin") != NULL;
		snprintf(g_core_id, sizeof(g_core_id), "%s %s", si.library_name, si.library_version ? si.library_version : "");
		logf_("core: %s %s", si.library_name, si.library_version ? si.library_version : "");
	}
	c_set_environment(env_cb);
	c_init();
	c_set_video_refresh(video_cb);
	c_set_audio_sample(audio_cb);
	c_set_audio_sample_batch(audio_batch_cb);
	c_set_input_poll(input_poll_cb);
	c_set_input_state(input_state_cb);

	memset(&gi, 0, sizeof(gi));
	gi.path = argv[3];
	if (si.need_fullpath) {
		/* (discs: the core reads the image itself, from the path; a .cue names its tracks) */
		rf = open_file(argv[3], "rb");
		if (!rf) { send_error("cannot open the game"); return 7; }
		fclose(rf);
	} else {
		rf = open_file(argv[3], "rb");
		if (!rf) { send_error("cannot open the ROM"); return 7; }
		fseek(rf, 0, SEEK_END);
		rom_size = ftell(rf);
		fseek(rf, 0, SEEK_SET);
		rom = (uint8_t *)malloc((size_t)rom_size + 1);
		if (fread(rom, 1, (size_t)rom_size, rf) != (size_t)rom_size) { send_error("cannot read the ROM"); return 7; }
		fclose(rf);
		gi.data = rom;
		gi.size = (size_t)rom_size;
	}
	if (!c_load_game(&gi)) { send_error("the core does not accept this game"); return 8; }
	memset(&av, 0, sizeof(av));
	c_get_system_av_info(&av);
	if (av.geometry.base_width > 0) g_geo_w = av.geometry.base_width;
	if (av.geometry.base_height > 0) g_geo_h = av.geometry.base_height;
#ifdef _WIN32
	if (g_use_hw) {
		/* the GPU core gets its framebuffer now, then is told its context is ready */
		if (av.geometry.max_width > g_fb_want_w) g_fb_want_w = av.geometry.max_width;
		if (av.geometry.max_height > g_fb_want_h) g_fb_want_h = av.geometry.max_height;
		if (!gl_make_fb(g_fb_want_w, g_fb_want_h)) { send_error("the graphics card could not make a picture for this core"); return 9; }
		if (g_hw.context_reset) g_hw.context_reset();
	}
#endif
	snprintf(g_srm_path, sizeof(g_srm_path), "%s/%s.srm", g_save_dir, base_name(argv[3]));
	load_srm();
	g_state_path[0] = 0;
	if (argc > 7 && argv[7][0]) snprintf(g_state_path, sizeof(g_state_path), "%s", argv[7]);
	{
		uint8_t hello[1 + 8 + 8 + 4 + 4];
		double fps = av.timing.fps > 1.0 ? av.timing.fps : 60.0;
		double rate = av.timing.sample_rate > 1000.0 ? av.timing.sample_rate : 44100.0;
		uint32_t w = av.geometry.base_width, h = av.geometry.base_height;
		hello[0] = 'H';
		memcpy(hello + 1, &fps, 8);
		memcpy(hello + 9, &rate, 8);
		memcpy(hello + 17, &w, 4);
		memcpy(hello + 21, &h, 4);
		send_all(hello, sizeof(hello));
	}
	logf_("game running");

	{
		double period = 1.0 / (av.timing.fps > 1.0 ? av.timing.fps : 60.0);
		double speed = 1.0, next = now_s();
		int paused = 0, credit = 1;
		int resume = (argc > 8 && argv[8][0] == '1' && g_state_path[0] != 0);
		unsigned resume_tries = 0;
		g_resume_pending = resume && g_heavy;
		g_fps_now = av.timing.fps > 1.0 ? av.timing.fps : 60.0;
		while (running) {
			double t = now_s();
			if (paused || next > t) {
				double w = paused ? 0.05 : next - t;
				int r = wait_readable(w);
				if (r < 0) break;
				if (r > 0) {
					uint8_t cmd;
					if (!recv_all(&cmd, 1)) break;
					if (cmd == 'B') {
						uint8_t b[4];
						if (!recv_all(b, 4)) break;
						g_buttons[0] = (uint16_t)(b[0] | (b[1] << 8));
						g_buttons[1] = (uint16_t)(b[2] | (b[3] << 8));
					} else if (cmd == 'L') {
						uint8_t v[2];
						const char *what;
						uint8_t msg[64];
						size_t n;
						if (!recv_all(v, 2)) break;
						what = plug_gun(v[0], v[1]);
						logf_("port %d: %s", v[0], what[0] ? what : "(no light gun on this port)");
						n = strlen(what);
						if (n > 60) n = 60;
						msg[0] = 'I';
						msg[1] = (uint8_t)n;
						memcpy(msg + 2, what, n);
						if (!send_all(msg, 2 + n)) break;
					} else if (cmd == 'G') {
						uint8_t v[6];
						unsigned port;
						if (!recv_all(v, 6)) break;
						port = v[0] & 1;
						g_gun_x[port] = (int16_t)(v[1] | (v[2] << 8));
						g_gun_y[port] = (int16_t)(v[3] | (v[4] << 8));
						g_gun_b[port] = v[5];
					} else if (cmd == 'X') {
						uint8_t v[13];
						unsigned port, k;
						if (!recv_all(v, 13)) break;
						port = v[0] & 1;
						for (k = 0; k < 4; k++) g_stick[port][k] = (int16_t)(v[1 + k * 2] | (v[2 + k * 2] << 8));
						g_trig[port][0] = (uint16_t)(v[9] | (v[10] << 8));
						g_trig[port][1] = (uint16_t)(v[11] | (v[12] << 8));
						if (g_trig[port][0] > 0x7FFF) g_trig[port][0] = 0x7FFF;
						if (g_trig[port][1] > 0x7FFF) g_trig[port][1] = 0x7FFF;
					} else if (cmd == 'S') {
						save_srm();
					} else if (cmd == 'T') {
						save_state();
					} else if (cmd == 'R') {
						c_reset();
					} else if (cmd == 'P') {
						uint8_t v;
						if (!recv_all(&v, 1)) break;
						paused = v;
						next = now_s();
					} else if (cmd == 'M') {
						uint8_t v;
						if (!recv_all(&v, 1)) break;
						speed = (v < 80 ? 80 : (v > 120 ? 120 : v)) / 100.0;
					} else if (cmd == 'D') {
						credit = 1;
					} else if (cmd == 'Q') {
						break;
					}
				}
				continue;
			}
			g_have_video = 0;
			g_want_frame = credit;
			c_run();
			frame_counter++;
#ifdef _WIN32
			if (g_use_hw && (g_fb_want_w > g_fb_w || g_fb_want_h > g_fb_h)) gl_make_fb(g_fb_want_w, g_fb_want_h);
#endif
			if (resume) {
				if (!g_heavy) { resume = 0; load_state(); }
				/* Dolphin boots over its first frames and only takes a saved position once it is really running */
				else if (frame_counter >= 30 && (frame_counter % 15) == 0) {
					if (c_serialize_size() > 0) { resume = 0; load_state(); }
					else if (++resume_tries > 40) { resume = 0; g_resume_pending = 0; logf_("the game never got ready for its saved position"); }
				}
			}
			if (g_have_video && credit) {
				uint8_t hdr[9];
				uint32_t w = g_frame_w, h = g_frame_h;
				hdr[0] = 'V';
				memcpy(hdr + 1, &w, 4);
				memcpy(hdr + 5, &h, 4);
				credit = 0;
				if (!send_all(hdr, 9) || !send_all(g_rgba, (size_t)w * h * 4)) break;
			}
			{
				size_t an = audio_take();
				if (an > 0) {
					uint8_t hdr[5];
					uint32_t cnt = (uint32_t)(an / 2);
					hdr[0] = 'A';
					memcpy(hdr + 1, &cnt, 4);
					if (!send_all(hdr, 5) || !send_all(g_audio_out, an * sizeof(float))) break;
				}
			}
			{
				uint8_t k[5];
				k[0] = 'K';
				memcpy(k + 1, &frame_counter, 4);
				if (!send_all(k, 5)) break;
			}
			if (frame_counter - saved_at > 900) {   /* about every 15 seconds */
				save_srm();
				/* (a Dolphin state is tens of MB and stalls the game: only when the power goes off or the game ends.
				   Its memory cards it writes itself, all the time.) */
				if (!g_heavy) save_state();
				saved_at = frame_counter;
			}
			if (g_fps_now > 1.0) period = 1.0 / g_fps_now;
			next += period / speed;
			t = now_s();
			if (t - next > 0.1) next = t;           /* fell far behind (a hitch): do not race to catch up */
		}
	}
	save_srm();
	save_state();
	c_unload_game();
	c_deinit();
	logf_("bye");
	CLOSESOCK(g_sock);
	return 0;
}
