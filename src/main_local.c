/*
 * Jailbreak (Local) Installer — Main Entry Point
 *
 * A shortcut-only variant of the installer. It creates a homescreen app whose
 * deeplink points straight at a host on your LAN (LOCAL_HOST, baked into
 * assets/param_local.json at build time), then exits.
 *
 * It shares app_installer.c with the normal installer, so the shortcut is
 * created by exactly the same method. What it deliberately does NOT do:
 *
 *   - no HTTP server (no libmicrohttpd, no WKALI_PORT bind)
 *   - no browser launch, no AppCache, no /install round-trip
 *   - no frontend embedded, so no file registry and no inflate
 *
 * There is nothing to cache: the page lives on the remote host and is fetched
 * over the network every launch. That also means this variant is useless
 * offline, which is the trade for not needing a cache at all.
 *
 * Because it installs a different title ID (WKLL00001) it coexists with both
 * the normal fork app (WKLX00001) and upstream PLK's (WKAL00001).
 */

#include <stdint.h>
#include <stdio.h>
#include <sys/syscall.h>
#include <unistd.h>

#include "app_installer.h"
#include "wkali.h"

/* PS5 System Calls (Internal) */
extern int sceUserServiceInitialize(void *);

__attribute__((used)) volatile const char wkali_version_sig[] =
    "WKALI_VER:" WKAL_FULL_VERSION "-local";

int main(void) {
    syscall(SYS_thr_set_name, -1, WKALI_THREAD_NAME);

    wkali_log("[WKALI] " WKAL_APP_LABEL " Installer v%s (built %s) starting...\n",
              WKAL_FULL_VERSION, WKAL_BUILD_TIME);

    /* Needed before the notification and app-install services are usable. */
    int err;
    int user_prio = 256;
    if ((err = sceUserServiceInitialize(&user_prio)) == 0) {
        wkali_log("[WKALI] User Service initialized.\n");
    } else {
        wkali_log("[WKALI] sceUserServiceInitialize failed: 0x%08X\n", err);
    }

    /* Unlike the cached variant there is no cache to verify first, so the
     * shortcut is installed immediately. */
    if (wkali_install_app_if_needed() != 0) {
        wkali_log("[WKALI] Failed to install the " WKAL_APP_LABEL " app.\n");
        wkali_notify(WKAL_APP_LABEL " install failed.\nSee the log for details.");
        return 1;
    }

    wkali_notify(WKAL_APP_LABEL " installed.\nReboot once, then launch it.");
    wkali_log("[WKALI] Done. Reboot once for the app to appear.\n");

    /* Let the notification surface before the process goes away. */
    sleep(1);
    return 0;
}
