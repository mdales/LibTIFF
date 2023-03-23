#ifndef _SWIFT_WRAPPER_
#define _SWIFT_WRAPPER_

#include "tiff.h"

/*
 * Functions to get a field.
 */
int TIFFGetField_uint32(TIFF *tif, ttag_t tag, uint32_t *v);
int TIFFGetField_uint16(TIFF *tif, ttag_t tag, uint16_t *v);

/*
 * Functions to set a field.
 */
int TIFFSetField_uint32(TIFF *tif, ttag_t tag, uint32_t v);
int TIFFSetField_uint16(TIFF *tif, ttag_t tag, uint16_t v);

/*
 * Sets & gets the extra sample field.
 * This is special, as it removes boilerplate from the swift code.
 */
int TIFFSetField_ExtraSample(TIFF *tif, uint16_t count, uint16_t *types);
int TIFFGetField_ExtraSample(TIFF *tif, uint16_t *count, uint16_t *types[]);

int TIFFGetField_CustomDataArray(TIFF *tif, ttag_t tag, uint16_t *count, void *ptr);

#endif /* _SWIFT_WRAPPER_ */
