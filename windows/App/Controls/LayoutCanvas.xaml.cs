using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;

namespace BarelyReal.App.Controls;

/// Visual layout designer mirroring mac/App/Views/Components/LayoutCanvas.swift.
///
/// Renders this Windows PC as a fixed center rectangle and the Mac peer as a draggable
/// rectangle. Snaps to .Left or .Right when dropped. The host wires `SideChanged` to its
/// state.
public partial class LayoutCanvas : UserControl
{
    public enum Side { Left, Right }

    public event Action<Side>? SideChanged;

    public Side PeerSide
    {
        get => _peerSide;
        set
        {
            if (_peerSide == value) return;
            _peerSide = value;
            Layout();
        }
    }

    public int MacWidth { get => _macWidth; set { _macWidth = Math.Max(value, 320); Layout(); } }
    public int MacHeight { get => _macHeight; set { _macHeight = Math.Max(value, 200); Layout(); } }

    private Side _peerSide = Side.Left;
    private int _macWidth = 2560;
    private int _macHeight = 1600;

    private Border? _winChip;
    private Border? _macChip;
    private bool _dragging;
    private Point _dragOrigin;
    private double _macStartLeft;

    public LayoutCanvas()
    {
        InitializeComponent();
        Loaded += (_, _) => Layout();
    }

    public void Refresh(int winWidth, int winHeight, int macWidth, int macHeight, Side side)
    {
        _macWidth = Math.Max(macWidth, 320);
        _macHeight = Math.Max(macHeight, 200);
        _peerSide = side;
        // Win width/height come from system metrics; we re-layout regardless of size of stage.
        _windowsWidth = Math.Max(winWidth, 320);
        _windowsHeight = Math.Max(winHeight, 200);
        Layout();
    }

    private int _windowsWidth = 1920;
    private int _windowsHeight = 1080;

    private void Stage_SizeChanged(object sender, SizeChangedEventArgs e) => Layout();

    private void Layout()
    {
        if (StageCanvas is null) return;

        StageCanvas.Children.Clear();
        var canvasW = Math.Max(StageCanvas.ActualWidth, 100);
        var canvasH = Math.Max(StageCanvas.ActualHeight, 100);

        // Floor line
        var floor = new Rectangle
        {
            Height = 1,
            Width = canvasW - 28,
            Fill = new SolidColorBrush(Color.FromArgb(0x33, 0x00, 0x00, 0x00))
        };
        Canvas.SetLeft(floor, 14);
        Canvas.SetTop(floor, canvasH - 24);
        StageCanvas.Children.Add(floor);

        // Compute scale so both screens fit horizontally with a small gap.
        var totalPixels = (double)_windowsWidth + _macWidth;
        var widthScale = (canvasW - 60) / totalPixels;
        var heightScale = (canvasH - 50) / Math.Max(_windowsHeight, _macHeight);
        var scale = Math.Min(widthScale, Math.Min(heightScale, 0.30));

        var winW = _windowsWidth * scale;
        var winH = _windowsHeight * scale;
        var macW = _macWidth * scale;
        var macH = _macHeight * scale;

        var centreX = canvasW / 2;
        var bottom = canvasH - 24;

        var winLeft = centreX - winW / 2;
        var winTop = bottom - winH;

        _winChip = MakeChip("This PC", $"{_windowsWidth}×{_windowsHeight}", "#0067C0", "🖥");
        _winChip.Width = winW;
        _winChip.Height = winH;
        Canvas.SetLeft(_winChip, winLeft);
        Canvas.SetTop(_winChip, winTop);
        StageCanvas.Children.Add(_winChip);

        var macLeft = _peerSide == Side.Left
            ? winLeft - macW - 12
            : winLeft + winW + 12;
        var macTop = bottom - macH;

        _macChip = MakeChip("Mac", $"{_macWidth}×{_macHeight}", "#7B61FF", "💻");
        _macChip.Width = macW;
        _macChip.Height = macH;
        Canvas.SetLeft(_macChip, macLeft);
        Canvas.SetTop(_macChip, macTop);
        _macChip.Cursor = Cursors.SizeAll;
        _macChip.MouseLeftButtonDown += MacChip_MouseDown;
        _macChip.MouseLeftButtonUp += MacChip_MouseUp;
        _macChip.MouseMove += MacChip_MouseMove;
        StageCanvas.Children.Add(_macChip);
    }

    private Border MakeChip(string title, string pixels, string accentHex, string glyph)
    {
        var accent = (Color)ColorConverter.ConvertFromString(accentHex)!;
        var soft = Color.FromArgb(0x28, accent.R, accent.G, accent.B);
        var stroke = Color.FromArgb(0x88, accent.R, accent.G, accent.B);

        var bg = new LinearGradientBrush
        {
            StartPoint = new Point(0, 0),
            EndPoint = new Point(0, 1)
        };
        bg.GradientStops.Add(new GradientStop(soft, 0));
        bg.GradientStops.Add(new GradientStop(Color.FromArgb(0x10, accent.R, accent.G, accent.B), 1));

        var border = new Border
        {
            CornerRadius = new CornerRadius(10),
            BorderBrush = new SolidColorBrush(stroke),
            BorderThickness = new Thickness(1.2),
            Background = bg
        };

        var grid = new Grid();
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        var glyphText = new TextBlock
        {
            Text = glyph,
            FontSize = 22,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Opacity = 0.7
        };
        Grid.SetRow(glyphText, 0);
        grid.Children.Add(glyphText);

        var labelStack = new StackPanel
        {
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Bottom,
            Margin = new Thickness(8, 0, 8, 6)
        };
        labelStack.Children.Add(new TextBlock
        {
            Text = title,
            FontWeight = FontWeights.SemiBold,
            FontSize = 11,
            Foreground = new SolidColorBrush(Color.FromRgb(0x1A, 0x1A, 0x1A))
        });
        labelStack.Children.Add(new TextBlock
        {
            Text = pixels,
            FontSize = 10,
            Foreground = new SolidColorBrush(Color.FromRgb(0x65, 0x65, 0x65))
        });
        Grid.SetRow(labelStack, 1);
        grid.Children.Add(labelStack);

        border.Child = grid;
        return border;
    }

    private void MacChip_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (_macChip is null) return;
        _dragging = true;
        _dragOrigin = e.GetPosition(StageCanvas);
        _macStartLeft = Canvas.GetLeft(_macChip);
        _macChip.CaptureMouse();
    }

    private void MacChip_MouseMove(object sender, MouseEventArgs e)
    {
        if (!_dragging || _macChip is null) return;
        var p = e.GetPosition(StageCanvas);
        var delta = p.X - _dragOrigin.X;
        Canvas.SetLeft(_macChip, _macStartLeft + delta);
    }

    private void MacChip_MouseUp(object sender, MouseButtonEventArgs e)
    {
        if (_macChip is null || _winChip is null) return;
        _dragging = false;
        _macChip.ReleaseMouseCapture();

        // Decide side based on chip centre relative to PC chip centre.
        var macLeft = Canvas.GetLeft(_macChip);
        var macCentre = macLeft + _macChip.Width / 2;
        var winLeft = Canvas.GetLeft(_winChip);
        var winCentre = winLeft + _winChip.Width / 2;
        var newSide = macCentre < winCentre ? Side.Left : Side.Right;
        if (newSide != _peerSide)
        {
            _peerSide = newSide;
            SideChanged?.Invoke(newSide);
        }
        Layout();
    }
}
