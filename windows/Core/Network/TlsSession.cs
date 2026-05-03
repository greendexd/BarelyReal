namespace BarelyReal.Core.Network;

/// TLS 1.3 control connection between two peers.
/// TODO(week 1): implement using TcpClient + SslStream with custom RemoteCertificateValidationCallback
/// that enforces the pinned SPKI hash from <see cref="PairingService"/>.
public sealed class TlsSession
{
    public sealed class TlsSessionException : Exception
    {
        public TlsSessionException(string operation)
            : base($"TlsSession.{operation} is not implemented in the current dev build")
        {
        }
    }

    public enum SessionState
    {
        Idle,
        Connecting,
        Handshaking,
        Ready,
        Failed,
        Closed
    }

    public SessionState State { get; private set; } = SessionState.Idle;

    public Task ConnectAsync(string host, ushort port, CancellationToken ct = default)
    {
        // TODO: TcpClient + SslStream.AuthenticateAsClientAsync with SslClientAuthenticationOptions
        //       { EnabledSslProtocols = SslProtocols.Tls13, RemoteCertificateValidationCallback = pin-check }
        throw new TlsSessionException("ConnectAsync");
    }

    public Task SendAsync(ReadOnlyMemory<byte> data, CancellationToken ct = default)
    {
        throw new TlsSessionException("SendAsync");
    }

    public void Close()
    {
        State = SessionState.Closed;
    }
}
