/*
  Copyright 2008-2013 LibRaw LLC (info@libraw.org)

LibRaw is free software; you can redistribute it and/or modify
it under the terms of the one of two licenses as you choose:

 * This file is provided for compatibility w/ old build scripts/tools:
 * It includes multiple separate files that should be built separately
 * if new build tools are used

1. GNU LESSER GENERAL PUBLIC LICENSE version 2.1
   (See file LICENSE.LGPL provided in LibRaw distribution archive for details).

2. COMMON DEVELOPMENT AND DISTRIBUTION LICENSE (CDDL) Version 1.0
   (See file LICENSE.CDDL provided in LibRaw distribution archive for details).

*/

#include <math.h>

#define LIBRAW_LIBRARY_BUILD
#define LIBRAW_IO_REDEFINED
#include "../libraw_src/libraw/libraw.h"
#include "defines.h"
#define SRC_USES_SHRINK
#define SRC_USES_BLACK
#define SRC_USES_CURVE

/* DHT and AAHD are LGPL licensed, so include them */
#include "../libraw_src/demosaic/dht_demosaic.cpp"
#include "../libraw_src/demosaic/aahd_demosaic.cpp"
#include "var_defines.h"

/* DCB is BSD licensed, so include it */
#include "../libraw_src/demosaic/dcb_demosaic.cpp"
