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
typedef SOCKET sock_t;
#define CLOSESOCK closesocket
#else
#include <dlfcn.h>
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
static uint16_t g_buttons[2] = {0, 0};
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
		case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO:
			return true;
		case RETRO_ENVIRONMENT_GET_VARIABLE: {
			/* a few core options of our own; the rest stay at the core's defaults */
			static const char *opts[][2] = {
				/* PCSX ReARMed's recompiler crashes after a saved position is loaded, and the
				   interpreter is quick enough on a PC */
				{ "pcsx_rearmed_drc", "disabled" },
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
	size_t need = g_audio_n + frames * 2, i;
	if (need > g_audio_cap) {
		g_audio_cap = need * 2;
		g_audio = (float *)realloc(g_audio, g_audio_cap * sizeof(float));
	}
	for (i = 0; i < frames * 2; i++) g_audio[g_audio_n + i] = (float)d[i] * (1.0f / 32768.0f);
	g_audio_n += frames * 2;
}
static void RETRO_CALLCONV audio_cb(int16_t l, int16_t r) { int16_t s[2]; s[0] = l; s[1] = r; audio_push(s, 1); }
static size_t RETRO_CALLCONV audio_batch_cb(const int16_t *d, size_t frames) { audio_push(d, frames); return frames; }
static void RETRO_CALLCONV input_poll_cb(void) {}
static int16_t RETRO_CALLCONV input_state_cb(unsigned port, unsigned device, unsigned index, unsigned id) {
	unsigned base = device & RETRO_DEVICE_MASK;
	(void)index;
	if (port > 1) return 0;
	if (base == RETRO_DEVICE_JOYPAD) return id > 15 ? 0 : (g_buttons[port] >> id) & 1;
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

static void save_state(void) {
	size_t n;
	void *buf;
	FILE *f;
	if (g_state_path[0] == 0) return;
	n = c_serialize_size();
	if (n == 0) return;
	buf = malloc(n);
	if (!buf) return;
	if (c_serialize(buf, n)) {
		f = open_file(g_state_path, "wb");
		if (f) { fwrite(buf, 1, n, f); fclose(f); }
		else logf_("cannot write %s", g_state_path);
	}
	free(buf);
}

static void load_state(void) {
	size_t n, got;
	void *buf;
	FILE *f = open_file(g_state_path, "rb");
	if (!f) return;
	n = c_serialize_size();
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
			g_audio_n = 0;
			c_run();
			frame_counter++;
			if (resume) { resume = 0; load_state(); }
			if (g_have_video && credit) {
				uint8_t hdr[9];
				uint32_t w = g_frame_w, h = g_frame_h;
				hdr[0] = 'V';
				memcpy(hdr + 1, &w, 4);
				memcpy(hdr + 5, &h, 4);
				credit = 0;
				if (!send_all(hdr, 9) || !send_all(g_rgba, (size_t)w * h * 4)) break;
			}
			if (g_audio_n > 0) {
				uint8_t hdr[5];
				uint32_t cnt = (uint32_t)(g_audio_n / 2);
				hdr[0] = 'A';
				memcpy(hdr + 1, &cnt, 4);
				if (!send_all(hdr, 5) || !send_all(g_audio, g_audio_n * sizeof(float))) break;
			}
			{
				uint8_t k[5];
				k[0] = 'K';
				memcpy(k + 1, &frame_counter, 4);
				if (!send_all(k, 5)) break;
			}
			if (frame_counter - saved_at > 900) {   /* about every 15 seconds */
				save_srm();
				save_state();
				saved_at = frame_counter;
			}
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
