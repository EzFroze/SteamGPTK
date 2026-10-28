// Compatibility tool support
#include "compat.h"
#include "../util/log.h"
#include "../util/file.h"

#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

// The client maps Cloud's Windows path roots into the compat prefix only when
// the tool's name contains "proton" so without a match every AutoCloud rule silently
// skips the app.
#define TOOL_DIR_NAME "steamgptk-proton"
#define TOOL_DISPLAY_NAME "SteamGPTK (Wine / GPTK)"

#define COMPAT_MANAGER_ENABLED_OFF  0x7B0
#define COMPAT_TOOL_STRIDE          0x130
#define COMPAT_TOOL_FLAGS_OFF       0x28  // bit 0: tool needs no downloaded app
#define COMPAT_TOOL_FLAG_NO_APP     0x1
#define COMPAT_TOOL_FROM_OSLIST_OFF 0x70
#define COMPAT_TOOL_TO_OSLIST_OFF   0x78

#define COMPAT_MAPPING_PRIORITY_GLOBAL 75
#define COMPAT_MAPPING_PRIORITY_APP    250

static const char TOOL_MANIFEST[] =
    "\"manifest\"\n"
    "{\n"
    "  \"version\" \"2\"\n"
    "  \"commandline\" \"/run %verb%\"\n"
    "}\n";

// Steam's compatibilitytools.d scanner registers a tool when this file is present
// in the tool subdirectory. install_path is "." because the manifest lives inside
// the tool directory. to_oslist is macos
static const char TOOL_DECLARATION[] =
    "\"compatibilitytools\"\n"
    "{\n"
    "  \"compat_tools\"\n"
    "  {\n"
    "    \"" TOOL_DIR_NAME "\"\n"
    "    {\n"
    "      \"install_path\" \".\"\n"
    "      \"display_name\" \"" TOOL_DISPLAY_NAME "\"\n"
    "      \"from_oslist\" \"windows\"\n"
    "      \"to_oslist\" \"macos\"\n"
    "    }\n"
    "  }\n"
    "}\n";

#include "compat_run.h"  // RUN_SCRIPT, generated from compat_run.sh

static int write_file(const char *path, const char *content, int executable) {
    FILE *f = fopen(path, "w");
    if (!f) return -1;
    fputs(content, f);
    int err = fclose(f);
    if (executable)
        chmod(path, 0755);
    return err ? -1 : 0;
}

static int ensure_dir(const char *path) {
    struct stat st;
    if (stat(path, &st) == 0)
        return S_ISDIR(st.st_mode) ? 0 : -1;
    return mkdir(path, 0755);
}

static int32_t g_tool_shift;

// LDR Wt,[X0,#imm]. Writes the byte offset and destination register.
static int ldr32_from_x0(uint32_t w, uint32_t *off, uint32_t *rt) {
    if ((w & 0xFFC003E0u) != 0xB9400000u) return 0;
    *rt  = w & 0x1Fu;
    *off = ((w >> 10) & 0xFFFu) * 4u;
    return 1;
}

// LDR Xt,[Xn,#imm] for a named base register.
static int ldr64_from(uint32_t w, uint32_t base, uint32_t *off) {
    if ((w & 0xFFC00000u) != 0xF9400000u) return 0;
    if (((w >> 5) & 0x1Fu) != base) return 0;
    *off = ((w >> 10) & 0xFFFu) * 8u;
    return 1;
}

static int ldr64_from_x0(uint32_t w, uint32_t *off) {
    return ldr64_from(w, 0, off);
}

// LDRB Wt,[Xn,#imm] for a named base register.
static int ldrb_from(uint32_t w, uint32_t base, uint32_t *off) {
    if ((w & 0xFFC00000u) != 0x39400000u) return 0;
    if (((w >> 5) & 0x1Fu) != base) return 0;
    *off = (w >> 10) & 0xFFFu;
    return 1;
}

// MOV Xd,X0, which assembles as ORR Xd,XZR,X0. Writes the destination register.
static int mov_from_x0(uint32_t w, uint32_t *rd) {
    if ((w & 0xFFFFFFE0u) != 0xAA0003E0u) return 0;
    *rd = w & 0x1Fu;
    return 1;
}

