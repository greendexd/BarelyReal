using System.Buffers.Binary;
using System.Net;
using System.Text;
using System.Text.Json;
using BarelyReal.Core.Clipboard;
using BarelyReal.Core.Km;
using BarelyReal.Core.Layout;
using BarelyReal.Core.Network;
using BarelyReal.Core.Protocol;

namespace BarelyReal.Tests;

internal static class ProtocolEncodingTests
{
    public static void RunAll()
    {
        Console.WriteLine("ProtocolEncodingTests");

        TestRunner.Run("kmFrameRoundTripHeartbeat", () =>
        {
            var frame = new KmFrame(42, 1_700_000_000_123_456UL, KmType.Heartbeat);
            var encoded = KmFrameCodec.Encode(frame);
            Expect.Equal(encoded.Length, 13);
            var decoded = KmFrameCodec.Decode(encoded);
            Expect.Equal(decoded, frame);
        });

        TestRunner.Run("kmFrameRoundTripMouseMoveRel", () =>
        {
            var payload = new byte[8];
            BinaryPrimitives.WriteInt32LittleEndian(payload.AsSpan(0, 4), -5);
            BinaryPrimitives.WriteInt32LittleEndian(payload.AsSpan(4, 4), 17);
            var frame = new KmFrame(1, 0, KmType.MouseMoveRel, payload);
            var encoded = KmFrameCodec.Encode(frame);
            var decoded = KmFrameCodec.Decode(encoded);
            Expect.Equal(decoded, frame);
            Expect.Equal(BinaryPrimitives.ReadInt32LittleEndian(decoded.Payload.AsSpan(0, 4)), -5);
            Expect.Equal(BinaryPrimitives.ReadInt32LittleEndian(decoded.Payload.AsSpan(4, 4)), 17);
        });

        TestRunner.Run("kmPayloadMouseMoveRoundTrip", () =>
        {
            var payload = KmPayload.EncodeMouseMove(new KmPayload.MouseMove(-1920, 1080));
            var decoded = KmPayload.DecodeMouseMove(payload);
            Expect.Equal(decoded, new KmPayload.MouseMove(-1920, 1080));
        });

        TestRunner.Run("kmPayloadMouseButtonRoundTrip", () =>
        {
            var payload = KmPayload.EncodeMouseButton(new KmPayload.MouseButton(2, true));
            var decoded = KmPayload.DecodeMouseButton(payload);
            Expect.Equal(decoded, new KmPayload.MouseButton(2, true));
        });

        TestRunner.Run("kmPayloadMouseScrollRoundTrip", () =>
        {
            var payload = KmPayload.EncodeMouseScroll(new KmPayload.MouseScroll(-12, 48));
            var decoded = KmPayload.DecodeMouseScroll(payload);
            Expect.Equal(decoded, new KmPayload.MouseScroll(-12, 48));
        });

        TestRunner.Run("kmPayloadKeyRoundTrip", () =>
        {
            var payload = KmPayload.EncodeKey(new KmPayload.Key(0x37, 0x0010_0000));
            var decoded = KmPayload.DecodeKey(payload);
            Expect.Equal(decoded, new KmPayload.Key(0x37, 0x0010_0000));
        });

        // Cross-platform fixture: this exact byte sequence MUST decode to the same frame on macOS.
        // Mirror of mac/Tests/ProtocolEncodingTests.swift::kmFrameKnownByteFixture.
        TestRunner.Run("kmFrameKnownByteFixture", () =>
        {
            byte[] bytes =
            {
                0x04, 0x03, 0x02, 0x01,                         // seq = 0x01020304
                0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, // ts  = 0x1122334455667788
                0xFE                                             // type = heartbeat
            };
            var decoded = KmFrameCodec.Decode(bytes);
            Expect.Equal(decoded.Seq, 0x01020304U);
            Expect.Equal(decoded.TimestampUs, 0x1122334455667788UL);
            Expect.Equal(decoded.Type, KmType.Heartbeat);
            Expect.Equal(decoded.Payload.Length, 0);

            var reEncoded = KmFrameCodec.Encode(decoded);
            Expect.EqualBytes(reEncoded, bytes);
        });

        TestRunner.Run("kmFrameTruncatedThrows", () =>
        {
            Expect.Throws<BrpCodecException>(() => KmFrameCodec.Decode(new byte[] { 0x01, 0x02, 0x03 }));
        });

        TestRunner.Run("kmFrameUnknownTypeThrows", () =>
        {
            var data = new byte[13];
            data[12] = 0x42;
            try
            {
                KmFrameCodec.Decode(data);
                throw new AssertionException("expected BrpCodecException");
            }
            catch (BrpCodecException ex)
            {
                Expect.Equal(ex.Error, BrpCodecError.UnknownType);
                Expect.Equal(ex.UnknownTypeByte, (byte?)0x42);
            }
        });

        TestRunner.Run("udpKmSourceFilterAllowsOnlyExpectedAddress", () =>
        {
            var filter = UdpKmSourceFilter.FromAddresses("mac", IPAddress.Parse("192.168.0.101"));
            Expect.True(filter.Enabled, "filter should be enabled");
            Expect.True(filter.Allows(IPAddress.Parse("192.168.0.101")), "expected peer must pass");
            Expect.True(!filter.Allows(IPAddress.Parse("192.168.0.102")), "unexpected peer must drop");
        });

        TestRunner.Run("udpKmSourceFilterNormalizesMappedIpv4", () =>
        {
            var filter = UdpKmSourceFilter.FromAddresses("mac", IPAddress.Parse("192.168.0.101").MapToIPv6());
            Expect.True(filter.Allows(IPAddress.Parse("192.168.0.101")), "mapped IPv4 should match IPv4 remote");
        });

        TestRunner.Run("udpKmSourceFilterDisabledAllowsAnyAddress", () =>
        {
            var filter = UdpKmSourceFilter.FromHost("");
            Expect.True(!filter.Enabled, "blank host should disable filtering");
            Expect.True(filter.Allows(IPAddress.Parse("10.0.0.25")), "disabled filter should allow any source");
        });

        TestRunner.Run("controlFrameRoundTripKeepAlive", () =>
        {
            var frame = new ControlFrame(ControlType.KeepAlive);
            var encoded = ControlFrameCodec.Encode(frame);
            Expect.Equal(encoded.Length, 5);
            var (decoded, consumed) = ControlFrameCodec.Decode(encoded);
            Expect.Equal(decoded, frame);
            Expect.Equal(consumed, 5);
        });

        TestRunner.Run("controlFrameRoundTripJsonBody", () =>
        {
            var json = "{\"name\":\"mac-mini\",\"os\":\"mac\",\"ver\":\"1.0.0\"}";
            var body = Encoding.UTF8.GetBytes(json);
            var frame = new ControlFrame(ControlType.Hello, body);
            var encoded = ControlFrameCodec.Encode(frame);
            var (decoded, consumed) = ControlFrameCodec.Decode(encoded);
            Expect.Equal(decoded, frame);
            Expect.Equal(consumed, encoded.Length);
            Expect.Equal(Encoding.UTF8.GetString(decoded.Body), json);
        });

        TestRunner.Run("controlFrameDecodeStopsAtFirstFrameInStream", () =>
        {
            var f1 = new ControlFrame(ControlType.KeepAlive);
            var f2 = new ControlFrame(ControlType.Bye, Encoding.UTF8.GetBytes("bye"));
            var e1 = ControlFrameCodec.Encode(f1);
            var e2 = ControlFrameCodec.Encode(f2);
            var stream = new byte[e1.Length + e2.Length];
            e1.CopyTo(stream, 0);
            e2.CopyTo(stream, e1.Length);

            var (d1, c1) = ControlFrameCodec.Decode(stream);
            Expect.Equal(d1, f1);
            Expect.Equal(c1, 5);

            var (d2, _) = ControlFrameCodec.Decode(stream.AsSpan(c1));
            Expect.Equal(d2, f2);
        });

        TestRunner.Run("controlFrameTruncatedHeader", () =>
        {
            Expect.Throws<BrpCodecException>(() => ControlFrameCodec.Decode(new byte[] { 0x01, 0x02 }));
        });

        TestRunner.Run("controlFrameTruncatedBody", () =>
        {
            var data = new byte[7];
            BinaryPrimitives.WriteUInt32LittleEndian(data.AsSpan(0, 4), 10);
            data[4] = 0x01;
            // Only 2 of the 9 declared body bytes present.
            Expect.Throws<BrpCodecException>(() => ControlFrameCodec.Decode(data));
        });

        // Cross-platform fixture: matches mac/Tests/ProtocolEncodingTests.swift::controlFrameKnownByteFixture.
        TestRunner.Run("controlFrameKnownByteFixture", () =>
        {
            byte[] bytes =
            {
                0x05, 0x00, 0x00, 0x00, // length = 5
                0xF0,                    // type = KeepAlive
                0x70, 0x69, 0x6E, 0x67   // "ping"
            };
            var (decoded, consumed) = ControlFrameCodec.Decode(bytes);
            Expect.Equal(decoded.Type, ControlType.KeepAlive);
            Expect.Equal(Encoding.UTF8.GetString(decoded.Body), "ping");
            Expect.Equal(consumed, 9);

            var reEncoded = ControlFrameCodec.Encode(decoded);
            Expect.EqualBytes(reEncoded, bytes);
        });

        TestRunner.Run("pairingSasFromExporter", () =>
        {
            Expect.Equal(PairingService.Sas(new byte[] { 0x40, 0x42, 0x0F, 0x00 }), "000000");
            Expect.Equal(PairingService.Sas(new byte[] { 0x3F, 0x42, 0x0F, 0x00 }), "999999");
            Expect.Equal(PairingService.Sas(new byte[] { 0x2A, 0x00, 0x00, 0x00 }), "000042");
        });

        TestRunner.Run("pairingPinLockoutAfterFiveWrongAttempts", () =>
        {
            var service = new PairingService(maxWrongAttempts: 5, lockoutSeconds: 60);
            for (var i = 0; i < 4; i++)
            {
                try
                {
                    service.Confirm("000000", "123456");
                    throw new AssertionException("expected mismatch");
                }
                catch (PairingService.PinException ex) when (ex.Reason == PairingService.PinError.Mismatch)
                {
                }
            }

            try
            {
                service.Confirm("000000", "123456");
                throw new AssertionException("expected lockout");
            }
            catch (PairingService.PinException ex) when (ex.Reason == PairingService.PinError.LockedOut)
            {
                Expect.Equal(ex.RetryAfterSeconds, 60);
            }
        });

        TestRunner.Run("pairingCorrectPinResetsWrongAttemptCounter", () =>
        {
            var service = new PairingService(maxWrongAttempts: 5, lockoutSeconds: 60);
            try
            {
                service.Confirm("000000", "123456");
                throw new AssertionException("expected mismatch");
            }
            catch (PairingService.PinException ex) when (ex.Reason == PairingService.PinError.Mismatch)
            {
            }

            service.Confirm("123456", "123456");

            for (var i = 0; i < 4; i++)
            {
                try
                {
                    service.Confirm("000000", "123456");
                    throw new AssertionException("expected mismatch");
                }
                catch (PairingService.PinException ex) when (ex.Reason == PairingService.PinError.Mismatch)
                {
                }
            }
        });

        TestRunner.Run("wakeOnLanMagicPacket", () =>
        {
            var packet = WakeOnLan.MagicPacket("AA:BB:CC:DD:EE:FF");
            Expect.Equal(packet.Length, 102);
            Expect.EqualBytes(packet[..6], new byte[] { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF });
            Expect.EqualBytes(packet[6..12], new byte[] { 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF });
            Expect.EqualBytes(packet[^6..], new byte[] { 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF });
        });

        TestRunner.Run("wakeOnLanRejectsInvalidMac", () =>
        {
            Expect.Throws<WakeOnLanException>(() => WakeOnLan.MagicPacket("not-a-mac"));
        });

        TestRunner.Run("clipboardHistoryDedupAndPrune", () =>
        {
            var dir = Path.Combine(Path.GetTempPath(), $"BarelyRealTests-{Guid.NewGuid()}");
            try
            {
                var history = new ClipboardHistory(dir, maxEntries: 2);
                var first = new ClipboardEntry { Id = 1, Formats = new() { ["text/plain"] = Encoding.UTF8.GetBytes("one") }, ContentHash = new byte[] { 1 } };
                var duplicate = new ClipboardEntry { Id = 2, Formats = new() { ["text/plain"] = Encoding.UTF8.GetBytes("one again") }, ContentHash = new byte[] { 1 } };
                var second = new ClipboardEntry { Id = 3, Formats = new() { ["text/plain"] = Encoding.UTF8.GetBytes("two") }, ContentHash = new byte[] { 2 } };
                var third = new ClipboardEntry { Id = 4, Formats = new() { ["text/plain"] = Encoding.UTF8.GetBytes("three") }, ContentHash = new byte[] { 3 } };
                history.Append(first);
                history.Append(duplicate);
                history.Append(second);
                history.Append(third);
                var recent = history.Recent();
                Expect.Equal(recent.Count, 2);
                Expect.Equal(recent[0].Id, 4UL);
                Expect.Equal(recent[1].Id, 3UL);
            }
            finally
            {
                try { Directory.Delete(dir, recursive: true); } catch { }
            }
        });

        TestRunner.Run("fileBundleRoundTrip", () =>
        {
            var bundle = new ClipboardFileBundle(new[]
            {
                new ClipboardFile("hello.txt", Encoding.UTF8.GetBytes("Hello, world!")),
                new ClipboardFile("image.png", new byte[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A }),
            });
            var encoded = ClipboardFileBundleCodec.Encode(bundle);
            var decoded = ClipboardFileBundleCodec.Decode(encoded);
            Expect.True(decoded.Equals(bundle), "round trip mismatch");
        });

        TestRunner.Run("fileBundleEmptyRoundTrip", () =>
        {
            var bundle = new ClipboardFileBundle(Array.Empty<ClipboardFile>());
            var encoded = ClipboardFileBundleCodec.Encode(bundle);
            Expect.Equal(encoded.Length, 4); // file_count = 0
            var decoded = ClipboardFileBundleCodec.Decode(encoded);
            Expect.True(decoded.Equals(bundle), "empty round trip mismatch");
        });

        TestRunner.Run("fileBundleTruncatedThrows", () =>
        {
            var data = new byte[4];
            BinaryPrimitives.WriteUInt32LittleEndian(data, 1);
            try
            {
                ClipboardFileBundleCodec.Decode(data);
                throw new AssertionException("expected ClipboardFileBundleException");
            }
            catch (ClipboardFileBundleException ex)
            {
                Expect.Equal(ex.ErrorKind, ClipboardFileBundleError.Truncated);
            }
        });

        TestRunner.Run("fileBundleSanitizesName", () =>
        {
            Expect.Equal(ClipboardFileBundleCodec.SanitizeName("safe.txt"), "safe.txt");
            Expect.Equal(ClipboardFileBundleCodec.SanitizeName("/etc/passwd"), "passwd");
            Expect.Equal(ClipboardFileBundleCodec.SanitizeName("../../secret.key"), "secret.key");
            Expect.Equal(ClipboardFileBundleCodec.SanitizeName("a:b\\c/d"), "d");
            Expect.True(ClipboardFileBundleCodec.SanitizeName("") == null, "empty name must be rejected");
            Expect.True(ClipboardFileBundleCodec.SanitizeName(".") == null, "dot must be rejected");
            Expect.True(ClipboardFileBundleCodec.SanitizeName("..") == null, "double dot must be rejected");
        });

        // Cross-platform fixture: byte-for-byte fixed bundle encoding.
        // Mirrors mac/Tests/ProtocolEncodingTests.swift::fileBundleKnownByteFixture.
        TestRunner.Run("fileBundleKnownByteFixture", () =>
        {
            var bundle = new ClipboardFileBundle(new[]
            {
                new ClipboardFile("ab", new byte[] { 0xCA, 0xFE }),
            });
            var encoded = ClipboardFileBundleCodec.Encode(bundle);
            byte[] expected =
            {
                0x01, 0x00, 0x00, 0x00,  // file_count = 1
                0x02, 0x00,               // name_len = 2
                0x61, 0x62,               // "ab"
                0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // size = 2
                0xCA, 0xFE,               // bytes
            };
            Expect.EqualBytes(encoded, expected);
            var decoded = ClipboardFileBundleCodec.Decode(expected);
            Expect.True(decoded.Equals(bundle), "decode mismatch");
        });

        TestRunner.Run("inputInjectorMapsMacSpecialKeysToWindowsScanCodes", () =>
        {
            var injector = new InputInjector();

            var printScreen = injector.TranslateKeyForInjection(0x69); // Mac F13 / PC Print Screen
            Expect.Equal(printScreen.ScanCode, (ushort)0x37);
            Expect.True(printScreen.IsExtended, "Print Screen must be sent as E0 37, not keypad multiply");

            var insert = injector.TranslateKeyForInjection(0x72); // Mac Help / Insert
            Expect.Equal(insert.ScanCode, (ushort)0x52);
            Expect.True(insert.IsExtended, "Insert must be sent as E0 52, not keypad 0");

            var home = injector.TranslateKeyForInjection(0x73);
            Expect.Equal(home.ScanCode, (ushort)0x47);
            Expect.True(home.IsExtended, "Home must be sent as E0 47, not keypad 7");

            var f1 = injector.TranslateKeyForInjection(0x7A);
            Expect.Equal(f1.ScanCode, (ushort)0x3B);
            Expect.True(!f1.IsExtended, "F1 is not an extended scan code");

            var keypadMultiply = injector.TranslateKeyForInjection(0x43);
            Expect.Equal(keypadMultiply.ScanCode, (ushort)0x37);
            Expect.True(!keypadMultiply.IsExtended, "keypad multiply must stay non-extended");

            var commandAsCtrl = injector.TranslateKeyForInjection(0x37);
            Expect.Equal(commandAsCtrl.ScanCode, (ushort)0x1D);
            Expect.True(!commandAsCtrl.IsExtended, "default Cmd->Ctrl remap should use left control");

            injector.Remap.CmdToCtrl = false;
            var commandAsWin = injector.TranslateKeyForInjection(0x37);
            Expect.Equal(commandAsWin.ScanCode, (ushort)0x5B);
            Expect.True(commandAsWin.IsExtended, "disabled Cmd->Ctrl remap should preserve the Windows key");
        });

        TestRunner.Run("lowLevelHooksPreserveExtendedScanCodesForWire", () =>
        {
            Expect.Equal(LowLevelHooks.EncodeKeyboardScanCodeForWire(0x37, 0x01), (ushort)0xE037); // Print Screen
            Expect.Equal(LowLevelHooks.EncodeKeyboardScanCodeForWire(0x37, 0x00), (ushort)0x0037); // Keypad *
            Expect.Equal(LowLevelHooks.EncodeKeyboardScanCodeForWire(0x52, 0x01), (ushort)0xE052); // Insert
        });

        TestRunner.Run("layoutEngineFindsContainingScreen", () =>
        {
            var mac = new ScreenRect("mac", 0, 0, 0, 1920, 1080);
            var win = new ScreenRect("win", 0, 1920, 0, 2560, 1440);
            var engine = new LayoutEngine(new Layout(new[] { mac, win }));

            Expect.Equal(engine.Screen(100, 100)?.PeerId, "mac");
            Expect.Equal(engine.Screen(2000, 100)?.PeerId, "win");
            Expect.True(engine.Screen(-1, 0) == null, "expected null at (-1,0)");
            Expect.True(engine.Screen(5000, 5000) == null, "expected null at (5000,5000)");
        });

        TestRunner.Run("screenAnnouncementJsonRoundTrip", () =>
        {
            var announcement = new ScreenAnnouncement(
                "windows",
                new[]
                {
                    new AnnouncedScreen(1, 0, 0, 2560, 1440, 1.0, true),
                    new AnnouncedScreen(2, 2560, 160, 1920, 1080, 1.0, false),
                });

            var json = JsonSerializer.Serialize(announcement);
            Expect.True(json.Contains("\"peer_id\":\"windows\""), "ScreenAnnounce must use peer_id wire key");
            Expect.True(json.Contains("\"screens\""), "ScreenAnnounce must include screens");

            var decoded = JsonSerializer.Deserialize<ScreenAnnouncement>(json);
            Expect.Equal(decoded, announcement);
        });

        TestRunner.Run("layoutSyncUsesWireKeys", () =>
        {
            var sync = new LayoutSyncMessage(new[]
            {
                new ScreenRect("mac", 7, -2560, 480, 2560, 1440),
            });

            var json = JsonSerializer.Serialize(sync);
            Expect.True(json.Contains("\"peer_id\":\"mac\""), "LayoutSync must use peer_id wire key");
            Expect.True(json.Contains("\"screen_id\":7"), "LayoutSync must use screen_id wire key");
            Expect.True(json.Contains("\"w\":2560"), "LayoutSync must use compact width key");
            Expect.True(json.Contains("\"h\":1440"), "LayoutSync must use compact height key");

            var decoded = JsonSerializer.Deserialize<LayoutSyncMessage>(json);
            Expect.Equal(decoded, sync);
        });

        TestRunner.Run("layoutTranslatedMovesOnlyPeerGroup", () =>
        {
            var winMain = new ScreenRect("windows", 1, 0, 0, 2560, 1440);
            var winExternal = new ScreenRect("windows", 2, 2560, 0, 1920, 1080);
            var mac = new ScreenRect("mac", 1, -1728, 240, 1728, 1117);
            var moved = new Layout(new[] { winMain, winExternal, mac }).Translated("mac", dx: 6400, dy: -400);

            Expect.True(moved.ScreensFor("windows").SequenceEqual(new[] { winMain, winExternal }), "local group moved unexpectedly");
            Expect.True(moved.ScreensFor("mac").SequenceEqual(new[]
            {
                new ScreenRect("mac", 1, 4672, -160, 1728, 1117),
            }), "remote group did not move by expected delta");
            Expect.Equal(moved.Bounds("windows"), new ScreenRectBounds(0, 0, 4480, 1440));
        });

        TestRunner.Run("layoutStickySnapAttachesPeerGroupToNearestScreenEdge", () =>
        {
            var win = new ScreenRect("windows", 1, 0, 0, 2560, 1440);
            var mac = new ScreenRect("mac", 1, -1800, 20, 1728, 1117);
            var snapped = new Layout(new[] { win, mac }).StickySnapped("mac", "windows");

            Expect.True(snapped.ScreensFor("mac").SequenceEqual(new[]
            {
                new ScreenRect("mac", 1, -1728, 0, 1728, 1117),
            }), "remote group should attach to the nearest local edge");
        });

        TestRunner.Run("layoutStickySnapSupportsTopPlacementWithOffset", () =>
        {
            var win = new ScreenRect("windows", 1, 0, 0, 2560, 1440);
            var mac = new ScreenRect("mac", 1, 260, -1200, 1728, 1117);
            var snapped = new Layout(new[] { win, mac }).StickySnapped("mac", "windows");

            Expect.True(snapped.ScreensFor("mac").SequenceEqual(new[]
            {
                new ScreenRect("mac", 1, 260, -1117, 1728, 1117),
            }), "remote group should attach above while preserving horizontal offset");
        });

        TestRunner.Run("displayEnumeratorReturnsLocalLayout", () =>
        {
            var layout = DisplayEnumerator.LocalLayout("test-win");
            Expect.True(layout.Screens.Count > 0, "expected at least one local screen");
            Expect.True(layout.Screens.All(screen => screen.PeerId == "test-win"), "wrong peer id in local layout");
        });
    }
}
