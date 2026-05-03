namespace BarelyReal.Core.Clipboard;

/// Mirrors Windows clipboard changes to the peer and applies inbound clipboard frames locally.
/// Uses AddClipboardFormatListener + WM_CLIPBOARDUPDATE on a message-only window.
/// TODO(week 5).
public sealed class ClipboardSync
{
    public event Action<ClipboardEntry>? OnLocalChange;

    public void Start()
    {
        // TODO: create message-only window, AddClipboardFormatListener
    }

    public void Stop()
    {
        // TODO: RemoveClipboardFormatListener, destroy window
    }

    public void ApplyRemote(ClipboardEntry entry)
    {
        // TODO: OpenClipboard, EmptyClipboard, SetClipboardData per format,
        //       set "echo guard" hash to suppress feedback loop.
    }

    private void PublishLocalChange(ClipboardEntry entry)
    {
        OnLocalChange?.Invoke(entry);
    }
}

public sealed class ClipboardEntry
{
    public ulong Id { get; init; }
    public required Dictionary<string, byte[]> Formats { get; init; }   // "text/plain" → utf8 bytes, "image/png" → png bytes, …
    public required byte[] ContentHash { get; init; }                   // SHA-256 over canonicalized payload
}
