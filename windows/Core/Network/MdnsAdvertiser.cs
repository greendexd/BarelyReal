using System.Net;
using Makaretu.Dns;

namespace BarelyReal.Core.Network;

public sealed record DiscoveredPeer(
    string Name,
    string Host,
    IReadOnlyList<IPAddress> Addresses,
    ushort Port,
    string Os,
    string PeerId,
    string PublicKeyFingerprint,
    bool Stale);

public sealed record MdnsAdvertisement(
    string Name,
    ushort Port,
    string Os,
    string Version,
    string PeerId,
    string PublicKeyFingerprint);

/// Advertises this device on `_barelyreal._tcp.local.` with TXT records per BRP discovery.
public sealed class MdnsAdvertiser : IDisposable
{
    public const string ServiceName = "_barelyreal._tcp";
    public const ushort DefaultControlPort = 24800;

    private ServiceDiscovery? _discovery;
    private ServiceProfile? _profile;

    public void Start(string deviceName, string publicKeyFingerprint)
    {
        Start(new MdnsAdvertisement(
            deviceName,
            DefaultControlPort,
            "windows",
            "0.1.0",
            "windows",
            string.IsNullOrWhiteSpace(publicKeyFingerprint) ? "dev" : publicKeyFingerprint));
    }

    public void Start(MdnsAdvertisement advertisement)
    {
        Stop();

        _discovery = new ServiceDiscovery();
        _discovery.Mdns.UseIpv6 = false;
        _discovery.Mdns.Start();

        var instanceName = SanitizeInstanceName(advertisement.Name);
        _profile = new ServiceProfile(instanceName, ServiceName, advertisement.Port, addresses: null);
        _profile.AddProperty("name", advertisement.Name);
        _profile.AddProperty("os", advertisement.Os);
        _profile.AddProperty("ver", advertisement.Version);
        _profile.AddProperty("peer_id", advertisement.PeerId);
        _profile.AddProperty("pk", advertisement.PublicKeyFingerprint);

        _discovery.Advertise(_profile);
        _discovery.Announce(_profile);
    }

    public void Stop()
    {
        if (_discovery is not null)
        {
            try
            {
                if (_profile is not null)
                    _discovery.Unadvertise(_profile);
            }
            catch
            {
                // mDNS shutdown is best-effort; do not block app shutdown on multicast cleanup.
            }

            _discovery.Dispose();
        }

        _profile = null;
        _discovery = null;
    }

    public void Dispose() => Stop();

    private static string SanitizeInstanceName(string name)
    {
        var trimmed = string.IsNullOrWhiteSpace(name) ? Environment.MachineName : name.Trim();
        return trimmed.Replace('.', '-');
    }
}

public sealed class MdnsBrowser : IDisposable
{
    private static readonly TimeSpan StaleAfter = TimeSpan.FromSeconds(45);
    private readonly object _lock = new();
    private readonly Dictionary<string, PeerState> _peers = new(StringComparer.OrdinalIgnoreCase);
    private ServiceDiscovery? _discovery;
    private System.Threading.Timer? _refreshTimer;

    public sealed record Peer(string Name, string Os, string Version, string PublicKeyFingerprint, string Endpoint);

    public event Action<IReadOnlyList<DiscoveredPeer>>? OnChange;

    public void Start()
    {
        Stop();

        _discovery = new ServiceDiscovery();
        _discovery.Mdns.UseIpv6 = false;
        _discovery.ServiceInstanceDiscovered += (_, e) =>
        {
            QueryInstance(e.ServiceInstanceName);
        };
        _discovery.ServiceInstanceShutdown += (_, e) =>
        {
            MarkStale(e.ServiceInstanceName);
        };
        _discovery.Mdns.AnswerReceived += (_, e) =>
        {
            HandleAnswer(e.Message);
        };
        _discovery.Mdns.Start();
        _discovery.QueryServiceInstances(MdnsAdvertiser.ServiceName);

        _refreshTimer = new System.Threading.Timer(_ =>
        {
            try
            {
                _discovery?.QueryServiceInstances(MdnsAdvertiser.ServiceName);
                PublishSnapshot();
            }
            catch
            {
                // Browsing continues on the next timer tick.
            }
        }, null, TimeSpan.FromSeconds(10), TimeSpan.FromSeconds(10));
    }

    public void Stop()
    {
        _refreshTimer?.Dispose();
        _refreshTimer = null;

        if (_discovery is not null)
        {
            _discovery.Dispose();
            _discovery = null;
        }

        lock (_lock)
        {
            _peers.Clear();
        }

        PublishChange(Array.Empty<DiscoveredPeer>());
    }

    public void Dispose() => Stop();

    private void QueryInstance(DomainName instanceName)
    {
        try
        {
            _discovery?.Mdns.SendQuery(instanceName, DnsClass.IN, DnsType.ANY);
        }
        catch
        {
            // Discovery is opportunistic; a later browse tick can retry.
        }
    }

