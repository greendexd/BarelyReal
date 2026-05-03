using System.ComponentModel;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using BarelyReal.App.Services;
using BarelyReal.Core.Layout;
using BarelyReal.Core.Network;

namespace BarelyReal.App;

public partial class MainWindow : Window
{
    private readonly DevReceiverService _receiver = new();
    private readonly DevSenderService _sender = new();
    private readonly DevControlSession _control = new();
    private const string LocalPeerId = "windows";
    private const string RemotePeerId = "mac";
    private List<DisplayInfo> _localDisplays = new();
    private List<DisplayInfo> _remoteDisplays = new();
    private BarelyReal.Core.Layout.Layout _virtualLayout = new();
    private bool _remoteScreensStale = true;
    private bool _uiReady;

    private bool IsSendMode => ModeSendRadio?.IsChecked == true;

    public MainWindow()
    {
        InitializeComponent();

        _receiver.LogLine += AppendLog;
        _receiver.StatsChanged += UpdateStatus;
        _receiver.HistoryChanged += () => Dispatcher.BeginInvoke(RefreshClipboardHistory);
        _sender.LogLine += AppendLog;
        _sender.StatsChanged += UpdateStatus;
        _control.LogLine += AppendLog;
        _control.ScreenAnnounced += announcement => Dispatcher.BeginInvoke(() => ApplyRemoteAnnouncement(announcement));
        _control.LayoutSynced += layout => Dispatcher.BeginInvoke(() => ApplyRemoteLayout(layout));

        KmPortBox.TextChanged += CommandInput_Changed;
        ClipboardPortBox.TextChanged += CommandInput_Changed;
        ClipboardPeerBox.TextChanged += CommandInput_Changed;
        ControlPortBox.TextChanged += CommandInput_Changed;

        Loaded += MainWindow_Loaded;
        Closing += MainWindow_Closing;
    }

    private void MainWindow_Loaded(object sender, RoutedEventArgs e)
    {
        WidthBox.Text = GetSystemMetric(0).ToString();
        HeightBox.Text = GetSystemMetric(1).ToString();

        RefreshDisplays();
        ReconcileLayout();
        RefreshAddresses();
        _uiReady = true;
        UpdateMacCommand();
        UpdateStatus();
        WireLayoutDesigner();
        StartReceiver();
    }

    private void WireLayoutDesigner()
    {
        if (LayoutDesigner is null) return;
        LayoutDesigner.RemoteMoved += MoveRemoteGroup;
        RefreshLayoutDesigner();
    }

    private void RefreshLayoutDesigner()
    {
        if (LayoutDesigner is null) return;
        LayoutDesigner.Refresh(_virtualLayout, LocalPeerId, RemotePeerId, _remoteScreensStale);
    }

    private void MainWindow_Closing(object? sender, CancelEventArgs e)
    {
        _receiver.Dispose();
        _sender.Dispose();
        _control.Dispose();
    }

    // MARK: - Navigation

    private void Nav_Changed(object sender, RoutedEventArgs e)
    {
        if (HomePage is null) return; // not yet loaded

        var home = NavHome?.IsChecked == true;
        var clipboard = NavClipboard?.IsChecked == true;
        var activity = NavActivity?.IsChecked == true;
        var settings = NavSettings?.IsChecked == true;

        HomePage.Visibility     = home      ? Visibility.Visible : Visibility.Collapsed;
        if (ClipboardPage is not null) ClipboardPage.Visibility = clipboard ? Visibility.Visible : Visibility.Collapsed;
        if (ActivityPage is not null)  ActivityPage.Visibility  = activity  ? Visibility.Visible : Visibility.Collapsed;
        if (SettingsPage is not null)  SettingsPage.Visibility  = settings  ? Visibility.Visible : Visibility.Collapsed;

        if (PageTitleText is not null)
            PageTitleText.Text = home ? "Home" : (clipboard ? "Clipboard" : (activity ? "Activity" : "Settings"));

        if (clipboard) RefreshClipboardHistory();
    }

    private void RefreshClipboardHistory_Click(object sender, RoutedEventArgs e)
    {
        RefreshClipboardHistory();
    }

