using System.Text.Json.Serialization;
using BarelyReal.Core.Layout;

namespace BarelyReal.Core.Network;

public sealed record ScreenAnnouncement(
    [property: JsonPropertyName("peer_id")] string PeerId,
    [property: JsonPropertyName("screens")] IReadOnlyList<AnnouncedScreen> Screens);

public sealed record AnnouncedScreen(
    [property: JsonPropertyName("id")] int Id,
    [property: JsonPropertyName("x")] int X,
    [property: JsonPropertyName("y")] int Y,
    [property: JsonPropertyName("w")] int W,
    [property: JsonPropertyName("h")] int H,
    [property: JsonPropertyName("scale")] double Scale,
    [property: JsonPropertyName("primary")] bool Primary)
{
    public static AnnouncedScreen FromDisplay(DisplayInfo display) =>
        new(display.ScreenId, display.X, display.Y, display.Width, display.Height, display.Scale, display.IsPrimary);

    public DisplayInfo ToDisplayInfo(string peerId) =>
        new(peerId, Id, X, Y, W, H, Scale, Primary);
}

public sealed record LayoutSyncMessage(
    [property: JsonPropertyName("layout")] IReadOnlyList<ScreenRect> Layout);

public sealed record HelloMessage(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("os")] string Os,
    [property: JsonPropertyName("ver")] string Ver,
    [property: JsonPropertyName("screens")] IReadOnlyList<AnnouncedScreen> Screens);
