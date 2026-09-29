namespace Festival.Core.ViewModels;

#region Paths session state
/// <summary>Per-launch Paths state.</summary>
public sealed partial class FestivalSession
{
    /// <summary>
    /// Whether the "Some Instruments Unavailable" notice already showed in this app session: it shows on the first Paths
    /// opening only, and never again after "Don't show again" (<see cref="AppSettings.PathUnavailableWarningDismissed"/>).
    /// </summary>
    public bool PathNoticeShown { get; set; }
}
#endregion