// CBZ Wt. Writes the branch target.
static int cbz32(uintptr_t pc, uint32_t w, uint32_t rt, uintptr_t *target) {
    if ((w & 0xFF000000u) != 0x34000000u) return 0;
    if ((w & 0x1Fu) != rt) return 0;
    int32_t imm = (int32_t)((w >> 5) & 0x7FFFFu);
    imm = (imm << 13) >> 13;
    *target = pc + (uintptr_t)(imm * 4);
    return 1;
}

// The oslist gate compares both oslist strings, so its two loads sit at the far
// end of the struct and corroborate a shift derived at the near end. The base
// register is whatever the compiler picked, so a build that stops using the one
// seen here yields nothing and the shift stands on the near-end pair alone.
// Returns the number of offsets written.
static int probe_oslist_offsets(uintptr_t oslist_gate, uint32_t base,
                                uint32_t *from_off, uint32_t *to_off) {
    if (!oslist_gate) return 0;

    uint32_t seen[2];
    int n = 0;
    for (uintptr_t pc = oslist_gate - 0x40; pc <= oslist_gate + 0x20; pc += 4) {
        uint32_t off;
        if (!ldr64_from(*(const uint32_t *)pc, base, &off)) continue;
        if (n > 0 && seen[0] == off) continue;
        if (n > 1 && seen[1] == off) continue;
        if (n == 2) return 0;
        seen[n++] = off;
    }
    if (n != 2) return 0;

    // to_oslist sits above from_oslist in the struct, whichever order the
    // comparison happens to load them in.
    *to_off   = seen[0] > seen[1] ? seen[0] : seen[1];
    *from_off = seen[0] > seen[1] ? seen[1] : seen[0];
    return 2;
}

int np_compat_probe_tool_layout(uintptr_t appid_gate, uintptr_t oslist_gate) {
    if (!appid_gate) return 0;

    uint32_t appid_off, rt;
    if (!ldr32_from_x0(*(const uint32_t *)appid_gate, &appid_off, &rt)) {
        NP_WARN("np_compat_probe_tool_layout: 0x%lx is not the appid load",
                (unsigned long)appid_gate);
        return 0;
    }

    uintptr_t local_path;
    if (!cbz32(appid_gate + 4, *(const uint32_t *)(appid_gate + 4), rt, &local_path)) {
        NP_WARN("np_compat_probe_tool_layout: no appid branch after 0x%lx",
                (unsigned long)appid_gate);
        return 0;
    }

    // The install field is the first thing the local path wants, within a few
    // instructions of the branch landing.
    uint32_t install_off = 0;
    for (uintptr_t pc = local_path; pc < local_path + 0x20; pc += 4) {
        if (ldr64_from_x0(*(const uint32_t *)pc, &install_off)) break;
    }
    if (!install_off) {
        NP_WARN("np_compat_probe_tool_layout: no install load at 0x%lx",
                (unsigned long)local_path);
        return 0;
    }

    int32_t by_appid   = (int32_t)appid_off   - COMPAT_TOOL_APPID_OFF;
    int32_t by_install = (int32_t)install_off - COMPAT_TOOL_INSTALL_OFF;
    if (by_appid != by_install) {
        NP_ERR("np_compat_probe_tool_layout: appid moved %+d but install moved %+d; "
               "the tool layout no longer shifts as one block",
               by_appid, by_install);
        return 0;
    }

    // COMPAT_TOOL_TO_OSLIST_OFF is the highest field written into a registration,
    // so agreement there means the shift holds across every field in use rather
    // than only the two it was read from.
    uint32_t from_off = 0, to_off = 0;
    if (probe_oslist_offsets(oslist_gate, 21, &from_off, &to_off) == 2) {
        int32_t by_from = (int32_t)from_off - COMPAT_TOOL_FROM_OSLIST_OFF;
        int32_t by_to   = (int32_t)to_off   - COMPAT_TOOL_TO_OSLIST_OFF;
        if (by_from != by_appid || by_to != by_appid) {
            NP_ERR("np_compat_probe_tool_layout: near fields moved %+d but oslist "
                   "moved %+d/%+d; the tool layout no longer shifts as one block",
                   by_appid, by_from, by_to);
            return 0;
        }
        NP_DBG("np_compat_probe_tool_layout: oslist offsets 0x%x/0x%x agree on %+d",
               from_off, to_off, by_appid);
    }

    g_tool_shift = by_appid;
    if (g_tool_shift)
        NP_LOG("np_compat_probe_tool_layout: tool fields from install onward are "
               "%+d from the baseline (appid 0x%x, install 0x%x)",
               g_tool_shift, appid_off, install_off);
    return 1;
}

