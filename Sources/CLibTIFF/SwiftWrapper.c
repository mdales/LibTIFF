#include "include/tiff.h"
#include "include/tiffconf.h"
#include "include/tiffio.h"
#include "include/tiffiop.h"
#include "include/tiffvers.h"

int TIFFGetField_uint32(TIFF *tif, ttag_t tag, uint32_t *v) {
	return TIFFGetField(tif, tag, v);
}

int TIFFGetField_uint16(TIFF *tif, ttag_t tag, uint16_t *v) {
	return TIFFGetField(tif, tag, v);
}

int TIFFSetField_uint32(TIFF *tif, ttag_t tag, uint32_t v) {
	return TIFFSetField(tif, tag, v);
}

int TIFFSetField_uint16(TIFF *tif, ttag_t tag, uint16_t v) {
	return TIFFSetField(tif, tag, v);
}

int TIFFSetField_ExtraSample(TIFF *tif, uint16_t count, uint16_t *types) {
	return TIFFSetField(tif, TIFFTAG_EXTRASAMPLES, count, types);
}

int TIFFGetField_ExtraSample(TIFF *tif, uint16_t *count, uint16_t* types[]) {
    return TIFFGetField(tif, TIFFTAG_EXTRASAMPLES, count, types);
}

int TIFFSetField_CustomDataArray(TIFF *tif, ttag_t tag, uint16_t count, void *ptr) {
	return TIFFSetField(tif, tag, count, ptr);
}

int TIFFSetField_CustomDataAscii(TIFF *tif, ttag_t tag, void *ptr) {
	return TIFFSetField(tif, tag, ptr);
}

int TIFFGetField_CustomDataArray(TIFF *tif, ttag_t tag, uint16_t *count, void *ptr) {
	// For custom tags where you expect a list of elements, then TIFFGetField will
	// return a pointer to the data that has been decoded in memory already, rather than
	// copying it.
	return TIFFGetField(tif, tag, count, ptr);
}


// http://www.simplesystems.org/libtiff/addingtags.html#define-application-tags

#define TIFFTAG_GEOPIXELSCALE 33550
#define TIFFTAG_GEOTRANSMATRIX 34264
#define TIFFTAG_GEOTIEPOINTS 33922
#define TIFFTAG_GEOKEYDIRECTORY 34735
#define TIFFTAG_GEODOUBLEPARAMS 34736
#define TIFFTAG_GEOASCIIPARAMS 34737

static const TIFFFieldInfo xtiffFieldInfo[] = {

	/* XXX Insert Your tags here */
	{ TIFFTAG_GEOPIXELSCALE,        -1,-1, TIFF_DOUBLE,     FIELD_CUSTOM,
	  TRUE, TRUE,   "GeoPixelScale" },
	{ TIFFTAG_GEOTRANSMATRIX,       -1,-1, TIFF_DOUBLE,     FIELD_CUSTOM,
	  TRUE, TRUE,   "GeoTransformationMatrix" },
	{ TIFFTAG_GEOTIEPOINTS, -1,-1, TIFF_DOUBLE,     FIELD_CUSTOM,
	  TRUE, TRUE,   "GeoTiePoints" },
	{ TIFFTAG_GEOKEYDIRECTORY, -1,-1, TIFF_SHORT,   FIELD_CUSTOM,
	  TRUE, TRUE,   "GeoKeyDirectory" },
	{ TIFFTAG_GEODOUBLEPARAMS,      -1,-1, TIFF_DOUBLE,     FIELD_CUSTOM,
	  TRUE, TRUE,   "GeoDoubleParams" },
	{ TIFFTAG_GEOASCIIPARAMS,       -1,-1, TIFF_ASCII,      FIELD_CUSTOM,
	  TRUE, FALSE,  "GeoASCIIParams" }
};

#define     N(a)    (sizeof (a) / sizeof (a[0]))

int SetGeoTIFFFields(TIFF *tif) {
	return TIFFMergeFieldInfo(tif, xtiffFieldInfo, N(xtiffFieldInfo));
}