namespace BarelyReal.Core.Network;

/// Advertises this device on `_barelyreal._tcp.` with TXT records per BRP § Discovery.
/// TODO(week 1): use Makaretu.Dns.Multicast (NuGet) to publish + browse.
public sealed class MdnsAdvertiser
{
    public void Start(string deviceName, string publicKeyFingerprint)
    {
        // TODO
    }

    public void Stop()
    {
        // TODO
    }

}

public sealed class MdnsBrowser
{
    public sealed record Peer(string Name, string Os, string Version, string PublicKeyFingerprint, string Endpoint);

    public event Action<IReadOnlyList<Peer>>? OnChange;

    public void Start()
    {
        // TODO
    }

    public void Stop()
    {
        // TODO
    }

    private void PublishChange(IReadOnlyList<Peer> peers)
    {
        OnChange?.Invoke(peers);
    }
}
