package dev.hydrocap.app.ui

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Read actual production resources/configuration; do not substitute Android or fixture values. */
class BrandingResourceTest {
    @Test fun displayAndNotificationNamesChangeWithoutChangingUpdateIdentity() {
        val appRoot = sequenceOf(File("."), File("app"), File("android/app"))
            .firstOrNull { File(it, "src/main/res/values/strings.xml").isFile }
            ?: error("Production Android resources are not available from this test directory")
        val factory = DocumentBuilderFactory.newInstance().apply {
            isNamespaceAware = true
            setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
        }
        val resources = factory.newDocumentBuilder()
            .parse(File(appRoot, "src/main/res/values/strings.xml"))
        val strings = resources.getElementsByTagName("string")
        val names = (0 until strings.length).associate { index ->
            val node = strings.item(index)
            node.attributes.getNamedItem("name").nodeValue to node.textContent
        }
        assertEquals("OpenBottle", names["app_name"])
        assertEquals("OpenBottle", names["notification_sync_title"])
        val manifest = factory.newDocumentBuilder().parse(File(appRoot, "src/main/AndroidManifest.xml"))
        val application = manifest.getElementsByTagName("application").item(0)
        val androidNamespace = "http://schemas.android.com/apk/res/android"
        assertEquals("@string/app_name", application.attributes.getNamedItemNS(androidNamespace, "label").nodeValue)
        assertEquals(".HydroCapApp", application.attributes.getNamedItemNS(androidNamespace, "name").nodeValue)
        val build = File(appRoot, "build.gradle.kts").readText()
        assertTrue(build.contains("namespace = \"dev.hydrocap.app\""))
        assertTrue(build.contains("applicationId = \"dev.hydrocap.app\""))
    }
}
