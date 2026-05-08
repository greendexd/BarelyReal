import Foundation
import BarelyRealCore
import CoreGraphics

@MainActor
enum ProtocolEncodingTests {
    static func runAll() {
        let r = TestRunner.shared
        print("ProtocolEncodingTests")

        r.run("kmFrameRoundTripHeartbeat") {
            let frame = KmFrame(seq: 42, timestampUs: 1_700_000_000_123_456, type: .heartbeat)
            let encoded = KmFrameCodec.encode(frame)
            try expectEqual(encoded.count, 13)
            let decoded = try KmFrameCodec.decode(encoded)
            try expectEqual(decoded, frame)
        }

        r.run("kmFrameRoundTripMouseMoveRel") {
            var payload = Data()
            payload.appendLE(Int32(-5))
            payload.appendLE(Int32(17))
            let frame = KmFrame(seq: 1, timestampUs: 0, type: .mouseMoveRel, payload: payload)
            let encoded = KmFrameCodec.encode(frame)
            let decoded = try KmFrameCodec.decode(encoded)
            try expectEqual(decoded, frame)
            try expectEqual(decoded.payload.readLE(at: 0) as Int32, Int32(-5))
            try expectEqual(decoded.payload.readLE(at: 4) as Int32, Int32(17))
        }

        r.run("kmPayloadMouseMoveRoundTrip") {
            let payload = KmPayload.encodeMouseMove(.init(x: -1920, y: 1080))
            let decoded = try KmPayload.decodeMouseMove(payload)
            try expectEqual(decoded, .init(x: -1920, y: 1080))
        }

        r.run("kmPayloadMouseButtonRoundTrip") {
            let payload = KmPayload.encodeMouseButton(.init(button: 2, isDown: true))
            let decoded = try KmPayload.decodeMouseButton(payload)
            try expectEqual(decoded, .init(button: 2, isDown: true))
        }

        r.run("kmPayloadMouseScrollRoundTrip") {
            let payload = KmPayload.encodeMouseScroll(.init(deltaX: -12, deltaY: 48))
            let decoded = try KmPayload.decodeMouseScroll(payload)
            try expectEqual(decoded, .init(deltaX: -12, deltaY: 48))
        }

        r.run("kmPayloadKeyRoundTrip") {
            let payload = KmPayload.encodeKey(.init(keyCode: 0x37, flags: 0x0010_0000))
            let decoded = try KmPayload.decodeKey(payload)
            try expectEqual(decoded, .init(keyCode: 0x37, flags: 0x0010_0000))
        }

        // Cross-platform fixture: this exact byte sequence MUST decode to the same frame on Windows.
        r.run("kmFrameKnownByteFixture") {
            let bytes: [UInt8] = [
                0x04, 0x03, 0x02, 0x01,                         // seq = 0x01020304
                0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, // ts  = 0x1122334455667788
                0xFE,                                            // type = heartbeat
            ]
            let decoded = try KmFrameCodec.decode(Data(bytes))
            try expectEqual(decoded.seq, 0x01020304)
            try expectEqual(decoded.timestampUs, 0x1122334455667788)
            try expectEqual(decoded.type, .heartbeat)
            try expectEqual(decoded.payload, Data())

            let reEncoded = KmFrameCodec.encode(decoded)
            try expectEqual(Array(reEncoded), bytes)
        }

        r.run("kmFrameTruncatedThrows") {
            try expectThrows(BrpCodecError.truncated) {
                _ = try KmFrameCodec.decode(Data([0x01, 0x02, 0x03]))
            }
        }

        r.run("kmFrameUnknownTypeThrows") {
            var data = Data()
            data.appendLE(UInt32(0))
            data.appendLE(UInt64(0))
            data.append(0x42)
            try expectThrows(BrpCodecError.unknownType(0x42)) {
                _ = try KmFrameCodec.decode(data)
            }
        }

        r.run("controlFrameRoundTripKeepAlive") {
            let frame = ControlFrame(type: .keepAlive, body: Data())
            let encoded = ControlFrameCodec.encode(frame)
            try expectEqual(encoded.count, 5)
            let (decoded, consumed) = try ControlFrameCodec.decode(encoded)
            try expectEqual(decoded, frame)
            try expectEqual(consumed, 5)
        }

        r.run("controlFrameRoundTripJsonBody") {
            let json = #"{"name":"mac-mini","os":"mac","ver":"1.0.0"}"#
            let body = json.data(using: .utf8)!
            let frame = ControlFrame(type: .hello, body: body)
            let encoded = ControlFrameCodec.encode(frame)
            let (decoded, consumed) = try ControlFrameCodec.decode(encoded)
            try expectEqual(decoded, frame)
            try expectEqual(consumed, encoded.count)
            try expectEqual(String(data: decoded.body, encoding: .utf8), json)
        }

        r.run("controlFrameDecodeStopsAtFirstFrameInStream") {
            let f1 = ControlFrame(type: .keepAlive, body: Data())
            let f2 = ControlFrame(type: .bye, body: Data("bye".utf8))
            var stream = Data()
            stream.append(ControlFrameCodec.encode(f1))
            stream.append(ControlFrameCodec.encode(f2))

            let (d1, c1) = try ControlFrameCodec.decode(stream)
            try expectEqual(d1, f1)
            try expectEqual(c1, 5)

            let rest = stream.subdata(in: c1..<stream.count)
            let (d2, _) = try ControlFrameCodec.decode(rest)
            try expectEqual(d2, f2)
        }

        r.run("controlFrameTruncatedHeader") {
            try expectThrows(BrpCodecError.truncated) {
                _ = try ControlFrameCodec.decode(Data([0x01, 0x02]))
            }
        }

        r.run("controlFrameTruncatedBody") {
            var data = Data()
            data.appendLE(UInt32(10))
            data.append(0x01)
            data.append(contentsOf: [0x00, 0x00])
            try expectThrows(BrpCodecError.truncated) {
                _ = try ControlFrameCodec.decode(data)
            }
        }

        r.run("controlFrameKnownByteFixture") {
            let bytes: [UInt8] = [
                0x05, 0x00, 0x00, 0x00,  // length = 5
                0xF0,                     // type = KeepAlive
                0x70, 0x69, 0x6E, 0x67,   // "ping"
            ]
            let (decoded, consumed) = try ControlFrameCodec.decode(Data(bytes))
            try expectEqual(decoded.type, .keepAlive)
            try expectEqual(String(data: decoded.body, encoding: .utf8), "ping")
            try expectEqual(consumed, 9)

            let reEncoded = ControlFrameCodec.encode(decoded)
            try expectEqual(Array(reEncoded), bytes)
        }

        r.run("pairingSasFromExporter") {
            try expectEqual(PairingService.sas(fromExporterBytes: Data([0x40, 0x42, 0x0F, 0x00])), "000000")
            try expectEqual(PairingService.sas(fromExporterBytes: Data([0x3F, 0x42, 0x0F, 0x00])), "999999")
            try expectEqual(PairingService.sas(fromExporterBytes: Data([0x2A, 0x00, 0x00, 0x00])), "000042")
        }

        r.run("pairingPinLockoutAfterFiveWrongAttempts") {
            let service = PairingService(maxWrongAttempts: 5, lockoutSeconds: 60)
            for _ in 0..<4 {
                try expectThrows(PairingService.PinError.mismatch) {
                    try service.confirm(enteredPin: "000000", expectedPin: "123456")
                }
            }
            do {
                try service.confirm(enteredPin: "000000", expectedPin: "123456")
                throw TestFailure.message("expected lockout")
            } catch PairingService.PinError.lockedOut(let retryAfterSeconds) {
                try expectEqual(retryAfterSeconds, 60)
            }
        }

        r.run("pairingCorrectPinResetsWrongAttemptCounter") {
            let service = PairingService(maxWrongAttempts: 5, lockoutSeconds: 60)
            try expectThrows(PairingService.PinError.mismatch) {
                try service.confirm(enteredPin: "000000", expectedPin: "123456")
            }
            try service.confirm(enteredPin: "123456", expectedPin: "123456")
            for _ in 0..<4 {
                try expectThrows(PairingService.PinError.mismatch) {
                    try service.confirm(enteredPin: "000000", expectedPin: "123456")
                }
            }
        }

        r.run("wakeOnLanMagicPacket") {
            let packet = try WakeOnLan.magicPacket(macAddress: "AA:BB:CC:DD:EE:FF")
            try expectEqual(packet.count, 102)
            try expectEqual(Array(packet.prefix(6)), [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
            try expectEqual(Array(packet[6..<12]), [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
            try expectEqual(Array(packet[(packet.count - 6)..<packet.count]), [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
        }

        r.run("wakeOnLanRejectsInvalidMac") {
            try expectThrows(WakeOnLanError.invalidMacAddress("not-a-mac")) {
                _ = try WakeOnLan.magicPacket(macAddress: "not-a-mac")
            }
        }

        r.run("clipboardHistoryDedupAndPrune") {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("BarelyRealTests-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let history = ClipboardHistory(directory: dir, maxEntries: 2)
            let first = ClipboardEntry(id: 1, formats: ["text/plain": Data("one".utf8)], contentHash: Data([1]))
            let duplicate = ClipboardEntry(id: 2, formats: ["text/plain": Data("one again".utf8)], contentHash: Data([1]))
            let second = ClipboardEntry(id: 3, formats: ["text/plain": Data("two".utf8)], contentHash: Data([2]))
            let third = ClipboardEntry(id: 4, formats: ["text/plain": Data("three".utf8)], contentHash: Data([3]))
            history.append(first)
            history.append(duplicate)
            history.append(second)
            history.append(third)
            try expectEqual(history.recent().map(\.id), [4, 3])
        }

        r.run("fileBundleRoundTrip") {
            let bundle = ClipboardFileBundle(files: [
                ClipboardFile(name: "hello.txt", bytes: Data("Hello, world!".utf8)),
                ClipboardFile(name: "image.png", bytes: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])),
            ])
            let encoded = ClipboardFileBundleCodec.encode(bundle)
            let decoded = try ClipboardFileBundleCodec.decode(encoded)
            try expectEqual(decoded, bundle)
        }

        r.run("fileBundleEmptyRoundTrip") {
            let bundle = ClipboardFileBundle(files: [])
            let encoded = ClipboardFileBundleCodec.encode(bundle)
            try expectEqual(encoded.count, 4) // just file_count = 0
            let decoded = try ClipboardFileBundleCodec.decode(encoded)
            try expectEqual(decoded, bundle)
        }

        r.run("fileBundleTruncatedThrows") {
            // file_count = 1 but no body
            var data = Data()
            data.appendLE(UInt32(1))
            try expectThrows(ClipboardFileBundleError.truncated) {
                _ = try ClipboardFileBundleCodec.decode(data)
            }
        }

        r.run("fileBundleSanitizesName") {
            try expectEqual(ClipboardFileBundleCodec.sanitizeName("safe.txt"), "safe.txt")
            try expectEqual(ClipboardFileBundleCodec.sanitizeName("/etc/passwd"), "passwd")
            try expectEqual(ClipboardFileBundleCodec.sanitizeName("../../secret.key"), "secret.key")
            try expectEqual(ClipboardFileBundleCodec.sanitizeName("a:b\\c/d"), "d")
            try expect(ClipboardFileBundleCodec.sanitizeName("") == nil, "empty name must be rejected")
            try expect(ClipboardFileBundleCodec.sanitizeName(".") == nil, "dot must be rejected")
            try expect(ClipboardFileBundleCodec.sanitizeName("..") == nil, "double dot must be rejected")
        }

        // Cross-platform fixture: byte-for-byte fixed bundle encoding.
        // Mirrors windows/Tests/ProtocolEncodingTests.cs::fileBundleKnownByteFixture.
        r.run("fileBundleKnownByteFixture") {
            let bundle = ClipboardFileBundle(files: [
                ClipboardFile(name: "ab", bytes: Data([0xCA, 0xFE])),
            ])
            let encoded = ClipboardFileBundleCodec.encode(bundle)
            let expected: [UInt8] = [
                0x01, 0x00, 0x00, 0x00,         // file_count = 1
                0x02, 0x00,                      // name_len = 2
                0x61, 0x62,                      // "ab"
                0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // size = 2
                0xCA, 0xFE,                      // bytes
            ]
            try expectEqual(Array(encoded), expected)
            let decoded = try ClipboardFileBundleCodec.decode(Data(expected))
            try expectEqual(decoded, bundle)
        }

        r.run("hidKeyMapRoundTripCommonKeys") {
            // Spot-check coverage: A, Z, 1, 0, F1, PrintScreen/F13, Insert, Space, Enter, Esc, modifiers.
            let pairs: [(UInt16, UInt16)] = [
                (0x00, 0x04), (0x06, 0x1D), (0x12, 0x1E), (0x1D, 0x27),
                (0x7A, 0x3A), (0x69, 0x46), (0x72, 0x49), (0x31, 0x2C), (0x24, 0x28), (0x35, 0x29),
                (0x3B, 0xE0), (0x38, 0xE1), (0x3A, 0xE2), (0x37, 0xE3),
            ]
            for (kvk, hid) in pairs {
                try expectEqual(HidKeyMap.hid(forKVK: kvk), hid)
                try expectEqual(HidKeyMap.kvk(forHID: hid), kvk)
            }
        }

        r.run("hidKeyMapUnknownReturnsNil") {
            try expect(HidKeyMap.hid(forKVK: 0xFFFF) == nil, "unknown kVK should return nil")
            try expect(HidKeyMap.kvk(forHID: 0xFFFF) == nil, "unknown HID should return nil")
        }

        r.run("hidModifiersRoundTrip") {
            let mods: HidKeyMap.Modifiers = [.leftShift, .leftCtrl, .leftAlt, .leftGui, .capsLock]
            let raw = HidKeyMap.cgEventFlagsRaw(from: mods)
            let recovered = HidKeyMap.modifiers(fromCGEventFlags: raw)
            // The mapping intentionally folds L/R into Left-only on the way back.
            try expectEqual(recovered, mods)
        }

        r.run("windowsScanCodeToMacVirtualKeyCoversSpecialKeys") {
            try expectEqual(EventInjector.macVirtualKeyForWindowsScanCode(0x3B), 0x7A) // F1
            try expectEqual(EventInjector.macVirtualKeyForWindowsScanCode(0x58), 0x6F) // F12
            try expectEqual(EventInjector.macVirtualKeyForWindowsScanCode(0xE037), 0x69) // Print Screen / F13
            try expectEqual(EventInjector.macVirtualKeyForWindowsScanCode(0xE052), 0x72) // Insert / Help
            try expectEqual(EventInjector.macVirtualKeyForWindowsScanCode(0xE048), 0x7E) // Up
            try expectEqual(EventInjector.macVirtualKeyForWindowsScanCode(0x37), 0x43) // Keypad *
        }

        r.run("eventTapEmergencyReturnHotkeyRequiresControlOptionCommandEscape") {
            let flags = CGEventFlags([.maskControl, .maskAlternate, .maskCommand]).rawValue
            try expect(EventTap.isEmergencyReturnHotkey(keyCode: 0x35, flagsRaw: flags), "expected Ctrl+Option+Command+Esc to be a panic return")
            try expect(!EventTap.isEmergencyReturnHotkey(keyCode: 0x35, flagsRaw: CGEventFlags([.maskAlternate, .maskCommand]).rawValue), "missing Ctrl must not trigger panic return")
            try expect(!EventTap.isEmergencyReturnHotkey(keyCode: 0x01, flagsRaw: flags), "non-Escape key must not trigger panic return")
        }

        r.run("layoutEngineFindsContainingScreen") {
            let mac = ScreenRect(peerId: "mac", screenId: 0, x: 0, y: 0, width: 1920, height: 1080)
            let win = ScreenRect(peerId: "win", screenId: 0, x: 1920, y: 0, width: 2560, height: 1440)
            let engine = LayoutEngine(layout: Layout(screens: [mac, win]))

            try expectEqual(engine.screen(at: 100, 100)?.peerId, "mac")
            try expectEqual(engine.screen(at: 2000, 100)?.peerId, "win")
            try expect(engine.screen(at: -1, 0) == nil, "expected nil at (-1,0)")
            try expect(engine.screen(at: 5000, 5000) == nil, "expected nil at (5000,5000)")
        }

        r.run("screenAnnouncementJsonRoundTrip") {
            let announcement = ScreenAnnouncement(
                peerId: "mac",
                screens: [
                    AnnouncedScreen(id: 1, x: -2560, y: 0, w: 2560, h: 1440, scale: 2.0, primary: true),
                    AnnouncedScreen(id: 2, x: 0, y: 160, w: 1728, h: 1117, scale: 2.0, primary: false),
                ]
            )

            let data = try JSONEncoder().encode(announcement)
            let json = String(data: data, encoding: .utf8) ?? ""
            try expect(json.contains(#""peer_id":"mac""#), "ScreenAnnounce must use peer_id wire key")
            try expect(json.contains(#""screens""#), "ScreenAnnounce must include screens")

            let decoded = try JSONDecoder().decode(ScreenAnnouncement.self, from: data)
            try expectEqual(decoded, announcement)
        }

        r.run("layoutSyncUsesWireKeys") {
            let sync = LayoutSyncMessage(layout: [
                ScreenRect(peerId: "windows", screenId: 7, x: -1920, y: 480, width: 1920, height: 1080),
            ])

            let data = try JSONEncoder().encode(sync)
            let json = String(data: data, encoding: .utf8) ?? ""
            try expect(json.contains(#""peer_id":"windows""#), "LayoutSync must use peer_id wire key")
            try expect(json.contains(#""screen_id":7"#), "LayoutSync must use screen_id wire key")
            try expect(json.contains(#""w":1920"#), "LayoutSync must use compact width key")
            try expect(json.contains(#""h":1080"#), "LayoutSync must use compact height key")

            let decoded = try JSONDecoder().decode(LayoutSyncMessage.self, from: data)
            try expectEqual(decoded, sync)
        }

        r.run("layoutTranslatedMovesOnlyPeerGroup") {
            let macMain = ScreenRect(peerId: "mac", screenId: 1, x: 0, y: 0, width: 2560, height: 1440)
            let macExternal = ScreenRect(peerId: "mac", screenId: 2, x: -1920, y: 0, width: 1920, height: 1080)
            let win = ScreenRect(peerId: "windows", screenId: 1, x: 2560, y: 240, width: 1920, height: 1080)
            let moved = Layout(screens: [macMain, macExternal, win]).translated(peerId: "windows", dx: -5120, dy: 400)

            try expectEqual(moved.screens(peerId: "mac"), [macMain, macExternal])
            try expectEqual(moved.screens(peerId: "windows"), [
                ScreenRect(peerId: "windows", screenId: 1, x: -2560, y: 640, width: 1920, height: 1080),
            ])
            try expectEqual(moved.bounds(peerId: "mac"), ScreenRectBounds(minX: -1920, minY: 0, maxX: 2560, maxY: 1440))
        }

        r.run("layoutStickySnapAttachesPeerGroupToNearestScreenEdge") {
            let mac = ScreenRect(peerId: "mac", screenId: 1, x: 0, y: 0, width: 2560, height: 1440)
            let win = ScreenRect(peerId: "windows", screenId: 1, x: -2000, y: 20, width: 1920, height: 1080)
            let snapped = Layout(screens: [mac, win]).stickySnapped(peerId: "windows", toPeerId: "mac")

            try expectEqual(snapped.screens(peerId: "windows"), [
                ScreenRect(peerId: "windows", screenId: 1, x: -1920, y: 0, width: 1920, height: 1080),
            ])
        }

        r.run("layoutStickySnapSupportsTopPlacementWithOffset") {
            let mac = ScreenRect(peerId: "mac", screenId: 1, x: 0, y: 0, width: 2560, height: 1440)
            let win = ScreenRect(peerId: "windows", screenId: 1, x: 260, y: -1200, width: 1920, height: 1080)
            let snapped = Layout(screens: [mac, win]).stickySnapped(peerId: "windows", toPeerId: "mac")

            try expectEqual(snapped.screens(peerId: "windows"), [
                ScreenRect(peerId: "windows", screenId: 1, x: 260, y: -1080, width: 1920, height: 1080),
            ])
        }

        r.run("displayEnumeratorReturnsLocalLayout") {
            let layout = DisplayEnumerator.localLayout(peerId: "test-mac")
            try expect(!layout.screens.isEmpty, "expected at least one local screen")
            try expect(layout.screens.allSatisfy { $0.peerId == "test-mac" }, "wrong peer id in local layout")
        }

        r.run("udpPeerFilterAllowsOnlyExpectedHost") {
            let filter = UdpPeerFilter(expectedHost: " 192.168.0.100 ")
            try expect(filter.isActive, "filter should be active with an expected host")
            try expect(filter.allows(remoteHost: "192.168.0.100"), "exact peer IP should pass")
            try expect(filter.allows(remoteHost: "::ffff:192.168.0.100"), "IPv4-mapped peer IP should pass")
            try expect(!filter.allows(remoteHost: "192.168.0.101"), "different LAN peer should be rejected")
        }

        r.run("udpPeerFilterAllowsLoopbackAliases") {
            let filter = UdpPeerFilter(expectedHost: "localhost")
            try expect(filter.allows(remoteHost: "127.0.0.1"), "localhost should allow IPv4 loopback")
            try expect(filter.allows(remoteHost: "::1"), "localhost should allow IPv6 loopback")
            try expect(!UdpPeerFilter(expectedHost: "").isActive, "empty peer host should disable receiver startup")
        }

        r.run("udpKmAuthenticatorRoundTripKnownFixture") {
            let frameBytes = Data([
                0x04, 0x03, 0x02, 0x01,
                0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11,
                0xFE,
            ])
            guard let authenticator = UdpKmAuthenticator(sharedSecret: "secret") else {
                throw TestFailure.message("expected authenticator")
            }
            let envelope = authenticator.seal(frameBytes)
            let expected: [UInt8] = [
                0x42, 0x52, 0x4B, 0x4D, 0x01, 0x01, 0x00, 0x00,
                0x0D, 0x00, 0x00, 0x00,
                0x04, 0x03, 0x02, 0x01,
                0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11,
                0xFE,
                0x6F, 0x78, 0xFE, 0xFD, 0x0F, 0x8C, 0x20, 0x69,
                0x24, 0x1D, 0x77, 0xFA, 0xBC, 0x50, 0xE8, 0xBF,
                0xF6, 0xCD, 0x98, 0x2E, 0xC5, 0x9E, 0x32, 0xB9,
                0x0E, 0x51, 0xFC, 0x67, 0x8A, 0x4C, 0x03, 0xDE,
            ]
            try expectEqual(Array(envelope), expected)
            try expectEqual(try authenticator.open(envelope), frameBytes)
        }

        r.run("udpKmAuthenticatorRejectsWrongSecretAndTamper") {
            let frameBytes = Data([0x01, 0x02, 0x03])
            guard let authenticator = UdpKmAuthenticator(sharedSecret: "secret"),
                  let wrong = UdpKmAuthenticator(sharedSecret: "wrong") else {
                throw TestFailure.message("expected authenticators")
            }
            let envelope = authenticator.seal(frameBytes)

            try expectThrows(UdpKmAuthenticationError.invalidTag) {
                _ = try wrong.open(envelope)
            }

            var tampered = envelope
            tampered[UdpKmAuthenticator.headerSize] ^= 0x01
            try expectThrows(UdpKmAuthenticationError.invalidTag) {
                _ = try authenticator.open(tampered)
            }
        }

        r.run("udpKmReplayGuardSplitsFlowAndInputLanes") {
            let guarder = UdpKmReplayGuard()
            try expect(guarder.accepts(KmFrame(seq: 1_000_000_000, timestampUs: 0, type: .heartbeat)), "first heartbeat should pass")
            try expect(guarder.accepts(KmFrame(seq: 0, timestampUs: 0, type: .mouseMoveRel)), "first input seq 0 should pass despite high heartbeat seq")
        }

        r.run("udpKmReplayGuardRejectsDuplicateAndOldFrames") {
            let guarder = UdpKmReplayGuard(windowSize: 4)
            for seq in 10...15 {
                try expect(guarder.accepts(KmFrame(seq: UInt32(seq), timestampUs: 0, type: .keyDown)), "seq \(seq) should pass")
            }
            try expect(!guarder.accepts(KmFrame(seq: 14, timestampUs: 0, type: .keyDown)), "duplicate within window should fail")
            try expect(!guarder.accepts(KmFrame(seq: 10, timestampUs: 0, type: .keyDown)), "old frame outside window should fail")
        }

        r.run("udpKmReplayGuardAllowsOutOfOrderWithinWindowOnce") {
            let guarder = UdpKmReplayGuard(windowSize: 4)
            try expect(guarder.accepts(KmFrame(seq: 10, timestampUs: 0, type: .mouseScroll)), "seq 10 should pass")
            try expect(guarder.accepts(KmFrame(seq: 12, timestampUs: 0, type: .mouseScroll)), "seq 12 should pass")
            try expect(guarder.accepts(KmFrame(seq: 11, timestampUs: 0, type: .mouseScroll)), "out-of-order seq 11 should pass once")
            try expect(!guarder.accepts(KmFrame(seq: 11, timestampUs: 0, type: .mouseScroll)), "duplicate out-of-order seq 11 should fail")
        }
    }
}
