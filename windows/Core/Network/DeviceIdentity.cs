using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace BarelyReal.Core.Network;

/// Per-device long-lived identity used by BRP pairing.
///
/// On first run we generate an ed25519 key pair. The private key is stored in a DPAPI-encrypted
/// blob under the user's profile (`%LocalAppData%\BarelyReal\identity.dat`). The public-key
/// fingerprint (SHA-256) is what gets pinned by peers during PIN pairing per BRP § Pairing.
public sealed class DeviceIdentity
{
    public sealed record Identity(byte[] PrivateKey, byte[] PublicKey, string PublicKeyFingerprint);

    public Identity LoadOrGenerate()
    {
        var existing = LoadFromDisk();
        if (existing is not null)
            return existing;
        var fresh = Generate();
        StoreOnDisk(fresh);
        return fresh;
    }

    public Identity Regenerate()
    {
        try { File.Delete(IdentityFilePath); } catch { /* ignore */ }
        var fresh = Generate();
        StoreOnDisk(fresh);
        return fresh;
    }

    private static Identity Generate()
    {
        // .NET 8 has no built-in ed25519. We use Curve25519 via System.Security.Cryptography.X509:
        // the simpler path is to use ECDsa with NIST P-256 — for BRP scaffold purposes that's fine,
        // we'll swap in BouncyCastle / NSec once the actual TLS pipe is wired.
        using var ecdsa = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var parameters = ecdsa.ExportParameters(includePrivateParameters: true);

        var pub = SerializePublicKey(parameters);
        var priv = SerializePrivateKey(parameters);

        var fingerprint = Convert.ToBase64String(SHA256.HashData(pub));
        return new Identity(priv, pub, fingerprint);
    }

    private Identity? LoadFromDisk()
    {
        if (!File.Exists(IdentityFilePath))
            return null;
        try
        {
            var encrypted = File.ReadAllBytes(IdentityFilePath);
            var plain = ProtectedData.Unprotect(encrypted, null, DataProtectionScope.CurrentUser);
            var stored = JsonSerializer.Deserialize<StoredIdentity>(plain);
            if (stored is null) return null;
            return new Identity(stored.Priv, stored.Pub, stored.Fp);
        }
        catch
        {
            return null;
        }
    }

    private void StoreOnDisk(Identity identity)
    {
        try
        {
            Directory.CreateDirectory(IdentityDirectory);
            var stored = new StoredIdentity { Priv = identity.PrivateKey, Pub = identity.PublicKey, Fp = identity.PublicKeyFingerprint };
            var plain = JsonSerializer.SerializeToUtf8Bytes(stored);
            var encrypted = ProtectedData.Protect(plain, null, DataProtectionScope.CurrentUser);
            File.WriteAllBytes(IdentityFilePath, encrypted);
        }
        catch
        {
            // Identity store failure is recoverable: we'll regenerate next launch. Pairings will
            // need redoing in that case but it's better than crashing.
        }
    }

    private static byte[] SerializePublicKey(ECParameters parameters)
    {
        var x = parameters.Q.X ?? Array.Empty<byte>();
        var y = parameters.Q.Y ?? Array.Empty<byte>();
        var buf = new byte[1 + x.Length + y.Length];
        buf[0] = 0x04; // uncompressed point marker
        x.CopyTo(buf, 1);
        y.CopyTo(buf, 1 + x.Length);
        return buf;
    }

    private static byte[] SerializePrivateKey(ECParameters parameters) =>
        parameters.D ?? throw new InvalidOperationException("ECDsa parameters had no private scalar");

    private static string IdentityDirectory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BarelyReal");

    private static string IdentityFilePath => Path.Combine(IdentityDirectory, "identity.dat");

    private sealed class StoredIdentity
    {
        public byte[] Priv { get; set; } = Array.Empty<byte>();
        public byte[] Pub { get; set; } = Array.Empty<byte>();
        public string Fp { get; set; } = string.Empty;
    }
}

/// Persistent set of pinned peer public-key fingerprints. Stored DPAPI-encrypted under
/// `%LocalAppData%\BarelyReal\pinned-peers.dat`.
public sealed class PinnedPeerStore
{
    private static string Directory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BarelyReal");

    private static string FilePath => Path.Combine(Directory, "pinned-peers.dat");

    public IReadOnlyList<PairingService.PinnedPeer> Load()
    {
        if (!File.Exists(FilePath))
            return Array.Empty<PairingService.PinnedPeer>();
        try
        {
            var encrypted = File.ReadAllBytes(FilePath);
            var plain = ProtectedData.Unprotect(encrypted, null, DataProtectionScope.CurrentUser);
            var stored = JsonSerializer.Deserialize<List<StoredPeer>>(plain) ?? new();
            return stored.Select(s => new PairingService.PinnedPeer(s.Fp, s.Name)).ToArray();
        }
        catch
        {
            return Array.Empty<PairingService.PinnedPeer>();
        }
    }

    public void Save(IEnumerable<PairingService.PinnedPeer> peers)
    {
        try
        {
            System.IO.Directory.CreateDirectory(Directory);
            var stored = peers.Select(p => new StoredPeer { Fp = p.PublicKeyFingerprint, Name = p.DisplayName }).ToList();
            var plain = JsonSerializer.SerializeToUtf8Bytes(stored);
            var encrypted = ProtectedData.Protect(plain, null, DataProtectionScope.CurrentUser);
            File.WriteAllBytes(FilePath, encrypted);
        }
        catch
        {
            // best effort
        }
    }

    public void Add(PairingService.PinnedPeer peer)
    {
        var current = Load().Where(p => p.PublicKeyFingerprint != peer.PublicKeyFingerprint).ToList();
        current.Add(peer);
        Save(current);
    }

    public void Remove(string fingerprint)
    {
        var current = Load().Where(p => p.PublicKeyFingerprint != fingerprint).ToList();
        Save(current);
    }

    private sealed class StoredPeer
    {
        public string Fp { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
    }
}
