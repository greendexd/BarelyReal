using System.Text.Json;

namespace BarelyReal.Core.Clipboard;

/// Persists the last 50 clipboard entries locally.
///
/// MVP implementation uses JSON under %AppData%\BarelyReal so the feature is usable without
/// introducing SQLite dependencies yet. The API stays storage-agnostic for a later SQLite swap.
public sealed class ClipboardHistory
{
    public const int MaxEntries = 50;

    private readonly string _path;
    private readonly int _maxEntries;

    public ClipboardHistory(string? directory = null, int maxEntries = MaxEntries)
    {
        var dir = directory
            ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "BarelyReal");
        Directory.CreateDirectory(dir);
        _path = Path.Combine(dir, "clipboard-history.json");
        _maxEntries = maxEntries;
    }

    public void Append(ClipboardEntry entry)
    {
        var entries = Recent()
            .Where(e => !e.ContentHash.AsSpan().SequenceEqual(entry.ContentHash))
            .ToList();
        entries.Insert(0, entry);
        if (entries.Count > _maxEntries)
            entries.RemoveRange(_maxEntries, entries.Count - _maxEntries);
        Save(entries);
    }

    public IReadOnlyList<ClipboardEntry> Recent()
    {
        try
        {
            if (!File.Exists(_path))
                return Array.Empty<ClipboardEntry>();

            var data = File.ReadAllBytes(_path);
            return JsonSerializer.Deserialize<List<ClipboardEntry>>(data) ?? new List<ClipboardEntry>();
        }
        catch
        {
            return Array.Empty<ClipboardEntry>();
        }
    }

    private void Save(IReadOnlyList<ClipboardEntry> entries)
    {
        try
        {
            var data = JsonSerializer.SerializeToUtf8Bytes(entries);
            File.WriteAllBytes(_path, data);
        }
        catch
        {
            // History is best-effort and must never break live clipboard sync.
        }
    }
}
