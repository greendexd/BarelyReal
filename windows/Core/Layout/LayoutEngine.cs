namespace BarelyReal.Core.Layout;

/// Virtual coordinate space across all peers' screens. Decides ownership transfer at edges.
public sealed record ScreenRect(string PeerId, int ScreenId, int X, int Y, int Width, int Height)
{
    public int MaxX => X + Width;
    public int MaxY => Y + Height;

    public bool Contains(int virtualX, int virtualY)
        => virtualX >= X && virtualX < MaxX && virtualY >= Y && virtualY < MaxY;
}

public sealed class Layout
{
    public List<ScreenRect> Screens { get; init; } = new();

    public Layout() { }
    public Layout(IEnumerable<ScreenRect> screens) { Screens = new(screens); }
}

public sealed class LayoutEngine
{
    public Layout Layout { get; private set; }

    public LayoutEngine() { Layout = new Layout(); }
    public LayoutEngine(Layout layout) { Layout = layout; }

    /// Given a global virtual point, return the screen that owns it (or null).
    public ScreenRect? Screen(int x, int y)
    {
        foreach (var s in Layout.Screens)
        {
            if (s.Contains(x, y)) return s;
        }
        return null;
    }

    public void Update(Layout layout) => Layout = layout;
}