// The manager is a much larger object than a tool entry and grows in the middle,
// so a single distance does not describe it the way one does for the tool tail:
// the tool array and its count sit below the growth and do not move, while the
// enabled flag sits above it and does. Reading the flag's own offset back keeps
// the two independent.
static uint32_t g_enabled_off = COMPAT_MANAGER_ENABLED_OFF;

int np_compat_probe_enabled_off(uintptr_t bis_enabled) {
    if (!bis_enabled) return 0;

    // this arrives in X0 and is parked in a callee-saved register before the
    // profiling call clobbers it, so the flag is read through that register.
    uint32_t base = 0;
    int have_base = 0;
    for (uintptr_t pc = bis_enabled; pc < bis_enabled + 0x40; pc += 4) {
        if (mov_from_x0(*(const uint32_t *)pc, &base)) { have_base = 1; break; }
    }
    if (!have_base) {
        NP_WARN("np_compat_probe_enabled_off: this is never parked in a register "
                "at 0x%lx", (unsigned long)bis_enabled);
        return 0;
    }

    // The flag is the first thing the body tests, ahead of any other byte read
    // through that register.
    uint32_t off = 0;
    int found = 0;
    for (uintptr_t pc = bis_enabled; pc < bis_enabled + 0x80; pc += 4) {
        if (ldrb_from(*(const uint32_t *)pc, base, &off)) { found = 1; break; }
    }
    if (!found) {
        NP_WARN("np_compat_probe_enabled_off: no flag load through x%u at 0x%lx",
                base, (unsigned long)bis_enabled);
        return 0;
    }

    // A tiny offset would mean the match landed on some unrelated early byte
    // read rather than on the flag, which sits far into the object.
    if (off < 0x100) {
        NP_ERR("np_compat_probe_enabled_off: 0x%x is too low to be the enabled "
               "flag; refusing to write it", off);
        return 0;
    }

    if (off != g_enabled_off)
        NP_LOG("np_compat_probe_enabled_off: enabled flag at 0x%x, %+d from the "
               "baseline", off, (int32_t)off - COMPAT_MANAGER_ENABLED_OFF);
    g_enabled_off = off;
    return 1;
}

uint32_t np_compat_enabled_off(void) {
    return g_enabled_off;
}

uint32_t np_compat_tool_off(uint32_t reference_off) {
    if (reference_off < COMPAT_TOOL_INSTALL_OFF) return reference_off;
    return (uint32_t)((int32_t)reference_off + g_tool_shift);
}

size_t np_compat_tool_stride(void) {
    return (size_t)((int32_t)COMPAT_TOOL_STRIDE + g_tool_shift);
}

// The compatibility tool needs to go in the folder Steam normally (on Linux)
// scans for compatibility tools. So the tool is shoved into
// ~/Library/Application Support/Steam/compatibilitytools.d and
// STEAM_EXTRA_COMPAT_TOOLS_PATHS points there.
void np_compat_export_tools_path(void) {
    const char *home = np_home_dir();
    if (!home) return;
    if (getenv("STEAM_EXTRA_COMPAT_TOOLS_PATHS")) return;

    char tools_dir[512];
    snprintf(tools_dir, sizeof(tools_dir),
             "%s/Library/Application Support/Steam/compatibilitytools.d", home);

    setenv("STEAM_EXTRA_COMPAT_TOOLS_PATHS", tools_dir, 1);
    NP_LOG("np_compat_export_tools_path: set STEAM_EXTRA_COMPAT_TOOLS_PATHS=%s",
           tools_dir);
}

