// Strips DYLD_INSERT_LIBRARIES from child processes
#include "hooks.h"
#include "../util/log.h"

#include <spawn.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern int   DobbyHook(void *address, void *replace_call, void **origin_call);
extern void *DobbySymbolResolver(const char *image_name, const char *symbol_name);

typedef int (*fn_execve)(const char *path, char *const argv[], char *const envp[]);
typedef int (*fn_posix_spawn)(pid_t *pid, const char *path,
                             const posix_spawn_file_actions_t *fa,
                             const posix_spawnattr_t *attr,
                             char *const argv[], char *const envp[]);

static fn_execve      orig_execve;
static fn_posix_spawn orig_posix_spawn;
static fn_posix_spawn orig_posix_spawnp;

#define NP_INSERT_KEY     "DYLD_INSERT_LIBRARIES="
#define NP_INSERT_KEY_LEN (sizeof(NP_INSERT_KEY) - 1)

// steam_osx re-execs itself and needs the insert for hooks. Steam Helper runs
// CEF and needs it for the webpatch fopen interpose, strips elsewhere
static int np_target_keeps_insert(const char *path) {
    if (!path)
        return 1;
    const char *base = strrchr(path, '/');
    base = base ? base + 1 : path;
    return strcmp(base, "steam_osx") == 0
        || strcmp(base, "Steam Helper") == 0;
}

static char **np_without_insert(char *const envp[]) {
    if (!envp)
        return NULL;

    int count = 0;
    int found = 0;
    for (int i = 0; envp[i]; i++) {
        if (strncmp(envp[i], NP_INSERT_KEY, NP_INSERT_KEY_LEN) == 0)
            found = 1;
        count++;
    }
    if (!found)
        return NULL;

    char **clean = malloc(sizeof(char *) * (size_t)(count + 1));
    if (!clean) {
        NP_WARN("[spawn] cannot allocate a stripped environment, insert passed through");
        return NULL;
    }

    int j = 0;
    for (int i = 0; envp[i]; i++) {
        if (strncmp(envp[i], NP_INSERT_KEY, NP_INSERT_KEY_LEN) != 0)
            clean[j++] = envp[i];
    }
    clean[j] = NULL;
    return clean;
}

static int np_hook_execve(const char *path, char *const argv[], char *const envp[]) {
    if (np_target_keeps_insert(path))
        return orig_execve(path, argv, envp);

    char **clean = np_without_insert(envp);
    if (!clean)
        return orig_execve(path, argv, envp);

    NP_DBG("[spawn] execve '%s' without the insert", path);
    int rc = orig_execve(path, argv, (char *const *)clean);
    // Only reached when the exec failed, since a successful one replaced this image.
    free(clean);
    return rc;
}

static int np_spawn_without_insert(fn_posix_spawn orig, const char *api,
                                   pid_t *pid, const char *path,
                                   const posix_spawn_file_actions_t *fa,
                                   const posix_spawnattr_t *attr,
                                   char *const argv[], char *const envp[]) {
    if (np_target_keeps_insert(path))
        return orig(pid, path, fa, attr, argv, envp);

    char **clean = np_without_insert(envp);
    if (!clean)
        return orig(pid, path, fa, attr, argv, envp);

    NP_DBG("[spawn] %s '%s' without the insert", api, path);
    int rc = orig(pid, path, fa, attr, argv, (char *const *)clean);
    free(clean);
    return rc;
}

static int np_hook_posix_spawn(pid_t *pid, const char *path,
                               const posix_spawn_file_actions_t *fa,
                               const posix_spawnattr_t *attr,
                               char *const argv[], char *const envp[]) {
    return np_spawn_without_insert(orig_posix_spawn, "posix_spawn",
                                   pid, path, fa, attr, argv, envp);
}

static int np_hook_posix_spawnp(pid_t *pid, const char *path,
                                const posix_spawn_file_actions_t *fa,
                                const posix_spawnattr_t *attr,
                                char *const argv[], char *const envp[]) {
    return np_spawn_without_insert(orig_posix_spawnp, "posix_spawnp",
                                   pid, path, fa, attr, argv, envp);
}

static void np_hook_symbol(const char *sym, void *repl, void **orig) {
    void *addr = DobbySymbolResolver("libsystem_kernel.dylib", sym);
    if (!addr)
        addr = DobbySymbolResolver(NULL, sym);
    if (!addr) {
        NP_WARN("[spawn] %s: unresolved, children keep the insert", sym);
        return;
    }

    int rc = DobbyHook(addr, repl, orig);
    if (rc == 0)
        NP_LOG("[spawn] %s: hooked @ %p", sym, addr);
    else
        NP_WARN("[spawn] %s: DobbyHook failed rc=%d, children keep the insert", sym, rc);
}

void np_hooks_spawn_install(void) {
    if (np_hooks_env_lists_label("STEAMGPTK_DISABLE", "spawn")) {
        NP_WARN("[spawn] DISABLED via STEAMGPTK_DISABLE, children keep the insert");
        return;
    }

    np_hook_symbol("execve",       (void *)np_hook_execve,       (void **)&orig_execve);
    np_hook_symbol("posix_spawn",  (void *)np_hook_posix_spawn,  (void **)&orig_posix_spawn);
    np_hook_symbol("posix_spawnp", (void *)np_hook_posix_spawnp, (void **)&orig_posix_spawnp);
}
