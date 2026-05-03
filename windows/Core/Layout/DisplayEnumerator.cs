using System.Windows.Forms;

namespace BarelyReal.Core.Layout;

public sealed record DisplayInfo(
    string PeerId,
    int ScreenId,
    int X,
    int Y,
    int Width,
    int Height,
    double Scale,
    bool IsPrimary)
{
    public ScreenRect ScreenRect => new(PeerId, ScreenId, X, Y, Width, Height);
}

public static class DisplayEnumerator
{
    public static IReadOnlyList<DisplayInfo> LocalDisplays(string? peerId = null)
    {
        peerId ??= Environment.MachineName;
        return Screen.AllScreens
            .Select((screen, index) => new DisplayInfo(
                peerId,
                index,
                screen.Bounds.X,
                screen.Bounds.Y,
                screen.Bounds.Width,
                screen.Bounds.Height,
                Scale: 1.0,
                IsPrimary: screen.Primary))
            .ToArray();
    }

    public static Layout LocalLayout(string? peerId = null)
    {
        return new Layout(LocalDisplays(peerId).Select(display => display.ScreenRect));
    }
}
