package com.festivalscoretracker.android.data.feedback

import com.festivalscoretracker.android.data.HttpBody
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID

// region Multipart body

/**
 * A streamed `multipart/form-data` body (RFC 7578). Text fields are UTF-8; file parts
 * are copied from [MultipartFormBody.FilePart.open] at write time so large videos are
 * never held in memory.
 *
 * @property fields Text fields in order.
 * @property files File parts in order.
 * @property boundary Part boundary (random by default; fixed in tests).
 */
class MultipartFormBody(
    private val fields: List<Pair<String, String>>,
    private val files: List<FilePart>,
    val boundary: String = "fst-" + UUID.randomUUID().toString().replace("-", ""),
) : HttpBody {
    /**
     * One file part.
     *
     * @property name Form field name.
     * @property filename Filename sent to the service (sanitized on write).
     * @property contentType Part MIME type.
     * @property length Byte count when known, else null (makes the body length unknown).
     * @property open Opens a fresh stream of the content; called once per write.
     */
    class FilePart(
        val name: String,
        val filename: String,
        val contentType: String,
        val length: Long?,
        val open: () -> InputStream,
    )

    override val contentType: String get() = "multipart/form-data; boundary=$boundary"

    override val contentLength: Long
        get() {
            if (files.any { it.length == null }) return -1
            var total = 0L
            fields.forEach { (name, value) -> total += fieldHeader(name).size + value.toByteArray().size + CRLF.size }
            files.forEach { total += fileHeader(it).size + it.length!! + CRLF.size }
            return total + closing().size
        }

    override fun writeTo(sink: OutputStream) {
        fields.forEach { (name, value) ->
            sink.write(fieldHeader(name))
            sink.write(value.toByteArray())
            sink.write(CRLF)
        }
        files.forEach { part ->
            sink.write(fileHeader(part))
            val copied = part.open().use { it.copyTo(sink) }
            if (part.length != null && copied != part.length) throw IOException("Attachment changed while sending")
            sink.write(CRLF)
        }
        sink.write(closing())
    }

    private fun fieldHeader(name: String): ByteArray =
        "--$boundary\r\nContent-Disposition: form-data; name=\"${quoted(name)}\"\r\n\r\n".toByteArray()

    private fun fileHeader(part: FilePart): ByteArray = (
        "--$boundary\r\nContent-Disposition: form-data; name=\"${quoted(part.name)}\"; " +
            "filename=\"${quoted(sanitizeFilename(part.filename))}\"\r\nContent-Type: ${headerSafe(part.contentType)}\r\n\r\n"
        ).toByteArray()

    private fun closing(): ByteArray = "--$boundary--\r\n".toByteArray()

    companion object {
        private val CRLF = "\r\n".toByteArray()

        /**
         * Make a user filename safe for a `Content-Disposition` parameter: drop path parts,
         * quotes, backslashes and control characters, and fall back to `attachment`.
         *
         * @param raw Provider display name.
         * @return Non-empty bounded filename.
         */
        fun sanitizeFilename(raw: String): String {
            val leaf = raw.substringAfterLast('/').substringAfterLast('\\')
            val cleaned = leaf.filter { it >= ' ' && it != '"' && it != '\\' && it != '\u007f' }.trim().take(120)
            return cleaned.ifEmpty { "attachment" }
        }

        private fun quoted(value: String): String = value.filter { it >= ' ' && it != '"' && it != '\\' }

        private fun headerSafe(value: String): String =
            value.filter { it > ' ' && it.code < 0x7f && it != ';' && it != '"' }.ifEmpty { "application/octet-stream" }
    }
}

// endregion
