package net.yoshida.morebettergakujo

internal object GakujoDownloadFormFields {
    fun parse(args: Map<*, *>): List<Pair<String, String>> {
        val pairs = args["formFieldPairs"] as? List<*>
        if (pairs != null) {
            return pairs.mapNotNull { raw ->
                val pair = raw as? List<*> ?: return@mapNotNull null
                if (pair.size != 2 || pair[0] == null || pair[1] == null) null
                else pair[0].toString() to pair[1].toString()
            }
        }
        return (args["formFields"] as? Map<*, *>).orEmpty().entries.map {
            it.key.toString() to it.value?.toString().orEmpty()
        }
    }
}
