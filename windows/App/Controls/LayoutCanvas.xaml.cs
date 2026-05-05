using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using BarelyReal.Core.Layout;

namespace BarelyReal.App.Controls;

public partial class LayoutCanvas : UserControl
{
    public event Action<int, int, bool>? RemoteMoved;

    private Layout _layout = new();
    private string _localPeerId = "windows";
    private string _remotePeerId = "mac";
    private bool _remoteIsStale;
    private bool _dragging;
    private Point _dragOrigin;
    private double _dragX;
    private double _dragY;
    private double _scale = 1;

    public LayoutCanvas()
    {
        InitializeComponent();
        Loaded += (_, _) => Render();
    }

    public void Refresh(Layout layout, string localPeerId, string remotePeerId, bool remoteIsStale)
    {
        _layout = layout;
        _localPeerId = localPeerId;
        _remotePeerId = remotePeerId;
        _remoteIsStale = remoteIsStale;
        Render();
    }

    private void Stage_SizeChanged(object sender, SizeChangedEventArgs e) => Render();

    private void Render()
    {
        if (StageCanvas is null) return;
        StageCanvas.Children.Clear();
        var canvasW = Math.Max(StageCanvas.ActualWidth, 100);
        var canvasH = Math.Max(StageCanvas.ActualHeight, 100);

        DrawGrid(canvasW, canvasH);

        var bounds = EditorBounds();
        _scale = Math.Min((canvasW - 44) / Math.Max(bounds.Width, 1), (canvasH - 44) / Math.Max(bounds.Height, 1));

        foreach (var screen in _layout.ScreensFor(_localPeerId))
            DrawScreen(screen, bounds, "This PC", "#0067C0", "🖥", false);

        var dragDx = (int)Math.Round(_dragX / Math.Max(_scale, 0.001));
        var dragDy = (int)Math.Round(_dragY / Math.Max(_scale, 0.001));
        var remoteScreens = _layout.ScreensFor(_remotePeerId);
        var previewLayout = _layout.Translated(_remotePeerId, dragDx, dragDy).StickySnapped(_remotePeerId, _localPeerId);
        var previewRemoteScreens = remoteScreens.Count == 0
            ? Array.Empty<ScreenRect>()
            : previewLayout.ScreensFor(_remotePeerId);

        foreach (var screen in previewRemoteScreens)
            DrawScreen(screen, bounds, "Mac", _remoteIsStale ? "#C19C00" : "#7B61FF", "💻", true);

        if (remoteScreens.Count == 0)
            DrawEmptyState(canvasW, canvasH);
    }

    private void DrawScreen(ScreenRect screen, ScreenRectBounds bounds, string title, string accentHex, string glyph, bool draggable)
    {
        var chip = MakeChip($"{title} {screen.ScreenId}", $"{screen.Width}×{screen.Height}  {screen.X},{screen.Y}", accentHex, glyph);
        chip.Width = screen.Width * _scale;
        chip.Height = screen.Height * _scale;
        Canvas.SetLeft(chip, 22 + (screen.X - bounds.MinX) * _scale);
        Canvas.SetTop(chip, 22 + (screen.Y - bounds.MinY) * _scale);
        if (draggable)
        {
            chip.Cursor = Cursors.SizeAll;
            chip.MouseLeftButtonDown += Remote_MouseDown;
            chip.MouseMove += Remote_MouseMove;
            chip.MouseLeftButtonUp += Remote_MouseUp;
        }
        StageCanvas.Children.Add(chip);
    }

