package com.example.gitpush.model

/** GitHub Actions depo secret'ı. Değer API tarafından asla geri verilmez; yalnızca ad ve tarih görünür. */
class ActionSecret(val name: String, val updatedAt: Long?) {
    companion object {
        fun fromJson(json: kotlinx.serialization.json.JsonObject): ActionSecret? {
            val name = (json["name"] as? kotlinx.serialization.json.JsonPrimitive)?.content ?: return null
            val updated = (json["updated_at"] as? kotlinx.serialization.json.JsonPrimitive)?.content
            return ActionSecret(name, parseIsoMillis(updated))
        }
    }
}

/** Secret adı ve değeri doğrulama (GitHub kuralları). */
object SecretRules {
    const val MAX_VALUE_BYTES = 48 * 1024
    private val nameRe = Regex("^[A-Za-z_][A-Za-z0-9_]{0,99}$")

    /** Geçerliyse null, değilse kullanıcıya gösterilecek hata. */
    fun validateName(name: String): String? = when {
        name.isEmpty() -> "Secret adı boş olamaz."
        !nameRe.matches(name) ->
            "Ad yalnızca harf, rakam ve alt çizgi içerebilir; rakamla başlayamaz (en çok 100 karakter)."
        name.uppercase().startsWith("GITHUB_") -> "Ad GITHUB_ ile başlayamaz (GitHub'ın kuralı)."
        else -> null
    }

    fun validateValue(value: String): String? = when {
        value.isEmpty() -> "Secret değeri boş olamaz."
        value.toByteArray(Charsets.UTF_8).size > MAX_VALUE_BYTES -> "Secret değeri en çok 48 KB olabilir."
        else -> null
    }

    /** GitHub adları büyük harfe çevirerek saklar. */
    fun normalizeName(name: String) = name.trim().uppercase()
}
