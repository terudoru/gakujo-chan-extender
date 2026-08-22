package net.yoshida.morebettergakujo

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class GakujoCalendarEventPolicyTest {
    @Test
    fun parsesValidEventBeforeCalendarMutation() {
        val event = GakujoCalendarEventPolicy.parse(
            mapOf(
                "id" to "course-1",
                "title" to "線形代数",
                "startMillis" to 1_000L,
                "endMillis" to "2000",
                "teacher" to "新潟 太郎",
                "location" to "B101"
            )
        )

        requireNotNull(event)
        assertEquals("線形代数", event.title)
        assertEquals(1_000L, event.startMillis)
        assertEquals(2_000L, event.endMillis)
        assertEquals("担当教員: 新潟 太郎\n\nMBG_UID:course-1", event.description)
        assertEquals("B101", event.location)
    }

    @Test
    fun notesTakePriorityOverTeacherInDescription() {
        val event = GakujoCalendarEventPolicy.parse(
            mapOf(
                "id" to "course-2",
                "title" to "物理学",
                "startMillis" to 3_000L,
                "endMillis" to 4_000L,
                "teacher" to "教員名",
                "notes" to "休講情報を確認"
            )
        )

        requireNotNull(event)
        assertEquals("休講情報を確認\n\nMBG_UID:course-2", event.description)
    }

    @Test
    fun rejectsEventMissingRequiredValues() {
        assertNull(
            GakujoCalendarEventPolicy.parse(
                mapOf(
                    "title" to "",
                    "startMillis" to 1_000L,
                    "endMillis" to 2_000L
                )
            )
        )
        assertNull(
            GakujoCalendarEventPolicy.parse(
                mapOf(
                    "title" to "化学",
                    "startMillis" to "not-a-number",
                    "endMillis" to 2_000L
                )
            )
        )
    }

    @Test
    fun narrowResyncReplacesAllEventsFromSameNamespaceOnly() {
        val incoming = listOf(
            requireNotNull(
                GakujoCalendarEventPolicy.parse(
                    mapOf(
                        "id" to "niigata-2026-term-1|course|1|1|room|2026|06|01",
                        "title" to "情報工学",
                        "startMillis" to 200L,
                        "endMillis" to 250L
                    )
                )
            )
        )
        val existing = listOf(
            ExistingGakujoCalendarEvent(
                id = 1L,
                startMillis = 200L,
                description = "MBG_UID:niigata-2026-term-1|course|1|1|room|2026|06|01"
            ),
            ExistingGakujoCalendarEvent(
                id = 2L,
                startMillis = 900L,
                description = "MBG_UID:niigata-2026-term-1|course|1|1|room|2026|08|01"
            ),
            ExistingGakujoCalendarEvent(
                id = 3L,
                startMillis = 200L,
                description = "MBG_UID:niigata-2026-term-2|course|1|1|room|2026|10|01"
            )
        )

        val eventIds = GakujoCalendarEventPolicy.eventIdsToReplace(
            existingEvents = existing,
            namespaces = GakujoCalendarEventPolicy.replacementNamespaces(incoming),
            replacementRange = CalendarEventReplacementRange(100L, 300L)
        )

        assertEquals(listOf(1L, 2L), eventIds)
    }

    @Test
    fun eventsWithoutNamespaceUseUnionOfPreviousAndCurrentRanges() {
        val range = GakujoCalendarEventPolicy.unionRange(
            current = CalendarEventReplacementRange(200L, 300L),
            previous = CalendarEventReplacementRange(100L, 900L)
        )
        val existing = listOf(
            ExistingGakujoCalendarEvent(1L, 150L, "MBG_UID:legacy-a"),
            ExistingGakujoCalendarEvent(2L, 500L, "MBG_UID:legacy-b"),
            ExistingGakujoCalendarEvent(3L, 950L, "MBG_UID:legacy-c")
        )

        val eventIds = GakujoCalendarEventPolicy.eventIdsToReplace(
            existingEvents = existing,
            namespaces = emptySet(),
            replacementRange = range
        )

        assertEquals(listOf(1L, 2L), eventIds)
        assertTrue(GakujoCalendarEventPolicy.replacementNamespaces(emptyList()).isEmpty())
    }

    @Test
    fun rangeReplacementKeepsEventAtExclusiveEndBoundary() {
        val existing = listOf(
            ExistingGakujoCalendarEvent(1L, 100L, "MBG_UID:legacy-start"),
            ExistingGakujoCalendarEvent(2L, 299L, "MBG_UID:legacy-inside"),
            ExistingGakujoCalendarEvent(3L, 300L, "MBG_UID:next-term-boundary")
        )

        val eventIds = GakujoCalendarEventPolicy.eventIdsToReplace(
            existingEvents = existing,
            namespaces = emptySet(),
            replacementRange = CalendarEventReplacementRange(100L, 300L)
        )

        assertEquals(listOf(1L, 2L), eventIds)
    }

    @Test
    fun emptySyncIsRejectedBeforeExistingEventsCanBeDeleted() {
        val error = assertThrows(IllegalArgumentException::class.java) {
            GakujoCalendarEventPolicy.parseEventsForSync(emptyList<Any>())
        }

        assertEquals("追加可能なカレンダー予定がありません", error.message)
    }

    @Test
    fun mixedValidAndInvalidSyncIsRejectedAsAWhole() {
        val error = assertThrows(IllegalArgumentException::class.java) {
            GakujoCalendarEventPolicy.parseEventsForSync(
                listOf(
                    mapOf(
                        "id" to "term-1|course|1",
                        "title" to "有効な予定",
                        "startMillis" to 100L,
                        "endMillis" to 200L
                    ),
                    mapOf(
                        "id" to "term-1|course|2",
                        "title" to "終了時刻のない予定",
                        "startMillis" to 300L
                    )
                )
            )
        }

        assertEquals("カレンダー予定2件目が不正です", error.message)
    }

    @Test
    fun nonMapSyncEventIsRejected() {
        val error = assertThrows(IllegalArgumentException::class.java) {
            GakujoCalendarEventPolicy.parseEventsForSync(
                listOf(
                    mapOf(
                        "id" to "term-1|course|1",
                        "title" to "有効な予定",
                        "startMillis" to 100L,
                        "endMillis" to 200L
                    ),
                    "not-an-event"
                )
            )
        }

        assertEquals("カレンダー予定2件目が不正です", error.message)
    }

    @Test
    fun blankIdAndNonPositiveDurationAreRejected() {
        assertNull(
            GakujoCalendarEventPolicy.parse(
                mapOf(
                    "id" to "   ",
                    "title" to "IDなし",
                    "startMillis" to 100L,
                    "endMillis" to 200L
                )
            )
        )
        assertNull(
            GakujoCalendarEventPolicy.parse(
                mapOf(
                    "id" to "course-equal",
                    "title" to "期間ゼロ",
                    "startMillis" to 200L,
                    "endMillis" to 200L
                )
            )
        )
        assertNull(
            GakujoCalendarEventPolicy.parse(
                mapOf(
                    "id" to "course-reversed",
                    "title" to "逆転期間",
                    "startMillis" to 300L,
                    "endMillis" to 200L
                )
            )
        )
    }

    @Test
    fun mixedNamedNamespacesAreRejectedAsAWhole() {
        val error = assertThrows(IllegalArgumentException::class.java) {
            GakujoCalendarEventPolicy.parseEventsForSync(
                listOf(
                    validRawEvent("term-1|course|1", 100L),
                    validRawEvent("term-2|course|2", 300L)
                )
            )
        }

        assertEquals("異なるnamespaceのカレンダー予定を同時に同期できません", error.message)
    }

    @Test
    fun namedAndLegacyNamespacesAreRejectedAsAWhole() {
        val error = assertThrows(IllegalArgumentException::class.java) {
            GakujoCalendarEventPolicy.parseEventsForSync(
                listOf(
                    validRawEvent("term-1|course|1", 100L),
                    validRawEvent("course-1", 300L)
                )
            )
        }

        assertEquals("namespaceあり・なしのカレンダー予定を同時に同期できません", error.message)
    }

    @Test
    fun allLegacyEventsRemainSupported() {
        val events = GakujoCalendarEventPolicy.parseEventsForSync(
            listOf(
                validRawEvent("course-1", 100L),
                validRawEvent("course-2", 300L)
            )
        )

        assertEquals(2, events.size)
        assertTrue(events.all { it.uidNamespace == null })
    }

    @Test
    fun normalAndValidationCalendarsUseSeparateRememberedIds() {
        assertEquals(
            GakujoCalendarIdentity.NORMAL,
            GakujoCalendarIdentityPolicy.forTitle("More Better Gakujo 授業")
        )
        assertEquals(
            GakujoCalendarIdentity.VALIDATION,
            GakujoCalendarIdentityPolicy.forTitle("More Better Gakujo 検証")
        )
        assertEquals(
            "calendar_id_normal",
            GakujoCalendarIdentityPolicy.preferenceKey(GakujoCalendarIdentity.NORMAL)
        )
        assertEquals(
            "calendar_id_validation",
            GakujoCalendarIdentityPolicy.preferenceKey(GakujoCalendarIdentity.VALIDATION)
        )
    }

    @Test
    fun validationNamespaceKeepsValidationIdentityAfterTitleChange() {
        val events = GakujoCalendarEventPolicy.parseEventsForSync(
            listOf(validRawEvent("calendar-validation|course|1", 100L))
        )

        assertEquals(
            GakujoCalendarIdentity.VALIDATION,
            GakujoCalendarIdentityPolicy.forSync("名前変更後の検証カレンダー", events)
        )
    }

    @Test
    fun normalNamespaceCannotUseReservedValidationTitle() {
        val events = GakujoCalendarEventPolicy.parseEventsForSync(
            listOf(validRawEvent("niigata-2026-第2ターム|course|1", 100L))
        )

        val error = assertThrows(IllegalArgumentException::class.java) {
            GakujoCalendarIdentityPolicy.forSync("More Better Gakujo 検証", events)
        }

        assertEquals(
            "「More Better Gakujo 検証」は検証用に予約されたカレンダー名です",
            error.message
        )
    }

    @Test
    fun rememberedWritableCalendarWinsWithoutTitleLookup() {
        var titleLookupCalled = false

        val calendarId = GakujoCalendarIdentityPolicy.preferredReusableId(42L) {
            titleLookupCalled = true
            99L
        }

        assertEquals(42L, calendarId)
        assertFalse(titleLookupCalled)
    }

    @Test
    fun missingRememberedCalendarFallsBackToTitleLookup() {
        var titleLookupCalled = false

        val calendarId = GakujoCalendarIdentityPolicy.preferredReusableId(null) {
            titleLookupCalled = true
            99L
        }

        assertEquals(99L, calendarId)
        assertTrue(titleLookupCalled)
    }

    @Test
    fun upgradeMigrationSelectsOnlyUniqueCalendarForIdentity() {
        val identities = mapOf(
            10L to setOf(GakujoCalendarIdentity.NORMAL),
            20L to setOf(GakujoCalendarIdentity.VALIDATION)
        )

        assertEquals(
            10L,
            GakujoCalendarIdentityPolicy.uniqueMigrationId(
                identities,
                GakujoCalendarIdentity.NORMAL
            )
        )
        assertEquals(
            20L,
            GakujoCalendarIdentityPolicy.uniqueMigrationId(
                identities,
                GakujoCalendarIdentity.VALIDATION
            )
        )
    }

    @Test
    fun upgradeMigrationRejectsAmbiguousOrMixedCalendars() {
        assertNull(
            GakujoCalendarIdentityPolicy.uniqueMigrationId(
                mapOf(
                    10L to setOf(GakujoCalendarIdentity.NORMAL),
                    11L to setOf(GakujoCalendarIdentity.NORMAL)
                ),
                GakujoCalendarIdentity.NORMAL
            )
        )
        assertNull(
            GakujoCalendarIdentityPolicy.uniqueMigrationId(
                mapOf(
                    10L to setOf(
                        GakujoCalendarIdentity.NORMAL,
                        GakujoCalendarIdentity.VALIDATION
                    )
                ),
                GakujoCalendarIdentity.NORMAL
            )
        )
    }

    @Test
    fun markerDescriptionClassifiesLegacyAndValidationCalendars() {
        assertEquals(
            GakujoCalendarIdentity.NORMAL,
            GakujoCalendarIdentityPolicy.forMarkerDescription("MBG_UID:course-1")
        )
        assertEquals(
            GakujoCalendarIdentity.VALIDATION,
            GakujoCalendarIdentityPolicy.forMarkerDescription(
                "検証予定\n\nMBG_UID:calendar-validation|course|1"
            )
        )
        assertNull(GakujoCalendarIdentityPolicy.forMarkerDescription("手動予定"))
    }

    @Test
    fun namespaceCleanupRemovesOnlyMatchingMarkersFromWritableCalendars() {
        val events = listOf(
            ExistingGakujoCalendarEvent(
                id = 1L,
                startMillis = 100L,
                description = "MBG_UID:term-1|course|1",
                calendarId = 10L
            ),
            ExistingGakujoCalendarEvent(
                id = 2L,
                startMillis = 200L,
                description = "MBG_UID:term-1|course|2",
                calendarId = 20L
            ),
            ExistingGakujoCalendarEvent(
                id = 3L,
                startMillis = 300L,
                description = "MBG_UID:term-2|course|3",
                calendarId = 20L
            ),
            ExistingGakujoCalendarEvent(
                id = 4L,
                startMillis = 400L,
                description = "MBG_UID:term-1|course|4",
                calendarId = 30L
            ),
            ExistingGakujoCalendarEvent(
                id = 5L,
                startMillis = 500L,
                description = "通常ユーザー予定",
                calendarId = 20L
            )
        )

        val eventIds = GakujoCalendarEventPolicy.eventIdsForNamespaceCleanup(
            existingEvents = events,
            writableCalendarIds = setOf(10L, 20L),
            namespaces = setOf("term-1"),
            targetCalendarId = 10L,
            includeForeignCalendars = true
        )

        assertEquals(listOf(1L, 2L), eventIds)
    }

    @Test
    fun foreignCleanupRequiresFinalMarkerButDedicatedCalendarAllowsAppendedNotes() {
        val eventIds = GakujoCalendarEventPolicy.eventIdsForNamespaceCleanup(
            existingEvents = listOf(
                ExistingGakujoCalendarEvent(
                    id = 1L,
                    startMillis = 100L,
                    description = "MBG_UID:term-1|course|1\nユーザー追記",
                    calendarId = 10L
                ),
                ExistingGakujoCalendarEvent(
                    id = 2L,
                    startMillis = 200L,
                    description = "MBG_UID:term-1|course|2\nユーザー追記",
                    calendarId = 20L
                )
            ),
            writableCalendarIds = setOf(10L, 20L),
            namespaces = setOf("term-1"),
            targetCalendarId = 10L,
            includeForeignCalendars = true
        )

        assertEquals(listOf(1L), eventIds)
    }

    @Test
    fun unifiedNiigataNamespaceReplacesOfficialAndMatchingLegacyManualRangeOnly() {
        val events = listOf(
            ExistingGakujoCalendarEvent(
                id = 1L,
                startMillis = 100L,
                description = "MBG_UID:manual-20260611-20260808|course|old",
                calendarId = 10L
            ),
            ExistingGakujoCalendarEvent(
                id = 2L,
                startMillis = 200L,
                description = "MBG_UID:niigata-2026-第2ターム|course|official",
                calendarId = 10L
            ),
            ExistingGakujoCalendarEvent(
                id = 3L,
                startMillis = 300L,
                description = "MBG_UID:manual-20260408-20260608|course|first",
                calendarId = 10L
            ),
            ExistingGakujoCalendarEvent(
                id = 4L,
                startMillis = 400L,
                description = "MBG_UID:manual-20250611-20250808|course|previous-year",
                calendarId = 10L
            ),
            ExistingGakujoCalendarEvent(
                id = 5L,
                startMillis = 500L,
                description = "MBG_UID:niigata-2026-第3ターム|course|other-term",
                calendarId = 10L
            )
        )

        val eventIds = GakujoCalendarEventPolicy.eventIdsForNamespaceCleanup(
            existingEvents = events,
            writableCalendarIds = setOf(10L),
            namespaces = setOf("niigata-2026-第2ターム"),
            targetCalendarId = 10L,
            includeForeignCalendars = true
        )

        assertEquals(listOf(1L, 2L), eventIds)
    }

    @Test
    fun completedMigrationLimitsCleanupToDedicatedCalendar() {
        val events = listOf(
            ExistingGakujoCalendarEvent(
                id = 1L,
                startMillis = 100L,
                description = "MBG_UID:term-1|course|dedicated",
                calendarId = 10L
            ),
            ExistingGakujoCalendarEvent(
                id = 2L,
                startMillis = 200L,
                description = "MBG_UID:term-1|course|imported-ics",
                calendarId = 20L
            )
        )

        val eventIds = GakujoCalendarEventPolicy.eventIdsForNamespaceCleanup(
            existingEvents = events,
            writableCalendarIds = setOf(10L, 20L),
            namespaces = setOf("term-1"),
            targetCalendarId = 10L,
            includeForeignCalendars = false
        )

        assertEquals(listOf(1L), eventIds)
    }

    @Test
    fun explicitDeleteWithoutDedicatedCalendarCleansOnlySafeWritableLegacyMarkersInRange() {
        val events = listOf(
            ExistingGakujoCalendarEvent(
                id = 1L,
                startMillis = 100L,
                description = "MBG_UID:niigata-2026-第2ターム|course|legacy",
                calendarId = 20L
            ),
            ExistingGakujoCalendarEvent(
                id = 2L,
                startMillis = 150L,
                description = "MBG_UID:niigata-2026-第2ターム|course|read-only",
                calendarId = 30L
            ),
            ExistingGakujoCalendarEvent(
                id = 3L,
                startMillis = 200L,
                description = "MBG_UID:niigata-2026-第2ターム|course|edited\nユーザー追記",
                calendarId = 20L
            ),
            ExistingGakujoCalendarEvent(
                id = 4L,
                startMillis = 299L,
                description = "通常ユーザー予定",
                calendarId = 20L
            ),
            ExistingGakujoCalendarEvent(
                id = 5L,
                startMillis = 300L,
                description = "MBG_UID:niigata-2026-第2ターム|course|next-term",
                calendarId = 20L
            )
        )

        val eventIds = GakujoCalendarEventPolicy.eventIdsForExplicitLegacyDelete(
            existingEvents = events,
            writableCalendarIds = setOf(20L),
            replacementRange = CalendarEventReplacementRange(100L, 300L)
        )

        assertEquals(listOf(1L), eventIds)
    }

    @Test
    fun invalidLegacyManualRangeIsNotTreatedAsAlias() {
        assertFalse(
            GakujoCalendarEventPolicy.namespacesMatchForCleanup(
                existingNamespace = "manual-20260230-20260808",
                incomingNamespace = "niigata-2026-第2ターム"
            )
        )
        assertFalse(
            GakujoCalendarEventPolicy.namespacesMatchForCleanup(
                existingNamespace = "manual-20260808-20260611",
                incomingNamespace = "niigata-2026-第2ターム"
            )
        )
    }

    @Test
    fun downloadNameAllocationSkipsExistingSuffixes() {
        assertEquals(
            "資料 (2).pdf",
            GakujoDownloadFilePolicy.uniqueName(
                setOf("資料.pdf", "資料 (1).pdf"),
                "資料.pdf"
            )
        )
    }

    @Test
    fun downloadNameUsesServerDispositionBeforePageButtonText() {
        assertEquals(
            "第1回講義資料.pdf",
            GakujoDownloadFilePolicy.preferredBaseName(
                requestedName = "ダウンロード",
                dispositionName = "第1回講義資料.pdf",
                urlName = "campussquare.do"
            )
        )
    }

    @Test
    fun downloadResultUsesProviderAssignedName() {
        assertEquals(
            "プロバイダ側の名前.pdf",
            GakujoDownloadFilePolicy.resolvedName(
                providerName = "プロバイダ側の名前.pdf",
                allocatedName = "資料.pdf"
            )
        )
        assertEquals(
            "資料.pdf",
            GakujoDownloadFilePolicy.resolvedName(
                providerName = null,
                allocatedName = "資料.pdf"
            )
        )
    }

    private fun validRawEvent(id: String, startMillis: Long): Map<String, Any> {
        return mapOf(
            "id" to id,
            "title" to "有効な予定",
            "startMillis" to startMillis,
            "endMillis" to startMillis + 100L
        )
    }
}