int np_compat_ensure_tool_manifest(void) {
    const char *home = np_home_dir();
    if (!home) return -1;

    char tools_dir[512];
    snprintf(tools_dir, sizeof(tools_dir),
             "%s/Library/Application Support/Steam/compatibilitytools.d", home);

    if (ensure_dir(tools_dir) != 0) {
        NP_WARN("np_compat_ensure_tool_manifest: cannot create %s", tools_dir);
        return -1;
    }

    char tool_dir[512];
    snprintf(tool_dir, sizeof(tool_dir), "%s/%s", tools_dir, TOOL_DIR_NAME);

    if (ensure_dir(tool_dir) != 0) {
        NP_WARN("np_compat_ensure_tool_manifest: cannot create %s", tool_dir);
        return -1;
    }

    char path[512];
    int wrote = 0;

    // Rewritten every launch so field changes take effect. A rescan replaces it in
    // place rather than adding a second copy.
    snprintf(path, sizeof(path), "%s/compatibilitytool.vdf", tool_dir);
    if (write_file(path, TOOL_DECLARATION, 0) == 0) wrote++;
    else NP_WARN("np_compat_ensure_tool_manifest: failed to write %s", path);

    snprintf(path, sizeof(path), "%s/toolmanifest.vdf", tool_dir);
    if (access(path, F_OK) != 0) {
        if (write_file(path, TOOL_MANIFEST, 0) == 0) wrote++;
        else NP_WARN("np_compat_ensure_tool_manifest: failed to write %s", path);
    }

    // The run script is the shim this project owns and updates, so rewrite it
    // every launch rather than leaving a stale copy behind.
    snprintf(path, sizeof(path), "%s/run", tool_dir);
    if (write_file(path, RUN_SCRIPT, 1) == 0) wrote++;
    else NP_WARN("np_compat_ensure_tool_manifest: failed to write %s", path);

    if (wrote > 0)
        NP_LOG("np_compat_ensure_tool_manifest: wrote %d file(s) to %s", wrote, tool_dir);

    return 0;
}

const char *np_compat_tool_dir(void) {
    static char dir[512];
    static int resolved = 0;

    if (resolved)
        return dir[0] ? dir : NULL;

    resolved = 1;

    const char *home = np_home_dir();
    if (!home) {
        dir[0] = '\0';
        return NULL;
    }

    snprintf(dir, sizeof(dir),
             "%s/Library/Application Support/Steam/compatibilitytools.d/%s",
             home, TOOL_DIR_NAME);
    return dir;
}

const char *np_compat_tool_commandline(void) {
    return "/run %verb%";
}

void np_compat_force_enable(void *compat_mgr) {
    if (!compat_mgr) return;

    uint8_t *base = (uint8_t *)compat_mgr;
    uint32_t off = np_compat_enabled_off();
    uint8_t prev = base[off];
    base[off] = 1;

    // Steam polls compat state frequently. Only log the one transition.
    if (!prev)
        NP_LOG("np_compat_force_enable: compat layer force-enabled (this+0x%X: 0 -> 1)",
               off);
}

typedef uint32_t (*fn_GetValidPlatforms)(void *compat_mgr, uint32_t appid);
static fn_GetValidPlatforms g_get_valid_platforms;

void np_compat_set_valid_platforms_fn(uintptr_t get_valid_platforms) {
    g_get_valid_platforms = (fn_GetValidPlatforms)get_valid_platforms;
}

uint32_t np_compat_valid_platforms(void *compat_mgr, uint32_t appid) {
    if (!g_get_valid_platforms || !compat_mgr)
        return 0;
    return g_get_valid_platforms(compat_mgr, appid);
}

typedef void *(*fn_FindToolForTargetApp)(void *compat_mgr, uint32_t appid);
static fn_FindToolForTargetApp g_find_tool_for_app;

void np_compat_set_find_tool_fn(uintptr_t find_tool_for_target_app) {
    g_find_tool_for_app = (fn_FindToolForTargetApp)find_tool_for_target_app;
}

void *np_compat_tool_for_app(void *compat_mgr, uint32_t appid) {
    if (!g_find_tool_for_app || !compat_mgr)
        return NULL;
    return g_find_tool_for_app(compat_mgr, appid);
}

