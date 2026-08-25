#ifndef POSTSCRIPT_H
#define POSTSCRIPT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct PsDocumentHandle PsDocumentHandle;

PsDocumentHandle *ps_document_open(const uint8_t *data, size_t len);
size_t ps_document_page_count(const PsDocumentHandle *handle);
int ps_document_get_page_size(const PsDocumentHandle *handle, size_t page_index, double *out_width, double *out_height);
int ps_document_render_page_rgba(const PsDocumentHandle *handle, size_t page_index, uint32_t width, uint32_t height, uint8_t *out_rgba_buffer);
void ps_document_free(PsDocumentHandle *handle);

#ifdef __cplusplus
}
#endif

#endif /* POSTSCRIPT_H */