    private Border MakeChip(string title, string pixels, string accentHex, string glyph)
    {
        var accent = (Color)ColorConverter.ConvertFromString(accentHex)!;
        var soft = Color.FromArgb(0x30, accent.R, accent.G, accent.B);
        var stroke = Color.FromArgb(0x99, accent.R, accent.G, accent.B);
        var bg = new LinearGradientBrush(Color.FromArgb(0x36, accent.R, accent.G, accent.B), Color.FromArgb(0x12, accent.R, accent.G, accent.B), 90);
        var border = new Border
        {
            CornerRadius = new CornerRadius(10),
            BorderBrush = new SolidColorBrush(stroke),
            BorderThickness = new Thickness(1.2),
            Background = bg,
            MinWidth = 80,
            MinHeight = 56
        };

        var grid = new Grid();
        grid.Children.Add(new TextBlock
        {
            Text = glyph,
            FontSize = 22,
            Opacity = 0.72,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center
        });
        var stack = new StackPanel
        {
            Margin = new Thickness(8, 0, 8, 6),
            VerticalAlignment = VerticalAlignment.Bottom,
            HorizontalAlignment = HorizontalAlignment.Left
        };
        stack.Children.Add(new TextBlock { Text = title, FontWeight = FontWeights.SemiBold, FontSize = 11 });
        stack.Children.Add(new TextBlock { Text = pixels, FontSize = 10, Foreground = new SolidColorBrush(Color.FromRgb(0x65, 0x65, 0x65)) });
        grid.Children.Add(stack);
        border.Child = grid;
        return border;
    }

    private void Remote_MouseDown(object sender, MouseButtonEventArgs e)
    {
        _dragging = true;
        _dragOrigin = e.GetPosition(StageCanvas);
        if (sender is UIElement element) element.CaptureMouse();
    }

    private void Remote_MouseMove(object sender, MouseEventArgs e)
    {
        if (!_dragging) return;
        var p = e.GetPosition(StageCanvas);
        _dragX = p.X - _dragOrigin.X;
        _dragY = p.Y - _dragOrigin.Y;
        Render();
    }

    private void Remote_MouseUp(object sender, MouseButtonEventArgs e)
    {
        if (!_dragging) return;
        _dragging = false;
        if (sender is UIElement element) element.ReleaseMouseCapture();
        var dx = (int)Math.Round(_dragX / Math.Max(_scale, 0.001));
        var dy = (int)Math.Round(_dragY / Math.Max(_scale, 0.001));
        _dragX = 0;
        _dragY = 0;
        RemoteMoved?.Invoke(dx, dy, true);
        Render();
    }

    private ScreenRectBounds EditorBounds()
    {
        var local = new BarelyReal.Core.Layout.Layout(_layout.ScreensFor(_localPeerId)).Bounds()
            ?? new ScreenRectBounds(0, 0, 1440, 900);
        var remote = new BarelyReal.Core.Layout.Layout(_layout.ScreensFor(_remotePeerId)).Bounds();

        var remoteWidth = Math.Max(remote?.Width ?? 1440, 640);
        var remoteHeight = Math.Max(remote?.Height ?? 900, 480);
        var padX = Math.Max(Math.Max(local.Width, remoteWidth) / 3, 280);
        var padY = Math.Max(Math.Max(local.Height, remoteHeight) / 3, 220);

        return new ScreenRectBounds(
            local.MinX - remoteWidth - padX,
            local.MinY - remoteHeight - padY,
            local.MaxX + remoteWidth + padX,
            local.MaxY + remoteHeight + padY);
    }

    private void DrawGrid(double canvasW, double canvasH)
    {
        const double spacing = 32;
        for (double x = 0; x <= canvasW; x += spacing)
            StageCanvas.Children.Add(new Line { X1 = x, Y1 = 0, X2 = x, Y2 = canvasH, Stroke = new SolidColorBrush(Color.FromArgb(0x12, 0, 0, 0)), StrokeThickness = 1 });
        for (double y = 0; y <= canvasH; y += spacing)
            StageCanvas.Children.Add(new Line { X1 = 0, Y1 = y, X2 = canvasW, Y2 = y, Stroke = new SolidColorBrush(Color.FromArgb(0x12, 0, 0, 0)), StrokeThickness = 1 });
    }

    private void DrawEmptyState(double canvasW, double canvasH)
    {
        var text = new TextBlock
        {
            Text = "Waiting for Mac screens",
            Foreground = new SolidColorBrush(Color.FromRgb(0x65, 0x65, 0x65)),
            FontWeight = FontWeights.SemiBold
        };
        Canvas.SetLeft(text, Math.Max(0, canvasW / 2 - 76));
        Canvas.SetTop(text, Math.Max(0, canvasH / 2 - 12));
        StageCanvas.Children.Add(text);
    }
}
