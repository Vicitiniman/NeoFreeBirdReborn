// Tests the production field-name resolver with compact Swift-shaped metadata.
// Inserting a field before the flags must not select the old Boolean ordinal.
static void BHTMakeCardMetadataFixture(uint8_t* bytes, BOOL insertedField) {
    memset(bytes, 0, 1024);
    uint32_t count = insertedField ? 26 : 25;
    *(int32_t*)(bytes + 16) = 48;
    *(uint32_t*)(bytes + 20) = count;
    *(uint16_t*)(bytes + 64 + 10) = 12;
    *(uint32_t*)(bytes + 64 + 12) = count;
    const char* names[] = {"displayMode", "isPanningBetweenCards", "isChromeFadedOutWhilePanning"};
    uint32_t indexes[] = {0, insertedField ? 21 : 20, insertedField ? 22 : 21};
    size_t nextName = 512;
    for (NSUInteger i = 0; i < 3; i++) {
        uint8_t* field = bytes + 80 + indexes[i] * 12 + 8;
        *(int32_t*)field = (int32_t)((bytes + nextName) - field);
        strcpy((char*)bytes + nextName, names[i]);
        nextName += strlen(names[i]) + 1;
    }
}

static void testSwiftFieldMetadata(void) {
    uint8_t storage[1024] __attribute__((aligned(8)));
    uint32_t index = 999;
    BHTMakeCardMetadataFixture(storage, NO);
    NSCAssert(cardStateFieldIndex(storage, "isPanningBetweenCards", &index) && index == 20,
              @"Resolve the current panning flag, not the old double-tap field at 19");
    NSCAssert(cardStateFieldIndex(storage, "isChromeFadedOutWhilePanning", &index) && index == 21,
              @"Resolve the separate faded-chrome flag");
    BHTMakeCardMetadataFixture(storage, YES);
    NSCAssert(cardStateFieldIndex(storage, "isPanningBetweenCards", &index) && index == 21,
              @"An inserted field does not redirect the lookup to another value");
    NSCAssert(!cardStateFieldIndex(storage, "missingFlag", &index), @"Unknown fields fail closed");
    *(uint16_t*)(storage + 74) = 4;
    NSCAssert(!cardStateFieldIndex(storage, "isPanningBetweenCards", &index), @"Reject truncated records");
    BHTMakeCardMetadataFixture(storage, NO);
    *(uint32_t*)(storage + 76) = 500;
    NSCAssert(!cardStateFieldIndex(storage, "isPanningBetweenCards", &index), @"Bound record traversal");
}
