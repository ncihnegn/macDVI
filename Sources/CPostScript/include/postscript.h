#ifndef POSTSCRIPT_H
#define POSTSCRIPT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct PsDocumentHandle PsDocumentHandle;
typedef struct PsInterpHandle PsInterpHandle;

PsDocumentHandle *ps_document_open(const uint8_t *data, size_t len);
size_t ps_document_page_count(const PsDocumentHandle *handle);
int ps_document_get_page_size(const PsDocumentHandle *handle, size_t page_index, double *out_width, double *out_height);
int ps_document_render_page_rgba(const PsDocumentHandle *handle, size_t page_index, uint32_t width, uint32_t height, uint8_t *out_rgba_buffer);
void ps_document_free(PsDocumentHandle *handle);

PsInterpHandle *ps_interp_create(double page_w, double page_h, uint32_t pixel_w, uint32_t pixel_h);
int ps_interp_execute(PsInterpHandle *handle, const uint8_t *data, size_t len);
int ps_interp_set_current_point(PsInterpHandle *handle, double x, double y);
int ps_interp_render_rgba(PsInterpHandle *handle, uint8_t *out_rgba_buffer, uint32_t width, uint32_t height);
void ps_interp_free(PsInterpHandle *handle);

#ifdef __cplusplus
}
#endif

#endif /* POSTSCRIPT_H */