    private void HandleAnswer(Makaretu.Dns.Message message)
    {
        var records = message.Answers
            .Concat(message.AdditionalRecords)
            .ToArray();
        if (records.Length == 0)
            return;

        var changed = false;
        lock (_lock)
        {
            foreach (var srv in records.OfType<SRVRecord>())
            {
                if (!IsBarelyRealInstance(srv.Name))
                    continue;

                var key = Canonical(srv.Name);
                var peer = StateFor(key, srv.Name);
                peer.Host = srv.Target.ToString().TrimEnd('.');
                peer.Port = srv.Port;
                peer.LastSeenUtc = DateTime.UtcNow;
                peer.ExplicitlyStale = srv.TTL == TimeSpan.Zero;
                changed = true;
            }

            foreach (var txt in records.OfType<TXTRecord>())
            {
                if (!IsBarelyRealInstance(txt.Name))
                    continue;

                var peer = StateFor(Canonical(txt.Name), txt.Name);
                var properties = ParseTxt(txt);
                if (properties.TryGetValue("name", out var name)) peer.Name = name;
                if (properties.TryGetValue("os", out var os)) peer.Os = os;
                if (properties.TryGetValue("peer_id", out var peerId)) peer.PeerId = peerId;
                if (properties.TryGetValue("pk", out var pk)) peer.PublicKeyFingerprint = pk;
                peer.LastSeenUtc = DateTime.UtcNow;
                peer.ExplicitlyStale = txt.TTL == TimeSpan.Zero;
                changed = true;
            }

            foreach (var address in records.OfType<AddressRecord>())
            {
                var host = Canonical(address.Name);
                foreach (var peer in _peers.Values.Where(peer => Canonical(peer.Host) == host))
                {
                    if (!peer.Addresses.Contains(address.Address))
                        peer.Addresses.Add(address.Address);
                    peer.LastSeenUtc = DateTime.UtcNow;
                    peer.ExplicitlyStale = address.TTL == TimeSpan.Zero;
                    changed = true;
                }
            }
        }

        if (changed)
            PublishSnapshot();
    }

    private void MarkStale(DomainName instanceName)
    {
        lock (_lock)
        {
            var key = Canonical(instanceName);
            if (_peers.TryGetValue(key, out var peer))
                peer.ExplicitlyStale = true;
        }

        PublishSnapshot();
    }

    private PeerState StateFor(string key, DomainName instanceName)
    {
        if (_peers.TryGetValue(key, out var peer))
            return peer;

        peer = new PeerState
        {
            Name = InstanceLabel(instanceName),
            Host = string.Empty,
            Port = MdnsAdvertiser.DefaultControlPort,
            LastSeenUtc = DateTime.UtcNow
        };
        _peers[key] = peer;
        return peer;
    }

    private void PublishSnapshot()
    {
        IReadOnlyList<DiscoveredPeer> peers;
        lock (_lock)
        {
            peers = _peers.Values
                .Select(static peer =>
                {
                    var stale = peer.ExplicitlyStale || DateTime.UtcNow - peer.LastSeenUtc > StaleAfter;
                    return new DiscoveredPeer(
                        peer.Name,
                        peer.Host,
                        peer.Addresses.ToArray(),
                        peer.Port,
                        peer.Os,
                        peer.PeerId,
                        peer.PublicKeyFingerprint,
                        stale);
                })
                .OrderBy(static peer => peer.Stale)
                .ThenBy(static peer => peer.Name, StringComparer.OrdinalIgnoreCase)
                .ToArray();
        }

        PublishChange(peers);
    }

    private void PublishChange(IReadOnlyList<DiscoveredPeer> peers)
    {
        OnChange?.Invoke(peers);
    }

    private static bool IsBarelyRealInstance(DomainName name) =>
        Canonical(name).EndsWith("." + MdnsAdvertiser.ServiceName + ".local", StringComparison.OrdinalIgnoreCase);

    private static string Canonical(DomainName name) =>
        name.ToString().TrimEnd('.').ToLowerInvariant();

    private static Dictionary<string, string> ParseTxt(TXTRecord record)
    {
        var properties = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var value in record.Strings)
        {
            var separator = value.IndexOf('=');
            if (separator <= 0)
                continue;

            properties[value[..separator]] = value[(separator + 1)..];
        }

        return properties;
    }

    private static string InstanceLabel(DomainName instanceName)
    {
        var name = instanceName.ToString().TrimEnd('.');
        var suffix = "." + MdnsAdvertiser.ServiceName + ".local";
        return name.EndsWith(suffix, StringComparison.OrdinalIgnoreCase)
            ? name[..^suffix.Length]
            : name;
    }

    private sealed class PeerState
    {
        public string Name { get; set; } = string.Empty;
        public string Host { get; set; } = string.Empty;
        public List<IPAddress> Addresses { get; } = new();
        public ushort Port { get; set; }
        public string Os { get; set; } = string.Empty;
        public string PeerId { get; set; } = string.Empty;
        public string PublicKeyFingerprint { get; set; } = string.Empty;
        public DateTime LastSeenUtc { get; set; }
        public bool ExplicitlyStale { get; set; }
    }
}