    private void RefreshClipboardHistory()
    {
        if (ClipboardHistoryList is null) return;

        var entries = _receiver.History.Recent();
        var items = entries.Select(MapEntry).ToList();
        ClipboardHistoryList.ItemsSource = items;
        if (ClipboardHistorySubtitle is not null)
            ClipboardHistorySubtitle.Text = $"{entries.Count} item{(entries.Count == 1 ? "" : "s")} synced";
    }

    private static ClipboardHistoryRow MapEntry(BarelyReal.Core.Clipboard.ClipboardEntry entry)
    {
        var time = DateTimeOffset.FromUnixTimeMilliseconds((long)entry.Id).LocalDateTime;
        string kind = "Item";
        string preview = string.Empty;
        long total = 0;
        foreach (var kv in entry.Formats)
        {
            total += kv.Value.Length;
            switch (kv.Key)
            {
                case "text/plain":
                    kind = "Text";
                    preview = System.Text.Encoding.UTF8.GetString(kv.Value);
                    break;
                case "image/png":
                    kind = "Image";
                    preview = $"PNG image ({kv.Value.Length:N0} bytes)";
                    break;
                case "application/x-barelyreal-files":
                    kind = "Files";
                    preview = $"{kv.Value.Length:N0} bytes (file bundle)";
                    break;
            }
        }
        if (preview.Length > 220) preview = preview[..220] + "…";

        return new ClipboardHistoryRow
        {
            KindLabel = kind,
            TimeLabel = time.ToString("HH:mm:ss"),
            SizeLabel = total > 1024
                ? $"{total / 1024.0:F1} KB"
                : $"{total} B",
            Preview = preview
        };
    }

    public sealed class ClipboardHistoryRow
    {
        public string KindLabel { get; set; } = string.Empty;
        public string TimeLabel { get; set; } = string.Empty;
        public string SizeLabel { get; set; } = string.Empty;
        public string Preview { get; set; } = string.Empty;
    }

    // MARK: - Buttons

    private void StartButton_Click(object sender, RoutedEventArgs e)
    {
        if (IsSendMode) StartSender();
        else StartReceiver();
    }

    private void StopButton_Click(object sender, RoutedEventArgs e)
    {
        if (IsSendMode) _sender.Stop();
        else _receiver.Stop();
        _control.Close();
    }

    private void ModeRadio_Changed(object sender, RoutedEventArgs e)
    {
        if (!_uiReady) return;
        if (ReceiveCard is null || SendCard is null) return;

        ReceiveCard.Visibility = IsSendMode ? Visibility.Collapsed : Visibility.Visible;
        SendCard.Visibility    = IsSendMode ? Visibility.Visible : Visibility.Collapsed;

        if (IsSendMode) _receiver.Stop();
        else            _sender.Stop();
        _control.Close();

        UpdateStatus();
    }

    private void StartSender()
    {
        if (!ushort.TryParse(SendMacKmPortBox.Text.Trim(), out var port))
        {
            AppendLog($"[{DateTime.Now:HH:mm:ss}] Invalid Mac KM port.");
            return;
        }
        var host = SendMacHostBox.Text.Trim();
        if (string.IsNullOrEmpty(host))
        {
            AppendLog($"[{DateTime.Now:HH:mm:ss}] Mac IP required.");
            return;
        }
        try
        {
            StartControl(host);
            _sender.Start(host, port, LocalPeerId, RemotePeerId, () => _virtualLayout, () => _remoteDisplays);
        }
        catch (Exception ex)
        {
            AppendLog($"[{DateTime.Now:HH:mm:ss}] Sender start failed: {ex.Message}");
        }
        UpdateStatus();
    }

    private void RefreshButton_Click(object sender, RoutedEventArgs e)
    {
        RefreshAddresses();
        UpdateMacCommand();
    }

