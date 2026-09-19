package com.aifitness

data class SavedSession(val endpoint: String, val token: String)

/** Synchronous platform boundary; callers use the IO dispatcher. */
interface CredentialVault {
    fun read(): SavedSession?

    fun save(session: SavedSession)

    fun clear()
}
