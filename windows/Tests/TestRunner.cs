namespace BarelyReal.Tests;

internal static class TestRunner
{
    private static int _passed;
    private static readonly List<(string Name, string Message)> _failed = new();

    public static void Run(string name, Action body)
    {
        try
        {
            body();
            _passed++;
            Console.WriteLine($"  ✓ {name}");
        }
        catch (Exception ex)
        {
            _failed.Add((name, ex.Message));
            Console.WriteLine($"  ✗ {name} — {ex.Message}");
        }
    }

    public static int Report()
    {
        Console.WriteLine();
        Console.WriteLine($"Passed: {_passed}  Failed: {_failed.Count}");
        return _failed.Count == 0 ? 0 : 1;
    }
}

internal sealed class AssertionException : Exception
{
    public AssertionException(string message) : base(message) { }
}

internal static class Expect
{
    public static void True(bool condition, string message)
    {
        if (!condition) throw new AssertionException(message);
    }

    public static void Equal<T>(T actual, T expected)
    {
        if (!EqualityComparer<T>.Default.Equals(actual, expected))
            throw new AssertionException($"expected {expected}, got {actual}");
    }

    public static void EqualBytes(byte[] actual, byte[] expected)
    {
        if (!actual.AsSpan().SequenceEqual(expected.AsSpan()))
            throw new AssertionException(
                $"byte mismatch: expected [{Convert.ToHexString(expected)}] got [{Convert.ToHexString(actual)}]");
    }

    public static void Throws<TException>(Action body) where TException : Exception
    {
        try
        {
            body();
        }
        catch (TException)
        {
            return;
        }
        catch (Exception other)
        {
            throw new AssertionException($"expected {typeof(TException).Name}, got {other.GetType().Name}: {other.Message}");
        }
        throw new AssertionException($"expected {typeof(TException).Name}, nothing thrown");
    }
}
