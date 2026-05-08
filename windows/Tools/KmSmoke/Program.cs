using BarelyReal.Core.Clipboard;
using BarelyReal.Core.Km;
using BarelyReal.Core.Network;
using BarelyReal.Core.Protocol;

if (args.Length == 0 || args[0] is "-h" or "--help" or "help")
{
    PrintUsage();
    return 0;
}

try
{
    switch (args[0].ToLowerInvariant())
    {
        case "udp-loopback":
            return await UdpLoopback(args);
        case "capture":
            return Capture(args);
        case "send":
            return Send(args);
        case "receive":
            return Receive(args);
        case "inject-mouse":
            return InjectMouse(args);
        case "inject-key":
            return InjectKey(args);
        default:
            Console.Error.WriteLine($"Unknown command: {args[0]}");
            PrintUsage();
            return 2;
    }
}
catch (Exception ex)
{
    Console.Error.WriteLine(ex);
    return 1;
}

static async Task<int> UdpLoopback(string[] args)
{
    var positionals = PositionalArguments(args);
    var port = positionals.Count >= 1 ? ushort.Parse(positionals[0]) : (ushort)24801;
    var kmSecret = OptionValue(args, "--km-secret");
    using var stream = new UdpKmStream(kmSecret);
    using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(3));
    var received = new TaskCompletionSource<KmFrame>(TaskCreationOptions.RunContinuationsAsynchronously);

    stream.OnFrame += frame => received.TrySetResult(frame);
    stream.Bind(port);

    var sent = new KmFrame(7, NowUs(), KmType.Heartbeat);
    stream.Send(sent, "127.0.0.1", port);

    using var registration = cts.Token.Register(() => received.TrySetCanceled(cts.Token));
    var got = await received.Task.ConfigureAwait(false);

    if (!sent.Equals(got))
    {
        Console.Error.WriteLine("UDP loopback mismatch");
        Console.Error.WriteLine($"Sent: {Describe(sent)}");
        Console.Error.WriteLine($"Got:  {Describe(got)}");
        return 1;
    }

    Console.WriteLine($"UDP loopback ok on 127.0.0.1:{port}: {Describe(got)}");
    return 0;
}

static int Capture(string[] args)
{
    var seconds = args.Length >= 2 ? int.Parse(args[1]) : 10;
    using var hooks = new LowLevelHooks();
    using var done = new ManualResetEventSlim(false);

    Console.CancelKeyPress += (_, e) =>
    {
        e.Cancel = true;
        done.Set();
    };

    hooks.OnFrame += frame => Console.WriteLine(Describe(frame));
    hooks.Start();

    Console.WriteLine($"Capturing KM frames for {seconds}s. Press Ctrl+C to stop.");
    done.Wait(TimeSpan.FromSeconds(seconds));
    hooks.Stop();
    Console.WriteLine("Capture stopped.");
    return 0;
}

static int Send(string[] args)
{
    var positionals = PositionalArguments(args);
    if (positionals.Count < 1)
    {
        Console.Error.WriteLine("send requires peer host: send <peerHost> [peerPort] [seconds]");
        return 2;
    }

    var peerHost = positionals[0];
    var peerPort = positionals.Count >= 2 ? ushort.Parse(positionals[1]) : (ushort)24801;
    var seconds = positionals.Count >= 3 ? int.Parse(positionals[2]) : 0;
    var kmSecret = OptionValue(args, "--km-secret");
    using var stream = new UdpKmStream(kmSecret);
    using var hooks = new LowLevelHooks();
    using var done = new ManualResetEventSlim(false);
    var sent = 0;

    Console.CancelKeyPress += (_, e) =>
    {
        e.Cancel = true;
        done.Set();
    };

    hooks.OnFrame += frame =>
    {
        stream.Send(frame, peerHost, peerPort);
        sent++;
        if (sent <= 10 || sent % 100 == 0)
            Console.WriteLine($"sent {Describe(frame)}");
    };

    hooks.Start();
    Console.WriteLine($"Sending KM frames to {peerHost}:{peerPort}{(string.IsNullOrWhiteSpace(kmSecret) ? "" : " with HMAC authentication")}. Press Ctrl+C to stop.");

    if (seconds > 0)
        done.Wait(TimeSpan.FromSeconds(seconds));
    else
        done.Wait();

    hooks.Stop();
    Console.WriteLine($"Send stopped. Frames sent: {sent}");
    return 0;
}