// The config argument is a tool-specific string the dropdown has no way to set, and
// the client passes it empty from its own handler.
static fn_FindToolForTargetApp g_chosen_tool;

void np_compat_set_chosen_tool_fn(uintptr_t find_tool_for_target_app) {
    g_chosen_tool = (fn_FindToolForTargetApp)find_tool_for_target_app;
}

void *np_compat_chosen_tool(void *compat_mgr, uint32_t appid) {
    if (!g_chosen_tool || !compat_mgr)
        return NULL;
    return g_chosen_tool(compat_mgr, appid);
}

bool np_compat_would_force(void *compat_mgr, uint32_t appid) {
    if (!compat_mgr || !appid)
        return false;
    uint32_t platforms = np_compat_valid_platforms(compat_mgr, appid);
    return (platforms & COMPAT_PLATFORM_WINDOWS) && !(platforms & COMPAT_PLATFORM_MACOS);
}

typedef void *(*fn_FindMapping)(void *compat_mgr, uint32_t appid);
static fn_FindMapping g_find_mapping;

void np_compat_set_app_mapping_fn(uintptr_t find_mapping) {
    g_find_mapping = (fn_FindMapping)find_mapping;
}

// { const char *name; const char *config; int32_t priority }, owned by the client.
static const char *mapping_name(const void *mapping) {
    const char *const *entry = (const char *const *)mapping;
    if (!entry || !entry[0] || !entry[0][0])
        return NULL;
    return entry[0];
}

const char *np_compat_app_mapping(void *compat_mgr, uint32_t appid) {
    if (!g_find_mapping || !compat_mgr || !appid)
        return NULL;
    return mapping_name(g_find_mapping(compat_mgr, appid));
}

static fn_FindMapping g_get_wildcard;

void np_compat_set_wildcard_fn(uintptr_t get_wildcard_mapping) {
    g_get_wildcard = (fn_FindMapping)get_wildcard_mapping;
}

const char *np_compat_wildcard_mapping(void *compat_mgr, uint32_t appid) {
    if (!g_get_wildcard || !compat_mgr || !appid)
        return NULL;
    return mapping_name(g_get_wildcard(compat_mgr, appid));
}

typedef void (*fn_SetCompatToolMapping)(void *compat_mgr, uint32_t appid,
                                        const char *tool_name, const char *config,
                                        uint32_t priority);
static fn_SetCompatToolMapping g_set_mapping;

void np_compat_set_mapping_fn(uintptr_t set_compat_tool_mapping) {
    g_set_mapping = (fn_SetCompatToolMapping)set_compat_tool_mapping;
}

void np_compat_map_tool(void *compat_mgr, uint32_t appid, const char *tool_name) {
    if (!g_set_mapping || !compat_mgr || !tool_name) {
        NP_ERR("np_compat_map_tool: app %u cannot be mapped to %s", appid,
               tool_name ? tool_name : "no tool");
        return;
    }
    g_set_mapping(compat_mgr, appid, tool_name, "",
                  appid ? COMPAT_MAPPING_PRIORITY_APP
                        : COMPAT_MAPPING_PRIORITY_GLOBAL);
}

typedef void (*fn_YldRegisterTool)(void *compat_mgr, void *tool);
static fn_YldRegisterTool g_yld_register_tool;
typedef void (*fn_PlatFree)(void *ptr);
static fn_PlatFree g_free_tool_path;

void np_compat_set_register_fn(uintptr_t yld_register_tool) {
    g_yld_register_tool = (fn_YldRegisterTool)yld_register_tool;
    g_free_tool_path = (fn_PlatFree)dlsym(RTLD_DEFAULT, "Plat_Free");
    if (!g_free_tool_path)
        NP_WARN("np_compat_set_register_fn: Plat_Free unresolved, temporary tool paths will leak");
}

static void free_tool_paths(uint8_t *tool) {
    // YldRegisterTool writes caller-owned CUtlStrings, using Steam's allocator.
    static const uint32_t offsets[] = {0x98, 0xA0, 0xA8, 0xD0, 0xD8, 0xE0, 0xE8, 0x118};
    if (!g_free_tool_path) return;
    for (size_t i = 0; i < sizeof(offsets) / sizeof(*offsets); i++) {
        void **path = (void **)(tool + np_compat_tool_off(offsets[i]));
        if (*path) g_free_tool_path(*path);
        *path = NULL;
    }
}

