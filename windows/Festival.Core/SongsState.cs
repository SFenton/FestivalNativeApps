using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Text.Json;

namespace Festival.Core;

#region Screen state
/// <summary>Observable state for the Songs screen, independent of WinUI and its test host.</summary>
public sealed class SongsState : INotifyPropertyChanged
{
    private readonly SongsClient client;
    private string publication = "Not loaded";
    private string status = "Load songs to see the current publication.";
    private bool isLoading;

    /// <summary>Creates screen state backed by a read-only client.</summary>
    /// <param name="client">The songs client.</param>
    public SongsState(SongsClient client) => this.client = client;

    /// <summary>Raised when a displayed property changes.</summary>
    public event PropertyChangedEventHandler? PropertyChanged;

    /// <summary>Visible songs in the current snapshot.</summary>
    public ObservableCollection<Song> Songs { get; } = [];

    /// <summary>Opaque publication label.</summary>
    public string Publication
    {
        get => publication;
        private set { publication = value; Notify(); }
    }

    /// <summary>Human-readable loading and failure status.</summary>
    public string Status
    {
        get => status;
        private set { status = value; Notify(); }
    }

    /// <summary>Whether loading is in progress.</summary>
    public bool IsLoading
    {
        get => isLoading;
        private set { isLoading = value; Notify(); }
    }

    /// <summary>Refreshes the snapshot and presents failures without discarding an already displayed list.</summary>
    /// <param name="cancellationToken">Cancellation of the read.</param>
    /// <returns>A task that completes once the state is updated.</returns>
    public async Task RefreshAsync(CancellationToken cancellationToken = default)
    {
        if (IsLoading) return;
        IsLoading = true;
        Status = "Loading songs…";
        try
        {
            var snapshot = await client.GetAsync(cancellationToken);
            Songs.Clear();
            foreach (var song in snapshot.Songs) Songs.Add(song);
            Publication = snapshot.PublicationId;
            Status = $"{Songs.Count} songs";
        }
        catch (Exception ex) when (ex is HttpRequestException or JsonException)
        {
            Status = $"Could not load songs: {ex.Message}";
        }
        finally
        {
            IsLoading = false;
        }
    }

    /// <summary>Notifies bindings about a changed property.</summary>
    /// <param name="name">Name of the changed property.</param>
    private void Notify([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
#endregion
}