static int Receive(string[] args)
{
    var positionals = PositionalArguments(args);
    var localPort = positionals.Count >= 1 ? ushort.Parse(positionals[0]) : (ushort)24801;
    var seconds = positionals.Count >= 2 ? int.Parse(positionals[1]) : 0;
    var clipboardPeer = OptionValue(args, "--clipboard-peer");
    var clipboardPort = OptionUInt16(args, "--clipboard-port", 24802);
    var kmSecret = OptionValue(args, "--km-secret");
    using var stream = new UdpKmStream(kmSecret);
    using var done = new ManualResetEventSlim(false);
    using var cts = new CancellationTokenSource();
    var injector = new InputInjector();
    var received = 0;
    Task? clipboardTask = null;

    Console.CancelKeyPress += (_, e) =>
    {
        e.Cancel = true;
        cts.Cancel();
        done.Set();
    };

    stream.OnFrame += frame =>
    {
        try
        {
            injector.Inject(frame);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"inject failed: {ex.Message}");
        }

        received++;
        if (received <= 10 || received % 100 == 0)
            Console.WriteLine($"received {Describe(frame)}");
    };

    stream.Bind(localPort);
    Console.WriteLine($"Receiving KM frames on UDP :{localPort}{(string.IsNullOrWhiteSpace(kmSecret) ? "" : " with HMAC authentication required")}. Press Ctrl+C to stop.");

    if (!string.IsNullOrWhiteSpace(clipboardPeer))
    {
        var clipboard = new WindowsClipboardTextSync(clipboardPeer, clipboardPort, Console.WriteLine);
        clipboardTask = Task.Run(async () =>
        {
            try
            {
                await clipboard.Run(cts.Token).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
            }
        }, cts.Token);
    }

    if (seconds > 0)
        done.Wait(TimeSpan.FromSeconds(seconds));
    else
        done.Wait();

    cts.Cancel();
    try { clipboardTask?.Wait(TimeSpan.FromSeconds(1)); } catch (AggregateException) { }
    stream.Close();
    Console.WriteLine($"Receive stopped. Frames received: {received}");
    return 0;
}

static int InjectMouse(string[] args)
{
    var dx = args.Length >= 2 ? int.Parse(args[1]) : 20;
    var dy = args.Length >= 3 ? int.Parse(args[2]) : 0;
    var injector = new InputInjector();
    var frame = new KmFrame(
        1,
        NowUs(),
        KmType.MouseMoveRel,
        KmPayload.EncodeMouseMove(new KmPayload.MouseMove(dx, dy)));

    injector.Inject(frame);
    Console.WriteLine($"Injected mouse move dx={dx}, dy={dy}");
    return 0;
}

static int InjectKey(string[] args)
{
    // Windows set-1 scan code for A. This is intentionally small and predictable for Notepad smoke.
    var scanCode = args.Length >= 2 ? ushort.Parse(args[1]) : (ushort)0x1E;
    var injector = new InputInjector { AssumeMacVirtualKeyCodes = false };

    injector.Inject(new KmFrame(1, NowUs(), KmType.KeyDown, KmPayload.EncodeKey(new KmPayload.Key(scanCode, 0))));
    injector.Inject(new KmFrame(2, NowUs(), KmType.KeyUp, KmPayload.EncodeKey(new KmPayload.Key(scanCode, 0))));

    Console.WriteLine($"Injected key scanCode=0x{scanCode:X2}");
    return 0;
}

static string Describe(KmFrame frame) =>
    $"seq={frame.Seq} ts={frame.TimestampUs} type={frame.Type} payload={Convert.ToHexString(frame.Payload)}";

static ulong NowUs() =>
    (ulong)((DateTimeOffset.UtcNow.Ticks - DateTimeOffset.UnixEpoch.Ticks) / 10);

static string? OptionValue(string[] args, string name)
{
    var index = Array.IndexOf(args, name);
    return index >= 0 && args.Length > index + 1 ? args[index + 1] : null;
}

static ushort OptionUInt16(string[] args, string name, ushort fallback)
{
    var value = OptionValue(args, name);
    return string.IsNullOrWhiteSpace(value) ? fallback : ushort.Parse(value);
}

static IReadOnlyList<string> PositionalArguments(string[] args)
{
    var values = new List<string>();
    for (var i = 1; i < args.Length; i++)
    {
        if (args[i].StartsWith("--", StringComparison.Ordinal))
        {
            if (i + 1 < args.Length && !args[i + 1].StartsWith("--", StringComparison.Ordinal))
                i++;
            continue;
        }

        values.Add(args[i]);
    }

    return values;
}

static void PrintUsage()
{
    Console.WriteLine("""
BarelyReal.KmSmoke

Usage:
  KmSmoke udp-loopback [port] [--km-secret <secret>]
      Sends one Heartbeat frame to 127.0.0.1 and verifies it comes back.

  KmSmoke capture [seconds]
      Prints captured low-level mouse/keyboard frames. Press Ctrl+C to stop.

  KmSmoke send <peerHost> [peerPort] [seconds] [--km-secret <secret>]
      Captures local KM frames and sends them to a peer over raw UDP.

  KmSmoke receive [localPort] [seconds] [--km-secret <secret>] [--clipboard-peer <mac-ip>] [--clipboard-port 24802]
      Receives raw UDP KM frames and injects them locally.
      With --clipboard-peer, also starts bidirectional text and PNG clipboard sync.

  KmSmoke inject-mouse [dx] [dy]
      Injects one relative mouse move. Default: dx=20 dy=0.

  KmSmoke inject-key [scanCode]
      Injects one key press/release by scan code. Default: 0x1E (A).

Suggested manual smoke:
  dotnet run --project windows/Tools/KmSmoke/KmSmoke.csproj -- udp-loopback
  dotnet run --project windows/Tools/KmSmoke/KmSmoke.csproj -- capture 10
  dotnet run --project windows/Tools/KmSmoke/KmSmoke.csproj -- receive 24801 --clipboard-peer <mac-ip>
  dotnet run --project windows/Tools/KmSmoke/KmSmoke.csproj -- send <mac-ip> 24801
  dotnet run --project windows/Tools/KmSmoke/KmSmoke.csproj -- inject-mouse 20 0
  # Open Notepad first, then:
  dotnet run --project windows/Tools/KmSmoke/KmSmoke.csproj -- inject-key
""");
}
