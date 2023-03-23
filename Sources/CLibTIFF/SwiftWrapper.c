#include "include/tiff.h"
#include "include/tiffconf.h"
#include "include/tiffio.h"
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

int TIFFGetField_CustomDataArray(TIFF *tif, ttag_t tag, uint16_t *count, void *ptr) {
	// For custom tags where you expect a list of elements, then TIFFGetField will
	// return a pointer to the data that has been decoded in memory already, rather than
	// copying it.
	return TIFFGetField(tif, tag, count, ptr);
}
