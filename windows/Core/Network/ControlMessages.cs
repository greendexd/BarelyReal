using System.Text.Json.Serialization;
using BarelyReal.Core.Layout;

namespace BarelyReal.Core.Network;

public sealed class ScreenAnnouncement : IEquatable<ScreenAnnouncement>
{
    [JsonPropertyName("peer_id")]
    public string PeerId { get; }

    [JsonPropertyName("screens")]
    public IReadOnlyList<AnnouncedScreen> Screens { get; }

    [JsonConstructor]
    public ScreenAnnouncement(string peerId, IReadOnlyList<AnnouncedScreen> screens)
    {
        PeerId = peerId;
        Screens = screens.ToArray();
    }

    public bool Equals(ScreenAnnouncement? other) =>
        other is not null
        && PeerId == other.PeerId
        && Screens.SequenceEqual(other.Screens);

    public override bool Equals(object? obj) => obj is ScreenAnnouncement other && Equals(other);

    public override int GetHashCode()
    {
        var hash = new HashCode();
        hash.Add(PeerId);
        foreach (var screen in Screens)
            hash.Add(screen);
        return hash.ToHashCode();
    }
}

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

public sealed class LayoutSyncMessage : IEquatable<LayoutSyncMessage>
{
    [JsonPropertyName("layout")]
    public IReadOnlyList<ScreenRect> Layout { get; }

    [JsonConstructor]
    public LayoutSyncMessage(IReadOnlyList<ScreenRect> layout)
    {
        Layout = layout.ToArray();
    }

    public bool Equals(LayoutSyncMessage? other) =>
        other is not null
        && Layout.SequenceEqual(other.Layout);

    public override bool Equals(object? obj) => obj is LayoutSyncMessage other && Equals(other);

    public override int GetHashCode()
    {
        var hash = new HashCode();
        foreach (var screen in Layout)
            hash.Add(screen);
        return hash.ToHashCode();
    }
}

public sealed record HelloMessage(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("os")] string Os,
    [property: JsonPropertyName("ver")] string Ver,
    [property: JsonPropertyName("screens")] IReadOnlyList<AnnouncedScreen> Screens);
