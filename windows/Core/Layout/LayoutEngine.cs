using System.Text.Json.Serialization;

namespace BarelyReal.Core.Layout;

/// Virtual coordinate space across all peers' screens. Decides ownership transfer at edges.
public sealed record ScreenRect(
    [property: JsonPropertyName("peer_id")] string PeerId,
    [property: JsonPropertyName("screen_id")] int ScreenId,
    [property: JsonPropertyName("x")] int X,
    [property: JsonPropertyName("y")] int Y,
    [property: JsonPropertyName("w")] int Width,
    [property: JsonPropertyName("h")] int Height)
{
    public int MaxX => X + Width;
    public int MaxY => Y + Height;

    public bool Contains(int virtualX, int virtualY)
        => virtualX >= X && virtualX < MaxX && virtualY >= Y && virtualY < MaxY;
}

public sealed record ScreenRectBounds(int MinX, int MinY, int MaxX, int MaxY)
{
    public int Width => MaxX - MinX;
    public int Height => MaxY - MinY;
    public int MidX => (MinX + MaxX) / 2;
    public int MidY => (MinY + MaxY) / 2;

    public static ScreenRectBounds From(ScreenRect screen) => new(screen.X, screen.Y, screen.MaxX, screen.MaxY);
    public ScreenRectBounds Union(ScreenRect screen) => new(
        Math.Min(MinX, screen.X),
        Math.Min(MinY, screen.Y),
        Math.Max(MaxX, screen.MaxX),
        Math.Max(MaxY, screen.MaxY));
}

public sealed class Layout
{
    public List<ScreenRect> Screens { get; init; } = new();

    public Layout() { }
    public Layout(IEnumerable<ScreenRect> screens) { Screens = new(screens); }

    public IReadOnlyList<ScreenRect> ScreensFor(string peerId) =>
        Screens.Where(s => s.PeerId == peerId).ToArray();

    public ScreenRect? Screen(int x, int y)
    {
        foreach (var screen in Screens)
        {
            if (screen.Contains(x, y)) return screen;
        }
        return null;
    }

    public ScreenRectBounds? Bounds(string? peerId = null)
    {
        var screens = peerId is null ? Screens : Screens.Where(s => s.PeerId == peerId).ToList();
        if (screens.Count == 0) return null;
        var bounds = ScreenRectBounds.From(screens[0]);
        foreach (var screen in screens.Skip(1))
            bounds = bounds.Union(screen);
        return bounds;
    }

    public Layout Translated(string peerId, int dx, int dy)
    {
        return new Layout(Screens.Select(screen => screen.PeerId == peerId
            ? screen with { X = screen.X + dx, Y = screen.Y + dy }
            : screen));
    }
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
