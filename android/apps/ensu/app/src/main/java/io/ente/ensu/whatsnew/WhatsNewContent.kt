package io.ente.ensu.whatsnew

data class WhatsNewEntry(
    val title: String,
    val description: String,
)

object WhatsNewContent {
    const val VERSION: Int = 3

    val entries: List<WhatsNewEntry> =
        listOf(
            WhatsNewEntry(
                title = "Keep the conversation going",
                description =
                    "Ensu now keeps better track of the details that matter in longer chats, so you can ask follow-up questions with less need to repeat yourself.",
            )
        )
}
