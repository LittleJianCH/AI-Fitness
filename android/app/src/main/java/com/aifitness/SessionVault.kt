package com.aifitness

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONObject

/** Only authenticated ciphertext is persisted; the AES key never leaves Android Keystore. */
class SessionVault(context: Context) : CredentialVault {
    private val preferences = context.getSharedPreferences("session", Context.MODE_PRIVATE)
    private val alias = "ai-fitness-session-v1"

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let {
            return it
        }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            .apply {
                init(
                    KeyGenParameterSpec.Builder(
                            alias,
                            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                        )
                        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                        .build()
                )
            }
            .generateKey()
    }

    override fun read(): SavedSession? {
        val encoded = preferences.getString("credential", null) ?: return null
        val bytes = Base64.decode(encoded, Base64.NO_WRAP)
        require(bytes.size > 28)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
        val json =
            JSONObject(String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8))
        return SavedSession(json.getString("endpoint"), json.getString("token"))
    }

    override fun save(session: SavedSession) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val plaintext =
            JSONObject()
                .put("endpoint", session.endpoint)
                .put("token", session.token)
                .toString()
                .toByteArray(Charsets.UTF_8)
        val bytes = cipher.iv + cipher.doFinal(plaintext)
        check(
            preferences
                .edit()
                .putString("credential", Base64.encodeToString(bytes, Base64.NO_WRAP))
                .commit()
        )
    }

    override fun clear() {
        check(preferences.edit().clear().commit())
    }
}
