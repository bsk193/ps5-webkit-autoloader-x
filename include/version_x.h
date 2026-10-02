#ifndef VERSION_X_H
#define VERSION_X_H

/* WKAL_X_VERSION: our own semver ("1.1.0", "1.1.1-beta.1"), set from the
 * wkx-v* git tag by the Makefile (-DWKAL_X_VERSION=...).
 * WKAL_X_VERSION_UPSTREAM: the upstream PLK release this fork is based on.
 *
 * WKAL_VERSION in include/wkali.h stays upstream's value and is never edited
 * here, so merging upstream never conflicts on the version line. */
#include "wkali.h"

#ifndef WKAL_X_VERSION
#define WKAL_X_VERSION "0.0.0-dev"
#endif

#define WKAL_X_VERSION_UPSTREAM WKAL_VERSION

#endif
