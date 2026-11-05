#pragma once
#include <stdint.h>

// Verified against the supplied X 12.40.1 build 1 arm64 T1Twitter image.
// Keep these inseparable: the new switch uses halfword table entries.
static const uintptr_t kBHTEntryFactoryOffset = 0x822CDC;
static const uintptr_t kBHTEntryFactoryJumpTableOffset = 0x15E2A00;
static const uintptr_t kBHTBookmarksFactoryCaseOffset = 0x822E00;
static const uint16_t kBHTBookmarksFactoryJump = 0x39;
static const uint8_t kBHTT1TwitterUUID[16] = {
    0x7B, 0x5F, 0xB7, 0x05, 0x90, 0xF7, 0x32, 0xBE,
    0xAD, 0x80, 0x23, 0x7C, 0xB4, 0x77, 0xCC, 0x1E
};
static const uint32_t kBHTEntryFactoryPrologue[] = {
    0xD10203FF, 0xA90557F6, 0xA9064FF4, 0xA9077BFD,
    0x9101C3FD, 0xAA0003E8, 0xF100641F, 0x54002308,
    0xAA0103F3, 0xD2800000, 0x90006E09, 0x91280129,
    0x1000008A, 0x7868792B, 0x8B0B094A, 0xD61F0140
};
static const uint32_t kBHTBookmarksFactoryCase[] = {
    0xD2800000, 0x942BFAC4, 0x9430090C, 0xAA0003F4,
    0xAA1303E0, 0x94300951, 0xAA0003F3, 0x942BFDD8,
    0x140000C5
};