static void *g_manager;

void *np_compat_manager(void) {
    return g_manager;
}

void np_compat_register_crossover(void *compat_mgr) {
    static int registered = 0;

    // Every compat query arrives on the instance the properties page reads, which is
    // the one the tool list has to be enumerated from.
    if (compat_mgr)
        g_manager = compat_mgr;

    if (registered || !compat_mgr || !g_yld_register_tool)
        return;

    // The compatibilitytools.d scan registers this tool from disk at client startup,
    // so any session that found the manifest there already holds an entry and a
    // second one is a duplicate under the same name. Only the first session after an
    // install, when the manifest did not exist to be scanned, has nothing to find.
    if (np_compat_registered_tool(compat_mgr)) {
        registered = 1;
        NP_LOG("np_compat_register_crossover: %s already registered from disk, "
               "skipping the runtime entry", TOOL_DIR_NAME);
        return;
    }

    // YldRegisterTool copies the entry and its strings. The buffer carries
    // headroom for a client that inserted a field. to_oslist=macos passes the
    // registration gate, from_oslist=windows intersects the app mask so the dropdown
    // keeps it, and appid 0 marks a manager-local tool the resolver routes to the
    // local run script.
    static uint8_t tool[COMPAT_TOOL_STRIDE + 64];
    memset(tool, 0, sizeof(tool));

    static const char name[]        = TOOL_DIR_NAME;
    static const char display[]     = TOOL_DISPLAY_NAME;
    static const char from_oslist[] = "windows";
    static const char to_oslist[]   = "macos";

    *(uint32_t *)(tool + COMPAT_TOOL_FLAGS_OFF)      = COMPAT_TOOL_FLAG_NO_APP;
    *(const char **)(tool + COMPAT_TOOL_NAME_OFF)    = name;
    *(const char **)(tool + COMPAT_TOOL_DISPLAY_OFF) = display;
    *(const char **)(tool + np_compat_tool_off(COMPAT_TOOL_INSTALL_OFF)) =
        np_compat_tool_dir();
    *(uint32_t *)(tool + np_compat_tool_off(COMPAT_TOOL_APPID_OFF)) = 0;
    *(const char **)(tool + np_compat_tool_off(COMPAT_TOOL_FROM_OSLIST_OFF)) = from_oslist;
    *(const char **)(tool + np_compat_tool_off(COMPAT_TOOL_TO_OSLIST_OFF))   = to_oslist;

    registered = 1;
    g_yld_register_tool(compat_mgr, tool);
    free_tool_paths(tool);
    NP_LOG("np_compat_register_crossover: registered %s into manager 0x%llx",
           name, (unsigned long long)(uintptr_t)compat_mgr);
}

void *np_compat_registered_tool(void *compat_mgr) {
    if (!compat_mgr)
        return NULL;

    uint8_t *base = (uint8_t *)compat_mgr;
    uint8_t *array = *(uint8_t **)(base + COMPAT_MANAGER_TOOL_ARRAY_OFF);
    uint32_t count = *(uint32_t *)(base + COMPAT_MANAGER_TOOL_COUNT_OFF);
    if (!array || count > COMPAT_MANAGER_TOOLS_MAX) {
        // Once, because Steam walks this for every windows-only app as the library
        // redraws and a count this wrong does not correct itself.
        static const char once = 0;
        if (np_log_first_hit(&once, 0))
            NP_ERR("np_compat_registered_tool: the manager reports %u tool(s) at %p, "
                   "which is not a list this reads", count, (const void *)array);
        return NULL;
    }

    for (uint32_t i = 0; i < count; i++) {
        uint8_t *entry = array + (size_t)i * np_compat_tool_stride();
        const char *name = *(const char **)(entry + COMPAT_TOOL_NAME_OFF);
        if (name && strcmp(name, TOOL_DIR_NAME) == 0)
            return entry;
    }
    return NULL;
}
