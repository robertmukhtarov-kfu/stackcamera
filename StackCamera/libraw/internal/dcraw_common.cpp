/*
  Copyright 2008-2020 LibRaw LLC (info@libraw.org)

 * This file is provided for compatibility w/ old build scripts/tools:
 * It includes multiple separate files that should be built separately
 * if new build tools are used

  LibRaw is free software; you can redistribute it and/or modify
  it under the terms of the one of two licenses as you choose:

1. GNU LESSER GENERAL PUBLIC LICENSE version 2.1
   (See file LICENSE.LGPL provided in LibRaw distribution archive for details).

2. COMMON DEVELOPMENT AND DISTRIBUTION LICENSE (CDDL) Version 1.0
   (See file LICENSE.CDDL provided in LibRaw distribution archive for details).

*/

#include "dcraw_defs.h"

#include "../libraw_src/utils/read_utils.cpp"
#include "../libraw_src/utils/curves.cpp"
#include "../libraw_src/utils/utils_dcraw.cpp"

#include "../libraw_src/tables/colordata.cpp"

#include "../libraw_src/decoders/canon_600.cpp"
#include "../libraw_src/decoders/decoders_dcraw.cpp"
#include "../libraw_src/decoders/decoders_libraw_dcrdefs.cpp"
#include "../libraw_src/decoders/generic.cpp"
#include "../libraw_src/decoders/kodak_decoders.cpp"
#include "../libraw_src/decoders/dng.cpp"
#include "../libraw_src/decoders/smal.cpp"
#include "../libraw_src/decoders/load_mfbacks.cpp"

#include "../libraw_src/metadata/sony.cpp"
#include "../libraw_src/metadata/nikon.cpp"
#include "../libraw_src/metadata/samsung.cpp"
#include "../libraw_src/metadata/cr3_parser.cpp"
#include "../libraw_src/metadata/canon.cpp"
#include "../libraw_src/metadata/epson.cpp"
#include "../libraw_src/metadata/olympus.cpp"
#include "../libraw_src/metadata/leica.cpp"
#include "../libraw_src/metadata/fuji.cpp"
#include "../libraw_src/metadata/adobepano.cpp"
#include "../libraw_src/metadata/pentax.cpp"
#include "../libraw_src/metadata/p1.cpp"
#include "../libraw_src/metadata/makernotes.cpp"
#include "../libraw_src/metadata/exif_gps.cpp"
#include "../libraw_src/metadata/kodak.cpp"
#include "../libraw_src/metadata/tiff.cpp"
#include "../libraw_src/metadata/ciff.cpp"
#include "../libraw_src/metadata/mediumformat.cpp"
#include "../libraw_src/metadata/minolta.cpp"
#include "../libraw_src/metadata/identify_tools.cpp"
#include "../libraw_src/metadata/normalize_model.cpp"
#include "../libraw_src/metadata/identify.cpp"
#include "../libraw_src/metadata/hasselblad_model.cpp"
#include "../libraw_src/metadata/misc_parsers.cpp"
#include "../libraw_src/tables/wblists.cpp"
#include "../libraw_src/postprocessing/postprocessing_aux.cpp"
#include "../libraw_src/postprocessing/postprocessing_utils_dcrdefs.cpp"
#include "../libraw_src/postprocessing/aspect_ratio.cpp"

#include "../libraw_src/demosaic/misc_demosaic.cpp"
#include "../libraw_src/demosaic/xtrans_demosaic.cpp"
#include "../libraw_src/demosaic/ahd_demosaic.cpp"
#include "../libraw_src/write/file_write.cpp"
