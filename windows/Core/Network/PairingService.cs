using System.Buffers.Binary;

namespace BarelyReal.Core.Network;

/// 6-digit PIN pairing per BRP § Pairing. Derives SAS from the TLS exporter, stores pinned SPKI
/// hashes in DPAPI. TODO(week 1).
public sealed class PairingService
{
    public sealed record PinnedPeer(string PublicKeyFingerprint, string DisplayName);

    private readonly PinnedPeerStore _pinnedPeerStore;
    private readonly int _maxWrongAttempts;
    private readonly int _lockoutSeconds;
    private int _wrongAttempts;
    private DateTimeOffset? _lockoutUntil;

    public PairingService()
        : this(new PinnedPeerStore())
    {
    }

    public PairingService(int maxWrongAttempts = 5, int lockoutSeconds = 60)
        : this(new PinnedPeerStore(), maxWrongAttempts, lockoutSeconds)
    {
    }

    public PairingService(PinnedPeerStore pinnedPeerStore, int maxWrongAttempts = 5, int lockoutSeconds = 60)
    {
        _pinnedPeerStore = pinnedPeerStore;
        _maxWrongAttempts = maxWrongAttempts;
        _lockoutSeconds = lockoutSeconds;
    }

    public enum PinError
    {
        Mismatch,
        LockedOut
    }

    public sealed class PinException : Exception
    {
        public PinError Reason { get; }
        public int? RetryAfterSeconds { get; }

        public PinException(PinError reason, int? retryAfterSeconds = null)
            : base($"PinError: {reason}")
        {
            Reason = reason;
            RetryAfterSeconds = retryAfterSeconds;
        }
    }

    /// Generate the 6-digit SAS from the TLS exporter output.
    /// Per spec: HKDF-Expand-Label(exporter_master_secret, "barelyreal sas", "", 4) mod 1_000_000.
    public static string Sas(ReadOnlySpan<byte> exporterBytes)
    {
        if (exporterBytes.Length < 4)
            throw new ArgumentException("Need at least 4 bytes", nameof(exporterBytes));

        var n = BinaryPrimitives.ReadUInt32LittleEndian(exporterBytes[..4]);
        var pin = (int)(n % 1_000_000);
        return pin.ToString("D6");
    }

    public void Confirm(string enteredPin, string expectedPin)
    {
        if (_lockoutUntil is { } lockoutUntil)
        {
            var remaining = (int)Math.Ceiling((lockoutUntil - DateTimeOffset.UtcNow).TotalSeconds);
            if (remaining > 0)
                throw new PinException(PinError.LockedOut, remaining);

            _lockoutUntil = null;
            _wrongAttempts = 0;
        }

        if (enteredPin != expectedPin)
        {
            _wrongAttempts++;
            if (_wrongAttempts >= _maxWrongAttempts)
            {
                _lockoutUntil = DateTimeOffset.UtcNow.AddSeconds(_lockoutSeconds);
                _wrongAttempts = 0;
                throw new PinException(PinError.LockedOut, _lockoutSeconds);
            }

            throw new PinException(PinError.Mismatch);
        }

        _wrongAttempts = 0;
        _lockoutUntil = null;
    }

    public IReadOnlyList<PinnedPeer> LoadPinnedPeers()
    {
        return _pinnedPeerStore.Load();
    }

    public void PinPeer(PinnedPeer peer)
    {
        _pinnedPeerStore.Add(peer);
    }

    public void UnpinPeer(string fingerprint)
    {
        _pinnedPeerStore.Remove(fingerprint);
    }
}