    private void CopyCommandButton_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Clipboard.SetText(CommandBox.Text, TextDataFormat.UnicodeText);
            CommandStatusText.Text = "Copied";
        }
        catch (Exception ex)
        {
            CommandStatusText.Text = $"Copy failed: {ex.Message}";
        }
    }

    private void ClearLogButton_Click(object sender, RoutedEventArgs e)
    {
        LogBox.Clear();
    }

    private void LockOnDisconnectCheck_Changed(object sender, RoutedEventArgs e)
    {
        _receiver.LockOnDisconnect = LockOnDisconnectCheck.IsChecked == true;
    }

    private async void WolButton_Click(object sender, RoutedEventArgs e)
    {
        var mac = WolMacBox.Text.Trim();
        var broadcast = string.IsNullOrWhiteSpace(WolBroadcastBox.Text) ? "255.255.255.255" : WolBroadcastBox.Text.Trim();
        if (string.IsNullOrEmpty(mac))
        {
            AppendLog($"[{DateTime.Now:HH:mm:ss}] Wake: MAC address required.");
            return;
        }
        try
        {
            await BarelyReal.Core.Network.WakeOnLan.SendAsync(mac, broadcast).ConfigureAwait(true);
            AppendLog($"[{DateTime.Now:HH:mm:ss}] Wake-on-LAN packet sent to {mac} via {broadcast}.");
        }
        catch (Exception ex)
        {
            AppendLog($"[{DateTime.Now:HH:mm:ss}] Wake failed: {ex.Message}");
        }
    }

    private void CommandInput_Changed(object sender, RoutedEventArgs e)
    {
        if (!_uiReady)
            return;

        if (CommandStatusText is not null)
            CommandStatusText.Text = string.Empty;
        UpdateMacCommand();
    }

    private void StartReceiver()
    {
        if (!TryReadPorts(out var kmPort, out var clipboardPort))
        {
            UpdateStatus();
            return;
        }

        try
        {
            _receiver.Start(kmPort, ClipboardPeerBox.Text, clipboardPort);
            StartControl(ClipboardPeerBox.Text);
        }
        catch (Exception ex)
        {
            AppendLog($"[{DateTime.Now:HH:mm:ss}] Start failed: {ex.Message}");
        }

        UpdateStatus();
    }

    private bool TryReadPorts(out ushort kmPort, out ushort clipboardPort)
    {
        kmPort = 0;
        clipboardPort = 0;

        if (!ushort.TryParse(KmPortBox.Text.Trim(), out kmPort))
        {
            AppendLog($"[{DateTime.Now:HH:mm:ss}] Invalid KM port.");
            return false;
        }

        if (!ushort.TryParse(ClipboardPortBox.Text.Trim(), out clipboardPort))
        {
            AppendLog($"[{DateTime.Now:HH:mm:ss}] Invalid clipboard port.");
            return false;
        }

        return true;
    }

    private void StartControl(string peerHost)
    {
        if (!ushort.TryParse(ControlPortBox.Text.Trim(), out var controlPort))
        {
            AppendLog($"[{DateTime.Now:HH:mm:ss}] Invalid control port.");
            return;
        }

        RefreshDisplays();
        ReconcileLayout();
        _control.Start(controlPort, peerHost, controlPort);
        SendControlSnapshot();
    }

    private void SendControlSnapshot()
    {
        var announced = _localDisplays.Select(AnnouncedScreen.FromDisplay).ToArray();
        _control.SendHello(new HelloMessage(Environment.MachineName, "Windows", "0.1.0", announced));
        _control.SendScreenAnnounce(new ScreenAnnouncement(LocalPeerId, announced));
        _control.SendLayoutSync(new LayoutSyncMessage(_virtualLayout.Screens));
    }

    private void RefreshDisplays()
    {
        _localDisplays = DisplayEnumerator.LocalDisplays(LocalPeerId).ToList();
    }

    private void ApplyRemoteAnnouncement(ScreenAnnouncement announcement)
    {
        if (announcement.PeerId == LocalPeerId) return;
        _remoteDisplays = announcement.Screens.Select(screen => screen.ToDisplayInfo(RemotePeerId)).ToList();
        _remoteScreensStale = false;
        ReconcileLayout();
        RefreshLayoutDesigner();
        AppendLog($"[{DateTime.Now:HH:mm:ss}] Peer screens updated: {_remoteDisplays.Count}");
    }

    private void ApplyRemoteLayout(LayoutSyncMessage message)
    {
        RefreshDisplays();
        var incoming = new BarelyReal.Core.Layout.Layout(message.Layout);
        var localNative = _localDisplays.Select(display => display.ScreenRect).ToList();
        var incomingLocal = incoming.Bounds(LocalPeerId);
        var nativeLocal = new BarelyReal.Core.Layout.Layout(localNative).Bounds(LocalPeerId);
        if (incomingLocal is null || nativeLocal is null)
        {
            _virtualLayout = new BarelyReal.Core.Layout.Layout(localNative.Concat(incoming.ScreensFor(RemotePeerId)));
            RefreshLayoutDesigner();
            return;
        }

        var dx = nativeLocal.MinX - incomingLocal.MinX;
        var dy = nativeLocal.MinY - incomingLocal.MinY;
        var remote = incoming.ScreensFor(RemotePeerId)
            .Select(screen => screen with { X = screen.X + dx, Y = screen.Y + dy });
        _virtualLayout = new BarelyReal.Core.Layout.Layout(localNative.Concat(remote));
        RefreshLayoutDesigner();
        AppendLog($"[{DateTime.Now:HH:mm:ss}] Layout synced from peer.");
    }

    private void ReconcileLayout()
    {
        RefreshDisplays();
        var localScreens = _localDisplays.Select(display => display.ScreenRect).ToList();
        var remoteScreens = _remoteDisplays.Select(display => display.ScreenRect).ToList();
        if (localScreens.Count == 0)
        {
            _virtualLayout = new BarelyReal.Core.Layout.Layout(remoteScreens);
            return;
        }
        if (remoteScreens.Count == 0)
        {
            _virtualLayout = new BarelyReal.Core.Layout.Layout(localScreens.Concat(_virtualLayout.ScreensFor(RemotePeerId)));
            return;
        }

        var existingRemote = _virtualLayout.ScreensFor(RemotePeerId);
        var remoteIds = remoteScreens.Select(screen => screen.ScreenId).OrderBy(id => id).ToArray();
        var existingIds = existingRemote.Select(screen => screen.ScreenId).OrderBy(id => id).ToArray();
        if (existingRemote.Count > 0 && remoteIds.SequenceEqual(existingIds))
        {
            var byId = existingRemote.ToDictionary(screen => screen.ScreenId);
            var updatedRemote = remoteScreens.Select(native => byId.TryGetValue(native.ScreenId, out var existing)
                ? native with { X = existing.X, Y = existing.Y }
                : native);
            _virtualLayout = new BarelyReal.Core.Layout.Layout(localScreens.Concat(updatedRemote));
            return;
        }

        var localBounds = new BarelyReal.Core.Layout.Layout(localScreens).Bounds(LocalPeerId);
        var remoteBounds = new BarelyReal.Core.Layout.Layout(remoteScreens).Bounds(RemotePeerId);
        if (localBounds is null || remoteBounds is null)
        {
            _virtualLayout = new BarelyReal.Core.Layout.Layout(localScreens.Concat(remoteScreens));
            return;
        }

        var dx = localBounds.MinX - remoteBounds.MaxX;
        var dy = localBounds.MinY - remoteBounds.MinY;
        var translated = remoteScreens.Select(screen => screen with { X = screen.X + dx, Y = screen.Y + dy });
        _virtualLayout = new BarelyReal.Core.Layout.Layout(localScreens.Concat(translated));
    }

    private void MoveRemoteGroup(int dx, int dy, bool snap)
    {
        _virtualLayout = _virtualLayout.Translated(RemotePeerId, dx, dy);
        if (snap) _virtualLayout = SnappedRemoteLayout(_virtualLayout);
        RefreshLayoutDesigner();
        _control.SendLayoutSync(new LayoutSyncMessage(_virtualLayout.Screens));
        AppendLog($"[{DateTime.Now:HH:mm:ss}] Layout updated: {RemotePeerId} moved.");
    }

    private BarelyReal.Core.Layout.Layout SnappedRemoteLayout(BarelyReal.Core.Layout.Layout layout)
    {
        var local = layout.Bounds(LocalPeerId);
        var remote = layout.Bounds(RemotePeerId);
        if (local is null || remote is null) return layout;

        var candidates = new (int Dx, int Dy, int Distance)[]
        {
            (local.MinX - remote.MaxX, 0, Math.Abs(local.MinX - remote.MaxX)),
            (local.MaxX - remote.MinX, 0, Math.Abs(local.MaxX - remote.MinX)),
            (0, local.MinY - remote.MaxY, Math.Abs(local.MinY - remote.MaxY)),
            (0, local.MaxY - remote.MinY, Math.Abs(local.MaxY - remote.MinY)),
        };
        var best = candidates.OrderBy(candidate => candidate.Distance).First();
        return layout.Translated(RemotePeerId, best.Dx, best.Dy);
    }

    // MARK: - Status

    private void UpdateStatus()
    {
        if (!Dispatcher.CheckAccess())
        {
            Dispatcher.BeginInvoke(UpdateStatus);
            return;
        }

        var running = IsSendMode ? _sender.IsRunning : _receiver.IsRunning;
        var linkUp  = !IsSendMode && _receiver.LinkUp;

        // Top-bar pill + sidebar footer
        var greyDot = new SolidColorBrush(Color.FromRgb(0xBF, 0xBF, 0xBF));
        StatusDot.Fill = running
            ? (Brush)FindResource("SuccessBrush")
            : greyDot;
        StatusText.Text = running ? "Running" : "Stopped";
        if (SidebarStatusDot is not null)
            SidebarStatusDot.Fill = StatusDot.Fill;
        if (SidebarStatusText is not null)
            SidebarStatusText.Text = StatusText.Text;

        // Hero
        UpdateHero(running, linkUp);

        // Stats
        if (IsSendMode)
        {
            FramesText.Text = _sender.FramesSent.ToString();
            ClipboardText.Text = "—";
            LinkText.Text = _sender.IsRunning ? "sending" : "—";
        }
        else
        {
            FramesText.Text = _receiver.FramesReceived.ToString();
            ClipboardText.Text = _receiver.ClipboardEvents.ToString();
            LinkText.Text = !_receiver.IsRunning
                ? "—"
                : _receiver.LinkUp ? "up" : "down";
        }

        // Enabled state
        StartButton.IsEnabled = !running;
        StopButton.IsEnabled = running;
        ControlPortBox.IsEnabled = !running;
        KmPortBox.IsEnabled = !running;
        ClipboardPortBox.IsEnabled = !running;
        ClipboardPeerBox.IsEnabled = !running;
        SendMacHostBox.IsEnabled = !running;
        SendMacKmPortBox.IsEnabled = !running;

        FooterText.Text = running
            ? IsSendMode
                ? $"Sending to {_sender.PeerHost}:{_sender.PeerPort}. Move cursor past the screen edge to enter Mac."
                : $"Listening on UDP {_receiver.KmPort} and TCP {_receiver.ClipboardPort}. Firewall may still need inbound allow rules."
            : IsSendMode
                ? "Sender is stopped."
                : "Receiver is stopped.";
    }

    private void UpdateHero(bool running, bool linkUp)
    {
        if (HeroTitle is null || HeroSubtitle is null || HeroIcon is null)
            return;

        if (IsSendMode)
        {
            if (running)
            {
                HeroTitle.Text = "Sharing keyboard & mouse";
                HeroSubtitle.Text = $"Streaming to {_sender.PeerHost}. Move cursor past the screen edge to enter Mac.";
                HeroIcon.Text = "✈";
                ApplyHeroTint("AccentBrush", "AccentSoftBrush");
            }
            else
            {
                HeroTitle.Text = "Ready to share with Mac";
                HeroSubtitle.Text = "Move your cursor past the screen edge to control the other machine.";
                HeroIcon.Text = "↑";
                ApplyHeroTint(null, null);
            }
        }
        else
        {
            if (!running)
            {
                HeroTitle.Text = "Ready to receive from Mac";
                HeroSubtitle.Text = "Listening for incoming keyboard and mouse.";
                HeroIcon.Text = "↓";
                ApplyHeroTint(null, null);
            }
            else if (linkUp)
            {
                HeroTitle.Text = "Connected";
                HeroSubtitle.Text = "Receiving keyboard and mouse from Mac.";
                HeroIcon.Text = "✓";
                ApplyHeroTint("SuccessBrush", "SuccessSoftBrush");
            }
            else
            {
                HeroTitle.Text = "Waiting for Mac…";
                HeroSubtitle.Text = "Make sure the Mac app is sending KM frames to this PC.";
                HeroIcon.Text = "◐";
                ApplyHeroTint("WarningBrush", "WarningSoftBrush");
            }
        }
    }

    private void ApplyHeroTint(string? foregroundResource, string? backgroundResource)
    {
        if (HeroIcon is null) return;
        if (foregroundResource is null)
        {
            HeroIcon.Foreground = (Brush)FindResource("MutedBrush");
            if (HeroIcon.Parent is Border border)
                border.Background = new SolidColorBrush(Color.FromArgb(0x10, 0x00, 0x00, 0x00));
            return;
        }
        HeroIcon.Foreground = (Brush)FindResource(foregroundResource);
        if (HeroIcon.Parent is Border heroIconBorder && backgroundResource is not null)
            heroIconBorder.Background = (Brush)FindResource(backgroundResource);
    }

    private void UpdateMacCommand()
    {
        if (!_uiReady || CommandBox is null)
            return;

        var ip = IpComboBox?.SelectedItem?.ToString() ?? "127.0.0.1";
        var side = (SideComboBox?.SelectedItem as ComboBoxItem)?.Content?.ToString() ?? "left";
        var kmPort = string.IsNullOrWhiteSpace(KmPortBox.Text) ? "24801" : KmPortBox.Text.Trim();
        var width = string.IsNullOrWhiteSpace(WidthBox?.Text) ? "1920" : WidthBox.Text.Trim();
        var height = string.IsNullOrWhiteSpace(HeightBox?.Text) ? "1080" : HeightBox.Text.Trim();

        CommandBox.Text = $"cd mac && swift run BarelyRealKmSmoke send {ip} {kmPort} 0 --peer-{side} --peer-size {width}x{height}";
    }

    private void RefreshAddresses()
    {
        if (IpComboBox is null) return;
        var previous = IpComboBox.SelectedItem?.ToString();
        var addresses = GetPrivateIpv4Addresses()
            .OrderByDescending(IsHomeLanAddress)
            .ThenByDescending(IsPrivateAddress)
            .ThenBy(static address => address)
            .ToList();

        IpComboBox.Items.Clear();
        foreach (var address in addresses)
            IpComboBox.Items.Add(address);

        if (previous is not null && addresses.Contains(previous))
            IpComboBox.SelectedItem = previous;
        else if (addresses.Count > 0)
            IpComboBox.SelectedIndex = 0;
        else
            IpComboBox.Items.Add("127.0.0.1");

        if (IpComboBox.SelectedIndex < 0)
            IpComboBox.SelectedIndex = 0;
    }

    private static IEnumerable<string> GetPrivateIpv4Addresses()
    {
        return NetworkInterface.GetAllNetworkInterfaces()
            .Where(static adapter => adapter.OperationalStatus == OperationalStatus.Up)
            .SelectMany(static adapter => adapter.GetIPProperties().UnicastAddresses)
            .Select(static address => address.Address)
            .Where(static address => address.AddressFamily == AddressFamily.InterNetwork)
            .Where(static address => !IPAddress.IsLoopback(address))
            .Where(static address => !address.ToString().StartsWith("169.254.", StringComparison.Ordinal))
            .Select(static address => address.ToString())
            .Distinct(StringComparer.Ordinal);
    }

    private static bool IsHomeLanAddress(string address) =>
        address.StartsWith("192.168.", StringComparison.Ordinal);

    private static bool IsPrivateAddress(string address)
    {
        if (address.StartsWith("10.", StringComparison.Ordinal))
            return true;

        var parts = address.Split('.');
        return parts.Length == 4
            && parts[0] == "172"
            && int.TryParse(parts[1], out var second)
            && second is >= 16 and <= 31;
    }

    private void AppendLog(string line)
    {
        if (!Dispatcher.CheckAccess())
        {
            Dispatcher.BeginInvoke(() => AppendLog(line));
            return;
        }

        LogBox.AppendText(line + Environment.NewLine);
        if (LogBox.Text.Length > 50_000)
            LogBox.Text = LogBox.Text[^40_000..];

        LogBox.ScrollToEnd();
    }

    private static int GetSystemMetric(int index)
    {
        var value = GetSystemMetrics(index);
        return value > 0 ? value : index == 0 ? 1920 : 1080;
    }

    [DllImport("user32.dll")]
    private static extern int GetSystemMetrics(int nIndex);
}
