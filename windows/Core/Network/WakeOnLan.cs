using System.Net;
using System.Net.Sockets;

namespace BarelyReal.Core.Network;

public sealed class WakeOnLanException : Exception
{
    public WakeOnLanException(string message) : base(message) { }
}

public static class WakeOnLan
{
    public static byte[] MagicPacket(string macAddress)
    {
        var mac = ParseMacAddress(macAddress);
        var packet = new byte[6 + 16 * mac.Length];
        Array.Fill(packet, (byte)0xFF, 0, 6);
        for (var i = 0; i < 16; i++)
            mac.CopyTo(packet.AsSpan(6 + i * mac.Length));
        return packet;
    }

    public static async Task SendAsync(string macAddress, string broadcastHost, ushort port = 9, CancellationToken ct = default)
    {
        var packet = MagicPacket(macAddress);
        using var client = new UdpClient();
        client.EnableBroadcast = true;
        await client.SendAsync(packet, packet.Length, broadcastHost, port).WaitAsync(ct).ConfigureAwait(false);
    }

    private static byte[] ParseMacAddress(string raw)
    {
        var cleaned = raw
            .Replace(":", string.Empty, StringComparison.Ordinal)
            .Replace("-", string.Empty, StringComparison.Ordinal)
            .Replace(" ", string.Empty, StringComparison.Ordinal)
            .Trim();

        if (cleaned.Length != 12)
            throw new WakeOnLanException($"Invalid MAC address: {raw}");

        var bytes = new byte[6];
        for (var i = 0; i < bytes.Length; i++)
        {
            if (!byte.TryParse(cleaned.AsSpan(i * 2, 2), System.Globalization.NumberStyles.HexNumber, null, out bytes[i]))
                throw new WakeOnLanException($"Invalid MAC address: {raw}");
        }
        return bytes;
    }
}
